# ==============================================================================
# PEMBUAT NOTEBOOK GOOGLE COLAB (analisis_colab.ipynb)
# ==============================================================================
# Menanamkan isi analisis_penelitian.py ke dalam notebook, sehingga di Colab cukup
# mengunggah penelitian_log_wajah.csv. Jalankan ulang setiap kali
# analisis_penelitian.py diubah agar program di notebook ikut terbaru.
#
# Penggunaan (dari folder proyek):
#   python tools/buat_notebook_colab.py analisis_colab.ipynb analisis_penelitian.py
# ==============================================================================
import json
import sys


def md(teks):
    return {"cell_type": "markdown", "metadata": {}, "source": teks.strip("\n").splitlines(keepends=True)}


def kode(teks):
    return {"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [],
            "source": teks.strip("\n").splitlines(keepends=True)}


sel = [
    md("""
# Analisis Penelitian SIAP (Google Colab)

Program analisis sudah tertanam di notebook ini, jadi **cukup unggah `penelitian_log_wajah.csv`**
dari HP. Tidak perlu memasang Python di laptop. Jalankan sel **dari atas ke bawah** dengan tombol ▶.

| Langkah | Isi | Hasil |
|---|---|---|
| 0 | Siapkan program analisis | Program siap dipakai (tidak perlu diubah) |
| 1 | Unggah log dari HP | `penelitian_log_wajah.csv` siap |
| 2 | Lihat daftar sesi | ID sesi validasi dan uji |
| 3 | Mode validasi | τ, δ, T_Y, konfigurasi terbaik, **lembar penetapan** (cetak dan tandatangani) |
| 4 | Mode uji | FAR/FRR/MIR skenario A–D, McNemar, Wilcoxon, FRR/MIR per siswa (**hasil Bab IV**) |
| 5 | RM 3 (opsional) | Presensi wajah vs manual dari log absensi guru |
| 6 | Unduh hasil | `hasil_analisis.zip` |

**Penting**
- Unggah berkas `penelitian_log_wajah.csv` **asli dari HP** (tombol *Bagikan Log CSV*). Jangan dibuka lalu disimpan ulang di Excel, karena Excel bisa mengubah kode dan angka.
- Folder dataset harus memakai **kode siswa** (`S01`, `TT01`), bukan NIS atau nama, karena nama folder ikut tercatat di log. Sel langkah 2 memeriksa hal ini.
- Berkas di Colab **hilang saat sesi ditutup**. Unduh hasil (langkah 6) sebelum menutup.
"""),
    md("## Langkah 0 — Siapkan program analisis\nKlik ▶ sekali. Sel ini berisi program `analisis_penelitian.py` dan tidak perlu dibuka atau diubah."),
    kode('#@title Program analisis (klik ▶) { display-mode: "form" }\n'
         'open("analisis_penelitian.py", "w", encoding="utf-8").write(r\'\'\''
         + open(sys.argv[2], encoding="utf-8").read()
         + '\'\'\')\nprint("✅ Program analisis siap")\n'),
    md("## Langkah 1 — Unggah log dari HP"),
    kode("""
from google.colab import files
import os, re

print("Pilih: penelitian_log_wajah.csv (asli dari tombol Bagikan Log CSV)")
print("Tambahan bila perlu: lembar_penetapan_parameter.txt (mode uji di sesi Colab baru),")
print("                     penelitian_log_sesi.csv (RM 3)")
diunggah = files.upload()

# Colab menamai unggahan ulang "nama (1).csv"; kembalikan ke nama aslinya
for nama in diunggah:
    asli = re.sub(r" \\(\\d+\\)(?=\\.[^.]+$)", "", nama)
    if asli != nama:
        os.replace(nama, asli)

print("✅ penelitian_log_wajah.csv" if os.path.exists("penelitian_log_wajah.csv")
      else "❌ penelitian_log_wajah.csv belum diunggah")
if not os.path.exists("analisis_penelitian.py"):
    print("❌ Jalankan sel Langkah 0 terlebih dahulu")
"""),
    md("## Langkah 2 — Lihat daftar sesi evaluasi\nSesi paling awal biasanya **validasi**, sesi berikutnya **uji**. Salin ID-nya ke langkah 3 dan 4."),
    kode("""
import pandas as pd

log = pd.read_csv("penelitian_log_wajah.csv", dtype=str)
ds = log[log["sumber"] == "dataset"]
sesi = (ds.groupby("sesi_id")
          .agg(mulai=("waktu", "min"), baris=("waktu", "size"))
          .sort_values("mulai"))
display(sesi)

# Pemeriksaan privasi: nama folder siswa harus berupa kode (S01, TT01)
folder = ds["file"].fillna("").str.split("/").str[0].unique()
bukan_kode = [f for f in folder if not re.fullmatch(r"(S|TT)\\d+", f)]
if bukan_kode:
    print("⚠️ Folder berikut bukan kode siswa dan ikut tercatat di log:", ", ".join(bukan_kode[:5]))
else:
    print("✅ Semua folder siswa memakai kode; log tidak memuat NIS atau nama.")
"""),
    md("## Langkah 3 — Mode validasi\nIsi `SESI_VALIDASI` dengan ID dari langkah 2. Boleh dikosongkan bila log hanya berisi satu sesi."),
    kode("""
SESI_VALIDASI = ""   # contoh: "dataset_1793555471085"

opsi = f"--sesi-dataset {SESI_VALIDASI}" if SESI_VALIDASI else ""
!python analisis_penelitian.py --mode validasi {opsi} --wajah penelitian_log_wajah.csv
"""),
    kode("""
# Lembar penetapan parameter: cetak dan tandatangani sebelum data uji diproses
print(open("lembar_penetapan_parameter.txt", encoding="utf-8").read())
"""),
    md("## Langkah 4 — Mode uji\nMemakai τ dan δ dari `lembar_penetapan_parameter.txt` (hasil langkah 3)."),
    kode("""
SESI_UJI = ""   # contoh: "dataset_1793556650668"

opsi = f"--sesi-dataset {SESI_UJI}" if SESI_UJI else ""
!python analisis_penelitian.py --mode uji {opsi} --wajah penelitian_log_wajah.csv
"""),
    kode("""
# Tabel hasil untuk Bab IV
for nama in ["uji_metrik_skenario.csv", "uji_mcnemar.csv", "uji_frr_mir_per_siswa.csv"]:
    path = os.path.join("hasil_analisis", nama)
    if os.path.exists(path):
        print("\\n" + nama)
        display(pd.read_csv(path))
"""),
    md("## Langkah 5 — RM 3 (opsional)\nButuh `penelitian_log_sesi.csv` dari absensi guru saat Mode Penelitian aktif."),
    kode("""
!python analisis_penelitian.py --wajah penelitian_log_wajah.csv --sesi penelitian_log_sesi.csv
"""),
    md("## Langkah 6 — Unduh hasil"),
    kode("""
!zip -qr hasil_analisis.zip hasil_analisis lembar_penetapan_parameter.txt
files.download("hasil_analisis.zip")
"""),
]

nb = {
    "nbformat": 4,
    "nbformat_minor": 5,
    "metadata": {
        "colab": {"provenance": []},
        "kernelspec": {"name": "python3", "display_name": "Python 3"},
        "language_info": {"name": "python"},
    },
    "cells": sel,
}
for i, c in enumerate(nb["cells"]):
    c["id"] = f"sel{i:02d}"
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(nb, f, ensure_ascii=False, indent=1)
print("ok", sys.argv[1])
