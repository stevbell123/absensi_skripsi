// =========================================================================
// AI PROVIDERS (Riverpod)
// =========================================================================
// File ini menyediakan "provider" untuk seluruh servis AI agar bisa diakses
// dari widget manapun menggunakan `ref.read(...)`.
//
// Mengapa pakai Riverpod?
// - Singleton: model TFLite hanya dimuat 1x, tidak dimuat ulang setiap
//   kali buka halaman absensi.
// - Testable: bisa di-override saat unit test.
// - Konsisten: proyek ini sudah memakai Riverpod di seluruh fitur lain.
// =========================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'face_detector_service.dart';
import 'face_embedding_service.dart';
import 'face_matching_service.dart';
import 'face_database_service.dart';

// ---------- PROVIDER 1: Deteksi Wajah (Google ML Kit) ----------
// Singleton — dibuat sekali, hidup selama aplikasi aktif.
final faceDetectorProvider = Provider<FaceDetectorService>((ref) {
  final service = FaceDetectorService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ---------- PROVIDER 2: Embedding Wajah (MobileFaceNet TFLite) ----------
// Async karena model TFLite perlu di-load dari assets.
final faceEmbeddingProvider =
    FutureProvider<FaceEmbeddingService>((ref) async {
  final service = FaceEmbeddingService();
  await service.initialize();
  ref.onDispose(() => service.dispose());
  return service;
});

// ---------- PROVIDER 3: Matching Wajah (Euclidean Distance) ----------
// Tidak async, hanya logika matematika murni.
final faceMatchingProvider = Provider<FaceMatchingService>((ref) {
  return FaceMatchingService();
});

// ---------- PROVIDER 4: Database Wajah (Firestore + Hive) ----------
// Async karena Hive perlu diinisialisasi.
final faceDatabaseProvider =
    FutureProvider<FaceDatabaseService>((ref) async {
  final service = FaceDatabaseService();
  await service.initHive();
  return service;
});
