# SIAP — Sistem Informasi Akademik Pintar

Aplikasi digitalisasi sekolah (absensi, nilai/rapor otomatis, materi
pembelajaran, dashboard analitik, dan modul AI prediksi siswa berisiko).
Dibangun dengan Flutter + Riverpod + go_router + Firebase.

> **Status saat ini: Fase 1 selesai** — setup project, Firebase, dan
> autentikasi berbasis role (admin/guru/siswa). Fase berikutnya dibangun
> secara bertahap, jangan loncat sebelum fase sebelumnya stabil (lihat
> "Roadmap" di bawah).

## Struktur folder (clean architecture)

```
lib/
  core/            # constants, theme, routing, utils lintas fitur
  features/
    auth/          # Fase 1 — SELESAI
      domain/      # entities & repository interface (tidak tahu Firebase)
      data/        # implementasi Firebase Auth + Firestore
      presentation/# providers (Riverpod), pages, widgets
    home/          # placeholder home per role, akan digantikan modul dashboard asli
  shared/          # widget lintas fitur (loading/error/empty state)
```

Fitur berikutnya (attendance, grades, learning_module, dashboard,
ai_prediction) mengikuti pola folder yang sama persis: domain → data →
presentation.

## Setup

### 1. Prasyarat
- Flutter SDK versi stable terbaru (`flutter --version`)
- Akun Firebase + Firebase CLI (`npm install -g firebase-tools`)
- FlutterFire CLI: `dart pub global activate flutterfire_cli`

### 2. Install dependencies
```bash
flutter pub get
```

### 3. Setup Firebase
1. Buat project baru di [Firebase Console](https://console.firebase.google.com).
2. Aktifkan **Authentication** → sign-in method **Email/Password**.
3. Aktifkan **Cloud Firestore** (mode production, pilih region terdekat, mis. `asia-southeast2`).
4. Login Firebase CLI: `firebase login`
5. Di root project, jalankan:
   ```bash
   flutterfire configure
   ```
   Ini akan generate ulang `lib/firebase_options.dart` (file placeholder saat
   ini sengaja `throw UnsupportedError` supaya kelihatan jelas kalau belum
   dikonfigurasi) dan mendaftarkan app Android/iOS/Web ke project Firebase kamu.

### 4. Deploy Firestore Security Rules
```bash
firebase deploy --only firestore:rules
```
Rules di `firestore.rules` sudah role-aware sesuai skema data di spek (siswa
hanya baca datanya sendiri, guru hanya tulis untuk kelas yang diajar, admin
full access). Ada satu catatan penting di file rules terkait koleksi
`attendance` — baca komentarnya sebelum lanjut ke Fase 3.

### 5. Setup Cloudinary (foto profil & materi pembelajaran)
Storage file pakai **Cloudinary**, bukan Firebase Storage.

1. Buat akun gratis di [cloudinary.com](https://cloudinary.com) → catat
   **Cloud Name** kamu (terlihat di Dashboard).
2. Buat *upload preset* tanpa signature (client-only, tidak butuh backend):
   Settings → **Upload** → scroll ke "Upload presets" → **Add upload preset**.
   - **Signing Mode**: `Unsigned`
   - **Folder**: kosongkan (folder sudah diatur dari kode, lihat
     `CloudinaryService` — otomatis masuk ke `siap/profile_photos` atau
     `siap/learning_materials/...`)
   - Disarankan batasi **Allowed formats** (mis. `jpg,png,pdf`) dan
     **Max file size** di preset ini, supaya upload dari client tidak
     disalahgunakan untuk isi sampah.
   - Simpan, catat **nama preset**-nya.
3. Jalankan app dengan dua `--dart-define` ini (cloud name & preset —
   keduanya aman ditaruh di client, ini bukan API secret):
   ```bash
   flutter run \
     --dart-define=CLOUDINARY_CLOUD_NAME=nama_cloud_kamu \
     --dart-define=CLOUDINARY_UPLOAD_PRESET=nama_preset_kamu
   ```
   Atau kalau pakai VS Code, edit `.vscode/launch.json` (sudah disiapkan)
   dan isi dua value itu, lalu jalankan lewat tombol Run/Debug seperti biasa.
4. Belum ada fitur upload yang benar-benar dipanggil di UI saat ini —
   `CloudinaryService` baru abstraksi siap pakai untuk foto profil dan
   modul materi pembelajaran di Fase 5. `cloudinaryServiceProvider` akan
   melempar error yang jelas kalau dipanggil sebelum dua define di atas diisi.

> Kalau nanti butuh keamanan lebih ketat (mis. validasi ukuran/tipe file di
> server, bukan cuma di preset), opsi lanjutannya adalah *signed upload*
> lewat Cloud Function — API Secret Cloudinary disimpan di server, bukan
> di app. Bisa kita bangun kalau memang dibutuhkan; untuk kebutuhan skripsi,
> unsigned preset yang dibatasi biasanya cukup.

### 6. Bootstrap akun admin pertama
Aplikasi ini **tidak punya halaman registrasi** (sesuai spek: akun dibuat
admin). Jadi akun admin pertama harus dibuat manual:
1. Firebase Console → Authentication → Add user (isi email + password).
2. Firebase Console → Firestore → buat dokumen di koleksi `users` dengan
   **document ID = UID user yang baru dibuat**, isi field:
   ```json
   {
     "name": "Nama Admin",
     "email": "admin@sekolah.sch.id",
     "role": "admin",
     "nisNip": null,
     "classId": null,
     "createdAt": <timestamp sekarang>
   }
   ```
3. Login pakai akun ini di app → otomatis diarahkan ke `/admin`.

Akun guru & siswa berikutnya dibuat lewat modul "Manajemen Pengguna" yang
akan dibangun di Fase 2.

### 7. Jalankan aplikasi
```bash
flutter run \
  --dart-define=CLOUDINARY_CLOUD_NAME=nama_cloud_kamu \
  --dart-define=CLOUDINARY_UPLOAD_PRESET=nama_preset_kamu
```
(Define Cloudinary boleh dilewati kalau kamu belum butuh upload apa pun —
app tetap jalan normal untuk login & routing, error Cloudinary baru muncul
kalau `cloudinaryServiceProvider` benar-benar dipanggil.)

## Apa yang sudah jadi di Fase 1

- Struktur clean architecture (`core`, `features`, `shared`)
- Firebase Auth (email/password) + sinkronisasi data profil dari Firestore
- Role-based routing pakai `go_router`: setelah login, user otomatis
  diarahkan ke `/admin`, `/guru`, atau `/siswa` sesuai field `role` di
  dokumen `users`
- State management dengan Riverpod (`StreamProvider` untuk auth state,
  `StateNotifierProvider` untuk form login)
- Draft Firestore Security Rules untuk semua koleksi di skema data
- `CloudinaryService` — abstraksi upload file (foto profil, materi
  pembelajaran) siap pakai untuk Fase 5, pengganti Firebase Storage
- Widget bersama (`LoadingWidget`, `AppErrorWidget`, `EmptyStateWidget`)
  yang akan dipakai ulang di semua fitur berikutnya
- Tema Material 3 (light/dark) dengan seed color yang bisa diganti sesuai
  identitas sekolah mitra

## Roadmap (jangan loncat fase)

- [x] **Fase 1** — Setup project, Firebase, autentikasi & role-based access
- [ ] **Fase 2** — Manajemen data akademik (semester, kelas, jadwal, user) — admin
- [ ] **Fase 3** — Sistem absensi + export PDF
- [ ] **Fase 4** — Input nilai + generate rapor otomatis (PDF)
- [ ] **Fase 5** — Modul pembelajaran (upload/akses materi)
- [ ] **Fase 6** — Dashboard real-time (tanpa AI dulu)
- [ ] **Fase 7** — Modul AI: prediksi siswa berisiko + integrasi dashboard
- [ ] **Fase 8** — Polish UI, testing, dokumentasi

## Catatan penting

- Sandbox tempat kode ini dibuat **tidak punya Flutter SDK / akses pub.dev**,
  jadi kode belum pernah dijalankan `flutter analyze` / `flutter run` secara
  otomatis. Setelah `flutter pub get` di mesin kamu, kalau ada error versi
  paket (API Firebase kadang berubah antar versi minor), kabari saya —
  gampang disesuaikan.
- Warna tema (`AppTheme._seedColor`) masih placeholder biru netral — ganti
  sesuai identitas sekolah mitra begitu sudah ditentukan.
- Nama aplikasi "SIAP" gampang diganti: cukup ubah `AppConstants.appName`
  dan label di `pubspec.yaml`.
