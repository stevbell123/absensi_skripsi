<USER_REQUEST>
import os
import urllib.request
import cv2
import numpy as np
import face_recognition
import asyncio
import json
import smtplib
import traceback
import psutil
import pickle
import hashlib
from email.message import EmailMessage
from datetime import datetime, timezone
from fastapi import FastAPI, File, UploadFile, Request, Form
from fastapi.responses import FileResponse, JSONResponse
from ultralytics import YOLO
import firebase_admin
from firebase_admin import credentials, firestore

from PIL import Image, ImageOps
import io

from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

app = FastAPI()

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# =========================================================================
# PENGATURAN UTAMA (SEMUA ANGKA PENTING DIKUMPULKAN DI SINI)
# =========================================================================

# Hasil kalibrasi dari log pengujian lapangan:
#   pencocokan BENAR  -> 0.306 s/d 0.351
#   pencocokan SALAH  -> 0.502
#   orang tak terdaftar -> 0.666 s/d 0.684
# Maka 0.45 aman: masih menerima yang benar, menolak yang 0.502.
BATAS_TERIMA = 0.45

# Kandidat terbaik harus lebih unggul minimal sekian dari kandidat kedua.
# Kalau selisihnya tipis, artinya sistem ragu -> lebih baik ditandai Unknown.
SELISIH_MINIMAL = 0.06

YOLO_IMGSZ = 1024
YOLO_CONF = 0.15          # Longgar: untuk /predict, wajah jauh & banyak di kelas
YOLO_CONF_REGISTER = 0.5  # Ketat: untuk /register & muat dataset, foto dekat 1 orang.
                          # Mencegah objek buram di latar belakang (tas, bayangan)
                          # salah dikira wajah kedua saat registrasi.
PADDING_KOTAK = 0.15

# Kredensial email diambil dari environment variable, JANGAN ditulis di kode.
# Cara set di server:  export PASSWORD_APP="xxxx xxxx xxxx xxxx"
EMAIL_BOT = os.getenv("EMAIL_BOT", "")
PASSWORD_APP = os.getenv("PASSWORD_APP", "")
EMAIL_TUJUAN = os.getenv("EMAIL_TUJUAN", "")


def kirim_email_alert(pesan_error):
    if EMAIL_BOT == "" or PASSWORD_APP == "":
        print("[EMAIL] Dilewati, kredensial belum di-set di environment.", flush=True)
        return
    try:
        msg = EmailMessage()
        msg.set_content("Peringatan! Server AI mengalami error:\n\n" + pesan_error)
        msg['Subject'] = 'CRITICAL ERROR: Server Absensi AI'
        msg['From'] = EMAIL_BOT
        msg['To'] = EMAIL_TUJUAN

        server = smtplib.SMTP_SSL('smtp.gmail.com', 465)
        server.login(EMAIL_BOT, PASSWORD_APP)
        server.send_message(msg)
        server.quit()
        print("[EMAIL] Alert berhasil dikirim.", flush=True)
    except Exception as e:
        print("[EMAIL] Gagal mengirim alert: " + str(e), flush=True)


@app.exception_handler(Exception)
async def tangkap_semua_error(request: Request, exc: Exception):
    error_detail = traceback.format_exc()
    print("CRITICAL ERROR:\n" + error_detail, flush=True)
    asyncio.create_task(asyncio.to_thread(kirim_email_alert, error_detail))
    return JSONResponse(
        status_code=500,
        content={"message": "Terjadi kesalahan internal. Developer telah diberitahu."},
    )


# =========================================================================
# 1. INISIALISASI FIREBASE
# =========================================================================
print("Menghubungkan ke Firebase...", flush=True)
db = None
try:
    cred = credentials.Certificate("firebase-adminsdk.json")
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print("Berhasil terhubung ke Firebase Database.", flush=True)
except Exception as e:
    print("GAGAL terhubung ke Firebase: " + str(e), flush=True)


# =========================================================================
# 2. LOGIKA BACKUP BACKGROUND
# =========================================================================
def eksekusi_backup():
    try:
        collections_to_backup = ['users', 'classes', 'schedules', 'attendance', 'modules']
        backup_data = {}

        for col in collections_to_backup:
            docs = db.collection(col).stream()
            data_list = []
            for doc in docs:
                doc_data = doc.to_dict()
                doc_data['id'] = doc.id
                data_list.append(doc_data)
            backup_data[col] = data_list

        folder_backup = "backup_data"
        if not os.path.exists(folder_backup):
            os.makedirs(folder_backup)

        tanggal_hari_ini = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        nama_file = folder_backup + "/backup_sistem_" + tanggal_hari_ini + ".json"

        def default_serializer(obj):
            if hasattr(obj, 'isoformat'):
                return obj.isoformat()
            return str(obj)

        with open(nama_file, 'w') as f:
            json.dump(backup_data, f, default=default_serializer, indent=4)

        print("Backup SUKSES disimpan di: " + nama_file, flush=True)
    except Exception as e:
        print("Error saat Backup: " + str(e), flush=True)


async def jadwal_backup_malam():
    print("Worker Backup Latar Belakang AKTIF.", flush=True)
    while True:
        sekarang = datetime.now(timezone.utc)
        # JAM 13 UTC = JAM 20:00 WIB
        if sekarang.hour == 13 and 0 <= sekarang.minute <= 2:
            print("Waktunya Backup Jam 8 Malam.", flush=True)
            await asyncio.to_thread(eksekusi_backup)
            await asyncio.sleep(180)
        else:
            await asyncio.sleep(30)


@app.on_event("startup")
async def jalankan_background_worker():
    asyncio.create_task(jadwal_backup_malam())


process_lock = asyncio.Semaphore(2)


# =========================================================================
# PERSIAPAN MODEL YOLOv8
# =========================================================================
YOLO_MODEL_PATH = "yolov8n-face.pt"

if not os.path.exists(YOLO_MODEL_PATH):
    print("Mengunduh model YOLOv8 Face...", flush=True)
    try:
        url = "https://github.com/akanametov/yolo-face/releases/download/v0.0.0/yolov8n-face.pt"
        opener = urllib.request.build_opener()
        opener.addheaders = [('User-agent', 'Mozilla/5.0')]
        urllib.request.install_opener(opener)
        urllib.request.urlretrieve(url, YOLO_MODEL_PATH)
        print("Download sukses.", flush=True)
    except Exception as e:
        print("Gagal download model khusus. Error: " + str(e), flush=True)
        YOLO_MODEL_PATH = "yolov8n.pt"

yolo_detector = YOLO(YOLO_MODEL_PATH)

dataset_dir = "dataset_wajah"
known_face_encodings = []
known_face_names = []
known_face_nims = []

CACHE_FILE = "encoding_cache.pkl"


# =========================================================================
# FUNGSI BANTU: CACHE VEKTOR DATASET
# Dengan 180 siswa, menghitung ulang SEMUA vektor setiap kali server
# di-restart bisa memakan waktu lama. Fungsi ini membuat "sidik jari"
# dari daftar file + waktu modifikasinya; kalau dataset tidak berubah
# sejak terakhir dihitung, vektor dimuat dari cache (cepat), bukan
# dihitung ulang dari foto (lambat).
# =========================================================================
def hitung_fingerprint_dataset():
    daftar = []
    if not os.path.exists(dataset_dir):
        return "kosong"
    for student_folder in sorted(os.listdir(dataset_dir)):
        student_path = os.path.join(dataset_dir, student_folder)
        if not os.path.isdir(student_path):
            continue
        for filename in sorted(os.listdir(student_path)):
            filepath = os.path.join(student_path, filename)
            try:
                mtime = os.path.getmtime(filepath)
            except OSError:
                mtime = 0
            daftar.append(student_folder + "/" + filename + ":" + str(mtime))
    gabungan = "|".join(daftar)
    return hashlib.md5(gabungan.encode("utf-8")).hexdigest()


def hapus_cache():
    if os.path.exists(CACHE_FILE):
        try:
            os.remove(CACHE_FILE)
        except Exception as e:
            print("[CACHE] Gagal hapus cache: " + str(e), flush=True)


# =========================================================================
# FUNGSI BANTU 1: AMBIL KOTAK WAJAH (DIPAKAI BERSAMA)
# PENTING: fungsi ini dipakai oleh /predict, /register, DAN saat memuat
# dataset. Dulu ketiganya memakai cara berbeda sehingga vektor referensi
# dan vektor uji tidak berada di "ruang" yang sama. Itu ikut menyebabkan
# jarak antar-orang menjadi kabur.
# =========================================================================
def ambil_kotak_wajah(rgb_img, hasil_yolo):
    kotak_ui = []
    kotak_dlib = []
    img_h = rgb_img.shape[0]
    img_w = rgb_img.shape[1]

    for r in hasil_yolo:
        for box in r.boxes:
            x1, y1, x2, y2 = box.xyxy[0]
            x1 = int(x1)
            y1 = int(y1)
            x2 = int(x2)
            y2 = int(y2)

            kotak_ui.append([x1, y1, x2, y2])

            tinggi = y2 - y1
            lebar = x2 - x1
            pad_y = int(tinggi * PADDING_KOTAK)
            pad_x = int(lebar * PADDING_KOTAK)

            top = max(0, y1 - pad_y)
            bottom = min(img_h, y2 + pad_y)
            left = max(0, x1 - pad_x)
            right = min(img_w, x2 + pad_x)

            kotak_dlib.append((top, right, bottom, left))

    return kotak_ui, kotak_dlib


# =========================================================================
# FUNGSI BANTU 2: ROTASI CERDAS (SOLUSI MASALAH FOTO LANDSCAPE)
# EXIF sering dihapus oleh paket kamera Flutter, jadi jangan bergantung
# padanya. Di sini server mencoba 4 orientasi dan memilih yang paling
# banyak menghasilkan wajah.
# =========================================================================
def deteksi_dengan_rotasi_cerdas(rgb_img, conf=YOLO_CONF):
    daftar_kandidat = []
    daftar_kandidat.append((0, rgb_img))
    daftar_kandidat.append((90, cv2.rotate(rgb_img, cv2.ROTATE_90_CLOCKWISE)))
    daftar_kandidat.append((270, cv2.rotate(rgb_img, cv2.ROTATE_90_COUNTERCLOCKWISE)))
    daftar_kandidat.append((180, cv2.rotate(rgb_img, cv2.ROTATE_180)))

    sudut_terbaik = 0
    gambar_terbaik = rgb_img
    hasil_terbaik = None
    skor_terbaik = -1.0

    for sudut, gambar in daftar_kandidat:
        hasil = yolo_detector(gambar, imgsz=YOLO_IMGSZ, conf=conf, verbose=False)

        jumlah_wajah = 0
        total_conf = 0.0
        for r in hasil:
            for box in r.boxes:
                jumlah_wajah = jumlah_wajah + 1
                total_conf = total_conf + float(box.conf[0])

        # Wajah banyak lebih diutamakan daripada sekadar confidence tinggi
        skor = (jumlah_wajah * 10.0) + total_conf
        print("[ROTASI " + str(sudut) + "] wajah=" + str(jumlah_wajah) +
              " skor=" + str(round(skor, 2)), flush=True)

        if skor > skor_terbaik:
            skor_terbaik = skor
            sudut_terbaik = sudut
            gambar_terbaik = gambar
            hasil_terbaik = hasil

        # Berhenti begitu SATU orientasi menemukan jumlah wajah yang masuk akal
        # (bukan hanya saat sudut == 0). Ini penting untuk server 4GB/2vCPU:
        # tanpa ini, SETIAP foto landscape memicu 4x pemanggilan YOLO penuh
        # karena orientasi 0 derajat selalu gagal duluan pada foto landscape.
        if jumlah_wajah >= 2:
            print("[ROTASI] Orientasi " + str(sudut) + " sudah cukup baik, "
                  "pencarian dihentikan lebih awal.", flush=True)
            break

    return sudut_terbaik, gambar_terbaik, hasil_terbaik


# =========================================================================
# FUNGSI BANTU 3: PRA-PEMROSESAN GAMBAR (EXIF + CLAHE)
# =========================================================================
def siapkan_gambar(contents):
    pil_img = Image.open(io.BytesIO(contents))
    pil_img = ImageOps.exif_transpose(pil_img)
    pil_img = pil_img.convert("RGB")
    rgb_img = np.array(pil_img)

    lab_img = cv2.cvtColor(rgb_img, cv2.COLOR_RGB2LAB)
    l, a, b = cv2.split(lab_img)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    cl = clahe.apply(l)
    limg = cv2.merge((cl, a, b))
    rgb_img = cv2.cvtColor(limg, cv2.COLOR_LAB2RGB)

    return rgb_img


# =========================================================================
# MEMUAT DATASET: SATU SISWA = SATU VEKTOR RATA-RATA
# Dulu setiap foto variasi menjadi satu vektor terpisah, sehingga siswa
# dengan foto terbanyak lebih sering "menang" saat argmin. Sekarang setiap
# siswa punya bobot yang sama persis.
# =========================================================================
def muat_ulang_dataset(paksa_hitung_ulang=False):
    known_face_encodings.clear()
    known_face_names.clear()
    known_face_nims.clear()

    if not os.path.exists(dataset_dir):
        os.makedirs(dataset_dir)

    fingerprint_sekarang = hitung_fingerprint_dataset()

    # Coba muat dari cache dulu kalau dataset belum berubah
    if not paksa_hitung_ulang and os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "rb") as f:
                cache = pickle.load(f)
            if cache.get("fingerprint") == fingerprint_sekarang:
                known_face_encodings.extend(cache["encodings"])
                known_face_names.extend(cache["names"])
                known_face_nims.extend(cache["nims"])
                print("[CACHE] Dataset dimuat dari cache: " + str(len(known_face_names)) +
                      " siswa (tidak dihitung ulang, dataset belum berubah).", flush=True)
                return
            else:
                print("[CACHE] Dataset berubah sejak cache terakhir, hitung ulang.", flush=True)
        except Exception as e:
            print("[CACHE] Gagal baca cache, hitung ulang dari awal: " + str(e), flush=True)

    print("Memuat dataset wajah...", flush=True)

    for student_folder in os.listdir(dataset_dir):
        student_path = os.path.join(dataset_dir, student_folder)
        if not os.path.isdir(student_path):
            continue

        try:
            parts = student_folder.split("_")
            nim = parts[0]
            nama = parts[1] if len(parts) > 1 else "Unknown"

            kumpulan_vektor = []

            for filename in os.listdir(student_path):
                if not filename.lower().endswith((".jpg", ".jpeg", ".png")):
                    continue

                filepath = os.path.join(student_path, filename)
                image = face_recognition.load_image_file(filepath)

                hasil = yolo_detector(image, imgsz=YOLO_IMGSZ, conf=YOLO_CONF_REGISTER, verbose=False)
                kotak_ui, kotak_dlib = ambil_kotak_wajah(image, hasil)

                if len(kotak_dlib) != 1:
                    print("  [LEWAT] " + filename + " berisi " +
                          str(len(kotak_dlib)) + " wajah, harus tepat 1. Kotak: " +
                          str(kotak_ui), flush=True)
                    continue

                # num_jitters=3 hanya di sini, karena cuma dijalankan sekali
                enc = face_recognition.face_encodings(image, kotak_dlib, num_jitters=3)[0]
                kumpulan_vektor.append(enc)

            if len(kumpulan_vektor) > 0:
                vektor_rata = np.mean(kumpulan_vektor, axis=0)
                known_face_encodings.append(vektor_rata)
                known_face_names.append(nama)
                known_face_nims.append(nim)
                print("[SIAP] " + nama + " (" + nim + ") dari " +
                      str(len(kumpulan_vektor)) + " foto variasi", flush=True)
            else:
                print("[KOSONG] " + student_folder + " tidak ada foto valid.", flush=True)

        except Exception as e:
            print("[ERROR] Gagal memuat folder " + student_folder + ": " + str(e), flush=True)

    print("Total siswa siap di RAM: " + str(len(known_face_names)) + " orang.", flush=True)

    # Simpan hasil hitungan ke cache supaya restart berikutnya lebih cepat
    try:
        with open(CACHE_FILE, "wb") as f:
            pickle.dump({
                "fingerprint": fingerprint_sekarang,
                "encodings": known_face_encodings,
                "names": known_face_names,
                "nims": known_face_nims,
            }, f)
        print("[CACHE] Cache dataset disimpan untuk restart berikutnya.", flush=True)
    except Exception as e:
        print("[CACHE] Gagal simpan cache: " + str(e), flush=True)


muat_ulang_dataset()


# =========================================================================
# API 1: PREDIKSI (ABSENSI KELAS MULTI-WAJAH)
# =========================================================================
@app.post("/predict")
@limiter.limit("60/minute")
async def predict_face(request: Request, file: UploadFile = None):
    async with process_lock:
        try:
            contents = None
            if file is not None:
                if file.content_type not in ["image/jpeg", "image/png", "image/jpg"]:
                    return {"data": [], "error": "Format ditolak! Hanya menerima JPG atau PNG."}
                contents = await file.read()
            else:
                contents = await request.body()

            if not contents:
                return {"data": [], "error": "Tidak ada gambar yang diterima."}

            rgb_img = siapkan_gambar(contents)

            # SOLUSI MASALAH FOTO HORIZONTAL
            sudut, gambar_dipakai, hasil_yolo = deteksi_dengan_rotasi_cerdas(rgb_img)

            if hasil_yolo is None:
                return {"data": [], "rotasi": 0, "error": "Tidak ada wajah terdeteksi."}

            kotak_ui, kotak_dlib = ambil_kotak_wajah(gambar_dipakai, hasil_yolo)

            if len(kotak_dlib) == 0:
                return {"data": [], "rotasi": sudut}

            semua_encoding = face_recognition.face_encodings(
                gambar_dipakai, kotak_dlib, num_jitters=1
            )

            # Siapkan hasil default: semua Unknown dulu
            hasil_akhir = []
            for i in range(len(semua_encoding)):
                hasil_akhir.append({
                    "nim": "Unknown",
                    "name": "Unknown",
                    "box": kotak_ui[i]
                })

            if len(known_face_encodings) == 0:
                return {"data": hasil_akhir, "rotasi": sudut}

            # -----------------------------------------------------------
            # TAHAP 1: kumpulkan kandidat yang lolos ambang + uji selisih
            # -----------------------------------------------------------
            daftar_pasangan = []

            for i in range(len(semua_encoding)):
                jarak_semua = face_recognition.face_distance(known_face_encodings, semua_encoding[i])
                urutan = np.argsort(jarak_semua)

                idx_terbaik = urutan[0]
                jarak_terbaik = jarak_semua[idx_terbaik]

                if len(urutan) > 1:
                    jarak_kedua = jarak_semua[urutan[1]]
                    selisih = jarak_kedua - jarak_terbaik
                else:
                    selisih = 999.0

                if jarak_terbaik >= BATAS_TERIMA:
                    print("[TOLAK JAUH] wajah-" + str(i) + " jarak=" +
                          str(round(float(jarak_terbaik), 3)), flush=True)
                    continue

                if selisih < SELISIH_MINIMAL:
                    print("[TOLAK RAGU] wajah-" + str(i) + " jarak=" +
                          str(round(float(jarak_terbaik), 3)) + " selisih=" +
                          str(round(float(selisih), 3)), flush=True)
                    continue

                daftar_pasangan.append((float(jarak_terbaik), i, int(idx_terbaik)))

            # -----------------------------------------------------------
            # TAHAP 2: urutkan dari yang paling mirip
            # -----------------------------------------------------------
            daftar_pasangan.sort(key=lambda x: x[0])

            # -----------------------------------------------------------
            # TAHAP 3: bagikan identitas, satu siswa hanya boleh satu kali
            # INI YANG MENCEGAH "BUDI SANTOSO" MUNCUL DUA KALI
            # -----------------------------------------------------------
            wajah_terpakai = []
            nim_terpakai = []

            for jarak, i, idx in daftar_pasangan:
                if i in wajah_terpakai:
                    continue

                if known_face_nims[idx] in nim_terpakai:
                    print("[TOLAK GANDA] " + known_face_names[idx] +
                          " sudah dipakai wajah lain (jarak=" +
                          str(round(jarak, 3)) + ")", flush=True)
                    continue

                hasil_akhir[i]["nim"] = known_face_nims[idx]
                hasil_akhir[i]["name"] = known_face_names[idx]
                wajah_terpakai.append(i)
                nim_terpakai.append(known_face_nims[idx])

                print("[BERHASIL KENAL] " + known_face_names[idx] +
                      " (Mirip: " + str(round(jarak, 3)) + ")", flush=True)

            return {"data": hasil_akhir, "rotasi": sudut}

        except Exception as e:
            print("[ERROR API PREDIKSI]: " + str(e), flush=True)
            return {"data": [], "error": str(e)}


# =========================================================================
# API 2: REGISTRASI
# =========================================================================
@app.post("/register")
@limiter.limit("30/minute")
async def register_student(
    request: Request,
    nim: str = Form(...),
    name: str = Form(...),
    variasi: str = Form("1"),
    file: UploadFile = File(...)
):
    try:
        if file.content_type not in ["image/jpeg", "image/png", "image/jpg"]:
            return {"status": "error", "message": "Format ditolak! Hanya menerima JPG/PNG."}

        contents = await file.read()
        rgb_img = siapkan_gambar(contents)

        # Foto registrasi juga diputar otomatis kalau perlu.
        # Pakai YOLO_CONF_REGISTER (lebih ketat) karena foto registrasi selalu
        # jarak dekat 1 orang -- ambang longgar /predict rawan salah kira
        # objek buram di latar belakang sebagai wajah kedua.
        sudut, gambar_dipakai, hasil_yolo = deteksi_dengan_rotasi_cerdas(
            rgb_img, conf=YOLO_CONF_REGISTER
        )

        if hasil_yolo is None:
            return {"status": "error", "message": "Wajah tidak terdeteksi. Geser ke tempat terang."}

        kotak_ui, kotak_dlib = ambil_kotak_wajah(gambar_dipakai, hasil_yolo)

        if len(kotak_dlib) == 0:
            return {"status": "error", "message": "Wajah tidak terdeteksi. Geser ke tempat terang."}
        if len(kotak_dlib) > 1:
            print("[REGISTER TOLAK] " + name + " (" + nim + ") terdeteksi " +
                  str(len(kotak_dlib)) + " wajah. Koordinat kotak: " + str(kotak_ui), flush=True)
            return {"status": "error", "message": "Lebih dari 1 wajah terdeteksi! Pastikan hanya 1 siswa."}

        folder_murid = dataset_dir + "/" + nim + "_" + name
        if not os.path.exists(folder_murid):
            os.makedirs(folder_murid)

        # Simpan foto dalam orientasi yang SUDAH benar
        bgr_simpan = cv2.cvtColor(gambar_dipakai, cv2.COLOR_RGB2BGR)
        nama_file_baru = folder_murid + "/" + variasi + ".jpg"
        cv2.imwrite(nama_file_baru, bgr_simpan)

        # Hitung ulang vektor rata-rata siswa ini saja (bukan seluruh dataset,
        # supaya cepat). Vektor lama dengan NIM sama dihapus dulu agar tidak dobel.
        indeks_hapus = []
        for i in range(len(known_face_nims)):
            if known_face_nims[i] == nim:
                indeks_hapus.append(i)
        for i in sorted(indeks_hapus, reverse=True):
            known_face_encodings.pop(i)
            known_face_names.pop(i)
            known_face_nims.pop(i)

        kumpulan_vektor = []
        for filename in os.listdir(folder_murid):
            if not filename.lower().endswith((".jpg", ".jpeg", ".png")):
                continue
            filepath = os.path.join(folder_murid, filename)
            image = face_recognition.load_image_file(filepath)
            hasil = yolo_detector(image, imgsz=YOLO_IMGSZ, conf=YOLO_CONF_REGISTER, verbose=False)
            k_ui, k_dlib = ambil_kotak_wajah(image, hasil)
            if len(k_dlib) == 1:
                enc = face_recognition.face_encodings(image, k_dlib, num_jitters=3)[0]
                kumpulan_vektor.append(enc)

        if len(kumpulan_vektor) > 0:
            vektor_rata = np.mean(kumpulan_vektor, axis=0)
            known_face_encodings.append(vektor_rata)
            known_face_names.append(name)
            known_face_nims.append(nim)

        # Cache dihapus supaya restart berikutnya menghitung ulang dengan
        # data terbaru (termasuk siswa yang baru saja didaftarkan ini).
        hapus_cache()

        return {
            "status": "success",
            "message": "Foto variasi ke-" + variasi + " milik " + name +
                       " berhasil didaftarkan. Total variasi: " + str(len(kumpulan_vektor))
        }

    except Exception as e:
        return {"status": "error", "message": str(e)}


# =========================================================================
# API 3: STATUS SERVER
# =========================================================================
@app.get("/")
def home():
    return {
        "message": "Server Absensi AI Aktif (Rotasi Cerdas + Penugasan Unik)",
        "total_siswa": len(known_face_names),
        "batas_terima": BATAS_TERIMA
    }


# =========================================================================
# API 4: MONITOR SERVER
# =========================================================================
@app.get("/server-monitor")
def monitor_server_sekarang():
    ram = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=1)
    disk = psutil.disk_usage('/')
    jumlah_murid = len(known_face_names)

    return {
        "status": "online",
        "cpu_usage_percent": cpu,
        "ram_sisa_mb": round(ram.available / (1024 * 1024), 2),
        "disk_terpakai_percent": disk.percent,
        "total_murid_terdaftar": jumlah_murid
    }


# =========================================================================
# API 5: MELIHAT DAFTAR BACKUP
# =========================================================================
@app.get("/list-backup")
def get_backup_list():
    folder_backup = "backup_data"
    if not os.path.exists(folder_backup):
        return {"status": "success", "data": [], "message": "Belum ada backup."}

    semua_file = os.listdir(folder_backup)
    file_json = []
    for f in semua_file:
        if f.endswith('.json'):
            file_json.append(f)
    file_json.sort(reverse=True)

    return {"status": "success", "data": file_json}


# =========================================================================
# API 6: DOWNLOAD FILE BACKUP (sudah diamankan dari path traversal)
# =========================================================================
@app.get("/download-backup/{nama_file}")
def download_backup_file(nama_file: str):
    # os.path.basename membuang "../" sehingga hanya nama file murni yang dipakai
    nama_bersih = os.path.basename(nama_file)

    if not nama_bersih.endswith(".json"):
        return {"status": "error", "message": "Hanya file .json yang boleh diunduh."}
    if not nama_bersih.startswith("backup_sistem_"):
        return {"status": "error", "message": "File bukan berkas backup."}

    file_path = os.path.join("backup_data", nama_bersih)
    if os.path.exists(file_path):
        return FileResponse(file_path, media_type='application/json', filename=nama_bersih)
    return {"status": "error", "message": "File tidak ditemukan!"}


# =========================================================================
# API 7: PAKSA BACKUP SEKARANG
# =========================================================================
@app.get("/force-backup")
async def force_backup_sekarang():
    try:
        print("Menerima perintah Backup Manual...", flush=True)
        await asyncio.to_thread(eksekusi_backup)
        return {"status": "success", "message": "Backup berhasil dieksekusi secara manual!"}
    except Exception as e:
        print("Error Backup Manual: " + str(e), flush=True)
        return {"status": "error", "message": "Gagal backup: " + str(e)}


# =========================================================================
# API 8: MUAT ULANG DATASET TANPA RESTART SERVER (BARU)
# =========================================================================
@app.get("/reload-dataset")
async def reload_dataset():
    # paksa_hitung_ulang=True: admin minta reload manual, selalu hitung ulang
    # dari foto asli, jangan pakai cache lama.
    await asyncio.to_thread(muat_ulang_dataset, True)
    return {"status": "success", "total_siswa": len(known_face_names)}
kalo server gak bisa real time ini solusi saya tapi 
(Coba pelajari proses deteksi dengan YOLOv8n-Face trus di ekstraksi fitur (dlib ResNet) ini dilakukan 100% lokal di dalam smartphone pengguna (menggunakan TensorFlow Lite atau ONNX Runtime yang diintegrasikan ke Flutter), bukan dikirim ke server cloud.)
ini kata dosbim saya
</USER_REQUEST>
<ADDITIONAL_METADATA>
The current local time is: 2026-09-30T00:52:47+07:00.
</ADDITIONAL_METADATA>
<USER_SETTINGS_CHANGE>
The user changed setting `Model Selection` from None to Claude Opus 4.6 (Thinking). No need to comment on this change if the user doesn't ask about it. If reporting what model you are, please use a human readable name instead of the exact string.
</USER_SETTINGS_CHANGE>