// =========================================================================
// PENCATAT DATA PENELITIAN (CSV LOKAL + FIRESTORE)
// =========================================================================
// Dua jenis log:
// 1. penelitian_log_wajah.csv  → 1 baris per wajah yang diproses
//    (jarak, keputusan, latensi per tahap) → bahan RM 1 & RM 2
// 2. penelitian_log_sesi.csv   → 1 baris per sesi absensi yang disimpan
//    (metode wajah/manual, durasi, koreksi guru) → bahan RM 3
//
// File CSV disimpan di folder eksternal aplikasi (bisa diambil via USB atau
// dibagikan lewat tombol "Bagikan Log"), dan salinannya dikirim ke Firestore
// secara batch agar hemat kuota tulis.
// =========================================================================

import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/ai/face_matching_service.dart';

class ResearchLogger {
  static const String koleksiWajah = 'penelitian_log_wajah';
  static const String koleksiSesi = 'penelitian_log_sesi';
  static const String fileWajah = 'penelitian_log_wajah.csv';
  static const String fileSesi = 'penelitian_log_sesi.csv';

  static const List<String> kolomWajah = [
    'waktu', 'sumber', 'sesi_id', 'kondisi_cahaya', 'clahe', 'mode_verifikasi',
    'ambang', 'margin', 'file', 'label_nim', 'terdaftar', 'jumlah_wajah',
    'indeks_wajah', 'raw_nim', 'raw_nama', 'jarak_terbaik', 'jarak_kedua',
    'selisih', 'alasan', 'pred_nim', 'pred_nim_tunggal', 'pred_nim_margin',
    'nim_daftar_hadir', 'cocok_via', 't_deteksi_ms', 't_decode_ms',
    't_crop_ms', 't_clahe_ms', 't_embedding_ms', 't_matching_ms', 't_frame_ms',
  ];

  static const List<String> kolomSesi = [
    'sesi_id', 'waktu_mulai', 'waktu_selesai', 'metode', 'kelas', 'mapel',
    'tanggal', 'jumlah_siswa', 'durasi_total_detik', 'durasi_scan_detik',
    'hadir_hasil_scan', 'hadir_akhir', 'koreksi_total', 'koreksi_jadi_hadir',
    'koreksi_batal_hadir', 'akurasi_scan_persen', 'kondisi_cahaya', 'clahe',
    'mode_verifikasi',
  ];

  static const int _ukuranBatch = 400; // Batas aman di bawah limit 500 Firestore

  static final List<Map<String, dynamic>> _antreanFirestore = [];
  static Future<void> _antreanTulis = Future.value();
  static bool _sedangKirim = false;

  static int get jumlahAntreanFirestore => _antreanFirestore.length;

  /// Folder penyimpanan log: /Android/data/<paket>/files/penelitian
  static Future<Directory> folderLog() async {
    final folder = Directory('${(await folderDasar()).path}/penelitian');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  /// Folder eksternal aplikasi (Android), atau folder dokumen di platform lain
  static Future<Directory> folderDasar() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    } catch (_) {
      // getExternalStorageDirectory hanya didukung di Android
    }
    return getApplicationDocumentsDirectory();
  }

  /// Kolom keputusan untuk satu hasil pencocokan.
  /// Keputusan mode ambang tunggal DAN mode margin dihitung sekaligus dari jarak
  /// yang sama, sehingga kedua mode bisa dibandingkan pada wajah yang identik (RM 2).
  static Map<String, dynamic> kolomKeputusan(
    MatchResult r, {
    required double ambang,
    required double margin,
  }) {
    final bool lolosAmbang = r.distance <= ambang;
    final double selisih = r.secondDistance - r.distance;
    // Sama dengan aturan di FaceMatchingService: margin hanya berlaku jika ada kandidat kedua
    final bool lolosMargin = r.secondDistance >= 999.0 || selisih >= margin;

    return {
      'raw_nim': r.rawNim,
      'raw_nama': r.rawName,
      'jarak_terbaik': _bulat(r.distance, 4),
      'jarak_kedua': _bulat(r.secondDistance, 4),
      'selisih': _bulat(selisih, 4),
      'alasan': r.alasan,
      'pred_nim': r.nim,
      'pred_nim_tunggal': lolosAmbang ? r.rawNim : 'Unknown',
      'pred_nim_margin': lolosAmbang && lolosMargin ? r.rawNim : 'Unknown',
    };
  }

  static double _bulat(double nilai, int digit) =>
      double.parse(nilai.toStringAsFixed(digit));

  static double ms(double nilai) => _bulat(nilai, 3);

  static String waktuSekarang() => DateTime.now().toIso8601String();

  /// Mencatat satu atau beberapa baris log wajah
  static Future<void> catatWajah(List<Map<String, dynamic>> baris) {
    if (baris.isEmpty) return Future.value();
    for (final b in baris) {
      _antreanFirestore.add({...b, '_koleksi': koleksiWajah});
    }
    if (_antreanFirestore.length >= _ukuranBatch) {
      unawaited(kirimKeFirestore());
    }
    return _tulisCsv(fileWajah, kolomWajah, baris);
  }

  /// Mencatat satu sesi absensi (langsung dikirim ke Firestore)
  static Future<void> catatSesi(Map<String, dynamic> baris) {
    _antreanFirestore.add({...baris, '_koleksi': koleksiSesi});
    unawaited(kirimKeFirestore());
    return _tulisCsv(fileSesi, kolomSesi, [baris]);
  }

  // Penulisan file diserialkan agar baris dari siklus scan yang berdekatan tidak saling tumpang tindih
  static Future<void> _tulisCsv(
      String namaFile, List<String> kolom, List<Map<String, dynamic>> baris) {
    _antreanTulis = _antreanTulis.then((_) async {
      try {
        final folder = await folderLog();
        final file = File('${folder.path}/$namaFile');
        final bool fileBaru = !await file.exists();

        final rows = <List<dynamic>>[
          if (fileBaru) kolom,
          ...baris.map((b) => kolom.map((k) => b[k] ?? '').toList()),
        ];
        await file.writeAsString(
          '${const ListToCsvConverter().convert(rows)}\r\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (e) {
        print('[ResearchLogger] Gagal menulis $namaFile: $e');
      }
    });
    return _antreanTulis;
  }

  /// Mengirim antrean log ke Firestore secara batch. Mengembalikan jumlah baris terkirim.
  static Future<int> kirimKeFirestore() async {
    if (_sedangKirim) return 0;
    _sedangKirim = true;
    int terkirim = 0;
    try {
      final db = FirebaseFirestore.instance;
      while (_antreanFirestore.isNotEmpty) {
        final potongan = _antreanFirestore.take(_ukuranBatch).toList();
        final batch = db.batch();
        for (final b in potongan) {
          final data = Map<String, dynamic>.of(b)..remove('_koleksi');
          batch.set(db.collection(b['_koleksi'] as String).doc(), data);
        }
        await batch.commit();
        _antreanFirestore.removeRange(0, potongan.length);
        terkirim += potongan.length;
      }
    } catch (e) {
      // CSV lokal tetap aman; antrean dicoba lagi pada pengiriman berikutnya
      print('[ResearchLogger] Gagal kirim ke Firestore: $e');
    } finally {
      _sedangKirim = false;
    }
    return terkirim;
  }

  /// Membagikan file CSV (WhatsApp, Drive, email, dll.)
  static Future<bool> bagikan() async {
    await _antreanTulis;
    final folder = await folderLog();
    final files = [fileWajah, fileSesi]
        .map((n) => File('${folder.path}/$n'))
        .where((f) => f.existsSync())
        .map((f) => XFile(f.path))
        .toList();
    if (files.isEmpty) return false;
    await Share.shareXFiles(files, text: 'Log Penelitian Presensi Wajah');
    return true;
  }

  /// Menghapus file CSV lokal (data di Firestore tidak ikut terhapus)
  static Future<void> hapusLogLokal() async {
    await _antreanTulis;
    final folder = await folderLog();
    for (final n in [fileWajah, fileSesi]) {
      final f = File('${folder.path}/$n');
      if (await f.exists()) await f.delete();
    }
  }
}
