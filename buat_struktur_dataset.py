# ==============================================================================
# PEMBUAT STRUKTUR FOLDER DATASET (BAB III TABEL 3.3)
# ==============================================================================
# Membaca daftar siswa (CSV) lalu membuat folder kosong untuk dataset_uji dan/atau
# dataset_kalibrasi, satu folder per siswa, sesuai format yang dibaca halaman
# Evaluasi Dataset (lib/features/research/dataset_reader.dart):
#   S01/registrasi/                      → 1 foto registrasi (hanya siswa terdaftar)
#   S01/<kondisi>/                       → foto memadai, low_light, backlight
#   S26/<kondisi>/                       → siswa tidak terdaftar (tanpa folder registrasi)
#
# Folder memakai KODE siswa = S + nomor urut absen (S01–S30, Bab III Tabel 3.8), bukan
# NIS atau nama, karena nama folder ikut tercatat di log penelitian. Status terdaftar
# ditentukan oleh ada tidaknya folder registrasi. Padanan kode
# dengan NIS dan nama ditulis ke padanan_kode_siswa_RAHASIA.csv di luar folder
# dataset; simpan terpisah dan jangan dibagikan. Opsi --folder-nis memakai
# nama folder <NIS>_<Nama> seperti versi sebelumnya.
#
# Jumlah foto per siswa:
#   Uji (10 foto)      : 5 memadai; absen 1–15 → 3 low-light + 2 backlight,
#                        absen 16–30 → 2 low-light + 3 backlight
#   Kalibrasi, siswa terdaftar (2 foto)      : 1 memadai; absen ganjil → 1 low-light,
#                                              absen genap → 1 backlight
#                                              (--kalibrasi-lengkap: 1 low-light DAN 1 backlight)
#   Kalibrasi, siswa tidak terdaftar (4 foto): 2 memadai, 1 low-light, 1 backlight
#   (Bab II Tabel 2.3, Bab III Tabel 3.10: 70 citra kalibrasi = 35 memadai, 18 low-light, 17 backlight)
#
# Setiap folder diberi berkas ISI_n_FOTO.txt sebagai pengingat jumlah foto.
# Berkas .txt diabaikan oleh aplikasi, jadi tidak perlu dihapus.
# Juga dibuat daftar_foto_<bagian>.csv berisi nama berkas yang harus ada (ceklis).
#
# Format daftar siswa (CSV, baris pertama judul kolom):
#   absen,nis,nama,status
#   1,2024001,Budi Santoso,terdaftar
#   4,,Rina Lestari,tidak_terdaftar
#
# Penggunaan:
#   python buat_struktur_dataset.py --daftar daftar_siswa.csv --keluar D:\Goals_16\dataset_skripsi --bagian uji
#   (--bagian: kalibrasi, uji, atau semua; "validasi" = nama lama untuk kalibrasi)
#   Nama berkas foto bebas (boleh nama asli kamera); kondisi dibaca dari nama subfolder.
# ==============================================================================

import argparse
import csv
import os
import re
import sys

KONDISI = ["memadai", "low_light", "backlight"]
KODE_KONDISI = {"memadai": "M", "low_light": "L", "backlight": "B"}
LABEL_TT = "tidak_terdaftar"


def muat_daftar(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        siswa = []
        for b in csv.DictReader(f):
            status = b["status"].strip().lower()
            if status not in ("terdaftar", LABEL_TT):
                sys.exit(f"Status tidak dikenal untuk absen {b['absen']}: '{b['status']}' "
                         "(isi 'terdaftar' atau 'tidak_terdaftar')")
            siswa.append({"absen": int(b["absen"]), "nis": b["nis"].strip(),
                          "nama": b["nama"].strip(), "status": status})
    siswa.sort(key=lambda s: s["absen"])

    # Kode = S + nomor urut absen (Bab III Tabel 3.8), untuk siswa terdaftar maupun tidak
    for s in siswa:
        s["kode"] = f"S{s['absen']:02d}"
        if s["status"] == "terdaftar" and "_" in s["nis"]:
            sys.exit(f"NIS absen {s['absen']} tidak boleh memuat garis bawah (_)")
    if len({s["kode"] for s in siswa}) != len(siswa):
        sys.exit("Nomor absen ganda pada daftar siswa")

    terdaftar = sum(s["status"] == "terdaftar" for s in siswa)
    if len(siswa) != 30 or terdaftar != 25:
        print(f"⚠️  Daftar berisi {len(siswa)} siswa ({terdaftar} terdaftar, "
              f"{len(siswa) - terdaftar} tidak terdaftar); rancangan Bab III: 30 (25 + 5).")
    return siswa


def jumlah_foto(s, bagian, kalibrasi_lengkap=False):
    """Jumlah foto per kondisi untuk satu siswa."""
    if bagian == "uji":
        awal = s["absen"] <= 15
        return {"memadai": 5, "low_light": 3 if awal else 2, "backlight": 2 if awal else 3}
    if s["status"] == LABEL_TT:  # kalibrasi siswa tidak terdaftar: 4 citra
        return {"memadai": 2, "low_light": 1, "backlight": 1}
    if kalibrasi_lengkap:
        return {"memadai": 1, "low_light": 1, "backlight": 1}
    ganjil = s["absen"] % 2 == 1
    return {"memadai": 1, "low_light": 1 if ganjil else 0, "backlight": 0 if ganjil else 1}


def nama_aman(teks):
    return re.sub(r'[\\/:*?"<>|]', "", teks).strip()


def tulis_pengingat(folder, n, keterangan):
    with open(os.path.join(folder, f"ISI_{n}_FOTO.txt"), "w", encoding="utf-8") as f:
        f.write(keterangan + "\n")


def nama_folder_siswa(s, folder_nis):
    if not folder_nis:
        return s["kode"]
    awal = s["nis"] if s["status"] == "terdaftar" else s["kode"]
    if not awal:
        sys.exit(f"--folder-nis: NIS kosong untuk siswa terdaftar absen {s['absen']}")
    return f"{awal}_{nama_aman(s['nama'])}"


def tulis_padanan(siswa, akar):
    path = os.path.join(akar, "padanan_kode_siswa_RAHASIA.csv")
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["kode", "absen", "nis", "nama", "status"])
        for s in siswa:
            w.writerow([s["kode"], s["absen"], s["nis"], s["nama"], s["status"]])
    print(f"🔒 Padanan kode siswa: {path} (simpan terpisah, jangan dibagikan)")


def buat_bagian(siswa, akar, bagian, kalibrasi_lengkap=False, folder_nis=False):
    kode_bagian = "U" if bagian == "uji" else "K"
    folder_dataset = os.path.join(akar, f"dataset_{bagian}")
    if os.path.exists(folder_dataset) and os.listdir(folder_dataset):
        sys.exit(f"Folder {folder_dataset} sudah berisi data. Pindahkan atau hapus dulu agar tidak tertimpa.")

    ceklis = []
    for s in siswa:
        folder_siswa = os.path.join(folder_dataset, nama_folder_siswa(s, folder_nis))
        os.makedirs(folder_siswa)

        # registrasi: hanya siswa terdaftar, 1 foto
        if s["status"] == "terdaftar":
            folder = os.path.join(folder_siswa, "registrasi")
            os.makedirs(folder)
            sumber = ("salin foto yang sama dari dataset_kalibrasi" if bagian == "uji"
                      else "pencahayaan memadai, wajah lurus ke kamera")
            tulis_pengingat(folder, 1, f"Absen {s['absen']} - {s['nama']}: foto registrasi, {sumber}.")
            ceklis.append([s["absen"], s["kode"], s["nama"], "registrasi",
                           f"{s['kode']}_R_M_01.jpg", os.path.relpath(folder, folder_dataset)])

        for kondisi, n in jumlah_foto(s, bagian, kalibrasi_lengkap).items():
            if n == 0:
                continue
            folder = os.path.join(folder_siswa, kondisi)
            os.makedirs(folder)
            tulis_pengingat(folder, n, f"Absen {s['absen']} - {s['nama']}: {n} foto {kondisi}.")
            for urut in range(1, n + 1):
                ceklis.append([s["absen"], s["kode"], s["nama"], kondisi,
                               f"{s['kode']}_{kode_bagian}_{KODE_KONDISI[kondisi]}_{urut:02d}.jpg",
                               os.path.relpath(folder, folder_dataset)])

    path_ceklis = os.path.join(akar, f"daftar_foto_{bagian}.csv")
    with open(path_ceklis, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["absen", "kode", "nama", "kondisi", "nama_berkas_saran", "folder", "sudah"])
        w.writerows(ceklis)

    per_kondisi = {k: sum(1 for b in ceklis if b[3] == k) for k in ["registrasi", *KONDISI]}
    print(f"✅ {folder_dataset}  ({len(siswa)} folder siswa)")
    print(f"   registrasi {per_kondisi['registrasi']} foto, "
          + ", ".join(f"{k} {per_kondisi[k]}" for k in KONDISI)
          + f" → total citra {bagian}: {sum(per_kondisi[k] for k in KONDISI)}")
    print(f"   ceklis: {path_ceklis}")


def main():
    parser = argparse.ArgumentParser(description="Membuat struktur folder dataset penelitian")
    parser.add_argument("--daftar", required=True, help="CSV daftar siswa (absen,nis,nama,status)")
    parser.add_argument("--keluar", required=True, help="Folder tujuan, sebaiknya di luar folder proyek")
    parser.add_argument("--bagian", choices=["kalibrasi", "uji", "semua", "validasi"], default="uji",
                        help="kalibrasi, uji, atau semua (validasi = nama lama untuk kalibrasi)")
    parser.add_argument("--folder-nis", action="store_true",
                        help="Nama folder <NIS>_<Nama> (nama siswa ikut tercatat di log)")
    parser.add_argument("--kalibrasi-lengkap", "--validasi-lengkap", dest="kalibrasi_lengkap",
                        action="store_true",
                        help="Kalibrasi: setiap siswa terdaftar difoto low-light dan backlight")
    args = parser.parse_args()
    if args.bagian == "validasi":
        args.bagian = "kalibrasi"

    siswa = muat_daftar(args.daftar)
    os.makedirs(args.keluar, exist_ok=True)
    for bagian in (["kalibrasi", "uji"] if args.bagian == "semua" else [args.bagian]):
        buat_bagian(siswa, args.keluar, bagian, args.kalibrasi_lengkap, args.folder_nis)
    tulis_padanan(siswa, args.keluar)


if __name__ == "__main__":
    main()
