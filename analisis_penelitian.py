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
# Hasil (CSV + grafik PNG + ringkasan.txt) disimpan di folder hasil_analisis/
# ==============================================================================

import argparse
import os

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
    "t_matching_ms", "t_frame_ms",
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
        df[k] = pd.to_numeric(df[k], errors="coerce")
    df["kondisi_cahaya"] = df["kondisi_cahaya"].fillna("tidak_diketahui")
    df["terdeteksi"] = df["alasan"] != "wajah_tidak_terdeteksi"
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
def main():
    parser = argparse.ArgumentParser(description="Analisis log penelitian presensi wajah")
    parser.add_argument("--wajah", default="penelitian_log_wajah.csv")
    parser.add_argument("--sesi", default="penelitian_log_sesi.csv")
    parser.add_argument("--sesi-dataset", default=None,
                        help="Hanya pakai sesi_id dataset tertentu (default: semua)")
    parser.add_argument("--keluar", default="hasil_analisis")
    args = parser.parse_args()

    os.makedirs(args.keluar, exist_ok=True)
    if stats is None:
        catat("⚠️  scipy tidak terpasang: uji statistik dilewati (pip install scipy)")
    if plt is None:
        catat("⚠️  matplotlib tidak terpasang: grafik dilewati (pip install matplotlib)")

    if os.path.exists(args.wajah):
        log = muat_log_wajah(args.wajah)
        ds = log[log["sumber"] == "dataset"]
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
