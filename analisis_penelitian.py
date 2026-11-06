# ==============================================================================
# ANALISIS DATA PENELITIAN PRESENSI WAJAH ON-DEVICE (BAB 4)
# ==============================================================================
# Membaca log CSV dari aplikasi (Mode Penelitian) dan menjawab:
#   RM 1: Pengaruh CLAHE terhadap kinerja pengenalan wajah per kondisi
#         pencahayaan + latensi pemrosesan
#   RM 2: Pengaruh verifikasi margin terhadap FAR, FRR, MIR dibanding
#         ambang jarak tunggal (termasuk sweep ambang & margin)
#   RM 3: Kinerja operasional konfigurasi terbaik vs presensi manual
#
# Definisi metrik (identifikasi open-set):
#   FAR = impostor (orang tak terdaftar) yang diterima / total impostor
#   FRR = genuine (orang terdaftar) yang ditolak       / total genuine
#   MIR = genuine yang dikenali sebagai orang LAIN     / total genuine
#   FTA = foto tanpa wajah terdeteksi. Dihitung sebagai keputusan DITOLAK
#         (genuine → masuk FRR, impostor → ditolak dengan benar), sesuai Tabel 2.2,
#         dan jumlahnya tetap dilaporkan terpisah pada kolom FTA.
#
# Penggunaan:
#   pip install pandas numpy scipy matplotlib
#   python analisis_penelitian.py --wajah penelitian_log_wajah.csv --sesi penelitian_log_sesi.csv
#
#   Penetapan parameter dari data kalibrasi (Bab III Subbab 3.4.4–3.4.6):
#   python analisis_penelitian.py --mode kalibrasi --sesi-dataset <sesi_id dataset_kalibrasi>
#   → menulis lembar_penetapan_parameter.txt (T_Y, τ dan δ per kondisi CLAHE beserta
#     langkah penetapan τ, metrik skenario A–D, konfigurasi terbaik, versi aplikasi
#     dan sidik jari model) serta sebaran d1 dan d2−d1 (tabel + grafik)
#   Aturan τ tiga langkah: FAR kalibrasi 0% selama FRR ≤ 10%; bila tidak, FRR ≤ 10%
#   dengan FAR ≤ 5%; bila tetap tidak bisa, FAR + FRR terkecil. Batas dapat diubah
#   dengan --frr-maks dan --far-longgar. (--mode validasi = nama lama, tetap diterima)
#
#   Pengujian pada data uji dengan parameter dari lembar penetapan:
#   python analisis_penelitian.py --mode uji --sesi-dataset <sesi_id dataset_uji>
#
#   Semua keluaran memakai kode siswa S01–S30, bukan NIM.
#
# Hasil (CSV + grafik PNG + ringkasan.txt) disimpan di folder hasil_analisis/
# ==============================================================================

import argparse
import hashlib
import os
import re
from datetime import datetime

import numpy as np
import pandas as pd

try:
    from scipy import stats
except ImportError:  # Uji statistik dilewati jika scipy tidak terpasang
    stats = None

try:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:  # Grafik dilewati jika matplotlib tidak terpasang
    plt = None

UNKNOWN = "Unknown"
KOLOM_NIM = ["label_nim", "raw_nim", "pred_nim", "pred_nim_tunggal", "pred_nim_margin", "nim_daftar_hadir"]
KOLOM_ANGKA_WAJAH = [
    "clahe", "ambang", "margin", "terdaftar", "jumlah_wajah", "jarak_terbaik", "jarak_kedua",
    "selisih", "t_deteksi_ms", "t_decode_ms", "t_crop_ms", "t_clahe_ms", "t_embedding_ms",
    "t_matching_ms", "t_frame_ms", "luminansi_wajah", "luminansi_latar",
]

_ringkasan = []


def catat(teks=""):
    """Cetak ke layar sekaligus simpan untuk ringkasan.txt"""
    print(teks)
    _ringkasan.append(teks)


def pct(a, b):
    return round(100.0 * a / b, 2) if b else np.nan


def mean_sd(seri):
    seri = seri.dropna()
    if seri.empty:
        return "-"
    return f"{seri.mean():.2f} ± {seri.std(ddof=1) if len(seri) > 1 else 0:.2f}"


# ==============================================================================
# PEMUATAN DATA
# ==============================================================================
def muat_log_wajah(path):
    df = pd.read_csv(path, dtype={k: str for k in KOLOM_NIM})
    for k in KOLOM_NIM:
        df[k] = df[k].fillna("").str.strip()
    for k in KOLOM_ANGKA_WAJAH:
        if k not in df:  # log lama belum punya kolom luminansi
            df[k] = np.nan
        df[k] = pd.to_numeric(df[k], errors="coerce")
    df["kondisi_cahaya"] = df["kondisi_cahaya"].fillna("tidak_diketahui")
    df["terdeteksi"] = df["alasan"] != "wajah_tidak_terdeteksi"
    # Aplikasi mengambil label dari nama folder sebelum "_", sehingga folder
    # tidak_terdaftar/ terbaca "tidak". Samakan label semua citra tidak terdaftar.
    df.loc[(df["sumber"] == "dataset") & (df["terdaftar"] == 0), "label_nim"] = "tidak_terdaftar"
    df["t_wajah_ms"] = df[["t_crop_ms", "t_clahe_ms", "t_embedding_ms"]].sum(axis=1)
    return df


def muat_log_sesi(path):
    df = pd.read_csv(path)
    # Nama lama kolom (log sebelum 5 Nov 2026); isi dan posisinya sama
    if "akurasi_scan_persen" in df and "kesesuaian_scan_persen" not in df:
        df = df.rename(columns={"akurasi_scan_persen": "kesesuaian_scan_persen"})
    for k in ["jumlah_siswa", "durasi_total_detik", "durasi_scan_detik", "hadir_hasil_scan",
              "hadir_akhir", "koreksi_total", "koreksi_jadi_hadir", "koreksi_batal_hadir",
              "kesesuaian_scan_persen", "clahe"]:
        df[k] = pd.to_numeric(df[k], errors="coerce")
    df["detik_per_siswa"] = df["durasi_total_detik"] / df["jumlah_siswa"]
    return df


# ==============================================================================
# KEPUTUSAN & METRIK
# ==============================================================================
def prediksi(df, ambang, margin=None):
    """Hitung ulang keputusan dari jarak mentah (aturan sama dengan FaceMatchingService)."""
    lolos = df["terdeteksi"] & (df["jarak_terbaik"] <= ambang)
    if margin is not None:
        tanpa_kandidat_kedua = df["jarak_kedua"] >= 999
        lolos &= tanpa_kandidat_kedua | ((df["jarak_kedua"] - df["jarak_terbaik"]) >= margin)
    return df["raw_nim"].where(lolos, UNKNOWN)


def metrik(df, pred):
    # Foto tanpa wajah terdeteksi tetap dihitung: prediksi() memberinya UNKNOWN (ditolak)
    det = df["terdeteksi"]
    gen = df["terdaftar"] == 1
    imp = df["terdaftar"] == 0
    n_gen, n_imp = int(gen.sum()), int(imp.sum())
    fa = int((imp & (pred != UNKNOWN)).sum())
    fr = int((gen & (pred == UNKNOWN)).sum())
    mi = int((gen & (pred != UNKNOWN) & (pred != df["label_nim"])).sum())
    return {
        "n_genuine": n_gen,
        "n_impostor": n_imp,
        "FTA": int((~det).sum()),
        "FAR_%": pct(fa, n_imp),
        "FRR_%": pct(fr, n_gen),
        "MIR_%": pct(mi, n_gen),
        "TAR_%": pct(n_gen - fr - mi, n_gen),
    }


def mcnemar(b, c):
    """Uji McNemar eksak (binomial) untuk data berpasangan: b, c = jumlah pasangan yang berbeda."""
    if stats is None or b + c == 0:
        return np.nan
    return stats.binomtest(min(b, c), b + c, 0.5).pvalue


def simpan(df, keluar, nama):
    path = os.path.join(keluar, nama)
    df.to_csv(path, index=False)
    catat(f"  → tersimpan: {path}")


# ==============================================================================
# RM 1: PENGARUH CLAHE
# ==============================================================================
def analisis_rm1(ds, keluar):
    catat("\n" + "=" * 78)
    catat("RM 1: PENGARUH CLAHE TERHADAP KINERJA PENGENALAN & LATENSI")
    catat("=" * 78)

    baris = []
    for (kondisi, clahe), g in list(ds.groupby(["kondisi_cahaya", "clahe"])) + [
        (("SEMUA", c), g) for c, g in ds.groupby("clahe")
    ]:
        ambang, margin = g["ambang"].iloc[0], g["margin"].iloc[0]
        lat = g[g["terdeteksi"]]
        baris.append({
            "kondisi": kondisi,
            "clahe": "Ya" if clahe == 1 else "Tidak",
            **metrik(g, prediksi(g, ambang, margin)),
            "t_clahe_ms": mean_sd(lat["t_clahe_ms"]),
            "t_embedding_ms": mean_sd(lat["t_embedding_ms"]),
            "t_wajah_ms (crop+clahe+embed)": mean_sd(lat["t_wajah_ms"]),
            "t_frame_ms": mean_sd(lat["t_frame_ms"]),
        })
    tabel = pd.DataFrame(baris)
    catat("\nKinerja per kondisi pencahayaan (mode verifikasi aplikasi: ambang + margin):")
    catat(tabel.to_string(index=False))
    simpan(tabel, keluar, "rm1_kinerja_per_kondisi.csv")

    # --- Uji McNemar: foto yang sama, CLAHE vs tanpa CLAHE ---
    gen = ds[ds["terdaftar"] == 1].copy()
    pasangan = pd.DataFrame()
    if not gen.empty:
        gen["benar"] = prediksi(gen, gen["ambang"].iloc[0], gen["margin"].iloc[0]) == gen["label_nim"]
        pasangan = gen.pivot_table(index=["sesi_id", "kondisi_cahaya", "file"], columns="clahe",
                                   values="benar", aggfunc="first").dropna()
    if {0, 1}.issubset(pasangan.columns):
        catat("\nUji McNemar (genuine dikenali benar, berpasangan per foto):")
        hasil = []
        for kondisi, p in list(pasangan.groupby(level="kondisi_cahaya")) + [("SEMUA", pasangan)]:
            b = int(((p[1] == True) & (p[0] == False)).sum())  # noqa: E712
            c = int(((p[1] == False) & (p[0] == True)).sum())  # noqa: E712
            hasil.append({"kondisi": kondisi, "n_pasangan": len(p), "hanya_benar_dg_CLAHE": b,
                          "hanya_benar_tanpa_CLAHE": c, "p_value": mcnemar(b, c)})
        tabel_uji = pd.DataFrame(hasil)
        catat(tabel_uji.to_string(index=False))
        catat("  (p < 0.05 → perbedaan akibat CLAHE signifikan)")
        simpan(tabel_uji, keluar, "rm1_uji_mcnemar.csv")

    # --- Latensi: overhead CLAHE ---
    det = ds[ds["terdeteksi"]]
    on, off = det[det["clahe"] == 1], det[det["clahe"] == 0]
    if not on.empty and not off.empty:
        catat("\nLatensi pemrosesan per wajah (ms):")
        catat(f"  CLAHE saja (overhead)          : {mean_sd(on['t_clahe_ms'])}")
        catat(f"  crop+clahe+embedding (CLAHE)   : {mean_sd(on['t_wajah_ms'])}")
        catat(f"  crop+embedding (tanpa CLAHE)   : {mean_sd(off['t_wajah_ms'])}")
        catat(f"  total frame (CLAHE)            : {mean_sd(on['t_frame_ms'])}")
        catat(f"  total frame (tanpa CLAHE)      : {mean_sd(off['t_frame_ms'])}")
        if stats is not None and len(on) > 1 and len(off) > 1:
            p = stats.mannwhitneyu(on["t_wajah_ms"], off["t_wajah_ms"]).pvalue
            catat(f"  Mann-Whitney t_wajah CLAHE vs tanpa: p = {p:.4g}")

    if plt is not None:
        per_kondisi = tabel[tabel["kondisi"] != "SEMUA"]
        fig, axes = plt.subplots(1, 3, figsize=(14, 4))
        for ax, m in zip(axes, ["FAR_%", "FRR_%", "MIR_%"]):
            pv = per_kondisi.pivot(index="kondisi", columns="clahe", values=m)
            pv.plot.bar(ax=ax, rot=20)
            ax.set_title(m.replace("_%", " (%)"))
            ax.set_xlabel("")
        fig.suptitle("RM 1: Kinerja per kondisi pencahayaan, CLAHE vs tanpa CLAHE")
        fig.tight_layout()
        fig.savefig(os.path.join(keluar, "rm1_grafik_kondisi.png"), dpi=150)
        plt.close(fig)


# ==============================================================================
# RM 2: VERIFIKASI MARGIN VS AMBANG TUNGGAL
# ==============================================================================
def analisis_rm2(ds, keluar):
    catat("\n" + "=" * 78)
    catat("RM 2: VERIFIKASI MARGIN VS AMBANG JARAK TUNGGAL (FAR, FRR, MIR)")
    catat("=" * 78)

    ambang_app, margin_app = ds["ambang"].iloc[0], ds["margin"].iloc[0]
    catat(f"Parameter aplikasi: ambang = {ambang_app}, margin = {margin_app}")

    perbandingan, rekomendasi = [], []
    for clahe, g in ds.groupby("clahe"):
        label = "CLAHE" if clahe == 1 else "Tanpa CLAHE"
        for mode, mg in [("ambang tunggal", None), ("ambang + margin", margin_app)]:
            m = metrik(g, prediksi(g, ambang_app, mg))
            perbandingan.append({"clahe": label, "mode": mode, **m})
            rekomendasi.append({"konfigurasi": f"{label} + {mode}",
                                "total_error_%": m["FAR_%"] + m["FRR_%"] + m["MIR_%"], **m})

        # Uji McNemar: misidentifikasi & penolakan, pasangan = foto yang sama
        gen = g[g["terdaftar"] == 1]
        p_t, p_m = prediksi(gen, ambang_app), prediksi(gen, ambang_app, margin_app)
        mi_t = (p_t != UNKNOWN) & (p_t != gen["label_nim"])
        mi_m = (p_m != UNKNOWN) & (p_m != gen["label_nim"])
        b, c = int((mi_t & ~mi_m).sum()), int((~mi_t & mi_m).sum())
        catat(f"\n[{label}] McNemar MIR: {b} kasus salah-identitas dicegah margin, "
              f"{c} kasus baru; p = {mcnemar(b, c):.4g}")

        # Sweep ambang
        sweep = []
        for a in np.round(np.arange(0.40, 1.61, 0.02), 2):
            for mode, mg in [("tunggal", None), ("margin", margin_app)]:
                sweep.append({"ambang": a, "mode": mode, **metrik(g, prediksi(g, a, mg))})
        sweep = pd.DataFrame(sweep)
        simpan(sweep, keluar, f"rm2_sweep_ambang_clahe{int(clahe)}.csv")
        for mode in ["tunggal", "margin"]:
            s = sweep[sweep["mode"] == mode].dropna(subset=["FAR_%", "FRR_%"])
            if not s.empty:
                eer = s.iloc[(s["FAR_%"] - s["FRR_%"]).abs().argmin()]
                catat(f"[{label}] Titik EER mode {mode}: ambang ≈ {eer['ambang']}, "
                      f"FAR {eer['FAR_%']}%, FRR {eer['FRR_%']}%, MIR {eer['MIR_%']}%")

        # Sweep margin pada ambang aplikasi
        sweep_m = pd.DataFrame([
            {"margin": mg, **metrik(g, prediksi(g, ambang_app, mg))}
            for mg in np.round(np.arange(0.0, 0.205, 0.01), 2)
        ])
        simpan(sweep_m, keluar, f"rm2_sweep_margin_clahe{int(clahe)}.csv")

        if plt is not None:
            fig, axes = plt.subplots(1, 2, figsize=(13, 4.5))
            for mode, gaya in [("tunggal", "--"), ("margin", "-")]:
                s = sweep[sweep["mode"] == mode]
                for m, warna in [("FAR_%", "tab:red"), ("FRR_%", "tab:blue"), ("MIR_%", "tab:orange")]:
                    axes[0].plot(s["ambang"], s[m], gaya, color=warna, label=f"{m[:3]} {mode}")
            axes[0].axvline(ambang_app, color="grey", lw=0.8)
            axes[0].set_xlabel("Ambang jarak Euclidean")
            axes[0].set_ylabel("%")
            axes[0].set_title("Sweep ambang: tunggal (--) vs margin (—)")
            axes[0].legend(fontsize=8)
            for m, warna in [("FAR_%", "tab:red"), ("FRR_%", "tab:blue"), ("MIR_%", "tab:orange")]:
                axes[1].plot(sweep_m["margin"], sweep_m[m], color=warna, label=m[:3])
            axes[1].axvline(margin_app, color="grey", lw=0.8)
            axes[1].set_xlabel(f"Margin (ambang tetap {ambang_app})")
            axes[1].set_title("Sweep margin")
            axes[1].legend(fontsize=8)
            fig.suptitle(f"RM 2 — {label}")
            fig.tight_layout()
            fig.savefig(os.path.join(keluar, f"rm2_grafik_clahe{int(clahe)}.png"), dpi=150)
            plt.close(fig)

    tabel = pd.DataFrame(perbandingan)
    catat("\nPerbandingan pada ambang aplikasi:")
    catat(tabel.to_string(index=False))
    simpan(tabel, keluar, "rm2_perbandingan_mode.csv")

    rek = pd.DataFrame(rekomendasi).sort_values(["total_error_%", "MIR_%", "FAR_%"])
    catat("\nPeringkat konfigurasi (total error = FAR + FRR + MIR) → kandidat 'konfigurasi terbaik' RM 3:")
    catat(rek[["konfigurasi", "total_error_%", "FAR_%", "FRR_%", "MIR_%"]].to_string(index=False))
    simpan(rek, keluar, "rm2_peringkat_konfigurasi.csv")


# ==============================================================================
# DATA LIVE (tanpa label): distribusi keputusan & jalur pencocokan nama
# ==============================================================================
def analisis_live(live, keluar):
    if live.empty:
        return
    catat("\n" + "=" * 78)
    catat("DATA LIVE DI KELAS (pelengkap RM 1 & RM 2, tanpa label kebenaran)")
    catat("=" * 78)
    tabel = (live.groupby(["kondisi_cahaya", "clahe", "mode_verifikasi", "alasan"])
             .size().unstack(fill_value=0).reset_index())
    catat(tabel.to_string(index=False))
    simpan(tabel, keluar, "live_distribusi_keputusan.csv")

    diterima = live[live["pred_nim"] != UNKNOWN]
    if not diterima.empty:
        via = diterima["cocok_via"].value_counts()
        catat("\nJalur pencocokan ke daftar hadir (hasil wajah diterima):")
        for k, v in via.items():
            catat(f"  {k:10s}: {v} ({pct(v, len(diterima))}%)")
        catat("  'nis' = baris daftar hadir ditemukan lewat NIS (seharusnya seluruhnya)."
              " 'nama' = cadangan nama persis untuk baris tanpa NIS; 'tidak_ada' = templat"
              " tidak punya baris di daftar hadir. Log sebelum 5 Nov 2026: 'nim'/'nama'"
              " memakai pencocokan nama longgar.")

    catat("\nLatensi live per kondisi (ms):")
    lat = live.groupby(["kondisi_cahaya", "clahe"]).agg(
        n=("t_frame_ms", "size"),
        t_clahe=("t_clahe_ms", "mean"),
        t_embedding=("t_embedding_ms", "mean"),
        t_frame=("t_frame_ms", "mean"),
    ).round(2).reset_index()
    catat(lat.to_string(index=False))
    simpan(lat, keluar, "live_latensi.csv")


# ==============================================================================
# RM 3: OPERASIONAL WAJAH VS MANUAL
# ==============================================================================
def analisis_rm3(sesi, keluar):
    catat("\n" + "=" * 78)
    catat("RM 3: KINERJA OPERASIONAL PRESENSI WAJAH VS MANUAL")
    catat("=" * 78)

    tabel = sesi.groupby("metode").agg(
        n_sesi=("sesi_id", "count"),
        rata_siswa=("jumlah_siswa", "mean"),
        durasi_total_detik=("durasi_total_detik", "mean"),
        sd_durasi=("durasi_total_detik", "std"),
        detik_per_siswa=("detik_per_siswa", "mean"),
        sd_detik_per_siswa=("detik_per_siswa", "std"),
        kesesuaian_scan_persen=("kesesuaian_scan_persen", "mean"),
        koreksi_total=("koreksi_total", "mean"),
        koreksi_jadi_hadir=("koreksi_jadi_hadir", "mean"),
        koreksi_batal_hadir=("koreksi_batal_hadir", "mean"),
    ).round(2).reset_index()
    catat(tabel.to_string(index=False))
    simpan(tabel, keluar, "rm3_wajah_vs_manual.csv")

    wajah = sesi[sesi["metode"] == "wajah"]
    manual = sesi[sesi["metode"] == "manual"]
    if not wajah.empty and not manual.empty:
        selisih = manual["detik_per_siswa"].mean() - wajah["detik_per_siswa"].mean()
        catat(f"\nSelisih rata-rata waktu per siswa (manual − wajah): {selisih:.2f} detik")
        if stats is not None and len(wajah) > 1 and len(manual) > 1:
            p = stats.mannwhitneyu(wajah["detik_per_siswa"], manual["detik_per_siswa"]).pvalue
            catat(f"Mann-Whitney detik/siswa wajah vs manual: p = {p:.4g}")

    if not wajah.empty:
        per_konfig = wajah.groupby(["clahe", "mode_verifikasi", "kondisi_cahaya"]).agg(
            n_sesi=("sesi_id", "count"),
            detik_per_siswa=("detik_per_siswa", "mean"),
            kesesuaian_scan_persen=("kesesuaian_scan_persen", "mean"),
            koreksi_total=("koreksi_total", "mean"),
        ).round(2).reset_index()
        catat("\nSesi wajah per konfigurasi:")
        catat(per_konfig.to_string(index=False))
        simpan(per_konfig, keluar, "rm3_wajah_per_konfigurasi.csv")

    if plt is not None and not tabel.empty:
        fig, ax = plt.subplots(figsize=(6, 4))
        sesi.boxplot(column="detik_per_siswa", by="metode", ax=ax)
        ax.set_title("RM 3: Waktu presensi per siswa")
        ax.set_ylabel("detik / siswa")
        fig.suptitle("")
        fig.tight_layout()
        fig.savefig(os.path.join(keluar, "rm3_grafik_durasi.png"), dpi=150)
        plt.close(fig)


# ==============================================================================
# KODE SISWA: NIM diganti S01–S30 pada semua keluaran
# ==============================================================================
BUKAN_NIM = {"", UNKNOWN, "tidak_terdaftar"}
# Nilai yang sudah berupa kode siswa (nama folder dataset S01…, TT01…) tidak dinomori ulang
POLA_KODE_SISWA = re.compile(r"(S|TT)\d+")


def baca_padanan(path):
    """Padanan resmi NIS → kode siswa (Bab III Tabel 3.8, kode = S + nomor urut absen), yaitu
    berkas padanan_kode_siswa_RAHASIA.csv buatan buat_struktur_dataset.py
    (kolom: kode, absen, nis, nama, status). Kolom 'nim' juga diterima sebagai pengganti 'nis'."""
    p = pd.read_csv(path, dtype=str).fillna("")
    kolom_nis = "nis" if "nis" in p else ("nim" if "nim" in p else None)
    if kolom_nis is None or "kode" not in p:
        raise SystemExit(f"❌ {path} harus memuat kolom 'kode' dan 'nis'.")
    p = p[p[kolom_nis].str.strip() != ""]
    padanan = dict(zip(p[kolom_nis].str.strip(), p["kode"].str.strip()))
    kembar = p[kolom_nis].str.strip().duplicated()
    if kembar.any():
        raise SystemExit(f"❌ NIS ganda di {path}: {', '.join(p.loc[kembar, kolom_nis])}")
    return padanan


def samarkan_nim(df, keluar, padanan=None):
    """Ganti NIS di kolom NIM dan jalur berkas dengan kode siswa.
    - Dengan [padanan] (dict NIS → kode dari baca_padanan): kode mengikuti nomor urut absen
      (Tabel 3.8). NIS yang tidak ada di padanan (mis. templat di luar kelas penelitian)
      diberi kode X01, X02, … dan dilaporkan.
    - Tanpa padanan: S01, S02, … menurut urutan NIS (BELUM TENTU sama dengan nomor absen).
    Nilai yang sudah berupa kode (log Evaluasi Dataset dengan folder S01…) dibiarkan apa adanya."""
    nim = sorted({v for k in KOLOM_NIM if k in df for v in df[k].unique()} - BUKAN_NIM)
    nim = [n for n in nim if not POLA_KODE_SISWA.fullmatch(n)]
    if padanan is not None:
        kode = {n: padanan[n] for n in nim if n in padanan}
        asing = [n for n in nim if n not in padanan]
        kode.update({n: f"X{i:02d}" for i, n in enumerate(asing, 1)})
        catat("ℹ️  Kode siswa mengikuti padanan resmi (nomor urut absen, Tabel 3.8).")
        if asing:
            catat(f"⚠️  {len(asing)} NIS di log tidak ada di padanan resmi → diberi kode "
                  f"X01–X{len(asing):02d} (mis. templat anggota tim / siswa kelas lain). "
                  "Periksa sebelum hasil dilaporkan.")
    else:
        kode = {n: f"S{i:02d}" for i, n in enumerate(nim, 1)}
        if kode:
            catat("⚠️  Tanpa --padanan: kode S diberi menurut urutan NIS dan BELUM TENTU sama "
                  "dengan nomor urut absen (Tabel 3.8). Untuk laporan, jalankan dengan "
                  "--padanan <padanan_kode_siswa_RAHASIA.csv>.")
    if not kode:
        return df
    for k in KOLOM_NIM:
        if k in df:
            df[k] = df[k].map(lambda v: kode.get(v, v))
    if "file" in df:
        pola = re.compile(r"(?<![0-9A-Za-z])(" + "|".join(map(re.escape, kode)) + r")(?![0-9A-Za-z])")
        df["file"] = df["file"].fillna("").map(lambda f: pola.sub(lambda m: kode[m.group(1)], f))
    # Nama berbeda dari berkas padanan resmi agar berkas resmi tidak tertimpa
    path = os.path.join(keluar, "padanan_kode_dipakai_RAHASIA.csv")
    pd.DataFrame({"kode": list(kode.values()), "nis": list(kode.keys())}).to_csv(path, index=False)
    catat(f"ℹ️  NIS diganti kode siswa. Padanan yang dipakai disimpan di {path} "
          "(simpan terpisah, jangan dilampirkan pada laporan atau di-commit).")
    return df


# ==============================================================================
# PENETAPAN PARAMETER (DATA KALIBRASI) DAN PENGUJIAN (DATA UJI)
# ==============================================================================
# Skenario: (kondisi CLAHE, verifikasi margin)
SKENARIO = {"A": (0, False), "B": (1, False), "C": (0, True), "D": (1, True)}
KONDISI_TIDAK_MEMADAI = ["low_light", "backlight"]
BATAS_LATENSI_MS = 600
BATAS_KENAIKAN_FRR = 4.0
BATAS_FRR_TAU = 10.0      # langkah 2–3 penetapan τ: batas toleransi FRR kalibrasi (%)
BATAS_FAR_LONGGAR = 5.0   # langkah 3 penetapan τ: FAR kalibrasi paling tinggi yang masih diterima (%)
PATH_MODEL = os.path.join("assets", "models", "mobilefacenet.tflite")
PATH_PUBSPEC = "pubspec.yaml"


def uji_mcnemar(b, c):
    """Persamaan (3.14) dengan koreksi kontinuitas. Uji binomial eksak dua sisi, persamaan (3.15),
    dipakai bila b + c < 25 atau perubahannya hanya satu arah (b = 0 atau c = 0), Bab III 3.5.6."""
    if b + c == 0:
        return np.nan, "-"
    if b + c < 25 or b == 0 or c == 0:
        p = stats.binomtest(min(b, c), b + c, 0.5).pvalue if stats is not None else np.nan
        return p, "binomial eksak"
    chi2 = (abs(b - c) - 1) ** 2 / (b + c)
    p = stats.chi2.sf(chi2, 1) if stats is not None else np.nan
    return p, f"χ² = {chi2:.3f}"


def statistik_latensi(seri):
    seri = seri.dropna()
    if seri.empty:
        return {"latensi_rata_ms": np.nan, "latensi": "-", "median_ms": np.nan, "P95_ms": np.nan}
    return {"latensi_rata_ms": round(seri.mean(), 2), "latensi": mean_sd(seri),
            "median_ms": round(seri.median(), 2), "P95_ms": round(seri.quantile(0.95), 2)}


def hasil_skenario(ds, s, par):
    clahe, pakai_margin = SKENARIO[s]
    g = ds[ds["clahe"] == clahe]
    delta = par[f"delta_clahe{clahe}"] if pakai_margin else None
    return g, prediksi(g, par[f"tau_clahe{clahe}"], delta)


# Kolom jumlah kesalahan (Tabel 3.33) dan rincian penolakan (persamaan 3.8)
KOLOM_RINCIAN = ["nFA", "nFR", "nMI", "nTD", "nTA", "nTM", "tolak_margin_TT"]


def rincian_penolakan(g, pred, tau, delta):
    """Jumlah kesalahan dan penyebab penolakan, dihitung ulang dari d1, d2, τ, dan δ yang dikunci
    (bukan dari kolom 'alasan' di log, yang memakai τ/δ aplikasi saat foto diproses).
      nTD = citra siswa terdaftar yang wajahnya tidak terdeteksi
      nTA = citra siswa terdaftar yang ditolak karena d1 > τ
      nTM = citra siswa terdaftar yang ditolak karena d2 − d1 < δ (selalu 0 pada skenario A, B)
      tolak_margin_TT = citra siswa tidak terdaftar yang ditolak karena margin (penolakan benar)
    Sesuai persamaan (3.8): nFR = nTD + nTA + nTM."""
    det = g["terdeteksi"]
    gen, imp = g["terdaftar"] == 1, g["terdaftar"] == 0
    lolos_ambang = det & (g["jarak_terbaik"] <= tau)
    if delta is None:
        gagal_margin = pd.Series(False, index=g.index)
    else:
        lolos_margin = (g["jarak_kedua"] >= 999) | ((g["jarak_kedua"] - g["jarak_terbaik"]) >= delta)
        gagal_margin = lolos_ambang & ~lolos_margin
    hasil = {
        "nFA": int((imp & (pred != UNKNOWN)).sum()),
        "nFR": int((gen & (pred == UNKNOWN)).sum()),
        "nMI": int((gen & (pred != UNKNOWN) & (pred != g["label_nim"])).sum()),
        "nTD": int((gen & ~det).sum()),
        "nTA": int((gen & det & ~lolos_ambang).sum()),
        "nTM": int((gen & gagal_margin).sum()),
        "tolak_margin_TT": int((imp & gagal_margin).sum()),
    }
    if hasil["nFR"] != hasil["nTD"] + hasil["nTA"] + hasil["nTM"]:
        catat(f"⚠️  Rincian FRR tidak cocok: nFR = {hasil['nFR']}, "
              f"nTD + nTA + nTM = {hasil['nTD'] + hasil['nTA'] + hasil['nTM']}")
    return hasil


def metrik_skenario(ds, par):
    baris = []
    for s in SKENARIO:
        g, pred = hasil_skenario(ds, s, par)
        if g.empty:
            continue
        m = metrik(g, pred)
        clahe, pakai_margin = SKENARIO[s]
        rincian = rincian_penolakan(g, pred, par[f"tau_clahe{clahe}"],
                                    par[f"delta_clahe{clahe}"] if pakai_margin else None)
        baris.append({"skenario": s, "n_citra": len(g),
                      "FAR_%": m["FAR_%"], "FRR_%": m["FRR_%"], "MIR_%": m["MIR_%"],
                      "FRR+MIR_%": round(m["FRR_%"] + m["MIR_%"], 2), "FTA": m["FTA"],
                      **rincian,
                      **statistik_latensi(g.loc[g["terdeteksi"], "t_frame_ms"])})
    return pd.DataFrame(baris)


def interaksi_clahe_margin(tabel):
    """Bab II Subbab 2.5 dan Bab III Subbab 3.5.6: interaksi CLAHE × verifikasi margin,
    dilaporkan deskriptif (tidak diuji sebagai hipotesis) untuk setiap metrik:
      pengaruh margin tanpa CLAHE  = C − A
      pengaruh margin dengan CLAHE = D − B
      interaksi                    = (D − B) − (C − A)
    dalam poin persentase. Nilai mendekati nol berarti pengaruh margin tidak bergantung
    pada CLAHE. [tabel] = keluaran metrik_skenario dengan kolom 'kategori'."""
    baris = []
    for kategori, t in tabel.groupby("kategori", sort=False):
        nilai = t.set_index("skenario")
        if not set(SKENARIO) <= set(nilai.index):
            continue
        for kolom in ["FAR_%", "FRR_%", "MIR_%"]:
            margin_tanpa_clahe = nilai.at["C", kolom] - nilai.at["A", kolom]
            margin_dengan_clahe = nilai.at["D", kolom] - nilai.at["B", kolom]
            baris.append({"kategori": kategori, "metrik": kolom.replace("_%", ""),
                          "C_minus_A": round(margin_tanpa_clahe, 2),
                          "D_minus_B": round(margin_dengan_clahe, 2),
                          "interaksi": round(margin_dengan_clahe - margin_tanpa_clahe, 2)})
    return pd.DataFrame(baris)


# Komponen waktu persamaan (2.16); Tpraproses = decode + crop
TAHAP_WAKTU = [
    ("Tdeteksi", ["t_deteksi_ms"]),
    ("Tpraproses (decode + crop)", ["t_decode_ms", "t_crop_ms"]),
    ("TCLAHE", ["t_clahe_ms"]),
    ("Tembedding (waktu inferensi)", ["t_embedding_ms"]),
    ("Tpencocokan", ["t_matching_ms"]),
    ("Total end-to-end", ["t_frame_ms"]),
]
TARAF_CLAHE = {0: "tanpa CLAHE (A, C)", 1: "dengan CLAHE (B, D)"}


def latensi_per_tahap(ds):
    """Bab III 3.5.3: rata-rata, SD, median, dan P95 setiap tahap per taraf CLAHE,
    hanya citra yang wajahnya terdeteksi."""
    baris, sebaran = [], {}
    for clahe, taraf in TARAF_CLAHE.items():
        g = ds[(ds["clahe"] == clahe) & ds["terdeteksi"]]
        for tahap, kolom in TAHAP_WAKTU:
            seri = g[kolom].sum(axis=1, min_count=len(kolom)).dropna()
            sebaran[(taraf, tahap)] = seri
            baris.append({"taraf": taraf, "tahap": tahap, "n": len(seri),
                          "rata_ms": round(seri.mean(), 2) if len(seri) else np.nan,
                          "sd_ms": round(seri.std(ddof=1), 2) if len(seri) > 1 else np.nan,
                          "median_ms": round(seri.median(), 2) if len(seri) else np.nan,
                          "P95_ms": round(seri.quantile(0.95), 2) if len(seri) else np.nan})
    return pd.DataFrame(baris), sebaran


def grafik_latensi_per_tahap(sebaran, path):
    if plt is None:
        return
    fig, axes = plt.subplots(1, len(TARAF_CLAHE), figsize=(12, 4.5), sharey=True)
    for ax, taraf in zip(np.atleast_1d(axes), TARAF_CLAHE.values()):
        nama = [t for t, _ in TAHAP_WAKTU if len(sebaran[(taraf, t)])]
        if not nama:
            continue
        ax.boxplot([sebaran[(taraf, t)].values for t in nama], showfliers=False)
        ax.set_xticks(range(1, len(nama) + 1))
        ax.set_xticklabels([t.split(" (")[0] for t in nama], rotation=30, ha="right")
        ax.set_title(taraf)
        ax.set_ylabel("waktu (ms)")
    fig.suptitle("Sebaran waktu per tahap pada data uji")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def pilih_tau(g, frr_maks=None, far_longgar=None):
    """Penetapan τ tiga langkah (Bab III Subbab 3.4.4), dicoba pada 0,50–1,50 (langkah 0,01),
    aturan ambang tunggal:
      Langkah 1: cari τ terbesar dengan FAR kalibrasi 0%.
      Langkah 2: pakai τ tersebut bila FRR kalibrasinya ≤ frr_maks (bawaan 10%).
      Langkah 3: bila FRR > frr_maks (atau tidak ada τ dengan FAR 0%), naikkan τ seperlunya:
                 τ terkecil dengan FRR ≤ frr_maks dan FAR ≤ far_longgar (bawaan 5%).
      Cadangan : bila tetap tidak ada, τ dengan FAR + FRR terkecil (dilaporkan sebagai
                 keterbatasan; bila sama, FAR lebih rendah, lalu τ lebih kecil).
    Mengembalikan (τ, tabel pencarian, kode langkah, keterangan)."""
    frr_maks = BATAS_FRR_TAU if frr_maks is None else frr_maks
    far_longgar = BATAS_FAR_LONGGAR if far_longgar is None else far_longgar
    hasil = pd.DataFrame([{"tau": a, **metrik(g, prediksi(g, a))}
                          for a in np.round(np.arange(0.50, 1.505, 0.01), 2)])
    nol = hasil[hasil["FAR_%"] == 0]
    tau1 = float(nol["tau"].max()) if not nol.empty else None
    if tau1 is not None:
        frr1 = float(hasil.loc[hasil["tau"] == tau1, "FRR_%"].iloc[0])
        if frr1 <= frr_maks:
            return tau1, hasil, "2", (f"langkah 1–2: τ terbesar dengan FAR 0% dan FRR {frr1:.2f}% "
                                      f"≤ {frr_maks:g}%")
        calon = hasil[(hasil["tau"] > tau1) & (hasil["FRR_%"] <= frr_maks)
                      & (hasil["FAR_%"] <= far_longgar)]
        alasan = f"FRR pada τ = {tau1:.2f} (FAR 0%) sebesar {frr1:.2f}% > {frr_maks:g}%"
    else:
        calon = hasil[(hasil["FRR_%"] <= frr_maks) & (hasil["FAR_%"] <= far_longgar)]
        alasan = "tidak ada τ dengan FAR 0%"
    if not calon.empty:
        baris = calon.sort_values("tau").iloc[0]
        return float(baris["tau"]), hasil, "3", (
            f"langkah 3: {alasan}; τ dinaikkan sampai FRR {baris['FRR_%']:.2f}% ≤ {frr_maks:g}% "
            f"dengan FAR {baris['FAR_%']:.2f}% ≤ {far_longgar:g}%")
    t = hasil.assign(jumlah=hasil["FAR_%"] + hasil["FRR_%"]).sort_values(["jumlah", "FAR_%", "tau"])
    baris = t.iloc[0]
    return float(baris["tau"]), hasil, "cadangan", (
        f"cadangan: {alasan} dan tidak ada τ dengan FRR ≤ {frr_maks:g}% serta FAR ≤ {far_longgar:g}%; "
        f"dipilih FAR + FRR terkecil (FAR {baris['FAR_%']:.2f}%, FRR {baris['FRR_%']:.2f}%) — "
        "laporkan sebagai keterbatasan")


def pilih_delta(g, tau):
    """δ = nilai terbesar (0,00–0,20) yang kenaikan FRR kalibrasinya ≤ 4 poin dibanding tanpa margin."""
    frr_tanpa = metrik(g, prediksi(g, tau))["FRR_%"]
    hasil = pd.DataFrame([{"delta": d, **metrik(g, prediksi(g, tau, d))}
                          for d in np.round(np.arange(0.0, 0.205, 0.01), 2)])
    hasil["kenaikan_FRR"] = (hasil["FRR_%"] - frr_tanpa).round(2)
    return float(hasil.loc[hasil["kenaikan_FRR"] <= BATAS_KENAIKAN_FRR, "delta"].max()), hasil


def pilih_konfigurasi(tabel):
    """Tabel 3.18: syarat latensi rata-rata ≤ 600 ms, lalu FAR terendah, FRR + MIR terendah,
    MIR terendah, dan konfigurasi paling sederhana (A, B, C, D)."""
    t = tabel.copy()
    t["urutan"] = t["skenario"].map({s: i for i, s in enumerate(SKENARIO)})
    memenuhi = t[t["latensi_rata_ms"] <= BATAS_LATENSI_MS]
    calon, catatan = (memenuhi, "memenuhi syarat latensi") if not memenuhi.empty else (
        t, f"tidak ada yang memenuhi latensi ≤ {BATAS_LATENSI_MS} ms; dipilih FAR kalibrasi terendah")
    terbaik = calon.sort_values(["FAR_%", "FRR+MIR_%", "MIR_%", "urutan"]).iloc[0]
    return terbaik["skenario"], catatan


# Kelompok jarak untuk memeriksa posisi τ dan δ (Bab II 2.2.6, Bab III 3.4.4)
KELOMPOK_JARAK = {
    "terdaftar_benar": "Terdaftar, kandidat pertama benar",
    "terdaftar_salah": "Terdaftar, kandidat pertama siswa lain",
    "tidak_terdaftar": "Tidak terdaftar (non-mated)",
}


def kelompok_jarak(g):
    """Kelompokkan citra yang wajahnya terdeteksi menurut jenis percobaan."""
    det = g[g["terdeteksi"]]
    gen = det["terdaftar"] == 1
    return {
        "terdaftar_benar": det[gen & (det["raw_nim"] == det["label_nim"])],
        "terdaftar_salah": det[gen & (det["raw_nim"] != det["label_nim"])],
        "tidak_terdaftar": det[det["terdaftar"] == 0],
    }


def _ringkas(seri):
    seri = seri.dropna()
    if seri.empty:
        return {"n": 0, "min": np.nan, "P5": np.nan, "median": np.nan, "P95": np.nan, "maks": np.nan}
    return {"n": len(seri), "min": round(seri.min(), 4), "P5": round(seri.quantile(0.05), 4),
            "median": round(seri.median(), 4), "P95": round(seri.quantile(0.95), 4),
            "maks": round(seri.max(), 4)}


def sebaran_jarak(ds, par):
    """Ringkasan sebaran d1 dan selisih d2 − d1 per taraf CLAHE dan jenis percobaan,
    beserta posisi τ dan δ terpilih. Tiga d1 non-mated terkecil ditampilkan untuk melihat
    apakah τ ditentukan oleh sebagian besar citra non-mated atau oleh satu citra menyimpang."""
    baris = []
    for clahe in [0, 1]:
        g = ds[ds["clahe"] == clahe]
        if g.empty:
            continue
        tau, delta = par[f"tau_clahe{clahe}"], par[f"delta_clahe{clahe}"]
        for kunci, k in kelompok_jarak(g).items():
            d1 = k["jarak_terbaik"]
            ada_d2 = k["jarak_kedua"] < 999
            selisih = (k["jarak_kedua"] - k["jarak_terbaik"])[ada_d2]
            terkecil = ", ".join(f"{v:.3f}" for v in sorted(d1.dropna())[:3]) if kunci == "tidak_terdaftar" else ""
            for besaran, seri, batas, nama_batas in [("d1", d1, tau, "tau"), ("d2-d1", selisih, delta, "delta")]:
                baris.append({"clahe": clahe, "besaran": besaran, "kelompok": KELOMPOK_JARAK[kunci],
                              **_ringkas(seri), nama_batas: batas,
                              # lolos ambang: d1 ≤ τ; lolos margin: d2 − d1 ≥ δ
                              "jumlah_lolos_batas": int((seri <= batas).sum() if besaran == "d1"
                                                        else (seri >= batas).sum()),
                              "3_d1_non_mated_terkecil": terkecil if besaran == "d1" else ""})
    kolom = ["clahe", "besaran", "kelompok", "n", "min", "P5", "median", "P95", "maks",
             "tau", "delta", "jumlah_lolos_batas", "3_d1_non_mated_terkecil"]
    return pd.DataFrame(baris).reindex(columns=kolom)


def grafik_sebaran(ds, par, keluar):
    """Histogram d1 (garis τ) dan d2 − d1 (garis δ) per taraf CLAHE."""
    if plt is None:
        return
    warna = {"terdaftar_benar": "tab:green", "terdaftar_salah": "tab:orange", "tidak_terdaftar": "tab:red"}
    for besaran, nama_berkas, judul_batas in [("d1", "kalibrasi_sebaran_d1.png", "τ"),
                                              ("d2-d1", "kalibrasi_sebaran_selisih.png", "δ")]:
        fig, axes = plt.subplots(1, 2, figsize=(12, 4.5), sharey=True)
        for ax, clahe in zip(axes, [0, 1]):
            g = ds[ds["clahe"] == clahe]
            if g.empty:
                continue
            batas = par[f"tau_clahe{clahe}"] if besaran == "d1" else par[f"delta_clahe{clahe}"]
            semua = []
            for kunci, k in kelompok_jarak(g).items():
                if besaran == "d1":
                    seri = k["jarak_terbaik"].dropna()
                else:
                    seri = (k["jarak_kedua"] - k["jarak_terbaik"])[k["jarak_kedua"] < 999].dropna()
                semua.append((kunci, seri))
            nilai = pd.concat([s for _, s in semua]) if semua else pd.Series(dtype=float)
            if nilai.empty:
                continue
            tepi = np.linspace(min(nilai.min(), batas) - 0.02, max(nilai.max(), batas) + 0.02, 31)
            for kunci, seri in semua:
                if len(seri):
                    ax.hist(seri, bins=tepi, alpha=0.55, color=warna[kunci],
                            label=f"{KELOMPOK_JARAK[kunci]} (n={len(seri)})")
            ax.axvline(batas, color="black", linestyle="--", linewidth=1.5,
                       label=f"{judul_batas} terpilih = {batas:.2f}")
            ax.set_title(f"{'Dengan' if clahe else 'Tanpa'} CLAHE")
            ax.set_xlabel("jarak d1" if besaran == "d1" else "selisih d2 − d1")
            ax.set_ylabel("jumlah citra")
            ax.legend(fontsize=8)
        fig.suptitle(f"Sebaran {'d1' if besaran == 'd1' else 'd2 − d1'} pada data kalibrasi")
        fig.tight_layout()
        fig.savefig(os.path.join(keluar, nama_berkas), dpi=150)
        plt.close(fig)


def info_versi(path_model=None, versi_app=None):
    """Versi aplikasi (pubspec.yaml) dan sidik jari SHA-256 berkas model (Tabel 3.31)."""
    if versi_app is None and os.path.exists(PATH_PUBSPEC):
        with open(PATH_PUBSPEC, encoding="utf-8") as f:
            m = re.search(r"^version:\s*(\S+)", f.read(), re.M)
            versi_app = m.group(1) if m else None
    path_model = path_model or PATH_MODEL
    sha = None
    if os.path.exists(path_model):
        h = hashlib.sha256()
        with open(path_model, "rb") as f:
            for blok in iter(lambda: f.read(1 << 20), b""):
                h.update(blok)
        sha = h.hexdigest()
    return versi_app, path_model, sha


def hitung_ty(ds, ty=None):
    """T_Y = (median Ȳw memadai + median Ȳw low-light) / 2, lalu verifikasi kategori tiap citra."""
    if ds["luminansi_wajah"].isna().all():
        return None, pd.DataFrame()
    citra = ds.dropna(subset=["luminansi_wajah"]).drop_duplicates("file")
    yw, yl = citra["luminansi_wajah"], citra["luminansi_latar"]
    if ty is None:
        ty = (yw[citra["kondisi_cahaya"] == "memadai"].median()
              + yw[citra["kondisi_cahaya"] == "low_light"].median()) / 2
    aturan = {"memadai": yw >= ty, "low_light": yw < ty, "backlight": (yw / yl) < 1}
    baris = []
    for kondisi, sesuai in aturan.items():
        pilih = citra["kondisi_cahaya"] == kondisi
        tidak = citra.loc[pilih & ~sesuai, "file"].tolist()
        baris.append({"kondisi": kondisi, "n_citra": int(pilih.sum()),
                      "sesuai": int((pilih & sesuai).sum()), "tidak_sesuai": len(tidak),
                      "berkas_tidak_sesuai": "; ".join(tidak)})
    return round(float(ty), 2), pd.DataFrame(baris)


def satu_sesi(ds, nama_mode):
    if ds.empty:
        catat("❌ Tidak ada data evaluasi dataset untuk sesi yang dipilih.")
        return False
    if ds["sesi_id"].nunique() > 1:
        catat(f"❌ Mode {nama_mode} membutuhkan satu sesi evaluasi. Pilih dengan --sesi-dataset, "
              f"pilihan: {', '.join(sorted(ds['sesi_id'].unique()))}")
        return False
    return True


def analisis_kalibrasi(ds, keluar, path_lembar, path_model=None, versi_app=None):
    catat("\n" + "=" * 78)
    catat("PENETAPAN PARAMETER DARI DATA KALIBRASI (Bab III Subbab 3.4.4–3.4.6)")
    catat("=" * 78)
    catat(f"Aturan τ: FAR 0% selama FRR ≤ {BATAS_FRR_TAU:g}%; bila tidak, FRR ≤ {BATAS_FRR_TAU:g}% "
          f"dengan FAR ≤ {BATAS_FAR_LONGGAR:g}%; bila tetap tidak bisa, FAR + FRR terkecil.")

    par, langkah = {}, {}
    for clahe in [0, 1]:
        g = ds[ds["clahe"] == clahe]
        if g.empty:
            catat(f"⚠️  Tidak ada data clahe = {clahe}; jalankan evaluasi dengan dan tanpa CLAHE.")
            return
        if not (g["terdaftar"] == 0).any() or not (g["terdaftar"] == 1).any():
            catat("❌ Data kalibrasi harus memuat citra siswa terdaftar DAN tidak terdaftar "
                  "(S26–S30, tanpa folder registrasi). τ tidak dapat ditetapkan tanpa keduanya.")
            return
        tau, sweep_tau, kode, keterangan = pilih_tau(g)
        delta, sweep_delta = pilih_delta(g, tau)
        par[f"tau_clahe{clahe}"], par[f"delta_clahe{clahe}"] = tau, delta
        m = metrik(g, prediksi(g, tau))
        langkah[clahe] = {"kode": kode, "keterangan": keterangan, "FAR": m["FAR_%"], "FRR": m["FRR_%"],
                          "n_non_mated": m["n_impostor"], "n_mated": m["n_genuine"]}
        simpan(sweep_tau, keluar, f"kalibrasi_pencarian_tau_clahe{clahe}.csv")
        simpan(sweep_delta, keluar, f"kalibrasi_pencarian_delta_clahe{clahe}.csv")
        catat(f"[clahe = {clahe}] τ = {tau:.2f} (FAR {m['FAR_%']:.2f}%, FRR {m['FRR_%']:.2f}%), "
              f"δ = {delta:.2f}")
        catat(f"              {keterangan}")
        if kode == "cadangan":
            catat("              ⚠️  Kondisi ini harus dilaporkan sebagai keterbatasan.")

    ty, cek_ty = hitung_ty(ds)
    tabel = metrik_skenario(ds, par)
    terbaik, catatan = pilih_konfigurasi(tabel)

    catat("\nMetrik skenario A–D pada data kalibrasi:")
    catat(tabel.drop(columns="latensi_rata_ms").to_string(index=False))
    simpan(tabel, keluar, "kalibrasi_metrik_skenario.csv")
    catat(f"\nKonfigurasi terbaik: {terbaik} ({catatan})")
    if ty is None:
        catat("⚠️  Kolom luminansi belum ada di log; T_Y tidak dihitung.")
    else:
        catat(f"T_Y = {ty}")
        catat(cek_ty.drop(columns="berkas_tidak_sesuai").to_string(index=False))
        simpan(cek_ty, keluar, "kalibrasi_verifikasi_luminansi.csv")

    # Sebaran d1 dan d2 − d1 beserta posisi τ dan δ (Bab III 3.4.4)
    sebaran = sebaran_jarak(ds, par)
    catat("\nSebaran jarak pada data kalibrasi (citra yang wajahnya terdeteksi):")
    catat(sebaran.to_string(index=False))
    simpan(sebaran, keluar, "kalibrasi_sebaran_jarak.csv")
    grafik_sebaran(ds, par, keluar)

    versi, path_model, sha = info_versi(path_model, versi_app)
    if versi is None or sha is None:
        catat("ℹ️  Versi aplikasi/berkas model tidak ditemukan di folder ini; isi manual di lembar "
              "atau jalankan dari folder proyek (opsi --versi-app dan --model).")

    with open(path_lembar, "w", encoding="utf-8") as f:
        f.write("LEMBAR PENETAPAN PARAMETER\n")
        f.write(f"Tanggal  : {datetime.now():%Y-%m-%d %H:%M}\n")
        f.write(f"Sesi     : {ds['sesi_id'].iloc[0]}\n\n")
        f.write("[parameter]\n")
        f.write(f"T_Y = {ty if ty is not None else '-'}\n")
        for k, v in par.items():
            f.write(f"{k} = {v:.2f}\n")
        f.write(f"konfigurasi_terbaik = {terbaik}\n\n")
        f.write("[penetapan τ — aturan tiga langkah, Bab III Subbab 3.4.4]\n")
        f.write(f"Batas: FRR kalibrasi ≤ {BATAS_FRR_TAU:g}%, FAR longgar ≤ {BATAS_FAR_LONGGAR:g}%\n")
        for clahe, l in langkah.items():
            f.write(f"{'Dengan' if clahe else 'Tanpa'} CLAHE : τ{clahe} = {par[f'tau_clahe{clahe}']:.2f}, "
                    f"FAR {l['FAR']:.2f}% ({l['n_non_mated']} citra non-mated), "
                    f"FRR {l['FRR']:.2f}% ({l['n_mated']} citra mated), langkah {l['kode']}\n")
            f.write(f"               {l['keterangan']}\n")
        f.write(f"\nAlasan pemilihan konfigurasi: {catatan}\n\n")
        f.write("[metrik data kalibrasi]\n")
        f.write(tabel.drop(columns=["latensi_rata_ms", *KOLOM_RINCIAN]).to_string(index=False) + "\n\n")
        f.write("[versi]\n")
        f.write(f"Versi aplikasi : {versi or '__________ (isi manual)'}\n")
        f.write(f"Berkas model   : {os.path.basename(path_model)}\n")
        f.write(f"sha256_model = {sha or '-'}\n")
        f.write("Versi aplikasi dan berkas model tidak diubah setelah penguncian.\n\n")
        f.write("Ditetapkan sebelum citra uji diproses.\n\n")
        f.write("Tanda tangan tim:\n\n1. ____________________\n2. ____________________\n"
                "3. ____________________\n")
    catat(f"  → lembar penetapan: {path_lembar}")


def baca_lembar(path):
    par = {}
    with open(path, encoding="utf-8") as f:
        for baris in f:
            m = re.match(r"^(T_Y|tau_clahe[01]|delta_clahe[01]|konfigurasi_terbaik|sha256_model) = (\S+)$",
                         baris.strip())
            if m:
                k, v = m.groups()
                par[k] = v if k in ("konfigurasi_terbaik", "sha256_model") or v == "-" else float(v)
    return par


def per_citra(ds, s, par):
    g, pred = hasil_skenario(ds, s, par)
    gen = g["terdaftar"] == 1
    return pd.DataFrame({
        "kondisi": g["kondisi_cahaya"].values,
        "terdaftar": gen.values,
        "label": g["label_nim"].values,
        "MIR": (gen & (pred != UNKNOWN) & (pred != g["label_nim"])).values,
        "FRR": (gen & (pred == UNKNOWN)).values,
        "FAR": (~gen & (pred != UNKNOWN)).values,
        "terdeteksi": g["terdeteksi"].values,
        "t_frame_ms": g["t_frame_ms"].values,
    }, index=g["file"].values)


def analisis_uji(ds, keluar, path_lembar, path_model=None, versi_app=None):
    catat("\n" + "=" * 78)
    catat("PENGUJIAN PADA DATA UJI (parameter dari lembar penetapan)")
    catat("=" * 78)
    if not os.path.exists(path_lembar):
        catat(f"❌ {path_lembar} tidak ditemukan. Jalankan --mode kalibrasi terlebih dahulu.")
        return
    par = baca_lembar(path_lembar)
    wajib = ["tau_clahe0", "delta_clahe0", "tau_clahe1", "delta_clahe1"]
    if any(k not in par for k in wajib):
        catat(f"❌ Lembar penetapan tidak lengkap: {', '.join(k for k in wajib if k not in par)}")
        return
    catat("Parameter: " + ", ".join(f"{k} = {par[k]}" for k in ["T_Y", *wajib, "konfigurasi_terbaik"]
                                     if k in par))

    # Berkas model harus sama dengan saat penetapan parameter (Tabel 3.31)
    _, _, sha_sekarang = info_versi(path_model, versi_app)
    sha_lembar = par.get("sha256_model")
    if sha_lembar not in (None, "-") and sha_sekarang is not None:
        if sha_lembar == sha_sekarang:
            catat("✅ Berkas model sama dengan saat penetapan parameter.")
        else:
            catat("⚠️  Berkas model BERBEDA dari yang tercatat di lembar penetapan. "
                  "Sesuai Bab III 3.4.6, kalibrasi harus diulang bila implementasi berubah.")

    # Metrik skenario: keseluruhan dan per kategori pencahayaan
    kategori = {"SEMUA": ds, "memadai": ds[ds["kondisi_cahaya"] == "memadai"],
                "tidak memadai": ds[ds["kondisi_cahaya"].isin(KONDISI_TIDAK_MEMADAI)]}
    kategori.update({k: ds[ds["kondisi_cahaya"] == k] for k in KONDISI_TIDAK_MEMADAI})
    tabel = pd.concat([metrik_skenario(d, par).assign(kategori=k)
                       for k, d in kategori.items() if not d.empty], ignore_index=True)
    tabel = tabel[["kategori"] + [c for c in tabel.columns if c != "kategori"]]
    catat("\nMetrik skenario A–D:")
    catat(tabel.drop(columns="latensi_rata_ms").to_string(index=False))
    simpan(tabel, keluar, "uji_metrik_skenario.csv")
    catat("Rincian: nFR = nTD (tidak terdeteksi) + nTA (d1 > τ) + nTM (margin); "
          "tolak_margin_TT = citra tidak terdaftar yang ditolak oleh margin.")

    # Interaksi CLAHE × margin (Bab II 2.5, Bab III 3.5.6), deskriptif
    interaksi = interaksi_clahe_margin(tabel)
    if not interaksi.empty:
        catat("\nInteraksi CLAHE × margin (poin persentase): (D − B) − (C − A), deskriptif:")
        catat(interaksi.to_string(index=False))
        simpan(interaksi, keluar, "uji_interaksi_clahe_margin.csv")
        catat("Nilai mendekati nol = pengaruh margin tidak bergantung pada CLAHE.")

    # Waktu inferensi dan latensi per tahap (Bab III 3.5.3, Tabel 3.36 RM 1)
    lat_tahap, sebaran = latensi_per_tahap(ds)
    catat("\nWaktu per tahap (ms), citra yang wajahnya terdeteksi:")
    catat(lat_tahap.to_string(index=False))
    simpan(lat_tahap, keluar, "uji_latensi_per_tahap.csv")
    grafik_latensi_per_tahap(sebaran, os.path.join(keluar, "uji_grafik_latensi_per_tahap.png"))

    citra = {s: per_citra(ds, s, par) for s in SKENARIO}

    # Uji McNemar (Bab III Tabel 3.22) terpisah untuk FAR, FRR, dan MIR,
    # pasangan = citra yang sama pada dua skenario.
    # b = kesalahan hanya terjadi pada skenario pertama, c = hanya pada skenario kedua.
    def pasangan(s1, s2, kolom, pilih):
        x, y = citra[s1], citra[s2]
        idx = x.index.intersection(y.index)
        x, y = x.loc[idx], y.loc[idx]
        m = pilih(x)
        x, y = x[m], y[m]
        b, c = int((x[kolom] & ~y[kolom]).sum()), int((~x[kolom] & y[kolom]).sum())
        p, metode = uji_mcnemar(b, c)
        return {"n_pasangan": len(x), "b": b, "c": c, "metode": metode,
                "p_value": round(p, 4) if not np.isnan(p) else np.nan,
                "signifikan": "-" if np.isnan(p) else ("ya" if p < 0.05 else "tidak")}

    def memadai(x):
        return x["kondisi"] == "memadai"

    def tidak_memadai(x):
        return x["kondisi"].isin(KONDISI_TIDAK_MEMADAI)

    def semua(x):
        return pd.Series(True, index=x.index)

    rancangan = [("H1a", "memadai", memadai, [("A", "B"), ("C", "D")]),
                 ("H1b", "tidak memadai", tidak_memadai, [("A", "B"), ("C", "D")]),
                 ("H2", "semua", semua, [("A", "C"), ("B", "D")])]
    uji = []
    for hipotesis, nama_kondisi, kondisi, daftar_pasangan in rancangan:
        for s1, s2 in daftar_pasangan:
            for kolom in ["FAR", "FRR", "MIR"]:
                # FAR dihitung dari citra siswa tidak terdaftar, FRR dan MIR dari siswa terdaftar
                ter = kolom != "FAR"
                uji.append({"hipotesis": hipotesis, "kondisi": nama_kondisi,
                            "data": "terdaftar" if ter else "tidak terdaftar", "metrik": kolom,
                            "perbandingan": f"{s1} vs {s2}",
                            **pasangan(s1, s2, kolom,
                                       lambda x, k=kondisi, t=ter: k(x) & (x["terdaftar"] == t))})
    uji = pd.DataFrame(uji)
    catat("\nUji McNemar (b = kesalahan hanya pada skenario pertama, c = hanya pada skenario kedua):")
    catat(uji.to_string(index=False))
    simpan(uji, keluar, "uji_mcnemar.csv")

    # Uji Wilcoxon signed-rank latensi (H1c), pasangan = citra yang sama tanpa vs dengan CLAHE
    x, y = citra["A"], citra["B"]
    idx = x.index.intersection(y.index)
    x, y = x.loc[idx], y.loc[idx]
    m = x["terdeteksi"] & y["terdeteksi"]
    t_tanpa, t_clahe = x.loc[m, "t_frame_ms"], y.loc[m, "t_frame_ms"]
    if len(t_tanpa) > 1 and stats is not None:
        p = stats.wilcoxon(t_tanpa, t_clahe).pvalue
        catat(f"\nH1c Wilcoxon latensi A vs B (sama dengan C vs D): n = {len(t_tanpa)}, "
              f"median selisih (CLAHE − tanpa) = {(t_clahe - t_tanpa).median():.2f} ms, p = {p:.4g}")

    # FRR dan MIR per siswa terdaftar
    kolom_siswa = {}
    for s in SKENARIO:
        per_label = citra[s][citra[s]["terdaftar"]].groupby("label")
        kolom_siswa[f"FRR_{s}_%"] = per_label["FRR"].mean().mul(100).round(2)
        kolom_siswa[f"MIR_{s}_%"] = per_label["MIR"].mean().mul(100).round(2)
    per_siswa = pd.DataFrame(kolom_siswa)
    per_siswa.insert(0, "n_citra", citra["A"][citra["A"]["terdaftar"]].groupby("label").size())
    per_siswa = per_siswa.rename_axis("kode_siswa").reset_index()
    catat("\nFRR dan MIR per siswa (%):")
    catat(per_siswa.to_string(index=False))
    simpan(per_siswa, keluar, "uji_frr_mir_per_siswa.csv")

    # Verifikasi kategori pencahayaan citra uji dengan T_Y dari data kalibrasi
    if isinstance(par.get("T_Y"), float):
        _, cek_ty = hitung_ty(ds, par["T_Y"])
        if not cek_ty.empty:
            catat(f"\nVerifikasi luminansi citra uji (T_Y = {par['T_Y']}):")
            catat(cek_ty.drop(columns="berkas_tidak_sesuai").to_string(index=False))
            simpan(cek_ty, keluar, "uji_verifikasi_luminansi.csv")


# ==============================================================================
def main():
    global BATAS_FRR_TAU, BATAS_FAR_LONGGAR
    parser = argparse.ArgumentParser(description="Analisis log penelitian presensi wajah")
    parser.add_argument("--wajah", default="penelitian_log_wajah.csv")
    parser.add_argument("--sesi", default="penelitian_log_sesi.csv")
    parser.add_argument("--sesi-dataset", default=None,
                        help="Hanya pakai sesi_id dataset tertentu (default: semua)")
    parser.add_argument("--keluar", default="hasil_analisis")
    parser.add_argument("--mode", choices=["semua", "kalibrasi", "validasi", "uji"], default="semua",
                        help="kalibrasi = tetapkan T_Y, τ, δ, konfigurasi terbaik (validasi = nama lama); "
                             "uji = pakai lembar penetapan pada data uji")
    parser.add_argument("--lembar", default="lembar_penetapan_parameter.txt")
    parser.add_argument("--frr-maks", type=float, default=BATAS_FRR_TAU,
                        help="Batas toleransi FRR kalibrasi pada penetapan τ, persen (bawaan 10)")
    parser.add_argument("--far-longgar", type=float, default=BATAS_FAR_LONGGAR,
                        help="FAR kalibrasi tertinggi yang diterima pada langkah 3 penetapan τ, persen (bawaan 5)")
    parser.add_argument("--model", default=None,
                        help=f"Berkas model untuk sidik jari SHA-256 (bawaan {PATH_MODEL})")
    parser.add_argument("--versi-app", default=None, help="Versi aplikasi (bawaan dibaca dari pubspec.yaml)")
    parser.add_argument("--padanan", default=None,
                        help="padanan_kode_siswa_RAHASIA.csv resmi (kode, absen, nis, …) agar NIS di log "
                             "presensi diganti kode menurut nomor urut absen (Tabel 3.8)")
    args = parser.parse_args()
    if args.mode == "validasi":
        catat("ℹ️  --mode validasi adalah nama lama; dijalankan sebagai --mode kalibrasi.")
        args.mode = "kalibrasi"
    BATAS_FRR_TAU, BATAS_FAR_LONGGAR = args.frr_maks, args.far_longgar

    os.makedirs(args.keluar, exist_ok=True)
    if stats is None:
        catat("⚠️  scipy tidak terpasang: uji statistik dilewati (pip install scipy)")
    if plt is None:
        catat("⚠️  matplotlib tidak terpasang: grafik dilewati (pip install matplotlib)")

    padanan = baca_padanan(args.padanan) if args.padanan else None
    if os.path.exists(args.wajah):
        log = samarkan_nim(muat_log_wajah(args.wajah), args.keluar, padanan)
        ds = log[log["sumber"] == "dataset"]
        if args.mode != "semua":
            if args.sesi_dataset:
                ds = ds[ds["sesi_id"] == args.sesi_dataset]
            if satu_sesi(ds, args.mode):
                (analisis_kalibrasi if args.mode == "kalibrasi" else analisis_uji)(
                    ds, args.keluar, args.lembar, args.model, args.versi_app)
            with open(os.path.join(args.keluar, "ringkasan.txt"), "w", encoding="utf-8") as f:
                f.write("\n".join(_ringkasan))
            return
        if args.sesi_dataset:
            ds = ds[ds["sesi_id"] == args.sesi_dataset]
        elif ds["sesi_id"].nunique() > 1:
            catat(f"ℹ️  Ada {ds['sesi_id'].nunique()} sesi evaluasi dataset; semuanya digabung. "
                  "Pakai --sesi-dataset untuk memilih satu.")
        if ds.empty:
            catat("ℹ️  Belum ada data evaluasi dataset (sumber=dataset); RM 1 & RM 2 dilewati.")
        else:
            analisis_rm1(ds, args.keluar)
            analisis_rm2(ds, args.keluar)
        analisis_live(log[log["sumber"] == "live"], args.keluar)
    else:
        catat(f"ℹ️  File {args.wajah} tidak ditemukan; RM 1 & RM 2 dilewati.")

    if os.path.exists(args.sesi):
        analisis_rm3(muat_log_sesi(args.sesi), args.keluar)
    else:
        catat(f"ℹ️  File {args.sesi} tidak ditemukan; RM 3 dilewati.")

    with open(os.path.join(args.keluar, "ringkasan.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(_ringkasan))
    print(f"\nSelesai. Semua hasil ada di folder: {args.keluar}/")


if __name__ == "__main__":
    main()
