// =========================================================================
// EVALUASI DATASET FOTO (RM 1 & RM 2)
// =========================================================================
// Menguji pipeline on-device yang SAMA PERSIS dengan layar absensi
// (ML Kit → crop → [CLAHE] → MobileFaceNet → pencocokan) pada folder foto
// berlabel, sehingga setiap konfigurasi diuji pada foto yang identik.
//
// Struktur folder dataset:
//   dataset_skripsi/
//     galeri/<NIM>_<Nama>/*.jpg          → foto pendaftaran (dirata-ratakan per orang)
//     uji/<kondisi>/<NIM>/*.jpg          → foto uji orang terdaftar (genuine)
//     uji/<kondisi>/tidak_terdaftar/*.jpg → foto orang di luar galeri (impostor, untuk FAR)
//
// Untuk setiap konfigurasi CLAHE (aktif / mati), galeri DIBANGUN ULANG dengan
// pra-pemrosesan yang sama agar perbandingan adil. Keputusan ambang tunggal dan
// margin dicatat sekaligus dari jarak yang sama (RM 2).
//
// Definisi metrik (identifikasi open-set):
//   FAR = impostor yang diterima sebagai siswa mana pun / total impostor
//   FRR = genuine yang ditolak (Unknown) / total genuine
//   MIR = genuine yang diterima sebagai siswa LAIN / total genuine
//   Foto tanpa wajah terdeteksi dihitung terpisah sebagai FTA (failure to acquire).
// =========================================================================

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../../../core/ai/face_detector_service.dart';
import '../../../core/ai/face_embedding_service.dart';
import '../../../core/ai/face_matching_service.dart';
import '../research_config.dart';
import '../research_logger.dart';

const String _labelImpostor = 'tidak_terdaftar';
const Set<String> _ekstensiFoto = {'.jpg', '.jpeg', '.png'};

class DatasetEvaluationPage extends StatefulWidget {
  const DatasetEvaluationPage({super.key});

  @override
  State<DatasetEvaluationPage> createState() => _DatasetEvaluationPageState();
}

class _DatasetEvaluationPageState extends State<DatasetEvaluationPage> {
  String? _folderDataset;
  bool _ujiDenganClahe = true;
  bool _ujiTanpaClahe = true;

  bool _berjalan = false;
  bool _dibatalkan = false;
  String _status = '';
  double _progres = 0;
  final List<_Ringkasan> _hasil = [];

  FaceDetectorService? _detector;
  FaceEmbeddingService? _embedding;

  @override
  void initState() {
    super.initState();
    _siapkanFolderBawaan();
  }

  @override
  void dispose() {
    _dibatalkan = true;
    _detector?.dispose();
    _embedding?.dispose();
    super.dispose();
  }

  Future<void> _siapkanFolderBawaan() async {
    final dasar = await ResearchLogger.folderDasar();
    if (mounted) setState(() => _folderDataset = '${dasar.path}/dataset_skripsi');
  }

  Future<void> _pilihFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null && mounted) setState(() => _folderDataset = path);
  }

  /// Membuat kerangka folder kosong agar peneliti tinggal mengisi foto
  Future<void> _buatStrukturFolder() async {
    if (_folderDataset == null) return;
    await Directory('$_folderDataset/galeri').create(recursive: true);
    for (final kondisi in ResearchConfig.kondisiBawaan.keys) {
      await Directory('$_folderDataset/uji/$kondisi/$_labelImpostor').create(recursive: true);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Struktur folder dibuat. Isi galeri/<NIM>_<Nama>/ dan uji/<kondisi>/<NIM>/ dengan foto.'),
      ));
    }
  }

  // =========================================================================
  // PEMBACAAN DATASET
  // =========================================================================
  static List<Directory> _subfolder(Directory dir) {
    final list = dir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return list;
  }

  static List<File> _fotoDi(Directory dir) {
    final list = dir
        .listSync()
        .whereType<File>()
        .where((f) => _ekstensiFoto.any((e) => f.path.toLowerCase().endsWith(e)))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return list;
  }

  static String _namaFolder(Directory dir) =>
      dir.path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).last;

  /// "12345_Budi Santoso" → nim "12345", nama "Budi Santoso"
  static ({String nim, String nama}) _parseOrang(String namaFolder) {
    final i = namaFolder.indexOf('_');
    if (i <= 0) return (nim: namaFolder, nama: namaFolder);
    return (nim: namaFolder.substring(0, i), nama: namaFolder.substring(i + 1));
  }

  // =========================================================================
  // PIPELINE SATU FOTO (sama dengan AttendanceScreen)
  // =========================================================================
  Future<_HasilWajah?> _prosesFoto(File file, bool clahe) async {
    final waktu = <String, double>{};
    final sw = Stopwatch()..start();

    // 1. Deteksi wajah (ML Kit)
    final faces = await _detector!.detectFaces(InputImage.fromFilePath(file.path));
    waktu['deteksi'] = sw.elapsedMicroseconds / 1000.0;
    if (faces.isEmpty) return _HasilWajah(null, null, 0, waktu);

    // 2. Decode + koreksi orientasi EXIF
    sw..reset()..start();
    final raw = img.decodeImage(await file.readAsBytes());
    if (raw == null) return _HasilWajah(null, null, faces.length, waktu);
    final fullImage = img.bakeOrientation(raw);
    waktu['decode'] = sw.elapsedMicroseconds / 1000.0;

    // 3. Ambil wajah terbesar (1 orang per foto), lalu crop 112x112
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));
    final bbox = faces.first.boundingBox;
    sw..reset()..start();
    final crop = _embedding!.cropAndAlignFace(fullImage, bbox);
    waktu['crop'] = sw.elapsedMicroseconds / 1000.0;

    // 4. [CLAHE] + MobileFaceNet (waktu dicatat di dalam service)
    final w = <String, double>{};
    final emb = _embedding!.extractEmbedding(crop, applyClahe: clahe, waktu: w);
    waktu['clahe'] = w['clahe_ms'] ?? 0.0;
    waktu['embedding'] = w['embedding_ms'] ?? 0.0;

    final box = [bbox.left.toInt(), bbox.top.toInt(), bbox.right.toInt(), bbox.bottom.toInt()];
    return _HasilWajah(emb, box, faces.length, waktu);
  }

  /// Membangun galeri: embedding semua foto satu orang dirata-ratakan lalu dinormalisasi L2
  Future<List<FaceRecord>> _bangunGaleri(
      List<Directory> folderOrang, bool clahe, void Function() majukanProgres) async {
    final galeri = <FaceRecord>[];
    for (final dir in folderOrang) {
      final orang = _parseOrang(_namaFolder(dir));
      List<double>? jumlah;
      int n = 0;
      for (final foto in _fotoDi(dir)) {
        if (_dibatalkan) return galeri;
        final h = await _prosesFoto(foto, clahe);
        majukanProgres();
        if (h?.embedding == null) continue;
        jumlah ??= List<double>.filled(h!.embedding!.length, 0);
        for (int i = 0; i < jumlah.length; i++) {
          jumlah[i] += h!.embedding![i];
        }
        n++;
      }
      if (jumlah == null || n == 0) continue;
      final norm = sqrt(jumlah.fold<double>(0, (s, v) => s + v * v));
      galeri.add(FaceRecord(
        nim: orang.nim,
        name: orang.nama,
        embedding: jumlah.map((v) => norm > 0 ? v / norm : v).toList(),
      ));
    }
    return galeri;
  }

  // =========================================================================
  // JALANKAN EVALUASI
  // =========================================================================
  Future<void> _jalankan() async {
    final root = _folderDataset;
    if (root == null) return;
    final dirGaleri = Directory('$root/galeri');
    final dirUji = Directory('$root/uji');

    if (!dirGaleri.existsSync() || !dirUji.existsSync()) {
      _tampilkanPesan('Folder galeri/ dan uji/ tidak ditemukan di $root');
      return;
    }

    final konfigurasi = [if (_ujiDenganClahe) true, if (_ujiTanpaClahe) false];
    if (konfigurasi.isEmpty) {
      _tampilkanPesan('Pilih minimal satu konfigurasi CLAHE.');
      return;
    }

    setState(() {
      _berjalan = true;
      _dibatalkan = false;
      _hasil.clear();
      _progres = 0;
      _status = 'Memuat model AI...';
    });

    try {
      _detector ??= FaceDetectorService();
      if (_embedding == null) {
        _embedding = FaceEmbeddingService();
        await _embedding!.initialize();
      }
      if (!_embedding!.isReady) throw Exception('Model MobileFaceNet gagal dimuat');

      // Kumpulkan daftar foto
      final folderOrangGaleri = _subfolder(dirGaleri);
      final jumlahFotoGaleri =
          folderOrangGaleri.fold<int>(0, (s, d) => s + _fotoDi(d).length);
      final fotoUji = <_FotoUji>[];
      for (final dirKondisi in _subfolder(dirUji)) {
        final kondisi = _namaFolder(dirKondisi);
        for (final dirOrang in _subfolder(dirKondisi)) {
          final label = _parseOrang(_namaFolder(dirOrang)).nim;
          for (final f in _fotoDi(dirOrang)) {
            fotoUji.add(_FotoUji(kondisi, label, f, f.path.substring(root.length + 1)));
          }
        }
      }
      if (folderOrangGaleri.isEmpty || fotoUji.isEmpty) {
        throw Exception('Galeri atau foto uji masih kosong.');
      }

      final totalLangkah = konfigurasi.length * (jumlahFotoGaleri + fotoUji.length);
      int langkah = 0;
      void majukan() => langkah++;
      final sesiId = 'dataset_${DateTime.now().millisecondsSinceEpoch}';

      for (final clahe in konfigurasi) {
        final labelKonfig = clahe ? 'CLAHE aktif' : 'Tanpa CLAHE';

        // 1. Galeri dibangun ulang dengan pra-pemrosesan yang sama
        setState(() => _status = '[$labelKonfig] Membangun galeri...');
        final galeri = await _bangunGaleri(folderOrangGaleri, clahe, () {
          majukan();
          if (mounted) setState(() => _progres = langkah / totalLangkah);
        });
        if (_dibatalkan) break;

        final matcher = FaceMatchingService()
          ..loadDatabase(galeri)
          ..gunakanMargin = true;
        final nimTerdaftar = galeri.map((g) => g.nim).toSet();

        // 2. Uji setiap foto
        final ringkasanPerKondisi = <String, _Ringkasan>{};
        final semua = _Ringkasan('SEMUA', clahe);
        final buffer = <Map<String, dynamic>>[];

        for (final foto in fotoUji) {
          if (_dibatalkan) break;
          final h = await _prosesFoto(foto.file, clahe);

          final w = h?.waktu ?? {};
          final terdaftar = foto.label != _labelImpostor && nimTerdaftar.contains(foto.label);
          final baris = <String, dynamic>{
            'waktu': ResearchLogger.waktuSekarang(),
            'sumber': 'dataset',
            'sesi_id': sesiId,
            'kondisi_cahaya': foto.kondisi,
            'clahe': clahe ? 1 : 0,
            'mode_verifikasi': 'margin',
            'ambang': matcher.ambang,
            'margin': matcher.margin,
            'file': foto.relatif,
            'label_nim': foto.label,
            'terdaftar': terdaftar ? 1 : 0,
            'jumlah_wajah': h?.jumlahWajah ?? 0,
            'indeks_wajah': 0,
            't_deteksi_ms': ResearchLogger.ms(w['deteksi'] ?? 0.0),
            't_decode_ms': ResearchLogger.ms(w['decode'] ?? 0.0),
            't_crop_ms': ResearchLogger.ms(w['crop'] ?? 0.0),
            't_clahe_ms': ResearchLogger.ms(w['clahe'] ?? 0.0),
            't_embedding_ms': ResearchLogger.ms(w['embedding'] ?? 0.0),
          };

          if (h?.embedding == null) {
            baris.addAll({
              'alasan': 'wajah_tidak_terdeteksi',
              'raw_nim': '',
              'pred_nim': 'Unknown',
              'pred_nim_tunggal': 'Unknown',
              'pred_nim_margin': 'Unknown',
              't_matching_ms': 0,
            });
          } else {
            final sw = Stopwatch()..start();
            final hasil = matcher.matchFaces([h!.embedding!], [h!.box!]).first;
            baris['t_matching_ms'] = ResearchLogger.ms(sw.elapsedMicroseconds / 1000.0);
            baris.addAll(ResearchLogger.kolomKeputusan(hasil,
                ambang: matcher.ambang, margin: matcher.margin));
          }
          baris['t_frame_ms'] = ResearchLogger.ms(
              ['deteksi', 'decode', 'crop', 'clahe', 'embedding']
                      .fold<double>(0, (s, k) => s + (w[k] ?? 0.0)) +
                  (baris['t_matching_ms'] as num).toDouble());

          ringkasanPerKondisi
              .putIfAbsent(foto.kondisi, () => _Ringkasan(foto.kondisi, clahe))
              .tambah(baris);
          semua.tambah(baris);

          buffer.add(baris);
          if (buffer.length >= 50) {
            await ResearchLogger.catatWajah(List.of(buffer));
            buffer.clear();
          }

          majukan();
          if (mounted) {
            setState(() {
              _progres = langkah / totalLangkah;
              _status = '[$labelKonfig] Menguji ${foto.relatif}';
            });
          }
          // Beri kesempatan UI menggambar ulang progres
          await Future.delayed(Duration.zero);
        }
        await ResearchLogger.catatWajah(buffer);

        _hasil.addAll(ringkasanPerKondisi.values);
        _hasil.add(semua);
        if (_dibatalkan) break;
      }

      await ResearchLogger.kirimKeFirestore();
      if (mounted) {
        setState(() => _status = _dibatalkan
            ? 'Dibatalkan. Hasil sebagian tersimpan di log.'
            : '✅ Selesai. Log tersimpan (sesi $sesiId).');
      }
    } catch (e) {
      if (mounted) setState(() => _status = '❌ Error: $e');
    } finally {
      if (mounted) setState(() => _berjalan = false);
    }
  }

  void _tampilkanPesan(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  // =========================================================================
  // TAMPILAN
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evaluasi Dataset Foto'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Folder Dataset', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SelectableText(_folderDataset ?? '-', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _berjalan ? null : _pilihFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Pilih Folder'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _berjalan ? null : _buatStrukturFolder,
                        icon: const Icon(Icons.create_new_folder),
                        label: const Text('Buat Struktur'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'galeri/<NIM>_<Nama>/*.jpg\n'
                    'uji/<kondisi>/<NIM>/*.jpg\n'
                    'uji/<kondisi>/$_labelImpostor/*.jpg',
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 11.5, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
          CheckboxListTile(
            value: _ujiDenganClahe,
            onChanged: _berjalan ? null : (v) => setState(() => _ujiDenganClahe = v!),
            title: const Text('Uji dengan CLAHE'),
          ),
          CheckboxListTile(
            value: _ujiTanpaClahe,
            onChanged: _berjalan ? null : (v) => setState(() => _ujiTanpaClahe = v!),
            title: const Text('Uji tanpa CLAHE'),
          ),
          const SizedBox(height: 8),
          _berjalan
              ? OutlinedButton.icon(
                  onPressed: () => setState(() => _dibatalkan = true),
                  icon: const Icon(Icons.stop),
                  label: const Text('Batalkan'),
                )
              : FilledButton.icon(
                  onPressed: _jalankan,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Mulai Evaluasi'),
                ),
          if (_berjalan || _status.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (_berjalan) LinearProgressIndicator(value: _progres),
            const SizedBox(height: 6),
            Text(_status, style: const TextStyle(fontSize: 12)),
          ],
          if (_hasil.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Ringkasan Hasil',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              'T = ambang tunggal, M = ambang + margin. Analisis lengkap (sweep ambang, uji statistik) '
              'dengan analisis_penelitian.py.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 14,
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 40,
                columns: const [
                  DataColumn(label: Text('CLAHE')),
                  DataColumn(label: Text('Kondisi')),
                  DataColumn(label: Text('Gen/Imp')),
                  DataColumn(label: Text('FTA')),
                  DataColumn(label: Text('FAR T/M %')),
                  DataColumn(label: Text('FRR T/M %')),
                  DataColumn(label: Text('MIR T/M %')),
                  DataColumn(label: Text('CLAHE ms')),
                  DataColumn(label: Text('Embed ms')),
                  DataColumn(label: Text('Total ms')),
                ],
                rows: _hasil.map((r) {
                  final tebal = r.kondisi == 'SEMUA';
                  Text t(String s) => Text(s,
                      style: TextStyle(fontWeight: tebal ? FontWeight.bold : FontWeight.normal));
                  return DataRow(cells: [
                    DataCell(t(r.clahe ? 'Ya' : 'Tidak')),
                    DataCell(t(r.kondisi)),
                    DataCell(t('${r.genuine}/${r.impostor}')),
                    DataCell(t('${r.fta}')),
                    DataCell(t('${_pct(r.faT, r.impostor)} / ${_pct(r.faM, r.impostor)}')),
                    DataCell(t('${_pct(r.frT, r.genuine)} / ${_pct(r.frM, r.genuine)}')),
                    DataCell(t('${_pct(r.miT, r.genuine)} / ${_pct(r.miM, r.genuine)}')),
                    DataCell(t(_rata(r.tClahe))),
                    DataCell(t(_rata(r.tEmbedding))),
                    DataCell(t(_rata(r.tFrame))),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _pct(int a, int b) => b == 0 ? '-' : (a * 100 / b).toStringAsFixed(1);

  static String _rata(List<double> v) {
    if (v.isEmpty) return '-';
    final mean = v.reduce((a, b) => a + b) / v.length;
    final sd = sqrt(v.fold<double>(0, (s, x) => s + (x - mean) * (x - mean)) / v.length);
    return '${mean.toStringAsFixed(1)}±${sd.toStringAsFixed(1)}';
  }
}

class _FotoUji {
  final String kondisi;
  final String label;
  final File file;
  final String relatif;
  _FotoUji(this.kondisi, this.label, this.file, this.relatif);
}

class _HasilWajah {
  final List<double>? embedding;
  final List<int>? box;
  final int jumlahWajah;
  final Map<String, double> waktu;
  _HasilWajah(this.embedding, this.box, this.jumlahWajah, this.waktu);
}

/// Akumulator metrik FAR / FRR / MIR + latensi per (konfigurasi CLAHE, kondisi)
class _Ringkasan {
  final String kondisi;
  final bool clahe;
  int genuine = 0, impostor = 0, fta = 0;
  // T = ambang tunggal, M = ambang + margin
  int faT = 0, frT = 0, miT = 0;
  int faM = 0, frM = 0, miM = 0;
  final List<double> tClahe = [], tEmbedding = [], tFrame = [];

  _Ringkasan(this.kondisi, this.clahe);

  void tambah(Map<String, dynamic> baris) {
    if (baris['alasan'] == 'wajah_tidak_terdeteksi') {
      fta++;
      return;
    }
    final bool terdaftar = baris['terdaftar'] == 1;
    final String label = baris['label_nim'];
    final String predT = baris['pred_nim_tunggal'];
    final String predM = baris['pred_nim_margin'];

    if (terdaftar) {
      genuine++;
      if (predT == 'Unknown') {
        frT++;
      } else if (predT != label) {
        miT++;
      }
      if (predM == 'Unknown') {
        frM++;
      } else if (predM != label) {
        miM++;
      }
    } else {
      impostor++;
      if (predT != 'Unknown') faT++;
      if (predM != 'Unknown') faM++;
    }

    if (clahe) tClahe.add((baris['t_clahe_ms'] as num).toDouble());
    tEmbedding.add((baris['t_embedding_ms'] as num).toDouble());
    tFrame.add((baris['t_frame_ms'] as num).toDouble());
  }
}
