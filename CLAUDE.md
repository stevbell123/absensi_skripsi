# CLAUDE.md — Konteks Proyek SIAP (Skripsi Presensi Wajah On-Device)

Berkas ini untuk asisten AI (Claude Code) yang melanjutkan pekerjaan di repo ini.
Bahasa kerja tim: **Bahasa Indonesia**. Jawab pengguna dalam Bahasa Indonesia.

## Aturan kerja (wajib)
- **Tanya dulu sebelum mengubah kode.** Jelaskan rencana perubahan, tunggu persetujuan.
- **Jangan mengubah berkas naskah milik tim** (`BAB *.docx`). Bila perlu dokumen, buat berkas baru.
- **Jangan pernah meng-commit:** foto dataset (`dataset_*/`), `padanan_kode_siswa_RAHASIA.csv`,
  log penelitian berisi data siswa, `android/key.properties`, `*.jks`. Stage berkas satu per satu,
  jangan `git add .`.
- Laporkan hasil apa adanya; bedakan yang sudah diuji dan yang belum.

## Tentang penelitian
Tim: Steven David Hasiholan Malau, Wan Saka Nasa, William Patar Wijaya Marpaung.
Mitra: SDN 116897 Hapoltakan Nauli. Perangkat uji: Samsung Galaxy S10 (Android 12).

Pipeline (semua di HP, tanpa server): ML Kit (fast, minFaceSize 0.1) → crop padding 15% →
112×112 bicubic → [CLAHE kanal Y, grid 8×8, clip 2.0] → MobileFaceNet (192-d, L2) →
jarak Euclidean. Diterima bila d₁ ≤ τ, dan pada skenario margin juga d₂ − d₁ ≥ δ.
Nilai awal τ = 1.0, δ = 0.06; nilai akhir ditetapkan dari data validasi.

- **RM 1:** pengaruh CLAHE per kondisi cahaya + latensi (A vs B, C vs D).
- **RM 2:** verifikasi margin vs ambang tunggal pada FAR, FRR, MIR (A vs C, B vs D).
- **RM 3:** konfigurasi terbaik vs absen manual di kelas (Eksperimen 3, 6 sesi).
- Skenario: A = tanpa CLAHE tanpa margin, B = CLAHE, C = margin, D = CLAHE + margin.
- Data: 25 siswa terdaftar + 5 tidak terdaftar. Registrasi 25, validasi 60, uji 300
  (per siswa uji: 5 memadai; absen 1–15 → 3 low-light + 2 backlight, absen 16–30 → 2 + 3).
- Penetapan (data validasi saja): τ = nilai terbesar 0.50–1.50 dengan FAR validasi 0%;
  δ = nilai terbesar 0.00–0.20 dengan kenaikan FRR ≤ 4 poin; konfigurasi terbaik = syarat
  latensi rata-rata ≤ 600 ms, lalu FAR terendah → FRR+MIR terendah → MIR terendah → paling
  sederhana. Laporan **tidak memakai akurasi**. Wajah tidak terdeteksi (FTA) = ditolak.
- Uji statistik: McNemar per metrik (FAR, FRR, MIR), binomial eksak bila b + c < 25,
  Wilcoxon untuk latensi. Ambang luminansi T_Y = (median Ȳw memadai + median Ȳw low-light)/2.

## Berkas penting
| Berkas | Fungsi |
|---|---|
| `lib/core/ai/*` | Deteksi, CLAHE, embedding, pencocokan (τ/δ di `face_matching_service.dart`) |
| `lib/features/attendance/presentation/AttendanceScreen.dart` | Presensi otomatis 600 ms, penghitung gagal 5×, log live |
| `lib/features/attendance/presentation/attendance_view.dart` | Input absensi guru, simpan (catat waktu sinkronisasi) |
| `lib/features/research/research_config.dart` | Saklar Mode Penelitian (disimpan per HP di Hive, bukan per akun) |
| `lib/features/research/research_logger.dart` | Log CSV lokal (tanpa nama, tidak dikirim ke cloud) |
| `lib/features/research/dataset_reader.dart` | Pembaca folder dataset (diuji di `test/dataset_reader_test.dart`) |
| `lib/features/research/presentation/dataset_evaluation_page.dart` | Halaman Evaluasi Dataset (RM 1–2) |
| `analisis_penelitian.py` | Analisis: `--mode validasi`, `--mode uji`, tanpa mode untuk RM 3 |
| `analisis_colab.ipynb` | Notebook Colab dengan program analisis tertanam (cukup unggah CSV) |
| `tools/buat_notebook_colab.py` | Membuat ulang notebook; **jalankan setiap kali `analisis_penelitian.py` diubah** |
| `buat_struktur_dataset.py` | Membuat folder dataset berkode + ceklis + berkas padanan rahasia |
| `firestore.rules` | Rules Firestore (developer = kunci master; data wajah hanya guru/admin) |

## Alur penelitian
1. Mode Penelitian hanya ada di Developer Control Panel (akun role `developer`).
2. **Evaluasi Dataset** (tidak butuh saklar Mode Penelitian): pilih folder → Mulai →
   hasil ditulis ke `Android/data/com.example.skripsi1/files/penelitian/penelitian_log_wajah.csv`
   (sumber = `dataset`, 1 baris per foto per kondisi CLAHE). ID sesi tampil di layar.
3. **Bagikan Log CSV** (panel Mode Penelitian) mengirim log ke laptop (Quick Share/USB).
4. Analisis: `python analisis_penelitian.py --mode validasi [--sesi-dataset ID] --wajah <csv>`
   → `lembar_penetapan_parameter.txt` (dicetak, ditandatangani). Lalu `--mode uji --sesi-dataset ID`
   → `hasil_analisis/uji_*.csv` (Bab IV). Alternatif: notebook Colab.
5. Pasang konfigurasi terbaik di kode (poin C4), lalu Eksperimen 3: saklar Mode Penelitian
   hidup → guru absen di HP itu → Bagikan Log → analisis tanpa `--mode` (pakai `--sesi`).

## Format folder dataset
```
dataset_uji/            (dataset_validasi/ sama, jumlah foto berbeda)
├── S01/registrasi/     1 foto (ada folder ini = siswa terdaftar)
├── S01/memadai/        foto memadai
├── S01/low_light/      foto low-light
├── S01/backlight/      foto backlight
└── TT01/<kondisi>/     siswa tidak terdaftar (tanpa registrasi)
```
- Nama folder = kode siswa dan **ikut tercatat di log**, jadi pakai `S01`/`TT01`, bukan NIS atau nama.
- Nama berkas foto bebas. Ekstensi .jpg/.jpeg/.png. Foto registrasi yang sama disalin ke kedua dataset.
- Aplikasi bisa membaca folder di `Android/data/.../files/` (lewat USB) atau di mana saja di HP
  (Pictures/Download/DCIM) lewat "Folder lain di penyimpanan HP…" (minta izin foto).
- Susunan lama (`galeri/` + `uji/<kondisi>/<NIS>/`) masih didukung.

## Verifikasi
- `flutter analyze lib test` — target 0 error (ada 4 warning lama yang dibiarkan).
- `flutter test test/dataset_reader_test.dart` — 7 uji pembaca folder.
- `flutter build apk --release` (butuh `android/key.properties` + keystore; tidak ada di repo).

## Status per 2 November 2026
Selesai di kode: semua poin A1–A6, B1–B3, C1–C3 dari review teman (PERUBAHAN_KODE_SESUAI_LAPORAN),
evaluasi dataset per siswa, izin baca foto, notebook Colab. Sudah dicoba di emulator Android 14
dengan 2 orang (20 foto): deteksi dan pengenalan berjalan, log lengkap, latensi ±370–400 ms.

Belum / perlu perhatian:
- **Belum diuji di Galaxy S10 asli** (izin foto Android 12, pemilih folder, latensi foto kamera asli).
- Analisis membutuhkan foto siswa **tidak terdaftar**; tanpa itu τ = `nan` dan FRR tampak 100%.
  Usulan (belum disetujui): skrip berhenti dengan pesan jelas bila tidak ada citra tidak terdaftar.
- **C4:** isi τ/δ terpilih dan konfigurasi terbaik di kode setelah lembar penetapan jadi.
- Naskah Bab III perlu menyesuaikan: log dipindah lewat USB **atau Quick Share**, analisis bisa
  di Colab (hanya log berkode), folder dataset berkode.
- Opsional: rapikan repo (`yolov8n.pt`, `server_guru/`, skrip server lama).

## Jebakan yang sudah diketahui
- Membuka CSV di Excel (bahasa Indonesia) menampilkan satu kolom; **jangan disimpan ulang dari Excel**
  (kode `001` → `1`, desimal berubah). Python membaca berkas asli dengan benar.
- Keluar dari halaman Evaluasi Dataset saat berjalan akan membatalkan evaluasi.
- Di emulator Android 11+, adb tidak bisa menulis ke `Android/data` tanpa `adb root`;
  pakai folder Pictures/Download + izin foto.
- Hasil Python mode validasi bernama `validasi_*.csv`, mode uji `uji_*.csv`.
