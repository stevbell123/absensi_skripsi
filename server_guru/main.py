# ==========================================================================
# BACKEND SERVER: Sistem Absensi Wajah Siswa Real-Time (YOLOv8 + ArcFace)
# ==========================================================================
# File       : main.py
# Framework  : FastAPI + Ultralytics YOLOv8 + DeepFace (ArcFace 512-d) + Firebase
# Fitur      : Multi-face detection, Cosine Similarity, Rate Limiter (slowapi),
#              Email Alert Darurat (smtplib), Monitoring RAM/CPU (psutil),
#              Auto Backup Database, dan Real-time Firestore Sync.
# Port       : 8001 (Tidak mengganggu server lama di port 8000)
# ==========================================================================

import os
# Matikan pencarian CUDA agar PyTorch & TensorFlow tidak konflik driver pada CPU VPS
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"
os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"
os.environ["OMP_NUM_THREADS"] = "1"
os.environ["OPENBLAS_NUM_THREADS"] = "1"
os.environ["MKL_NUM_THREADS"] = "1"

# Aktifkan pelacak error C++ (faulthandler) untuk mencegah silent crash
import faulthandler
faulthandler.enable()

import io
import cv2
cv2.setNumThreads(0)

import json
import psutil
import smtplib
import asyncio
import traceback
import numpy as np
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Optional
from email.message import EmailMessage
from PIL import Image, ImageOps

import firebase_admin
from firebase_admin import credentials, firestore
from fastapi import FastAPI, File, UploadFile, Form, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from ultralytics import YOLO

# DeepFace tidak di-import di tingkat atas agar tidak membebani 1.5GB RAM dan tidak bentrok C++ runtime

# Anti-DDoS & Pembatas Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

# =====================================================================
# PENGATURAN UTAMA & THRESHOLD
# =====================================================================
# --- Model YOLOv26 (Ultralytics Release 2026) ---
# Menggunakan arsitektur NMS-Free End-to-End & DFL-Free terbaru
YOLO_MODEL_PATH = "yolov26n.pt"
YOLO_CONFIDENCE = 0.35       # Confidence deteksi wajah siswa
YOLO_IMGSZ = 640             # Resolusi inference YOLOv26 (optimal di VPS 4GB)
FACE_MODEL = "ArcFace"       # Model embedding ArcFace 512 dimensi (atau MobileFaceNet 128-d)
COSINE_THRESHOLD = 0.65      # Ambang batas kemiripan wajah (> 0.65)
FACE_PADDING = 0.15          # Padding 15% sekitar bounding box wajah
MAX_IMAGE_SIZE = 15 * 1024 * 1024  # Maks 15 MB
WIB = timezone(timedelta(hours=7))

# --- Pra-Pemrosesan Citra: Peningkatan Kontras Adaptif (CLAHE) ---
# Menjaga fitur wajah tetap tajam & jelas saat pencahayaan kelas redup, bayangan, atau backlight
CLAHE_CLIP_LIMIT = 2.0       # Batas ambang amplifikasi kontras adaptif
CLAHE_TILE_GRID = (8, 8)     # Pembagian grid kontekstual blok piksel (8x8)

# --- Model MobileFaceNet TFLite (128 Dimensi) ---
# Kompatibel 100% dengan ruang vektor embedding aplikasi mobile Flutter
tflite_interpreter = None
tflite_input_details = None
tflite_output_details = None

for m_path in [
    "mobilefacenet.tflite",
    "../mobilefacenet.tflite",
    "/root/mobilefacenet.tflite",
    "/root/server_guru/mobilefacenet.tflite",
    "../assets/models/mobilefacenet.tflite",
]:
    if os.path.exists(m_path):
        try:
            import tensorflow as tf
            tflite_interpreter = tf.lite.Interpreter(model_path=m_path, num_threads=1)
            tflite_interpreter.allocate_tensors()
            tflite_input_details = tflite_interpreter.get_input_details()
            tflite_output_details = tflite_interpreter.get_output_details()
            print(f"[TFLITE] ✅ Model MobileFaceNet aktif dari {m_path}", flush=True)
            break
        except Exception as te:
            print(f"[TFLITE] ⚠️ Info model TFLite {m_path}: {te}", flush=True)



# Kredensial Email Alert (bisa diisi via environment variable atau langsung)
EMAIL_BOT = os.getenv("EMAIL_BOT", "")
PASSWORD_APP = os.getenv("PASSWORD_APP", "")
EMAIL_TUJUAN = os.getenv("EMAIL_TUJUAN", "")

# =====================================================================
# 1. INISIALISASI APLIKASI & RATE LIMITER
# =====================================================================
limiter = Limiter(key_func=get_remote_address)
app = FastAPI(
    title="API Absensi Wajah Siswa SIAP (YOLOv8 + ArcFace)",
    description="Sistem Absensi Real-Time Multi-Wajah untuk Guru dan Siswa",
    version="2.1.0",
)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# =====================================================================
# 2. SISTEM EMAIL ALERT DARURAT
# =====================================================================
def kirim_email_alert(pesan_error: str):
    """Mengirim email peringatan darurat ke developer jika server crash"""
    if not EMAIL_BOT or not PASSWORD_APP:
        print("[EMAIL] Dilewati: Kredensial email belum diatur di environment.", flush=True)
        return
    try:
        msg = EmailMessage()
        msg.set_content(f"Peringatan! Server Absensi AI mengalami error:\n\n{pesan_error}")
        msg['Subject'] = '🚨 CRITICAL ALERT: Server Absensi AI Error'
        msg['From'] = EMAIL_BOT
        msg['To'] = EMAIL_TUJUAN

        server = smtplib.SMTP_SSL('smtp.gmail.com', 465)
        server.login(EMAIL_BOT, PASSWORD_APP)
        server.send_message(msg)
        server.quit()
        print("[EMAIL] ✅ Alert berhasil dikirim ke developer.", flush=True)
    except Exception as e:
        print(f"[EMAIL] ❌ Gagal mengirim alert: {e}", flush=True)

@app.exception_handler(Exception)
async def tangkap_semua_error(request: Request, exc: Exception):
    """Menangkap seluruh error tak terduga agar server tidak crash"""
    error_detail = traceback.format_exc()
    print(f"[CRITICAL ERROR]\n{error_detail}", flush=True)
    # Jalankan pengiriman email di background thread agar tidak memblokir event loop
    asyncio.create_task(asyncio.to_thread(kirim_email_alert, error_detail))
    return JSONResponse(
        status_code=500,
        content={"success": False, "pesan": "Terjadi kesalahan internal. Developer telah diberitahu."},
    )

# =====================================================================
# 3. INISIALISASI FIREBASE ADMIN SDK
# =====================================================================
print("[FIREBASE] Menghubungkan ke Firebase...", flush=True)
db = None
try:
    cred = credentials.Certificate("firebase-adminsdk.json")
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print("[FIREBASE] ✅ Berhasil terhubung ke Firestore.", flush=True)
except Exception as e:
    print(f"[FIREBASE] ❌ Gagal terhubung ke Firebase: {e}", flush=True)

# =====================================================================
# 4. INISIALISASI MODEL YOLOv26 (NMS-FREE)
# =====================================================================
print(f"[YOLO] Memuat model {YOLO_MODEL_PATH}...", flush=True)
yolo_model = None
for candidate_model in [YOLO_MODEL_PATH, "yolo26n.pt", "yolov8n-face.pt"]:
    try:
        yolo_model = YOLO(candidate_model)
        print(f"[YOLO] ✅ Model {candidate_model} berhasil dimuat.", flush=True)
        YOLO_MODEL_PATH = candidate_model
        break
    except Exception as e:
        print(f"[YOLO] ⚠️ Gagal memuat {candidate_model}: {e}", flush=True)

if yolo_model is None:
    print("[YOLO] ❌ Gagal memuat model YOLO apapun. Pastikan koneksi internet / file model tersedia.", flush=True)

# =====================================================================
# 5. IN-MEMORY DATABASE SISWA (CACHE CEPAT)
# =====================================================================
siswa_database: Dict[str, dict] = {}

def muat_database_siswa():
    """Memuat seluruh vektor embedding siswa dari Firestore koleksi face_embeddings"""
    global siswa_database
    if db is None:
        return

    try:
        docs = db.collection("face_embeddings").stream()
        siswa_database.clear()

        for doc in docs:
            data = doc.to_dict()
            emb = data.get("embedding", [])
            if len(emb) == 0:
                continue

            emb_arr = np.array(emb, dtype=np.float64)
            nama_siswa = data.get("name") or data.get("nama") or ""
            siswa_database[doc.id] = {
                "nim": data.get("nim", doc.id),
                "nama": nama_siswa,
                "class_id": data.get("classId") or data.get("class_id") or "",
                "embedding": emb_arr,
            }
            print(f"  [DB DATA] Siswa {nama_siswa} ({doc.id}) -> Dimensi Vektor: {len(emb_arr)}", flush=True)

        print(f"[DB] ✅ {len(siswa_database)} data siswa aktif di memori server.", flush=True)
    except Exception as e:
        print(f"[DB] ❌ Gagal memuat database siswa: {e}", flush=True)

def _warmup_background():
    """Warmup model MobileFaceNet TFLite agar siap di memori"""
    if tflite_interpreter is not None:
        try:
            dummy = np.zeros((1, 112, 112, 3), dtype=np.float32)
            tflite_interpreter.set_tensor(tflite_input_details[0]['index'], dummy)
            tflite_interpreter.invoke()
            print("[TFLITE] ✅ Model MobileFaceNet siap & teruji di memori.", flush=True)
        except Exception as e:
            print(f"[TFLITE WARMUP] ⚠️ {e}", flush=True)

@app.on_event("startup")
async def startup_event():
    muat_database_siswa()
    _warmup_background()

# =====================================================================
# 6. FUNGSI UTILITAS AI: PREPROCESSING, DETEKSI & MATCHING
# =====================================================================
def terapkan_clahe(gambar_rgb: np.ndarray, clip_limit: float = CLAHE_CLIP_LIMIT, tile_grid: tuple = CLAHE_TILE_GRID) -> np.ndarray:
    """
    Contrast Limited Adaptive Histogram Equalization (CLAHE):
    Meningkatkan kontras lokal pada kanal Luminance (L) dalam ruang warna CIELAB.
    Mencegah distorsi warna dan kebal terhadap bayangan/backlight di ruang kelas.
    """
    gambar_c = np.ascontiguousarray(gambar_rgb)
    lab = cv2.cvtColor(gambar_c, cv2.COLOR_RGB2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=tile_grid)
    l_clahe = clahe.apply(l)
    lab_clahe = cv2.merge((l_clahe, a, b))
    return cv2.cvtColor(lab_clahe, cv2.COLOR_LAB2RGB)

def perbaiki_orientasi_gambar(gambar_bytes: bytes, gunakan_clahe: bool = True) -> np.ndarray:
    """
    Pipeline Pra-Pemrosesan Citra:
    1. Membaca bytes gambar dan memperbaiki orientasi EXIF kamera smartphone secara otomatis
    2. Batasi ukuran maksimum ke 1280px agar hemat RAM dan mencegah crash segfault
    3. Konversi ke ruang warna RGB
    4. Menerapkan Contrast Limited Adaptive Histogram Equalization (CLAHE) pada kanal Luminance
    """
    pil_img = Image.open(io.BytesIO(gambar_bytes))
    pil_img = ImageOps.exif_transpose(pil_img)
    pil_img = pil_img.convert("RGB")

    # Batasi resolusi maksimum ke 1280px untuk kestabilan memori pada VPS 4GB
    pil_img.thumbnail((1280, 1280), Image.Resampling.LANCZOS)
    gambar_rgb = np.ascontiguousarray(np.array(pil_img), dtype=np.uint8)

    if gunakan_clahe:
        gambar_rgb = terapkan_clahe(gambar_rgb)

    return np.ascontiguousarray(gambar_rgb)

# Alias fungsi agar kompatibel penuh dengan semua modul
praproses_gambar = perbaiki_orientasi_gambar

def hitung_cosine_similarity(vektor_a: np.ndarray, vektor_b: np.ndarray) -> float:
    """Menghitung Cosine Similarity: dot(A, B) / (||A|| * ||B||) dengan proteksi keselarasan dimensi vektor"""
    if len(vektor_a) == 0 or len(vektor_b) == 0:
        return 0.0
    if len(vektor_a) != len(vektor_b):
        min_dim = min(len(vektor_a), len(vektor_b))
        vektor_a = vektor_a[:min_dim]
        vektor_b = vektor_b[:min_dim]
    dot_product = np.dot(vektor_a, vektor_b)
    norma_a = np.linalg.norm(vektor_a)
    norma_b = np.linalg.norm(vektor_b)
    if norma_a == 0 or norma_b == 0:
        return 0.0
    return float(dot_product / (norma_a * norma_b))

def ekstrak_embedding_tflite(gambar_wajah: np.ndarray) -> Optional[np.ndarray]:
    """Ekstraksi embedding via MobileFaceNet TFLite (~3ms, 100% cocok dengan Flutter)"""
    if tflite_interpreter is None:
        return None
    try:
        wajah_c = np.ascontiguousarray(gambar_wajah)
        wajah_resized = cv2.resize(wajah_c, (112, 112))
        wajah_norm = (wajah_resized.astype(np.float32) - 127.5) / 128.0
        input_tensor = np.expand_dims(wajah_norm, axis=0)

        tflite_interpreter.set_tensor(tflite_input_details[0]['index'], input_tensor)
        tflite_interpreter.invoke()
        output = tflite_interpreter.get_tensor(tflite_output_details[0]['index'])[0]

        # L2 Normalization (sesuai mobilefacenet)
        norm = np.linalg.norm(output)
        if norm > 0:
            output = output / norm
        return output.astype(np.float64)
    except Exception as e:
        print(f"[TFLITE EMBEDDING] Error: {e}", flush=True)
        return None

def ekstrak_embedding(gambar_wajah: np.ndarray) -> Optional[np.ndarray]:
    """Mengekstrak vektor embedding 192-dimensi via MobileFaceNet TFLite (100% cocok dengan Flutter)"""
    return ekstrak_embedding_tflite(gambar_wajah)

def deteksi_dan_crop_wajah(gambar_rgb: np.ndarray):
    """YOLO mendeteksi multi-wajah (1-5 orang) dan memotong dengan padding 15%"""
    if yolo_model is None or gambar_rgb is None or gambar_rgb.size == 0:
        return [], []

    try:
        import torch
        torch.set_num_threads(1)
        with torch.no_grad():
            img_input = np.ascontiguousarray(gambar_rgb)
            if img_input.shape[0] < 32 or img_input.shape[1] < 32:
                return [], []

            hasil_yolo = yolo_model.predict(
                img_input,
                conf=YOLO_CONFIDENCE,
                imgsz=YOLO_IMGSZ,
                device='cpu',
                verbose=False,
            )
            daftar_crop = []
            daftar_box = []
            tinggi_img, lebar_img = img_input.shape[:2]

            for r in hasil_yolo:
                if r.boxes is None or len(r.boxes) == 0:
                    continue
                for box in r.boxes:
                    coords = box.xyxy[0].tolist()
                    x1, y1, x2, y2 = int(coords[0]), int(coords[1]), int(coords[2]), int(coords[3])
                    w = x2 - x1
                    h = y2 - y1
                    if w <= 10 or h <= 10:
                        continue
                    pad_x = int(w * FACE_PADDING)
                    pad_y = int(h * FACE_PADDING)

                    crop_y1 = max(0, y1 - pad_y)
                    crop_x1 = max(0, x1 - pad_x)
                    crop_y2 = min(tinggi_img, y2 + pad_y)
                    crop_x2 = min(lebar_img, x2 + pad_x)

                    if crop_y2 <= crop_y1 or crop_x2 <= crop_x1:
                        continue

                    crop = img_input[crop_y1:crop_y2, crop_x1:crop_x2]
                    if crop.size > 0 and crop.shape[0] > 10 and crop.shape[1] > 10:
                        daftar_crop.append(np.ascontiguousarray(crop))
                        daftar_box.append([x1, y1, x2, y2])

            return daftar_crop, daftar_box
    except Exception as e:
        print(f"[YOLO DETEKSI ERROR] {e}", flush=True)
        return [], []

def cocokkan_dengan_kelas(embedding: np.ndarray, class_id: Optional[str] = None) -> Optional[dict]:
    """Mencocokkan embedding wajah siswa dengan database (difilter per kelas jika ada)"""
    if len(siswa_database) == 0:
        return None

    skor_terbaik = -1.0
    siswa_terbaik = None

    for nim, data in siswa_database.items():
        if class_id and data["class_id"] and data["class_id"] != class_id:
            continue

        skor = hitung_cosine_similarity(embedding, data["embedding"])
        print(f"    [MATCHING] {data['nama']} ({nim}) -> Similarity: {skor:.4f} (Threshold: {COSINE_THRESHOLD})", flush=True)
        if skor > skor_terbaik:
            skor_terbaik = skor
            siswa_terbaik = {
                "nim": nim,
                "nama": data["nama"],
                "similarity": round(skor, 4),
            }

    if siswa_terbaik and skor_terbaik >= COSINE_THRESHOLD:
        return siswa_terbaik
    return None

# =====================================================================
# 7. LOGIKA BACKUP DATABASE KE STORAGE
# =====================================================================
def eksekusi_backup() -> str:
    """Melakukan backup otomatis seluruh koleksi penting Firestore ke file JSON"""
    if not db:
        raise Exception("Database Firebase belum terhubung.")

    koleksi = ['users', 'classes', 'schedules', 'attendance', 'modules', 'face_embeddings']
    backup_data = {}

    for col in koleksi:
        docs = db.collection(col).stream()
        data_list = []
        for doc in docs:
            d = doc.to_dict()
            d['id'] = doc.id
            data_list.append(d)
        backup_data[col] = data_list

    folder_backup = "backup_data"
    os.makedirs(folder_backup, exist_ok=True)

    timestamp = datetime.now(WIB).strftime("%Y-%m-%d_%H-%M-%S")
    nama_file = f"{folder_backup}/backup_sistem_{timestamp}.json"

    def serializer(obj):
        if hasattr(obj, 'isoformat'):
            return obj.isoformat()
        return str(obj)

    with open(nama_file, 'w', encoding='utf-8') as f:
        json.dump(backup_data, f, default=serializer, indent=4)

    return nama_file

# =====================================================================
# 8. ENDPOINT UTAMA: SCAN ABSENSI SISWA (YOLO + ARCFACE)
# =====================================================================
proses_lock = asyncio.Semaphore(2)  # Batasi 2 request AI bersamaan agar RAM 4GB tidak sesak

@app.post("/api/scan-attendance")
@limiter.limit("30/minute")  # Maksimal 30 request scan per menit
async def scan_attendance(
    request: Request,
    file: UploadFile = File(...),
    class_id: Optional[str] = Form(None)
):
    async with proses_lock:
        try:
            konten = await file.read()
            if len(konten) == 0:
                raise HTTPException(400, "File gambar kosong.")
            if len(konten) > MAX_IMAGE_SIZE:
                raise HTTPException(413, "Ukuran gambar terlalu besar (maks 15MB).")

            # Perbaiki orientasi EXIF & konversi ke RGB + CLAHE
            print(f"\n[SCAN REQUEST] Menerima foto absensi ({len(konten)} bytes). Menerapkan CLAHE & YOLO...", flush=True)
            gambar_rgb = perbaiki_orientasi_gambar(konten)

            # 1. YOLO mendeteksi seluruh koordinat wajah (Multi-wajah)
            daftar_crop, daftar_box = deteksi_dan_crop_wajah(gambar_rgb)
            jumlah_wajah = len(daftar_crop)
            print(f"[YOLO DETEKSI] Berhasil mendeteksi {jumlah_wajah} wajah dalam gambar.", flush=True)

            if jumlah_wajah == 0:
                print("  [INFO] Tidak ada wajah terdeteksi dalam frame.", flush=True)
                return {
                    "success": True,
                    "wajah_terdeteksi": 0,
                    "siswa_dikenali": [],
                    "pesan": "Tidak ada wajah terdeteksi dalam foto.",
                }

            siswa_dikenali = []
            nim_sudah_cocok = set()

            # 2. Looping ekstraksi embedding & pencocokan Cosine Similarity
            for i, crop in enumerate(daftar_crop):
                emb = ekstrak_embedding(crop)
                if emb is None:
                    continue

                cocok = cocokkan_dengan_kelas(emb, class_id)
                if cocok and cocok["nim"] not in nim_sudah_cocok:
                    nim_sudah_cocok.add(cocok["nim"])
                    siswa_dikenali.append({
                        "nim": cocok["nim"],
                        "nama": cocok["nama"],
                        "similarity": cocok["similarity"],
                        "box": daftar_box[i],
                    })
                    print(f"  [HADIR] ✅ {cocok['nama']} ({cocok['nim']}) - Sim: {cocok['similarity']}", flush=True)

            # 3. Update Firestore absensi_harian/YYYY-MM-DD secara Real-Time via Admin SDK
            if db and len(siswa_dikenali) > 0:
                try:
                    sekarang = datetime.now(WIB)
                    tanggal_hari_ini = sekarang.strftime("%Y-%m-%d")
                    jam_sekarang = sekarang.strftime("%H:%M:%S")
                    doc_ref = db.collection("absensi_harian").document(tanggal_hari_ini)

                    kehadiran_dict = {}
                    for s in siswa_dikenali:
                        kehadiran_dict[s["nim"]] = {
                            "nama": s["nama"],
                            "nim": s["nim"],
                            "waktu": jam_sekarang,
                            "similarity": s["similarity"],
                            "status": "hadir",
                        }

                    doc_ref.set({
                        "tanggal": tanggal_hari_ini,
                        "kehadiran": kehadiran_dict
                    }, merge=True)
                    print(f"  [FIRESTORE] ✅ {len(siswa_dikenali)} siswa berhasil dicatat di absensi_harian/{tanggal_hari_ini}", flush=True)
                except Exception as fe:
                    print(f"  [FIRESTORE] ⚠️ Gagal update real-time: {fe}", flush=True)

            return {
                "success": True,
                "wajah_terdeteksi": jumlah_wajah,
                "jumlah_hadir": len(siswa_dikenali),
                "siswa_dikenali": siswa_dikenali,
            }

        except HTTPException:
            raise
        except Exception as e:
            traceback.print_exc()
            return JSONResponse(status_code=500, content={"success": False, "pesan": str(e)})

# =====================================================================
# 9. ENDPOINT REGISTRASI WAJAH SISWA (MENU AKADEMIK)
# =====================================================================
@app.post("/api/register-student")
@limiter.limit("20/minute")
async def register_student(
    request: Request,
    file: UploadFile = File(...),
    nim: str = Form(...),
    nama: str = Form(...),
    class_id: str = Form(""),
):
    try:
        konten = await file.read()
        if len(konten) == 0:
            raise HTTPException(400, "File gambar kosong.")

        gambar_rgb = perbaiki_orientasi_gambar(konten)
        daftar_crop, _ = deteksi_dan_crop_wajah(gambar_rgb)

        if len(daftar_crop) == 0:
            raise HTTPException(400, "Tidak ada wajah terdeteksi. Pastikan wajah terlihat jelas.")
        if len(daftar_crop) > 1:
            raise HTTPException(400, f"Terdeteksi {len(daftar_crop)} wajah. Pastikan hanya 1 siswa di depan kamera.")

        embedding = ekstrak_embedding(daftar_crop[0])
        if embedding is None:
            raise HTTPException(500, "Gagal mengekstrak fitur wajah siswa.")

        # Simpan ke Firestore
        if db:
            db.collection("face_embeddings").document(nim).set({
                "nim": nim,
                "name": nama,
                "classId": class_id,
                "embedding": embedding.tolist(),
                "updatedAt": firestore.SERVER_TIMESTAMP,
            }, merge=True)

        # Update cache in-memory
        siswa_database[nim] = {
            "nim": nim,
            "nama": nama,
            "class_id": class_id,
            "embedding": embedding,
        }

        print(f"[REGISTER] ✅ Siswa {nama} ({nim}) berhasil didaftarkan.", flush=True)
        return {
            "success": True,
            "pesan": f"Siswa {nama} berhasil didaftarkan ke sistem AI.",
            "nim": nim,
        }

    except HTTPException:
        raise
    except Exception as e:
        traceback.print_exc()
        return JSONResponse(status_code=500, content={"success": False, "pesan": str(e)})

# =====================================================================
# 10. MONITORING RAM, CPU & STATUS SERVER (PSUTIL)
# =====================================================================
@app.get("/")
def home():
    return {
        "status": "✅ Server AI Siswa Aktif",
        "praproses_citra": "EXIF Transpose + CLAHE (CIELAB L-channel)",
        "clahe_clip_limit": CLAHE_CLIP_LIMIT,
        "clahe_tile_grid": CLAHE_TILE_GRID,
        "model_deteksi": YOLO_MODEL_PATH,
        "model_embedding": "MobileFaceNet TFLite (128-d)" if tflite_interpreter else f"DeepFace {FACE_MODEL} (512-d)",
        "threshold_cosine": COSINE_THRESHOLD,
        "total_siswa_terdaftar": len(siswa_database),
    }

@app.get("/server-monitor")
def monitor_server_sekarang():
    """Memantau performa hardware VPS 4GB secara real-time"""
    ram = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=0.5)
    disk = psutil.disk_usage('/')

    return {
        "status": "online",
        "cpu_usage_percent": cpu,
        "ram_total_mb": round(ram.total / (1024 * 1024), 2),
        "ram_terpakai_mb": round(ram.used / (1024 * 1024), 2),
        "ram_sisa_mb": round(ram.available / (1024 * 1024), 2),
        "disk_terpakai_percent": disk.percent,
        "total_siswa_terdaftar": len(siswa_database),
    }

# =====================================================================
# 11. ENDPOINT MANAJEMEN BACKUP DATABASE
# =====================================================================
@app.get("/force-backup")
async def force_backup():
    try:
        nama_file = await asyncio.to_thread(eksekusi_backup)
        return {"success": True, "pesan": f"Backup berhasil: {nama_file}"}
    except Exception as e:
        return {"success": False, "pesan": str(e)}

@app.get("/list-backup")
def list_backup():
    folder = "backup_data"
    if not os.path.exists(folder):
        return {"success": True, "files": []}
    files = [f for f in os.listdir(folder) if f.endswith(".json")]
    files.sort(reverse=True)
    return {"success": True, "files": files}

@app.get("/download-backup/{nama_file}")
def download_backup(nama_file: str):
    nama_bersih = os.path.basename(nama_file)
    if not nama_bersih.endswith(".json") or not nama_bersih.startswith("backup_sistem_"):
        raise HTTPException(400, "Berkas backup tidak valid.")
    path = os.path.join("backup_data", nama_bersih)
    if os.path.exists(path):
        return FileResponse(path, media_type='application/json', filename=nama_bersih)
    raise HTTPException(404, "File tidak ditemukan.")

@app.post("/api/reload-database")
async def reload_database():
    muat_database_siswa()
    return {"success": True, "total_siswa": len(siswa_database)}

# =====================================================================
# 12. ENTRY POINT
# =====================================================================
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
