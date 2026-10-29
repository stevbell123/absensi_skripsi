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
#   Penetapan parameter dari data validasi (Bab III Subbab 3.4.3):
#   python analisis_penelitian.py --mode validasi --sesi-dataset <sesi_id dataset_validasi>
#   → menulis lembar_penetapan_parameter.txt (T_Y, τ dan δ per kondisi CLAHE,
#     metrik skenario A–D, konfigurasi terbaik)
#
#   Pengujian pada data uji dengan parameter dari lembar penetapan:
#   python analisis_penelitian.py --mode uji --sesi-dataset <sesi_id dataset_uji>
#
#   Semua keluaran memakai kode siswa S01–S30, bukan NIM.
#
# Hasil (CSV + grafik PNG + ringkasan.txt) disimpan di folder hasil_analisis/
# ==============================================================================

import argparse
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
    for k in ["jumlah_siswa", "durasi_total_detik", "durasi_scan_detik", "hadir_hasil_scan",
              "hadir_akhir", "koreksi_total", "koreksi_jadi_hadir", "koreksi_batal_hadir",
              "akurasi_scan_persen", "clahe"]:
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
        catat("  'nama' = siswa ditemukan lewat pencocokan nama longgar, bukan NIM →"
              " potensi salah-identitas di luar model.")

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
        akurasi_scan_persen=("akurasi_scan_persen", "mean"),
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
            akurasi_scan_persen=("akurasi_scan_persen", "mean"),
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


def samarkan_nim(df, keluar):
    """Ganti NIM di kolom NIM dan jalur berkas dengan kode S01, S02, ... (urut NIM)."""
    nim = sorted({v for k in KOLOM_NIM if k in df for v in df[k].unique()} - BUKAN_NIM)
    kode = {n: f"S{i:02d}" for i, n in enumerate(nim, 1)}
    for k in KOLOM_NIM:
        if k in df:
            df[k] = df[k].map(lambda v: kode.get(v, v))
    if "file" in df and kode:
        pola = re.compile(r"(?<![0-9A-Za-z])(" + "|".join(map(re.escape, nim)) + r")(?![0-9A-Za-z])")
        df["file"] = df["file"].fillna("").map(lambda f: pola.sub(lambda m: kode[m.group(1)], f))
    path = os.path.join(keluar, "padanan_kode_siswa_RAHASIA.csv")
    pd.DataFrame({"kode": list(kode.values()), "nim": list(kode.keys())}).to_csv(path, index=False)
    catat(f"ℹ️  NIM diganti kode siswa. Padanan kode disimpan di {path} "
          "(simpan terpisah, jangan dilampirkan pada laporan).")
    return df


# ==============================================================================
# PENETAPAN PARAMETER (DATA VALIDASI) DAN PENGUJIAN (DATA UJI)
# ==============================================================================
# Skenario: (kondisi CLAHE, verifikasi margin)
SKENARIO = {"A": (0, False), "B": (1, False), "C": (0, True), "D": (1, True)}
KONDISI_TIDAK_MEMADAI = ["low_light", "backlight"]
BATAS_LATENSI_MS = 600
BATAS_KENAIKAN_FRR = 4.0


def uji_mcnemar(b, c):
    """Persamaan (2.21) dengan koreksi kontinuitas; uji binomial eksak bila b + c < 25."""
    if b + c == 0:
        return np.nan, "-"
    if b + c < 25:
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


def metrik_skenario(ds, par):
    baris = []
    for s in SKENARIO:
        g, pred = hasil_skenario(ds, s, par)
        if g.empty:
            continue
        m = metrik(g, pred)
        baris.append({"skenario": s, "n_citra": len(g),
                      "FAR_%": m["FAR_%"], "FRR_%": m["FRR_%"], "MIR_%": m["MIR_%"],
                      "FRR+MIR_%": round(m["FRR_%"] + m["MIR_%"], 2), "FTA": m["FTA"],
                      **statistik_latensi(g.loc[g["terdeteksi"], "t_frame_ms"])})
    return pd.DataFrame(baris)


def pilih_tau(g):
    """τ = nilai terbesar (0,50–1,50, langkah 0,01) dengan FAR validasi 0% (ambang tunggal)."""
    hasil = pd.DataFrame([{"tau": a, **metrik(g, prediksi(g, a))}
                          for a in np.round(np.arange(0.50, 1.505, 0.01), 2)])
    nol = hasil[hasil["FAR_%"] == 0]
    if not nol.empty:
        return float(nol["tau"].max()), hasil, True
    terendah = hasil[hasil["FAR_%"] == hasil["FAR_%"].min()]
    return float(terendah["tau"].max()), hasil, False


def pilih_delta(g, tau):
    """δ = nilai terbesar (0,00–0,20) yang kenaikan FRR validasinya ≤ 4 poin dibanding tanpa margin."""
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
        t, f"tidak ada yang memenuhi latensi ≤ {BATAS_LATENSI_MS} ms; dipilih FAR validasi terendah")
    terbaik = calon.sort_values(["FAR_%", "FRR+MIR_%", "MIR_%", "urutan"]).iloc[0]
    return terbaik["skenario"], catatan


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


def analisis_validasi(ds, keluar, path_lembar):
    catat("\n" + "=" * 78)
    catat("PENETAPAN PARAMETER DARI DATA VALIDASI (Bab III Subbab 3.4.3)")
    catat("=" * 78)

    par = {}
    for clahe in [0, 1]:
        g = ds[ds["clahe"] == clahe]
        if g.empty:
            catat(f"⚠️  Tidak ada data clahe = {clahe}; jalankan evaluasi dengan dan tanpa CLAHE.")
            return
        tau, sweep_tau, far_nol = pilih_tau(g)
        delta, sweep_delta = pilih_delta(g, tau)
        par[f"tau_clahe{clahe}"], par[f"delta_clahe{clahe}"] = tau, delta
        simpan(sweep_tau, keluar, f"validasi_pencarian_tau_clahe{clahe}.csv")
        simpan(sweep_delta, keluar, f"validasi_pencarian_delta_clahe{clahe}.csv")
        catat(f"[clahe = {clahe}] τ = {tau:.2f}"
              + ("" if far_nol else "  ⚠️ tidak ada τ dengan FAR 0%; dipakai FAR terendah")
              + f", δ = {delta:.2f}")

    ty, cek_ty = hitung_ty(ds)
    tabel = metrik_skenario(ds, par)
    terbaik, catatan = pilih_konfigurasi(tabel)

    catat("\nMetrik skenario A–D pada data validasi:")
    catat(tabel.drop(columns="latensi_rata_ms").to_string(index=False))
    simpan(tabel, keluar, "validasi_metrik_skenario.csv")
    catat(f"\nKonfigurasi terbaik: {terbaik} ({catatan})")
    if ty is None:
        catat("⚠️  Kolom luminansi belum ada di log; T_Y tidak dihitung.")
    else:
        catat(f"T_Y = {ty}")
        catat(cek_ty.drop(columns="berkas_tidak_sesuai").to_string(index=False))
        simpan(cek_ty, keluar, "validasi_verifikasi_luminansi.csv")

    with open(path_lembar, "w", encoding="utf-8") as f:
        f.write("LEMBAR PENETAPAN PARAMETER\n")
        f.write(f"Tanggal  : {datetime.now():%Y-%m-%d %H:%M}\n")
        f.write(f"Sesi     : {ds['sesi_id'].iloc[0]}\n\n")
        f.write("[parameter]\n")
        f.write(f"T_Y = {ty if ty is not None else '-'}\n")
        for k, v in par.items():
            f.write(f"{k} = {v:.2f}\n")
        f.write(f"konfigurasi_terbaik = {terbaik}\n\n")
        f.write(f"Alasan pemilihan: {catatan}\n\n")
        f.write("[metrik data validasi]\n")
        f.write(tabel.drop(columns="latensi_rata_ms").to_string(index=False) + "\n\n")
        f.write("Ditetapkan sebelum citra uji diproses.\n\n")
        f.write("Tanda tangan tim:\n\n1. ____________________\n2. ____________________\n"
                "3. ____________________\n")
    catat(f"  → lembar penetapan: {path_lembar}")


def baca_lembar(path):
    par = {}
    with open(path, encoding="utf-8") as f:
        for baris in f:
            m = re.match(r"^(T_Y|tau_clahe[01]|delta_clahe[01]|konfigurasi_terbaik) = (\S+)$", baris.strip())
            if m:
                k, v = m.groups()
                par[k] = v if k == "konfigurasi_terbaik" or v == "-" else float(v)
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


def analisis_uji(ds, keluar, path_lembar):
    catat("\n" + "=" * 78)
    catat("PENGUJIAN PADA DATA UJI (parameter dari lembar penetapan)")
    catat("=" * 78)
    if not os.path.exists(path_lembar):
        catat(f"❌ {path_lembar} tidak ditemukan. Jalankan --mode validasi terlebih dahulu.")
        return
    par = baca_lembar(path_lembar)
    wajib = ["tau_clahe0", "delta_clahe0", "tau_clahe1", "delta_clahe1"]
    if any(k not in par for k in wajib):
        catat(f"❌ Lembar penetapan tidak lengkap: {', '.join(k for k in wajib if k not in par)}")
        return
    catat("Parameter: " + ", ".join(f"{k} = {par[k]}" for k in ["T_Y", *wajib, "konfigurasi_terbaik"]
                                     if k in par))

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

    # Verifikasi kategori pencahayaan citra uji dengan T_Y dari data validasi
    if isinstance(par.get("T_Y"), float):
        _, cek_ty = hitung_ty(ds, par["T_Y"])
        if not cek_ty.empty:
            catat(f"\nVerifikasi luminansi citra uji (T_Y = {par['T_Y']}):")
            catat(cek_ty.drop(columns="berkas_tidak_sesuai").to_string(index=False))
            simpan(cek_ty, keluar, "uji_verifikasi_luminansi.csv")


# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description="Analisis log penelitian presensi wajah")
    parser.add_argument("--wajah", default="penelitian_log_wajah.csv")
    parser.add_argument("--sesi", default="penelitian_log_sesi.csv")
    parser.add_argument("--sesi-dataset", default=None,
                        help="Hanya pakai sesi_id dataset tertentu (default: semua)")
    parser.add_argument("--keluar", default="hasil_analisis")
    parser.add_argument("--mode", choices=["semua", "validasi", "uji"], default="semua",
                        help="validasi = tetapkan T_Y, τ, δ, konfigurasi terbaik; "
                             "uji = pakai lembar penetapan pada data uji")
    parser.add_argument("--lembar", default="lembar_penetapan_parameter.txt")
    args = parser.parse_args()

    os.makedirs(args.keluar, exist_ok=True)
    if stats is None:
        catat("⚠️  scipy tidak terpasang: uji statistik dilewati (pip install scipy)")
    if plt is None:
        catat("⚠️  matplotlib tidak terpasang: grafik dilewati (pip install matplotlib)")

    if os.path.exists(args.wajah):
        log = samarkan_nim(muat_log_wajah(args.wajah), args.keluar)
        ds = log[log["sumber"] == "dataset"]
        if args.mode != "semua":
            if args.sesi_dataset:
                ds = ds[ds["sesi_id"] == args.sesi_dataset]
            if satu_sesi(ds, args.mode):
                (analisis_validasi if args.mode == "validasi" else analisis_uji)(ds, args.keluar, args.lembar)
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
