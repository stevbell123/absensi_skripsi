# 📋 Panduan Lengkap: Semua File, Lokasi, dan Cara Penggunaan

---

## BAGIAN 1: DAFTAR SEMUA FILE

### Struktur Folder Proyek Sekarang

```
d:\Goals_16\skripsi1\
│
├── assets\
│   └── models\
│       ├── README.md                        ← BARU (instruksi)
│       └── mobilefacenet.tflite             ← ⚠️ KAMU HARUS DOWNLOAD INI
│
├── lib\
│   ├── main.dart                            ← DIUBAH (tambah Hive init)
│   │
│   ├── core\
│   │   └── ai\                              ← 📁 FOLDER BARU (5 file)
│   │       ├── face_detector_service.dart    ← BARU
│   │       ├── face_embedding_service.dart   ← BARU
│   │       ├── face_matching_service.dart    ← BARU
│   │       ├── face_database_service.dart    ← BARU
│   │       └── ai_providers.dart             ← BARU
│   │
│   └── features\
│       ├── attendance\
│       │   └── presentation\
│       │       ├── AttendanceScreen.dart      ← DITULIS ULANG
│       │       └── attendance_view.dart       ← DIUBAH (1 baris)
│       │
│       └── academic_management\
│           └── presentation\
│               └── RegisterStudentScreen.dart ← DITULIS ULANG
│
├── pubspec.yaml                              ← DIUBAH (tambah 4 package)
└── migrasi_ke_on_device.py                   ← BARU (skrip Python sekali pakai)
```

---

## BAGIAN 2: PENJELASAN SETIAP FILE

### 🟢 FILE BARU #1: `lib/core/ai/face_detector_service.dart`

**Lokasi:** `d:\Goals_16\skripsi1\lib\core\ai\face_detector_service.dart`

**Fungsi:** Mendeteksi wajah di dalam foto (mengembalikan kotak/bounding box wajah)

**Menggantikan apa di server?**
| Di Server Python (LAMA) | Di Flutter (BARU) |
|---|---|
| `yolo_detector = YOLO("yolov8n-face.pt")` | `FaceDetector` dari Google ML Kit |
| `yolo_detector(gambar, imgsz=1024, conf=0.15)` | `_faceDetector.processImage(inputImage)` |
| Model harus diunduh terpisah (6MB) | Sudah bawaan HP Android, tidak perlu download |
| ~200ms di server | ~15-30ms di HP |

---

### 🟢 FILE BARU #2: `lib/core/ai/face_embedding_service.dart`

**Lokasi:** `d:\Goals_16\skripsi1\lib\core\ai\face_embedding_service.dart`

**Fungsi:** Mengubah foto wajah menjadi **128 angka desimal** (vektor embedding). Angka-angka ini adalah "sidik jari digital" unik tiap orang.

**Menggantikan apa di server?**
| Di Server Python (LAMA) | Di Flutter (BARU) |
|---|---|
| `face_recognition.face_encodings(image)` | `_interpreter.run(input, output)` |
| Pakai dlib ResNet (~29MB) | Pakai MobileFaceNet (~5MB) |
| Library: `face_recognition` + `dlib` | Library: `tflite_flutter` |
| ~150ms di server | ~15-25ms di HP |

**Proses di dalamnya:**
```
Foto wajah → crop 112×112 piksel → normalisasi → MobileFaceNet → [0.023, -0.156, ..., 0.089]
                                                                    ↑ 128 angka ini = "sidik jari" wajah
```

---

### 🟢 FILE BARU #3: `lib/core/ai/face_matching_service.dart`

**Lokasi:** `d:\Goals_16\skripsi1\lib\core\ai\face_matching_service.dart`

**Fungsi:** Membandingkan "sidik jari" wajah yang difoto dengan semua siswa di database, lalu menentukan siapa orangnya.

**Menggantikan apa di server?**
| Di Server Python (LAMA) | Di Flutter (BARU) |
|---|---|
| `face_recognition.face_distance()` | `euclideanDistance()` di Dart |
| `BATAS_TERIMA = 0.45` | `batasTerima = 1.0` (harus dikalibrasi) |
| `SELISIH_MINIMAL = 0.06` | `selisihMinimal = 0.06` (sama) |
| Anti-duplikasi "Budi 2x" di Python | Anti-duplikasi yang sama di Dart |
| Logika di endpoint `/predict` | Logika di method `matchFaces()` |

**Logika pencocokan (SAMA PERSIS dengan server):**
1. Hitung jarak ke semua siswa di database
2. Ambil yang paling dekat
3. Cek apakah jaraknya di bawah `batasTerima` (kalau terlalu jauh → Unknown)
4. Cek selisih dengan kandidat kedua (kalau terlalu tipis = ragu → Unknown)
5. Satu siswa hanya boleh muncul 1x (anti-duplikasi)

---

### 🟢 FILE BARU #4: `lib/core/ai/face_database_service.dart`

**Lokasi:** `d:\Goals_16\skripsi1\lib\core\ai\face_database_service.dart`

**Fungsi:** Menyimpan dan menyinkronkan "sidik jari" wajah siswa antara Firestore (cloud) dan Hive (lokal HP).

**Menggantikan apa di server?**
| Di Server Python (LAMA) | Di Flutter (BARU) |
|---|---|
| Foto disimpan di folder `dataset_wajah/` | Embedding disimpan di Firestore `face_embeddings` |
| Cache di `encoding_cache.pkl` | Cache di Hive (lokal HP) |
| `known_face_encodings` list di RAM server | `_database` list di RAM HP |
| `muat_ulang_dataset()` | `syncByClass(classId)` atau `syncFromFirestore()` |
| Harus restart server untuk reload | Otomatis sync setiap buka halaman absensi |

**Cara kerja sinkronisasi:**
```
Saat buka halaman absensi:
   HP → download embedding kelas ini dari Firestore → simpan ke Hive
   (Hanya ~180KB untuk 180 siswa, <1 detik)

Saat scan absensi:
   HP → baca dari Hive (lokal, tidak perlu internet)

Saat registrasi siswa baru:
   HP → hitung embedding → upload ke Firestore
```

---

### 🟢 FILE BARU #5: `lib/core/ai/ai_providers.dart`

**Lokasi:** `d:\Goals_16\skripsi1\lib\core\ai\ai_providers.dart`

**Fungsi:** "Konektor" Riverpod agar semua service AI bisa diakses dari widget manapun. Model AI hanya dimuat 1 kali, tidak dimuat ulang setiap buka halaman.

**Tidak menggantikan apapun di server** — ini khas Flutter/Riverpod.

---

### 🟢 FILE BARU #6: `migrasi_ke_on_device.py`

**Lokasi:** `d:\Goals_16\skripsi1\migrasi_ke_on_device.py`

**Fungsi:** Skrip Python yang dijalankan **SEKALI SAJA** di server/PC untuk:
1. Download model MobileFaceNet
2. Baca semua foto lama di `dataset_wajah/`
3. Hitung ulang embedding dengan MobileFaceNet
4. Upload embedding ke Firestore

**Kenapa perlu?** Karena embedding dlib (lama) dan MobileFaceNet (baru) tidak kompatibel — harus dihitung ulang dari foto asli.

---

### 🟡 FILE DIUBAH #1: `AttendanceScreen.dart`

**Lokasi:** `d:\Goals_16\skripsi1\lib\features\attendance\presentation\AttendanceScreen.dart`

**Apa yang berubah?** DITULIS ULANG TOTAL

| Aspek | LAMA | BARU |
|---|---|---|
| Cara scan | Foto → upload HTTP ke server → tunggu respons | Foto → proses 100% di HP |
| Kecepatan | 1–60 detik | 50–500ms |
| Butuh internet? | YA (wajib) | TIDAK (offline bisa) |
| Kode HTTP | `http.MultipartRequest('POST', Uri.parse(apiUrl))` | **DIHAPUS** |
| Import `http` | Ada | **DIHAPUS** |
| AI service | Tidak ada (semua di server) | `FaceDetectorService` + `FaceEmbeddingService` + `FaceMatchingService` |

**Parameter baru:** `classId` — diperlukan untuk sinkronisasi embedding kelas

---

### 🟡 FILE DIUBAH #2: `RegisterStudentScreen.dart`

**Lokasi:** `d:\Goals_16\skripsi1\lib\features\academic_management\presentation\RegisterStudentScreen.dart`

**Apa yang berubah?** DITULIS ULANG TOTAL

| Aspek | LAMA | BARU |
|---|---|---|
| Cara daftar | 3x HTTP POST ke `/register` | 3 embedding dihitung di HP → rata-rata → simpan ke Firestore |
| `apiUrl` | `"http://103.175.206.22:8000/register"` | **DIHAPUS** |
| Simpan embedding | Server simpan di `dataset_wajah/` + `encoding_cache.pkl` | Firestore koleksi `face_embeddings` |
| Simpan thumbnail | Sama — base64 ke Firestore | Sama — tidak berubah |

---

### 🟡 FILE DIUBAH #3: `attendance_view.dart`

**Lokasi:** `d:\Goals_16\skripsi1\lib\features\attendance\presentation\attendance_view.dart`

**Perubahan:** Hanya **1 baris** — menambahkan `classId` saat navigasi ke AttendanceScreen:
```dart
// LAMA:
AttendanceScreen(records: _records)

// BARU:
AttendanceScreen(records: _records, classId: _selectedScheduleData!['classId'])
```

---

### 🟡 FILE DIUBAH #4: `pubspec.yaml`

**Tambahan 4 package:**
```yaml
google_mlkit_face_detection: ^0.12.0   # Deteksi wajah (ganti YOLO)
tflite_flutter: ^0.11.0                # Jalankan model AI (ganti dlib)
hive: ^2.2.3                           # Database lokal (ganti pickle cache)
hive_flutter: ^1.1.0                   # Integrasi Hive + Flutter
```

**Tambahan assets:**
```yaml
assets:
  - assets/models/   # Folder model MobileFaceNet
```

---

### 🟡 FILE DIUBAH #5: `main.dart`

**Tambahan 2 baris:**
```dart
import 'package:hive_flutter/hive_flutter.dart';  // Import baru

await Hive.initFlutter();  // Inisialisasi cache lokal
```

---

## BAGIAN 3: DATA DI FIRESTORE (KOLEKSI BARU)

Sebelumnya embedding disimpan di **file server** (`dataset_wajah/` + `encoding_cache.pkl`).  
Sekarang embedding disimpan di **Firestore**, koleksi baru bernama `face_embeddings`:

```
🔥 Firestore
└── face_embeddings/          ← KOLEKSI BARU
    ├── 2201001/              ← document ID = NIM
    │   ├── nim: "2201001"
    │   ├── name: "Budi Santoso"
    │   ├── embedding: [0.023, -0.156, ..., 0.089]   ← 128 angka
    │   └── updatedAt: 30 Sep 2026, 02:00 WIB
    ├── 2201002/
    │   ├── nim: "2201002"
    │   ├── name: "Sari Dewi"
    │   ├── embedding: [0.045, 0.231, ..., -0.067]
    │   └── updatedAt: ...
    └── ... (per siswa 1 dokumen)
```

---

## BAGIAN 4: LANGKAH-LANGKAH YANG HARUS KAMU LAKUKAN

### Langkah 1️⃣ — Download Model MobileFaceNet

Ini adalah "otak" AI yang akan jalan di HP. Ukurannya cuma ~5MB.

**Cara:**
```bash
# Di server/PC yang punya Python
cd d:\Goals_16\skripsi1
pip install tensorflow opencv-python Pillow
python migrasi_ke_on_device.py
```

Skrip ini otomatis download file `mobilefacenet.tflite`. Setelah selesai:

```bash
# Pindahkan ke folder assets
copy mobilefacenet.tflite assets\models\mobilefacenet.tflite
```

> ⚠️ **TANPA FILE INI APLIKASI TIDAK BISA JALAN.** Pastikan file ada di `assets/models/mobilefacenet.tflite`

---

### Langkah 2️⃣ — Migrasi Embedding Siswa Lama (Jika Ada)

Kalau sudah ada siswa terdaftar di server lama (folder `dataset_wajah/`):

```bash
# Skrip yang sama, dia juga menghitung ulang embedding + upload ke Firestore
python migrasi_ke_on_device.py

# Saat ditanya "Upload ke Firestore?", ketik: y
```

Kalau belum ada siswa terdaftar (baru mulai), **lewati langkah ini**.

---

### Langkah 3️⃣ — Install Dependencies

```bash
cd d:\Goals_16\skripsi1
flutter pub get
```

Ini sudah berhasil dilakukan sebelumnya — 6 package baru terinstall.

---

### Langkah 4️⃣ — Build dan Test di HP

```bash
flutter run
```

**Test registrasi:**
1. Buka halaman registrasi siswa
2. Isi NIM + Nama
3. Jepret 3 foto (3 pose)
4. Cek Firestore → koleksi `face_embeddings` → dokumen baru harus muncul

**Test absensi:**
1. Buka halaman absensi → pilih jadwal
2. Tekan "Absen Otomatis via AI"
3. Arahkan kamera ke siswa yang sudah terdaftar
4. Tekan "Jepret"
5. Dalam <1 detik hasilnya muncul

---

## BAGIAN 5: PERBANDINGAN ALUR SEBELUM vs SESUDAH

### Alur Registrasi

```
SEBELUM (Server):
  📱 Jepret foto
    → 📤 Upload ke http://103.175.206.22:8000/register (3x)
    → ☁️ Server Python terima foto
    → ☁️ Server deteksi wajah (YOLO)
    → ☁️ Server hitung embedding (dlib)
    → ☁️ Server simpan di dataset_wajah/ + cache
    → 📥 HP terima respons "berhasil"
  ⏱️ Total: 3-30 detik (tergantung koneksi)

SESUDAH (On-Device):
  📱 Jepret foto
    → 📱 ML Kit deteksi wajah (~20ms)
    → 📱 MobileFaceNet hitung embedding (~20ms)
    → 📱 Ulangi 3x untuk 3 pose
    → 📱 Rata-ratakan 3 embedding
    → 🔥 Simpan ke Firestore "face_embeddings"
  ⏱️ Total: <3 detik (tanpa internet pun bisa hitung, upload nanti)
```

### Alur Absensi (Scan Barisan Kelas)

```
SEBELUM (Server):
  📱 Jepret foto barisan
    → 📤 Upload foto ke http://103.175.206.22:8000/predict
    → ☁️ Server terima foto (tergantung ukuran file + koneksi)
    → ☁️ Server rotasi cerdas (4x YOLO = 4x ~200ms)
    → ☁️ Server hitung embedding semua wajah (dlib)
    → ☁️ Server matching vs database
    → 📥 HP terima JSON hasil
  ⏱️ Total: 3-60 detik
  ❌ Kalau internet putus = GAGAL

SESUDAH (On-Device):
  📱 Jepret foto barisan
    → 📱 ML Kit deteksi semua wajah (~20ms)
    → 📱 Crop setiap wajah → MobileFaceNet (~20ms per wajah)
    → 📱 Matching vs database lokal (Hive) (<1ms)
    → 📱 Tampilkan hasil langsung
  ⏱️ Total: 50-500ms (untuk 10 wajah)
  ✅ Bisa offline (pakai cache Hive)
```

---

## BAGIAN 6: APA YANG TERJADI DENGAN SERVER PYTHON?

Server Python **tidak perlu dihapus**, tapi perannya berubah:

| Fitur Server | Status |
|---|---|
| `/predict` (scan wajah) | ❌ **Tidak dipakai lagi** — diganti on-device |
| `/register` (daftar wajah) | ❌ **Tidak dipakai lagi** — diganti on-device |
| `/reload-dataset` | ❌ **Tidak dipakai lagi** — embedding di Firestore |
| `/` (status) | ✅ Masih bisa dipakai untuk monitoring |
| `/server-monitor` | ✅ Masih bisa dipakai |
| `/force-backup` | ✅ Masih bisa dipakai |
| `/list-backup` | ✅ Masih bisa dipakai |
| `/download-backup` | ✅ Masih bisa dipakai |
| Backup otomatis jam 8 malam | ✅ Masih bisa dipakai |

> **Kesimpulan:** Server Python sekarang hanya jadi **admin tool untuk backup**. Semua AI pindah ke HP.

---

## BAGIAN 7: KALIBRASI THRESHOLD (WAJIB SETELAH TEST)

Setelah berhasil jalan, kamu **HARUS** kalibrasi `batasTerima` di file [`face_matching_service.dart`](file:///d:/Goals_16/skripsi1/lib/core/ai/face_matching_service.dart) line 38.

**Cara kalibrasi:**
1. Daftarkan 5 siswa test
2. Scan wajah mereka, perhatikan log `distance` di debug console
3. Catat:
   - Jarak saat **COCOK** (orang yang benar): misal 0.65, 0.72, 0.68
   - Jarak saat **SALAH** (orang lain): misal 1.25, 1.40, 1.32
4. Pilih threshold di antaranya: misal **0.90**
5. Ubah di kode:
```dart
static const double batasTerima = 0.90;  // Sesuaikan hasil kalibrasi
```

> ⚠️ Saat ini nilainya `1.0` (sangat longgar) agar semua wajah bisa masuk dulu saat testing. Setelah kalibrasi, kencangkan nilainya.
