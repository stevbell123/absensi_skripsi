import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'face_matching_service.dart';

/// Service untuk menangani sinkronisasi embedding wajah antara Firestore (cloud) dan penyimpanan lokal (Hive).
///
/// Strategi Sinkronisasi:
/// - Saat registrasi wajah: embedding langsung disimpan ke Firestore.
/// - Sebelum scan absensi: sinkronisasi embedding untuk kelas tersebut (unduh dari Firestore → cache ke Hive).
/// - Saat proses scan berjalan: gunakan cache di Hive (berfungsi secara offline).
/// - Ukuran data: 180 mahasiswa × 128 float ≈ 180KB, sangat cepat untuk disinkronisasi.
class FaceDatabaseService {
  static const String _firestoreCollection = 'face_embeddings';
  static const String _hiveBoxName = 'face_embeddings_cache';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Membuka Hive box jika belum terbuka
  Future<void> initHive() async {
    if (!Hive.isBoxOpen(_hiveBoxName)) {
      await Hive.openBox(_hiveBoxName);
    }
  }

  /// Mengubah data mentah (Firestore / Hive) menjadi FaceRecord.
  /// Firestore menyimpan array angka sebagai List<dynamic>, sehingga dikonversi ke List<double>.
  static FaceRecord _recordDariMap(Map<dynamic, dynamic> data) {
    final List<dynamic> embeddingDynamic = data['embedding'] ?? [];
    final List<dynamic>? tanpaClaheDynamic = data['embedding_tanpa_clahe'];

    return FaceRecord(
      nim: data['nim'] as String,
      name: data['name'] as String,
      embedding: embeddingDynamic.map((e) => (e as num).toDouble()).toList(),
      embeddingTanpaClahe:
          tanpaClaheDynamic?.map((e) => (e as num).toDouble()).toList(),
    );
  }

  /// Format penyimpanan cache Hive untuk satu FaceRecord
  static Map<String, dynamic> _mapCache(FaceRecord record) {
    return {
      'nim': record.nim,
      'name': record.name,
      'embedding': record.embedding,
      if (record.embeddingTanpaClahe != null)
        'embedding_tanpa_clahe': record.embeddingTanpaClahe,
    };
  }

  /// Menyimpan embedding baru ke penyimpanan lokal (Hive) dan Firestore (Cloud).
  /// [embeddingTanpaClahe] adalah embedding foto yang sama tanpa CLAHE (untuk eksperimen RM 1).
  Future<void> saveEmbedding(
    String nim,
    String name,
    List<double> embedding, {
    List<double>? embeddingTanpaClahe,
  }) async {
    final record = FaceRecord(
      nim: nim,
      name: name,
      embedding: embedding,
      embeddingTanpaClahe: embeddingTanpaClahe,
    );

    // 1. Simpan ke Hive box dulu agar lokal on-device SELALU punya datanya
    try {
      await initHive();
      final box = Hive.box(_hiveBoxName);
      await box.put(nim, _mapCache(record));
      print('[FaceDatabaseService] ✅ Embedding tersimpan di penyimpanan lokal (Hive).');
    } catch (e) {
      print('[FaceDatabaseService] ⚠️ Gagal simpan ke Hive: $e');
    }

    // 2. Simpan ke Firestore (Cloud)
    try {
      await _firestore.collection(_firestoreCollection).doc(nim).set({
        ..._mapCache(record),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('[FaceDatabaseService] ✅ Embedding tersimpan di Firestore.');
    } catch (e) {
      print('[FaceDatabaseService] ⚠️ Peringatan Firestore (permission-denied atau offline): $e');
      // Tidak me-rethrow agar registrasi lokal siswa tetap sukses berjalan di HP
    }
  }

  /// Menghapus embedding dari Firestore berdasarkan NIM
  Future<void> deleteEmbedding(String nim) async {
    await _firestore.collection(_firestoreCollection).doc(nim).delete();
  }

  /// Mengunduh SEMUA embedding dari Firestore, menyimpannya di Hive untuk offline,
  /// dan mengembalikan daftar FaceRecord.
  Future<List<FaceRecord>> syncFromFirestore() async {
    final snapshot = await _firestore.collection(_firestoreCollection).get();

    await initHive();
    final box = Hive.box(_hiveBoxName);
    await box.clear(); // Bersihkan cache lama

    List<FaceRecord> records = [];

    for (var doc in snapshot.docs) {
      final record = _recordDariMap(doc.data());
      records.add(record);

      // Simpan ke Hive sebagai map
      await box.put(record.nim, _mapCache(record));
    }

    return records;
  }

  /// Mengunduh embedding hanya untuk siswa di kelas tertentu.
  /// 1. Ambil daftar siswa dari sub-collection classes/{classId}/students
  /// 2. Kumpulkan NIM/ID mereka
  /// 3. Ambil embedding dari collection face_embeddings
  /// 4. Cache ke Hive dan kembalikan daftarnya
  ///
  /// CATATAN: Proyek ini menyimpan siswa sebagai SUB-COLLECTION, bukan array.
  /// Lihat: attendance_remote_datasource.dart → getStudentsByClass()
  Future<List<FaceRecord>> syncByClass(String classId) async {
    // 1. Ambil semua dokumen siswa dari sub-collection
    final studentsSnapshot = await _firestore
        .collection('classes')
        .doc(classId)
        .collection('students')
        .get();

    if (studentsSnapshot.docs.isEmpty) return [];

    // 2. Kumpulkan NIM/ID siswa. Coba field 'nisNip' dulu, fallback ke doc.id
    final List<String> studentNims = [];
    for (var doc in studentsSnapshot.docs) {
      final data = doc.data();
      final nim = (data['nisNip'] ?? data['nim'] ?? doc.id).toString();
      studentNims.add(nim);
    }

    if (studentNims.isEmpty) return [];

    await initHive();
    final box = Hive.box(_hiveBoxName);
    await box.clear(); // Bersihkan cache lokal untuk persiapan data kelas baru

    List<FaceRecord> records = [];

    // 3. Firestore `whereIn` dibatasi maksimal 10 elemen.
    // Membagi menjadi chunk berukuran 10.
    for (var i = 0; i < studentNims.length; i += 10) {
      final end = (i + 10 < studentNims.length) ? i + 10 : studentNims.length;
      final chunk = studentNims.sublist(i, end);

      final snapshot = await _firestore
          .collection(_firestoreCollection)
          .where('nim', whereIn: chunk)
          .get();

      for (var doc in snapshot.docs) {
        final record = _recordDariMap(doc.data());
        records.add(record);

        // Simpan ke Hive
        await box.put(record.nim, _mapCache(record));
      }
    }

    return records;
  }

  /// Memuat data embedding yang sudah di-cache dari penyimpanan lokal (Hive)
  Future<List<FaceRecord>> loadFromLocal() async {
    await initHive();
    final box = Hive.box(_hiveBoxName);
    List<FaceRecord> records = [];

    for (var key in box.keys) {
      final data = box.get(key) as Map<dynamic, dynamic>;
      records.add(_recordDariMap(data));
    }

    return records;
  }

  /// Membersihkan penyimpanan cache lokal (Hive)
  Future<void> clearLocalCache() async {
    await initHive();
    final box = Hive.box(_hiveBoxName);
    await box.clear();
  }
}
