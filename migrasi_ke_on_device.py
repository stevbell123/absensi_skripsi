# =========================================================================
# SKRIP PERSIAPAN MODEL & MIGRASI EMBEDDING
# =========================================================================
# Skrip ini melakukan 3 hal:
#
# 1. KONVERSI MODEL: Mengunduh MobileFaceNet (.tflite) jika belum ada
# 2. VALIDASI: Membandingkan akurasi MobileFaceNet vs dlib pada dataset
#    yang sudah ada di folder dataset_wajah/
# 3. MIGRASI: Menghitung ulang semua embedding menggunakan MobileFaceNet
#    lalu meng-upload ke Firestore koleksi 'face_embeddings'
#
# CARA PAKAI:
#   pip install tensorflow onnxruntime numpy opencv-python Pillow firebase-admin
#   python migrasi_ke_on_device.py
#
# CATATAN PENTING:
# - Jalankan ini di server/PC yang sudah punya folder dataset_wajah/
# - Pastikan firebase-adminsdk.json ada di direktori yang sama
# - Setelah skrip selesai, salin file mobilefacenet.tflite ke folder
#   Flutter: assets/models/mobilefacenet.tflite
# =========================================================================

import os
import sys
import urllib.request
import numpy as np
import cv2
from PIL import Image
import json

# =========================================================================
# LANGKAH 1: UNDUH MODEL MobileFaceNet TFLite
# =========================================================================
MODEL_URL = "https://github.com/sirius-ai/MobileFaceNet_TF/raw/master/tflite/MobileFaceNet.tflite"
MODEL_PATH = "mobilefacenet.tflite"
DATASET_DIR = "dataset_wajah"

def unduh_model():
    """Mengunduh MobileFaceNet .tflite jika belum ada di lokal."""
    if os.path.exists(MODEL_PATH):
        ukuran = os.path.getsize(MODEL_PATH)
        print(f"[OK] Model sudah ada: {MODEL_PATH} ({ukuran / 1024:.0f} KB)")
        return True

    print(f"[UNDUH] Mengunduh MobileFaceNet dari {MODEL_URL}...")
    try:
        opener = urllib.request.build_opener()
        opener.addheaders = [('User-agent', 'Mozilla/5.0')]
        urllib.request.install_opener(opener)
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        ukuran = os.path.getsize(MODEL_PATH)
        print(f"[OK] Berhasil diunduh: {ukuran / 1024:.0f} KB")
        return True
    except Exception as e:
        print(f"[GAGAL] Tidak bisa mengunduh model: {e}")
        print("Silakan unduh manual dari:")
        print("  https://github.com/sirius-ai/MobileFaceNet_TF/tree/master/tflite")
        print(f"  Simpan sebagai: {MODEL_PATH}")
        return False


# =========================================================================
# LANGKAH 2: HITUNG EMBEDDING DENGAN MobileFaceNet
# =========================================================================
def muat_interpreter():
    """Memuat model TFLite ke interpreter."""
    try:
        import tensorflow as tf
        interpreter = tf.lite.Interpreter(model_path=MODEL_PATH)
        interpreter.allocate_tensors()
        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()
        print(f"[MODEL] Input shape : {input_details[0]['shape']}")
        print(f"[MODEL] Output shape: {output_details[0]['shape']}")
        return interpreter, input_details, output_details
    except ImportError:
        print("[GAGAL] tensorflow tidak terinstal. Jalankan: pip install tensorflow")
        sys.exit(1)


def pra_proses_wajah(image_bgr, bbox):
    """
    Crop wajah dari gambar, tambahkan padding 15%, resize ke 112x112,
    normalisasi ke [-1, 1].
    
    Ini HARUS identik dengan cara Flutter memproses gambar nanti,
    supaya vektor yang dihasilkan konsisten.
    """
    h, w = image_bgr.shape[:2]
    x1, y1, x2, y2 = bbox
    
    # Padding 15%
    tinggi = y2 - y1
    lebar = x2 - x1
    pad_y = int(tinggi * 0.15)
    pad_x = int(lebar * 0.15)
    
    y1 = max(0, y1 - pad_y)
    y2 = min(h, y2 + pad_y)
    x1 = max(0, x1 - pad_x)
    x2 = min(w, x2 + pad_x)
    
    # Crop dan resize
    wajah = image_bgr[y1:y2, x1:x2]
    wajah = cv2.resize(wajah, (112, 112))
    
    # BGR -> RGB
    wajah_rgb = cv2.cvtColor(wajah, cv2.COLOR_BGR2RGB)
    
    # Normalisasi ke [-1, 1] (cara MobileFaceNet dilatih)
    wajah_norm = (wajah_rgb.astype(np.float32) - 127.5) / 127.5
    
    # Tambahkan dimensi batch: [1, 112, 112, 3]
    return np.expand_dims(wajah_norm, axis=0)


def hitung_embedding(interpreter, input_details, output_details, input_data):
    """Jalankan inference dan kembalikan vektor 128-d yang sudah dinormalisasi."""
    interpreter.set_tensor(input_details[0]['index'], input_data)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]['index'])
    
    # L2 normalisasi: buat vektor menjadi panjang 1
    # Ini penting agar euclidean distance setara dengan cosine distance
    vektor = output[0]
    norma = np.linalg.norm(vektor)
    if norma > 0:
        vektor = vektor / norma
    
    return vektor.tolist()


# =========================================================================
# LANGKAH 3: DETEKSI WAJAH (MENGGUNAKAN YOLO YANG SUDAH ADA)
# =========================================================================
def deteksi_wajah(image_bgr):
    """Deteksi wajah menggunakan YOLOv8n-face yang sudah ada di server."""
    try:
        from ultralytics import YOLO
        yolo = YOLO("yolov8n-face.pt")
        hasil = yolo(image_bgr, imgsz=1024, conf=0.5, verbose=False)
        
        kotak = []
        for r in hasil:
            for box in r.boxes:
                x1, y1, x2, y2 = box.xyxy[0]
                kotak.append([int(x1), int(y1), int(x2), int(y2)])
        
        return kotak
    except ImportError:
        print("[WARNING] ultralytics tidak terinstal, pakai Haar Cascade sebagai fallback")
        return deteksi_wajah_haar(image_bgr)


def deteksi_wajah_haar(image_bgr):
    """Fallback: deteksi wajah dengan Haar Cascade OpenCV."""
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
    faces = cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(60, 60))
    return [[x, y, x + w, y + h] for (x, y, w, h) in faces]


# =========================================================================
# LANGKAH 4: PROSES SELURUH DATASET
# =========================================================================
def proses_dataset():
    """
    Membaca semua foto di dataset_wajah/, menghitung embedding MobileFaceNet
    untuk setiap siswa (rata-rata dari semua variasi foto), lalu menyimpan
    hasilnya ke file JSON.
    """
    if not os.path.exists(DATASET_DIR):
        print(f"[GAGAL] Folder {DATASET_DIR} tidak ditemukan!")
        return {}
    
    interpreter, input_details, output_details = muat_interpreter()
    
    hasil_semua = {}  # nim -> {name, embedding}
    
    for student_folder in sorted(os.listdir(DATASET_DIR)):
        student_path = os.path.join(DATASET_DIR, student_folder)
        if not os.path.isdir(student_path):
            continue
        
        parts = student_folder.split("_")
        nim = parts[0]
        nama = parts[1] if len(parts) > 1 else "Unknown"
        
        kumpulan_vektor = []
        
        for filename in sorted(os.listdir(student_path)):
            if not filename.lower().endswith((".jpg", ".jpeg", ".png")):
                continue
            
            filepath = os.path.join(student_path, filename)
            image_bgr = cv2.imread(filepath)
            
            if image_bgr is None:
                print(f"  [LEWAT] Tidak bisa baca: {filepath}")
                continue
            
            kotak = deteksi_wajah(image_bgr)
            
            if len(kotak) != 1:
                print(f"  [LEWAT] {filename} berisi {len(kotak)} wajah, harus 1")
                continue
            
            input_data = pra_proses_wajah(image_bgr, kotak[0])
            vektor = hitung_embedding(interpreter, input_details, output_details, input_data)
            kumpulan_vektor.append(vektor)
        
        if len(kumpulan_vektor) > 0:
            # Rata-rata semua variasi, lalu normalisasi lagi
            vektor_rata = np.mean(kumpulan_vektor, axis=0)
            norma = np.linalg.norm(vektor_rata)
            if norma > 0:
                vektor_rata = vektor_rata / norma
            
            hasil_semua[nim] = {
                "nim": nim,
                "name": nama,
                "embedding": vektor_rata.tolist(),
            }
            print(f"[SIAP] {nama} ({nim}) dari {len(kumpulan_vektor)} foto")
        else:
            print(f"[KOSONG] {student_folder} tidak ada foto valid")
    
    print(f"\nTotal siswa berhasil diproses: {len(hasil_semua)}")
    return hasil_semua


# =========================================================================
# LANGKAH 5: UPLOAD KE FIRESTORE
# =========================================================================
def upload_ke_firestore(data_embedding):
    """Upload semua embedding ke koleksi 'face_embeddings' di Firestore."""
    import firebase_admin
    from firebase_admin import credentials, firestore
    
    # Inisialisasi Firebase (kalau belum)
    if not firebase_admin._apps:
        cred = credentials.Certificate("firebase-adminsdk.json")
        firebase_admin.initialize_app(cred)
    
    db = firestore.client()
    koleksi = db.collection('face_embeddings')
    
    jumlah_sukses = 0
    for nim, data in data_embedding.items():
        try:
            koleksi.document(nim).set({
                'nim': data['nim'],
                'name': data['name'],
                'embedding': data['embedding'],
                'updatedAt': firestore.SERVER_TIMESTAMP,
                'migratedFrom': 'dlib_to_mobilefacenet',
            })
            jumlah_sukses += 1
            print(f"  [UPLOAD] {data['name']} ({nim})")
        except Exception as e:
            print(f"  [GAGAL] {nim}: {e}")
    
    print(f"\nUpload selesai: {jumlah_sukses}/{len(data_embedding)} berhasil")


# =========================================================================
# LANGKAH 6: SIMPAN JUGA KE FILE LOKAL (CADANGAN)
# =========================================================================
def simpan_ke_json(data_embedding):
    """Simpan embedding ke file JSON lokal sebagai cadangan."""
    nama_file = "embedding_mobilefacenet.json"
    
    with open(nama_file, 'w') as f:
        json.dump(data_embedding, f, indent=2)
    
    print(f"[CADANGAN] Disimpan ke {nama_file}")


# =========================================================================
# MAIN: JALANKAN SEMUA LANGKAH
# =========================================================================
if __name__ == "__main__":
    print("=" * 60)
    print("MIGRASI EMBEDDING: dlib → MobileFaceNet")
    print("=" * 60)
    
    # Langkah 1: Pastikan model ada
    if not unduh_model():
        print("\nProses dihentikan. Unduh model dulu.")
        sys.exit(1)
    
    # Langkah 2-4: Proses seluruh dataset
    print("\n" + "=" * 60)
    print("MEMPROSES DATASET...")
    print("=" * 60)
    data = proses_dataset()
    
    if not data:
        print("\nTidak ada data yang diproses. Pastikan folder dataset_wajah/ berisi foto.")
        sys.exit(1)
    
    # Langkah 5: Simpan ke JSON lokal
    simpan_ke_json(data)
    
    # Langkah 6: Upload ke Firestore
    print("\n" + "=" * 60)
    print("UPLOAD KE FIRESTORE...")
    print("=" * 60)
    
    jawab = input("Upload embedding ke Firestore sekarang? (y/n): ").strip().lower()
    if jawab == 'y':
        upload_ke_firestore(data)
    else:
        print("Dilewati. Jalankan ulang kalau mau upload nanti.")
    
    # Instruksi terakhir
    print("\n" + "=" * 60)
    print("LANGKAH SELANJUTNYA:")
    print("=" * 60)
    print(f"1. Salin '{MODEL_PATH}' ke proyek Flutter:")
    print(f"   → d:\\Goals_16\\skripsi1\\assets\\models\\{MODEL_PATH}")
    print("2. Jalankan 'flutter pub get' di proyek Flutter")
    print("3. Build dan test di HP Android")
    print("=" * 60)
