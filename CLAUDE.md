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
Nilai awal τ = 1.0, δ = 0.06; nilai akhir ditetapkan dari data **kalibrasi** (istilah naskah;
dulu disebut "validasi").

- **RM 1:** pengaruh CLAHE per kondisi cahaya + latensi (A vs B, C vs D).
- **RM 2:** verifikasi margin vs ambang tunggal pada FAR, FRR, MIR (A vs C, B vs D).
- **RM 3:** konfigurasi terbaik vs absen manual di kelas (Eksperimen 3, 6 sesi).
- Skenario: A = tanpa CLAHE tanpa margin, B = CLAHE, C = margin, D = CLAHE + margin.
- Data: 30 siswa, kode = S + nomor absen; S01–S25 terdaftar, S26–S30 tidak terdaftar.
  Registrasi 25, kalibrasi 70, uji 300. Kalibrasi: terdaftar 1 memadai + 1 tidak memadai
  (absen ganjil low-light, genap backlight); tidak terdaftar 2 memadai + 1 low-light + 1 backlight
  (total 35/18/17). Uji per siswa: 5 memadai; absen 1–15 → 3 low-light + 2 backlight, 16–30 → 2 + 3.
- Penetapan (data kalibrasi saja), τ tiga langkah (masukan dosbim 4 Nov, Bab II 2.2.6, Bab III 3.4.4):
  τ terbesar 0.50–1.50 dengan FAR 0% → dipakai bila FRR ≤ 10% → bila tidak, τ terkecil di atasnya
  dengan FRR ≤ 10% dan FAR ≤ 5% → bila tetap tidak ada, FAR + FRR terkecil (keterbatasan).
  Sebaran d1 dan d2−d1 (tabel + grafik) ikut dikeluarkan. δ = nilai terbesar 0.00–0.20 dengan
  kenaikan FRR ≤ 4 poin; konfigurasi terbaik = syarat
  latensi rata-rata ≤ 600 ms, lalu FAR terendah → FRR+MIR terendah → MIR terendah → paling
  sederhana. Laporan **tidak memakai akurasi**. Wajah tidak terdeteksi (FTA) = ditolak.
- Uji statistik: McNemar per metrik (FAR, FRR, MIR), binomial eksak bila b + c < 25 atau b/c = 0,
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
| `analisis_penelitian.py` | Analisis: `--mode kalibrasi` (alias lama `validasi`), `--mode uji`, tanpa mode untuk RM 3 |
| `analisis_colab.ipynb` | Notebook Colab dengan program analisis tertanam (cukup unggah CSV) |
| `tools/buat_notebook_colab.py` | Membuat ulang notebook; **jalankan setiap kali `analisis_penelitian.py` diubah** |
| `buat_struktur_dataset.py` | Membuat folder dataset berkode (`--bagian kalibrasi/uji/semua`) + ceklis + padanan rahasia |
| `lib/features/research/presentation/contoh_templat_page.dart` | Gambar 3.15 Bab III (contoh tahapan templat, ML Kit asli) |
| `firestore.rules` | Rules Firestore (developer = kunci master; data wajah hanya guru/admin) |

## Alur penelitian
1. Mode Penelitian hanya ada di Developer Control Panel (akun role `developer`).
2. **Evaluasi Dataset** (tidak butuh saklar Mode Penelitian): pilih folder → Mulai →
   hasil ditulis ke `Android/data/com.example.skripsi1/files/penelitian/penelitian_log_wajah.csv`
   (sumber = `dataset`, 1 baris per foto per kondisi CLAHE). ID sesi tampil di layar.
3. **Bagikan Log CSV** (panel Mode Penelitian) mengirim log ke laptop (Quick Share/USB).
4. Analisis: `python analisis_penelitian.py --mode kalibrasi [--sesi-dataset ID] --wajah <csv>`
   → `lembar_penetapan_parameter.txt` (langkah τ, versi aplikasi, SHA-256 model; dicetak, ditandatangani)
   + `hasil_analisis/kalibrasi_*.csv/png`. Lalu `--mode uji --sesi-dataset ID`
   → `hasil_analisis/uji_*.csv` (Bab IV). Alternatif: notebook Colab.
5. Pasang konfigurasi terbaik di kode (poin C4), lalu Eksperimen 3: saklar Mode Penelitian
   hidup → guru absen di HP itu → Bagikan Log → analisis tanpa `--mode` (pakai `--sesi` dan
   `--padanan`). Log wajah presensi berisi NIS: analisis di laptop, bukan Colab (log sesi boleh ke Colab).

## Format folder dataset
```
dataset_uji/            (dataset_kalibrasi/ sama, jumlah foto berbeda)
├── S01/registrasi/     1 foto (ada folder ini = siswa terdaftar)
├── S01/memadai/        foto memadai
├── S01/low_light/      foto low-light
├── S01/backlight/      foto backlight
└── S26/<kondisi>/      siswa tidak terdaftar (tanpa registrasi)
```
- Nama folder = kode siswa dan **ikut tercatat di log**, jadi pakai `S01`…`S30`, bukan NIS atau nama.
- Folder kosong siap isi + `cek_dataset.py` + ceklis ada di `C:/Users/ACER ASPIRE 7/Downloads/dataset_penelitian/`
  (di luar repo, berisi foto siswa — jangan diunggah ke cloud).
- Nama berkas foto bebas. Ekstensi .jpg/.jpeg/.png. Foto registrasi yang sama disalin ke kedua dataset.
- Aplikasi bisa membaca folder di `Android/data/.../files/` (lewat USB) atau di mana saja di HP
  (Pictures/Download/DCIM) lewat "Folder lain di penyimpanan HP…" (minta izin foto).
- Susunan lama (`galeri/` + `uji/<kondisi>/<NIS>/`) masih didukung.

## Verifikasi
- `flutter analyze lib test` — target 0 error (ada 4 warning lama yang dibiarkan).
- `flutter test test/dataset_reader_test.dart` — 7 uji pembaca folder.
- `flutter build apk --release` (butuh `android/key.properties` + `android/app/siap-release.jks`,
  dibuat 3 Nov 2026, di-ignore git; cadangan disimpan tim). Path proyek berspasi membuat build gagal:
  jalankan `subst S: "<folder proyek>"` lalu build dari drive S: (hapus `.dart_tool/flutter_build` bila
  masih menyimpan path lama). Butuh SDK platform 31, 35, 36 (pasang via PowerShell Administrator).
- `flutter test` — 21 uji (pembaca dataset, parser CSV siswa, contoh templat, pembacaan NIS).

## Status per 5 November 2026
- **C4-NIS selesai di kode:** hasil pengenalan dicocokkan ke daftar hadir lewat NIS
  (`cocok_via = nis`); nama hanya cadangan (persis + unik, baris tanpa NIS). NIS dibaca satu aturan
  `lib/core/utils/nis_siswa.dart` (nisNip → nis → email tanpa '@') di registrasi, sinkronisasi
  templat, dan daftar hadir. `AttendanceRecord` menyimpan `nis`; log `nim_daftar_hadir` kini berisi NIS.
- **Registrasi tepat 1 wajah** (aturan 35% dihapus). **Registrasi ulang:** siswa yang sudah
  terdaftar menampilkan peringatan + dialog konfirmasi; data lama di Hive dan Firestore ditimpa
  setelah foto baru berhasil diproses (dokumen NIS sama). `saveEmbedding` mengembalikan false bila Firestore gagal.
- Skrip analisis: tabel interaksi (D−B)−(C−A) → `hasil_analisis/uji_interaksi_clahe_margin.csv`; notebook dibuat ulang.
- Belum diuji di HP asli. Naskah Bab III perlu menyesuaikan: Tabel 3.5 `records` kini punya `nis`;
  struktur folder dataset (3.2.8); Quick Share/Colab (Tabel 3.14); Android S10 di Tabel 3.26;
  satu kalimat pembagian sisa CLAHE ke bin berurutan (3.4.2).
- **KF-04:** AttendanceScreen hanya memuat templat kelas itu (tidak lagi `syncFromFirestore` seluruh
  sekolah); cache Hive disaring dengan NIS daftar hadir. Kelas tanpa templat → pesan peringatan.
- **Kode siswa = nomor absen:** `analisis_penelitian.py --padanan <padanan_kode_siswa_RAHASIA.csv>`
  (berkas resmi dari `buat_struktur_dataset.py`) mengganti NIS log presensi dengan kode Tabel 3.8;
  NIS di luar padanan → X01…; tanpa `--padanan` kode urut NIS (ada peringatan). Nilai yang sudah
  berupa kode (log dataset S01…) tidak dinomori ulang. Keluaran padanan: `padanan_kode_dipakai_RAHASIA.csv`.
- Kolom log sesi `akurasi_scan_persen` → `kesesuaian_scan_persen` (posisi sama; skrip menerima nama lama).
  Gambar 3.18 Bab III perlu tangkapan layar baru.

## Status per 4 November 2026
- Skrip analisis mengikuti naskah 4 Nov: aturan τ tiga langkah, sebaran d1/d2−d1, rincian FRR
  (nTD/nTA/nTM), waktu per tahap, binomial bila b/c = 0, istilah kalibrasi, versi + SHA-256 model di lembar.
- APK rilis (keystore `siap`) sudah dibuat; fitur Gambar 3.15 dan impor CSV siswa belum diuji di S10 asli.
- Belum diputuskan: registrasi masih menerima wajah kedua < 35% luas wajah utama (Bab III: tepat 1 wajah).

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
- Hasil Python mode kalibrasi bernama `kalibrasi_*.csv`, mode uji `uji_*.csv`.
- Matplotlib di laptop ini rusak (paket `packaging` tidak ada); grafik baru muncul di Colab.
