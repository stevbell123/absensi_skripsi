# Panduan Pengambilan Data Penelitian (RM 1 – RM 3)

| Rumusan Masalah | Sumber data | Output analisis |
|---|---|---|
| **RM 1** – Pengaruh CLAHE pada kondisi cahaya berbeda & latensi | Evaluasi Dataset Foto (utama) + log live | `rm1_kinerja_per_kondisi.csv`, `rm1_uji_mcnemar.csv`, `rm1_grafik_kondisi.png` |
| **RM 2** – Margin vs ambang tunggal (FAR, FRR, MIR) | Evaluasi Dataset Foto (kedua mode dihitung dari jarak yang sama) | `rm2_perbandingan_mode.csv`, `rm2_sweep_*.csv`, `rm2_grafik_*.png`, `rm2_peringkat_konfigurasi.csv` |
| **RM 3** – Konfigurasi terbaik vs presensi manual | Log sesi absensi di kelas | `rm3_wajah_vs_manual.csv`, `rm3_wajah_per_konfigurasi.csv`, `rm3_grafik_durasi.png` |

## Definisi metrik (identifikasi open-set)

- **FAR** = foto orang **tidak terdaftar** yang diterima sebagai siswa mana pun ÷ total foto tidak terdaftar
- **FRR** = foto orang **terdaftar** yang ditolak (Unknown) ÷ total foto terdaftar
- **MIR** = foto orang terdaftar yang dikenali sebagai **siswa lain** ÷ total foto terdaftar
- **FTA** = foto tanpa wajah terdeteksi, dilaporkan terpisah dan tidak masuk FAR/FRR/MIR

## Persiapan

1. **Daftarkan ulang wajah siswa** yang dipakai uji live. Pendaftaran sekarang menyimpan dua embedding: dengan dan tanpa CLAHE. Data pendaftaran lama hanya punya versi CLAHE, sehingga tidak bisa dipakai saat CLAHE dimatikan.
2. **Izinkan Firestore menulis** ke koleksi `penelitian_log_wajah` dan `penelitian_log_sesi` (Firebase Console → Firestore → Rules). Jika ditolak, CSV lokal tetap tersimpan.
3. Buka **Input Absensi → ikon 🧪 → aktifkan Mode Penelitian**. Selama mode ini mati, aplikasi berjalan normal (CLAHE + margin) dan tidak ada data yang dicatat.

## RM 1 & RM 2: Evaluasi Dataset Foto

1. Ikon 🧪 → **Evaluasi Dataset Foto** → **Buat Struktur**. Folder dibuat di `/Android/data/<paket aplikasi>/files/dataset_skripsi/` dan bisa diakses lewat kabel USB dari PC.
2. Isi foto dengan struktur berikut:
   ```
   dataset_skripsi/
     galeri/12345_Budi/*.jpg               ← foto pendaftaran (1–3 per orang)
     uji/terang/12345/*.jpg                ← foto uji orang terdaftar
     uji/redup/12345/*.jpg
     uji/backlight/12345/*.jpg
     uji/samping_bayangan/12345/*.jpg
     uji/<kondisi lain>/12345/*.jpg        ← kondisi tambahan boleh, nama folder bebas
     uji/<kondisi>/tidak_terdaftar/*.jpg   ← orang yang TIDAK ada di galeri (wajib untuk FAR)
   ```
   - Satu orang per foto uji.
   - Usahakan jumlah foto per orang sama di setiap kondisi.
   - Ambil foto dengan kamera HP yang sama, resolusi sekitar 1280 px (setara kamera absensi).
3. Centang **Uji dengan CLAHE** dan **Uji tanpa CLAHE**, lalu tekan **Mulai Evaluasi**. Untuk setiap konfigurasi, galeri dibangun ulang dengan pra-pemrosesan yang sama agar perbandingan adil.
4. Tabel ringkasan muncul di layar. Data lengkapnya tersimpan di `penelitian_log_wajah.csv`.

## RM 1 (pelengkap): Uji live di kelas

1. Ikon 🧪 → pilih **kondisi cahaya** yang sedang berlaku → nyalakan atau matikan **CLAHE**.
2. Lakukan absensi wajah seperti biasa. Setiap wajah dicatat beserta jarak, keputusan, dan latensi per tahap.
3. Ulangi dengan CLAHE dibalik pada kondisi yang sama.

## RM 3: Presensi wajah vs manual

1. Gunakan **konfigurasi terbaik** dari `rm2_peringkat_konfigurasi.csv` (atur di ikon 🧪).
2. **Sesi wajah**: pilih jadwal → *Absen Otomatis via AI* → selesai → guru mengoreksi status yang salah → **Simpan Absensi**.
3. **Sesi manual**: pilih jadwal → isi status manual → **Simpan Absensi** (tanpa membuka kamera).
4. Satu sesi dicatat dari saat daftar siswa tampil sampai tombol Simpan ditekan. Untuk sesi wajah, status hasil scan dibandingkan dengan status akhir yang sudah dikoreksi guru:
   - **koreksi_jadi_hadir**: siswa yang terlewat oleh scan
   - **koreksi_batal_hadir**: siswa yang salah ditandai hadir
   - **akurasi_scan_persen**: kesesuaian hadir/tidak hadir hasil scan dengan absensi akhir
5. Lakukan beberapa sesi untuk masing-masing metode (idealnya kelas dan jumlah siswa sebanding).

## Analisis

1. Ikon 🧪 → **Bagikan Log CSV** → kirim ke PC.
2. Jalankan:
   ```
   pip install pandas numpy scipy matplotlib
   python analisis_penelitian.py --wajah penelitian_log_wajah.csv --sesi penelitian_log_sesi.csv
   ```
3. Hasilnya ada di `hasil_analisis/`, termasuk `ringkasan.txt` yang berisi semua tabel.

## Kolom penting di log wajah

- `jarak_terbaik`, `jarak_kedua`, `raw_nim`: data mentah. Skrip analisis memakainya untuk menghitung ulang keputusan pada ambang atau margin berapa pun.
- `pred_nim_tunggal` / `pred_nim_margin`: keputusan kedua mode pada parameter aplikasi.
- `cocok_via` (live): `nim` atau `nama`. Nilai `nama` berarti siswa ditemukan lewat pencocokan nama yang longgar di daftar hadir. Ini sumber salah identitas di luar model dan dilaporkan terpisah.
- `t_clahe_ms`, `t_embedding_ms`, `t_frame_ms`: latensi per tahap, diukur di HP.
