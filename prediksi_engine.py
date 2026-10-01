import firebase_admin
from firebase_admin import credentials, firestore
import joblib
import warnings

warnings.filterwarnings("ignore", category=UserWarning)

print("==================================================")
print("MEMULAI MESIN AI PREDIKSI (DATA ASLI REAL-TIME)")
print("==================================================")

# 1. KONEKSIKAN PYTHON KE FIREBASE
print("\n[1] Menghubungkan ke Firebase...")
try:
    cred = credentials.Certificate("skripsi1-fa8f3-firebase-adminsdk-fbsvc-09538b5cb8.json") 
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print("✅ Berhasil terhubung ke database!")
except Exception as e:
    print(f"❌ Gagal terhubung ke Firebase. Error: {e}")
    exit()

# 2. MUAT MODEL MACHINE LEARNING
print("\n[2] Membangunkan otak AI (Model ML)...")
try:
    model = joblib.load('model_risiko_siswa.pkl')
    print("✅ AI siap bekerja!")
except Exception as e:
    print(f"❌ File model_risiko_siswa.pkl tidak ditemukan! Error: {e}")
    exit()

# 3. PROSES PENCARIAN & PREDIKSI DATA SISWA
def hitung_risiko_semua_siswa():
    print("\n[3] Membaca rekap nilai asli siswa dari database...")
    
    koleksi_kelas = db.collection('classes').stream()
    jumlah_diproses = 0
    
    for kelas_doc in koleksi_kelas:
        kelas_id = kelas_doc.id
        nama_kelas = kelas_doc.to_dict().get('name', 'Kelas Tanpa Nama')
        print(f"\n📁 Memeriksa: {nama_kelas} (ID: {kelas_id})")
        
        # Ambil SEMUA nilai kegiatan (activity_grades) untuk kelas ini
        # Ini mengambil data asli yang diinput oleh Guru!
        kegiatan_kelas = db.collection('activity_grades').where('classId', '==', kelas_id).stream()
        daftar_kegiatan = [keg.to_dict() for keg in kegiatan_kelas]
        
        koleksi_siswa = db.collection('classes').document(kelas_id).collection('students').stream()
        
        for siswa_doc in koleksi_siswa:
            data_siswa = siswa_doc.to_dict()
            siswa_id = siswa_doc.id
            nama_siswa = data_siswa.get('name', 'Siswa Tanpa Nama')
            
            # --- MULAI MENGHITUNG DATA ASLI ---
            total_nilai = 0
            jumlah_nilai_masuk = 0
            tugas_kosong = 0
            
            for kegiatan in daftar_kegiatan:
                kategori = kegiatan.get('category', '').lower()
                scores = kegiatan.get('scores', {})
                
                # Jika siswa ada di daftar nilai kegiatan ini
                if siswa_id in scores:
                    nilai_kegiatan = scores[siswa_id]
                    total_nilai += nilai_kegiatan
                    jumlah_nilai_masuk += 1
                    
                    # Deteksi tugas kosong (Jika nilainya 0)
                    if kategori == 'tugas' and nilai_kegiatan == 0:
                        tugas_kosong += 1
                else:
                    # Jika nama siswa tidak ada di daftar nilai Tugas, anggap kosong
                    if kategori == 'tugas':
                        tugas_kosong += 1
            
            # Kalkulasi Rata-rata Nilai Asli
            rata_rata_nilai = 100 # Default jika belum ada ujian sama sekali
            if jumlah_nilai_masuk > 0:
                rata_rata_nilai = total_nilai / jumlah_nilai_masuk
                
            # Untuk absen, kita baca dari data profil siswa (atau default 0 jika belum ada rekap absen)
            absen = data_siswa.get('persentase_absen_asli', 0) 
            
            # --- AI MULAI MEMPREDIKSI BERDASARKAN DATA ASLI ---
            fitur_siswa = [[absen, rata_rata_nilai, tugas_kosong]]
            
            probabilitas = model.predict_proba(fitur_siswa)[0][1] 
            persentase_risiko = round(probabilitas * 100, 2)
            
            status = 'Berisiko Tinggi' if probabilitas > 0.5 else 'Aman'
            
            alasan = f"Siswa terpantau aman dengan rata-rata nilai {rata_rata_nilai:.1f}."
            if status == 'Berisiko Tinggi':
                alasan = f"Peringatan: Rata-rata nilai anjlok ke {rata_rata_nilai:.1f} dan ada {tugas_kosong} tugas kosong."
            
            # Update ke database agar muncul di HP Guru
            db.collection('classes').document(kelas_id).collection('students').document(siswa_id).update({
                'ml_risk_status': status,
                'ml_risk_score': persentase_risiko,
                'ml_risk_reason': alasan,
                'calculated_avg_score': rata_rata_nilai # Menyimpan riwayat hitungan untuk dicek
            })
            
            simbol = "🔴" if status == 'Berisiko Tinggi' else "🟢"
            print(f"   {simbol} {nama_siswa} | Nilai Asli: {rata_rata_nilai:.1f} | Risiko: {persentase_risiko}%")
            jumlah_diproses += 1

    print(f"\n==================================================")
    print(f"✅ SELESAI! {jumlah_diproses} siswa dianalisis dari data nilai asli Guru.")
    print(f"==================================================")

if __name__ == "__main__":
    hitung_risiko_semua_siswa()