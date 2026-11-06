// =========================================================================
// SERVICE BACKUP & RESTORE DATABASE (KHUSUS DEVELOPER)
// =========================================================================
// Backup disimpan di Cloud Firestore, tidak lagi di server VPS:
//   backups/{id}                → info backup (tanggal, pembuat, jumlah dokumen)
//   backups/{id}/bagian/{000..} → isi backup (JSON) dipecah per ±250 ribu karakter,
//                                 karena satu dokumen Firestore maksimal 1 MB
//
// Isi backup:
// - Koleksi operasional sekolah + subkoleksi classes/{id}/students.
// - Tipe data Firestore (Timestamp, GeoPoint, referensi, angka, list, map) dijaga,
//   sehingga hasil restore sama persis dengan aslinya.
// - TIDAK menyimpan data biometrik: face_embeddings tidak ikut, dan foto siswa
//   (photoBase64) dibuang, sesuai prinsip pelindungan data pada skripsi.
// - Log penelitian tidak ikut (diambil terpisah lewat "Bagikan Log CSV").
// =========================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class InfoBackup {
  final String id;
  final DateTime? dibuatPada;
  final String dibuatOleh;
  final int totalDokumen;
  final int ukuranKarakter;
  final Map<String, dynamic> jumlahDokumen;

  InfoBackup({
    required this.id,
    required this.dibuatPada,
    required this.dibuatOleh,
    required this.totalDokumen,
    required this.ukuranKarakter,
    required this.jumlahDokumen,
  });

  factory InfoBackup.dariDokumen(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return InfoBackup(
      id: doc.id,
      dibuatPada: (d['dibuatPada'] as Timestamp?)?.toDate(),
      dibuatOleh: d['dibuatOleh'] as String? ?? '-',
      totalDokumen: (d['totalDokumen'] as num?)?.toInt() ?? 0,
      ukuranKarakter: (d['ukuranKarakter'] as num?)?.toInt() ?? 0,
      jumlahDokumen: Map<String, dynamic>.from(d['jumlahDokumen'] as Map? ?? {}),
    );
  }
}

class BackupService {
  static const String koleksiBackup = 'backups';
  static const String subkoleksiBagian = 'bagian';
  static const int versiFormat = 2;

  /// Koleksi tingkat atas yang dicadangkan
  static const List<String> koleksiDicadangkan = [
    'users', 'classes', 'schedules', 'attendance', 'modules',
    'subjects', 'semesters', 'activity_grades', 'laporan_bantuan', 'students',
  ];

  /// Subkoleksi yang ikut dicadangkan per koleksi induk
  static const Map<String, List<String>> subkoleksi = {
    'classes': ['students'],
  };

  /// Field yang sengaja tidak dicadangkan (foto wajah siswa)
  static const Set<String> fieldDibuang = {'photoBase64'};

  static const int _karakterPerBagian = 250000; // aman di bawah 1 MB walau karakter non-ASCII
  static const int _operasiPerBatch = 400; // di bawah batas 500 operasi per batch

  final FirebaseFirestore _db;

  BackupService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _backups => _db.collection(koleksiBackup);

  // =========================================================================
  // MEMBUAT BACKUP
  // =========================================================================

  /// Membaca seluruh koleksi lalu menyusunnya menjadi isi backup (format versi 2)
  Future<Map<String, dynamic>> susunIsiBackup() async {
    final koleksi = <String, dynamic>{};
    for (final nama in koleksiDicadangkan) {
      final snap = await _db.collection(nama).get();
      final daftar = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final item = <String, dynamic>{'id': doc.id, 'data': _bersihkan(doc.data())};
        final sub = <String, dynamic>{};
        for (final namaSub in subkoleksi[nama] ?? const <String>[]) {
          final subSnap = await doc.reference.collection(namaSub).get();
          sub[namaSub] = subSnap.docs
              .map((s) => {'id': s.id, 'data': _bersihkan(s.data())})
              .toList();
        }
        if (sub.isNotEmpty) item['sub'] = sub;
        daftar.add(item);
      }
      koleksi[nama] = daftar;
    }
    return {
      'format': 'SIAP-backup',
      'versi': versiFormat,
      'dibuat': DateTime.now().toIso8601String(),
      'koleksi': koleksi,
    };
  }

  /// Membuat backup baru di Firestore. Mengembalikan jumlah dokumen yang dicadangkan.
  Future<int> buatBackup({required String dibuatOleh}) async {
    final isi = await susunIsiBackup();
    final teks = jsonEncode(isi);
    final jumlah = hitungDokumen(isi);
    final total = jumlah.values.fold<int>(0, (s, n) => s + n);

    final ref = _backups.doc();
    // Bagian ditulis lebih dulu; dokumen info ditulis terakhir agar backup
    // yang gagal di tengah jalan tidak muncul di riwayat.
    int urutan = 0;
    for (int i = 0; i < teks.length; i += _karakterPerBagian) {
      final akhir = (i + _karakterPerBagian < teks.length) ? i + _karakterPerBagian : teks.length;
      await ref.collection(subkoleksiBagian).doc(urutan.toString().padLeft(3, '0')).set({
        'urutan': urutan,
        'isi': teks.substring(i, akhir),
      });
      urutan++;
    }
    await ref.set({
      'dibuatPada': FieldValue.serverTimestamp(),
      'dibuatOleh': dibuatOleh,
      'versi': versiFormat,
      'jumlahDokumen': jumlah,
      'totalDokumen': total,
      'ukuranKarakter': teks.length,
      'jumlahBagian': urutan,
    });
    return total;
  }

  /// Daftar backup terbaru lebih dulu (untuk halaman Riwayat Backup)
  Stream<List<InfoBackup>> riwayat() => _backups
      .orderBy('dibuatPada', descending: true)
      .snapshots()
      .map((s) => s.docs.map(InfoBackup.dariDokumen).toList());

  /// Mengambil isi backup (JSON) dengan menggabungkan seluruh bagiannya
  Future<String> ambilIsiBackup(String id) async {
    final snap = await _backups.doc(id).collection(subkoleksiBagian).orderBy('urutan').get();
    return snap.docs.map((d) => d.data()['isi'] as String).join();
  }

  /// Menyimpan isi backup ke berkas JSON lalu membuka menu bagikan (WhatsApp, Drive, dll.)
  Future<void> bagikanSebagaiJson(String id, {DateTime? tanggal}) async {
    final teks = await ambilIsiBackup(id);
    final waktu = (tanggal ?? DateTime.now()).toIso8601String().substring(0, 19).replaceAll(':', '-');
    final file = File('${(await getTemporaryDirectory()).path}/Backup_SIAP_$waktu.json');
    await file.writeAsString(teks);
    await Share.shareXFiles([XFile(file.path)], text: 'Backup Database SIAP $waktu');
  }

  /// Menghapus satu backup beserta seluruh bagiannya
  Future<void> hapusBackup(String id) async {
    final ref = _backups.doc(id);
    final bagian = await ref.collection(subkoleksiBagian).get();
    for (final d in bagian.docs) {
      await d.reference.delete();
    }
    await ref.delete();
  }

  // =========================================================================
  // RESTORE
  // =========================================================================

  /// Memulihkan backup dari riwayat Firestore. Mengembalikan jumlah dokumen yang ditulis.
  Future<int> pulihkanDariRiwayat(String id) async =>
      pulihkanDariJson(await ambilIsiBackup(id));

  /// Memulihkan dari teks JSON (format versi 2, atau format lama tombol Export sebelumnya).
  /// Dokumen dengan ID yang sama ditimpa; dokumen yang tidak ada di backup dibiarkan.
  Future<int> pulihkanDariJson(String teks) async {
    final data = jsonDecode(teks) as Map<String, dynamic>;
    final penulis = _PenulisBatch(_db, _operasiPerBatch);

    if (data['versi'] == versiFormat && data['koleksi'] is Map) {
      final koleksi = Map<String, dynamic>.from(data['koleksi'] as Map);
      for (final entri in koleksi.entries) {
        for (final item in (entri.value as List)) {
          final ref = _db.collection(entri.key).doc(item['id'] as String);
          await penulis.set(ref, _dariJson(item['data']) as Map<String, dynamic>);
          final sub = item['sub'] as Map<String, dynamic>? ?? {};
          for (final s in sub.entries) {
            for (final anak in (s.value as List)) {
              await penulis.set(ref.collection(s.key).doc(anak['id'] as String),
                  _dariJson(anak['data']) as Map<String, dynamic>);
            }
          }
        }
      }
    } else {
      // Format lama: { koleksi: [ {id, field: "teks"} ] }, semua nilai berupa teks
      for (final entri in data.entries) {
        if (entri.value is! List) continue;
        for (final doc in (entri.value as List)) {
          final isi = Map<String, dynamic>.from(doc as Map);
          final id = isi.remove('id') as String?;
          final ref = id != null ? _db.collection(entri.key).doc(id) : _db.collection(entri.key).doc();
          await penulis.set(ref, isi);
        }
      }
    }
    await penulis.selesai();
    return penulis.jumlah;
  }

  // =========================================================================
  // KONVERSI TIPE DATA FIRESTORE <-> JSON
  // =========================================================================

  static Map<String, int> hitungDokumen(Map<String, dynamic> isi) {
    final hasil = <String, int>{};
    final koleksi = Map<String, dynamic>.from(isi['koleksi'] as Map);
    for (final e in koleksi.entries) {
      final daftar = e.value as List;
      hasil[e.key] = daftar.length;
      for (final item in daftar) {
        final sub = item['sub'] as Map<String, dynamic>? ?? {};
        for (final s in sub.entries) {
          final kunci = '${e.key}/${s.key}';
          hasil[kunci] = (hasil[kunci] ?? 0) + (s.value as List).length;
        }
      }
    }
    return hasil;
  }

  static Map<String, dynamic> _bersihkan(Map<String, dynamic> data) {
    final salinan = Map<String, dynamic>.of(data)..removeWhere((k, _) => fieldDibuang.contains(k));
    return _keJson(salinan) as Map<String, dynamic>;
  }

  static const String _penandaTipe = '__tipe';

  static dynamic _keJson(dynamic v) {
    if (v is Timestamp) {
      return {_penandaTipe: 'timestamp', 'detik': v.seconds, 'nano': v.nanoseconds};
    }
    if (v is GeoPoint) {
      return {_penandaTipe: 'geopoint', 'lat': v.latitude, 'lng': v.longitude};
    }
    if (v is DocumentReference) return {_penandaTipe: 'referensi', 'path': v.path};
    if (v is Blob) return {_penandaTipe: 'blob', 'base64': base64Encode(v.bytes)};
    if (v is double && (v.isNaN || v.isInfinite)) {
      return {_penandaTipe: 'double', 'nilai': v.toString()};
    }
    if (v is Map) return v.map((k, x) => MapEntry(k.toString(), _keJson(x)));
    if (v is List) return v.map(_keJson).toList();
    return v; // String, int, double, bool, null
  }

  dynamic _dariJson(dynamic v) {
    if (v is Map) {
      switch (v[_penandaTipe]) {
        case 'timestamp':
          return Timestamp(v['detik'] as int, v['nano'] as int);
        case 'geopoint':
          return GeoPoint((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble());
        case 'referensi':
          return _db.doc(v['path'] as String);
        case 'blob':
          return Blob(Uint8List.fromList(base64Decode(v['base64'] as String)));
        case 'double':
          return double.parse(v['nilai'] as String);
      }
      return v.map((k, x) => MapEntry(k.toString(), _dariJson(x)));
    }
    if (v is List) return v.map(_dariJson).toList();
    return v;
  }
}

/// Menulis dokumen dalam beberapa batch agar tidak melewati batas 500 operasi Firestore
class _PenulisBatch {
  final FirebaseFirestore _db;
  final int _batas;
  WriteBatch _batch;
  int _isiBatch = 0;
  int jumlah = 0;

  _PenulisBatch(this._db, this._batas) : _batch = _db.batch();

  Future<void> set(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) async {
    _batch.set(ref, data);
    _isiBatch++;
    jumlah++;
    if (_isiBatch >= _batas) {
      await _batch.commit();
      _batch = _db.batch();
      _isiBatch = 0;
    }
  }

  Future<void> selesai() async {
    if (_isiBatch > 0) await _batch.commit();
  }
}
