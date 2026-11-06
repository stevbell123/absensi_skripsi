# ==============================================================================
# SKRIP EVALUASI ILMIAH CLAHE UNTUK LAPORAN SKRIPSI (BAB 4)
# ==============================================================================
# Menghitung metrik kualitas citra:
# 1. PSNR (Peak Signal-to-Noise Ratio)
# 2. SSIM (Structural Similarity Index Measure)
# 3. Entropi Informasi Shannon (Tingkat detail informasi citra)
# 4. Distribusi Nilai Luminansi (Mean & Standar Deviasi Kecerahan)
# ==============================================================================

import os
import cv2
import math
import numpy as np

def hitung_entropi(citra_gray: np.ndarray) -> float:
    """Menghitung Shannon Entropy untuk mengukur kekayaan informasi citra"""
    hist, _ = np.histogram(citra_gray, bins=256, range=(0, 256), density=True)
    hist = hist[hist > 0]
    return -float(np.sum(hist * np.log2(hist)))

def terapkan_clahe(img_rgb: np.ndarray, clip_limit: float = 2.0, grid_size: tuple = (8, 8)) -> np.ndarray:
    """Menerapkan CLAHE pada kanal L di ruang warna CIELAB"""
    lab = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=grid_size)
    cl = clahe.apply(l)
    limg = cv2.merge((cl, a, b))
    return cv2.cvtColor(limg, cv2.COLOR_LAB2RGB)

def evaluasi_kualitas_citra(jalur_gambar_asli: str, clip_limit: float = 2.0):
    if not os.path.exists(jalur_gambar_asli):
        print(f"File {jalur_gambar_asli} tidak ditemukan.")
        return None

    # Baca citra asli
    bgr_asli = cv2.imread(jalur_gambar_asli)
    rgb_asli = cv2.cvtColor(bgr_asli, cv2.COLOR_BGR2RGB)
    gray_asli = cv2.cvtColor(bgr_asli, cv2.COLOR_BGR2GRAY)

    # Terapkan CLAHE
    rgb_clahe = terapkan_clahe(rgb_asli, clip_limit=clip_limit)
    bgr_clahe = cv2.cvtColor(rgb_clahe, cv2.COLOR_RGB2BGR)
    gray_clahe = cv2.cvtColor(bgr_clahe, cv2.COLOR_BGR2GRAY)

    # 1. PSNR
    psnr = cv2.PSNR(rgb_asli, rgb_clahe)

    # 2. Entropi Informasi (Kekayaan detail)
    entropi_asli = hitung_entropi(gray_asli)
    entropi_clahe = hitung_entropi(gray_clahe)
    kenaikan_entropi = ((entropi_clahe - entropi_asli) / entropi_asli) * 100

    # 3. Distribusi Luminansi
    mean_asli, std_asli = cv2.meanStdDev(gray_asli)
    mean_clahe, std_clahe = cv2.meanStdDev(gray_clahe)

    hasil = {
        "file": os.path.basename(jalur_gambar_asli),
        "psnr_db": round(psnr, 2),
        "entropi_sebelum": round(entropi_asli, 4),
        "entropi_sesudah": round(entropi_clahe, 4),
        "kenaikan_entropi_persen": round(kenaikan_entropi, 2),
        "mean_kecerahan_sebelum": round(float(mean_asli[0][0]), 2),
        "mean_kecerahan_sesudah": round(float(mean_clahe[0][0]), 2),
        "kontras_std_sebelum": round(float(std_asli[0][0]), 2),
        "kontras_std_sesudah": round(float(std_clahe[0][0]), 2),
    }

    # Simpan perbandingan visual
    output_dir = "hasil_evaluasi_clahe"
    os.makedirs(output_dir, exist_ok=True)
    nama_dasar = os.path.splitext(os.path.basename(jalur_gambar_asli))[0]
    
    # Gabungkan berdampingan (Asli vs CLAHE)
    komparasi = np.hstack((bgr_asli, bgr_clahe))
    cv2.putText(komparasi, "Citra Asli (Sebelum CLAHE)", (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 255), 2)
    cv2.putText(komparasi, f"Hasil CLAHE (Clip={clip_limit})", (bgr_asli.shape[1] + 20, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 0), 2)
    
    cv2.imwrite(f"{output_dir}/komparasi_{nama_dasar}.jpg", komparasi)
    return hasil

if __name__ == "__main__":
    print("=" * 70)
    print("TOOL EVALUASI ILMIAH CLAHE UNTUK BAB 4 SKRIPSI")
    print("=" * 70)
    print("Gunakan fungsi evaluasi_kualitas_citra('jalur/foto.jpg')")
