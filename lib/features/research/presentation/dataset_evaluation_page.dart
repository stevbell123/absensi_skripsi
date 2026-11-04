// =========================================================================
// EVALUASI DATASET FOTO (RM 1 & RM 2)
// =========================================================================
// Menguji pipeline on-device yang SAMA PERSIS dengan layar absensi
// (ML Kit → crop → [CLAHE] → MobileFaceNet → pencocokan) pada folder foto
// berlabel, sehingga setiap konfigurasi diuji pada foto yang identik.
//
// Struktur folder dataset (dibaca oleh dataset_reader.dart):
//   dataset_validasi/ atau dataset_uji/
//     S01/registrasi/*.jpg   → foto acuan siswa terdaftar (kode siswa, bukan NIS/nama)
//     S01/<kondisi>/*.jpg    → foto siswa terdaftar (genuine)
//     TT01/<kondisi>/*.jpg   → tanpa registrasi = tidak terdaftar (impostor, untuk FAR)
//   Susunan lama (galeri/ + uji/<kondisi>/<NIS>/) tetap dibaca.
//
// Untuk setiap konfigurasi CLAHE (aktif / mati), galeri DIBANGUN ULANG dengan
// pra-pemrosesan yang sama agar perbandingan adil. Keputusan ambang tunggal dan
// margin dicatat sekaligus dari jarak yang sama (RM 2).
//
// Definisi metrik (identifikasi open-set):
//   FAR = impostor yang diterima sebagai siswa mana pun / total impostor
//   FRR = genuine yang ditolak (Unknown) / total genuine
//   MIR = genuine yang diterima sebagai siswa LAIN / total genuine
//   Foto tanpa wajah terdeteksi (FTA) dihitung sebagai keputusan DITOLAK
//   (genuine → FRR, impostor → ditolak dengan benar) sesuai Tabel 2.2 Bab II,
//   dan jumlahnya tetap ditampilkan terpisah pada kolom FTA.
// =========================================================================

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../../../core/ai/face_detector_service.dart';
import '../../../core/ai/face_embedding_service.dart';
import '../../../core/ai/face_matching_service.dart';
import '../dataset_reader.dart';
import '../research_config.dart';
import '../research_logger.dart';

class DatasetEvaluationPage extends StatefulWidget {
  const DatasetEvaluationPage({super.key});

  @override
  State<DatasetEvaluationPage> createState() => _DatasetEvaluationPageState();
}

class _DatasetEvaluationPageState extends State<DatasetEvaluationPage> {
  String? _folderDataset;
  IsiDataset? _isi; // hasil pemeriksaan folder sebelum evaluasi
  String? _galatFolder;
  final List<String> _peringatanJalan = [];
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
    _aturFolder('${dasar.path}/dataset_validasi');
  }

  void _aturFolder(String path) {
    if (!mounted) return;
    setState(() {
      _folderDataset = path;
      _hasil.clear();
      _peringatanJalan.clear();
      _status = '';
    });
    _periksaFolder();
  }

  /// Membaca isi folder tanpa memproses foto, agar kesalahan susunan terlihat sebelum evaluasi
  void _periksaFolder() {
    final folder = _folderDataset;
    if (folder == null) return;
    try {
      final isi = bacaDataset(folder, kondisiDikenal: ResearchConfig.kondisiBawaan.keys.toSet());
      setState(() {
        _isi = isi;
        _galatFolder = null;
      });
    } catch (e) {
      setState(() {
        _isi = null;
        _galatFolder = e is FormatException ? e.message : '$e';
      });
    }
  }

  /// Daftar folder di dalam folder aplikasi (Android/data/<paket>/files), tempat dataset
  /// disalin lewat USB. Pemilih folder Android sering tidak bisa membuka Android/data.
  Future<void> _pilihFolder() async {
    final dasar = await ResearchLogger.folderDasar();
    final daftar = subfolder(dasar).where((d) => namaFolder(d) != 'penelitian').toList();
    if (!mounted) return;
    final pilihan = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Pilih folder dataset',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(dasar.path, style: const TextStyle(fontSize: 11.5)),
            ),
            if (daftar.isEmpty)
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Belum ada folder. Salin dataset_validasi / dataset_uji '
                    'ke folder di atas lewat kabel USB.'),
              ),
            ...daftar.map((d) => ListTile(
                  leading: const Icon(Icons.folder, color: Colors.indigo),
                  title: Text(namaFolder(d)),
                  onTap: () => Navigator.pop(ctx, d.path),
                )),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.sd_storage),
              title: const Text('Folder lain di penyimpanan HP...'),
              subtitle: const Text('Misalnya Pictures, Download, atau DCIM'),
              onTap: () async {
                if (!await _mintaIzinFoto()) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  return;
                }
                final path = await FilePicker.platform.getDirectoryPath();
                if (ctx.mounted) Navigator.pop(ctx, path);
              },
            ),
          ],
        ),
      ),
    );
    if (pilihan != null) _aturFolder(pilihan);
  }

  /// Izin membaca foto di luar folder aplikasi: READ_MEDIA_IMAGES (Android 13+)
  /// atau READ_EXTERNAL_STORAGE (Android 12 ke bawah, misalnya Galaxy S10).
  Future<bool> _mintaIzinFoto() async {
    if (!Platform.isAndroid) return true;
    final status = await [Permission.photos, Permission.storage].request();
    if (status.values.any((s) => s.isGranted || s.isLimited)) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Izin akses foto ditolak. Aktifkan di pengaturan aplikasi.'),
        action: SnackBarAction(label: 'Pengaturan', onPressed: openAppSettings),
      ));
    }
    return false;
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

    // Luminansi untuk ambang T_Y (Bab III), dihitung di luar pengukuran latensi
    final lum = _luminansi(fullImage, bbox);

    // 4. [CLAHE] + MobileFaceNet (waktu dicatat di dalam service)
    final w = <String, double>{};
    final emb = _embedding!.extractEmbedding(crop, applyClahe: clahe, waktu: w);
    waktu['clahe'] = w['clahe_ms'] ?? 0.0;
    waktu['embedding'] = w['embedding_ms'] ?? 0.0;

    final box = [bbox.left.toInt(), bbox.top.toInt(), bbox.right.toInt(), bbox.bottom.toInt()];
    return _HasilWajah(emb, box, faces.length, waktu,
        lumWajah: lum.wajah, lumLatar: lum.latar);
  }

  /// Rata-rata luminansi Y (BT.601, sama dengan ClaheService) pada citra utuh
  /// sebelum CLAHE: di dalam bounding box wajah (Ȳw) dan di luarnya (Ȳl).
  static ({double? wajah, double? latar}) _luminansi(img.Image citra, Rect kotak) {
    double jumlahWajah = 0, jumlahLatar = 0;
    int nWajah = 0, nLatar = 0;
    for (final p in citra) {
      final y = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (kotak.contains(Offset(p.x + 0.5, p.y + 0.5))) {
        jumlahWajah += y;
        nWajah++;
      } else {
        jumlahLatar += y;
        nLatar++;
      }
    }
    return (
      wajah: nWajah > 0 ? jumlahWajah / nWajah : null,
      latar: nLatar > 0 ? jumlahLatar / nLatar : null,
    );
  }

  /// Membangun galeri: embedding semua foto satu orang dirata-ratakan lalu dinormalisasi L2
  Future<List<FaceRecord>> _bangunGaleri(
      List<OrangGaleri> daftarOrang, bool clahe, void Function() majukanProgres) async {
    final galeri = <FaceRecord>[];
    for (final orang in daftarOrang) {
      List<double>? jumlah;
      int n = 0;
      for (final foto in orang.foto) {
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
    if (_folderDataset == null) return;
    _periksaFolder();
    final isi = _isi;
    if (isi == null) {
      _tampilkanPesan(_galatFolder ?? 'Folder dataset belum dipilih.');
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
      _peringatanJalan.clear();
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

      final fotoUji = isi.uji;
      if (isi.galeri.isEmpty) {
        throw Exception('Belum ada siswa terdaftar (folder registrasi berisi foto).');
      }
      if (fotoUji.isEmpty) throw Exception('Belum ada foto di subfolder kondisi.');

      final totalLangkah = konfigurasi.length * (isi.jumlahFotoGaleri + fotoUji.length);
      int langkah = 0;
      void majukan() => langkah++;
      final sesiId = 'dataset_${DateTime.now().millisecondsSinceEpoch}';

      for (final clahe in konfigurasi) {
        final labelKonfig = clahe ? 'CLAHE aktif' : 'Tanpa CLAHE';

        // 1. Galeri dibangun ulang dengan pra-pemrosesan yang sama
        setState(() => _status = '[$labelKonfig] Membangun galeri...');
        final galeri = await _bangunGaleri(isi.galeri, clahe, () {
          majukan();
          if (mounted) setState(() => _progres = langkah / totalLangkah);
        });
        if (_dibatalkan) break;

        // Siswa yang wajahnya tidak terdeteksi di foto registrasi tidak masuk galeri,
        // sehingga semua fotonya akan terhitung sebagai siswa tidak terdaftar.
        final nimGaleri = galeri.map((g) => g.nim).toSet();
        for (final orang in isi.galeri.where((o) => !nimGaleri.contains(o.nim))) {
          final pesan = '${orang.nim}_${orang.nama}: wajah tidak terdeteksi di foto registrasi '
              '(${clahe ? 'CLAHE' : 'tanpa CLAHE'}). Ganti foto registrasinya lalu ulangi evaluasi.';
          if (mounted) setState(() => _peringatanJalan.add(pesan));
        }

        final matcher = FaceMatchingService()
          ..loadDatabase(galeri)
          ..gunakanMargin = true;
        final nimTerdaftar = galeri.map((g) => g.nim).toSet();

        // Pemanasan: 10 pemrosesan pertama tidak dicatat (Bab III Subbab 3.4.6)
        setState(() => _status = '[$labelKonfig] Pemanasan...');
        for (final foto in fotoUji.take(10)) {
          await _prosesFoto(foto.file, clahe);
        }

        // 2. Uji setiap foto
        final ringkasanPerKondisi = <String, _Ringkasan>{};
        final semua = _Ringkasan('SEMUA', clahe);
        final buffer = <Map<String, dynamic>>[];

        for (final foto in fotoUji) {
          if (_dibatalkan) break;
          final h = await _prosesFoto(foto.file, clahe);

          final w = h?.waktu ?? {};
          final terdaftar =
              foto.label != labelTidakTerdaftar && nimTerdaftar.contains(foto.label);
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
            'luminansi_wajah': h?.lumWajah == null ? '' : ResearchLogger.ms(h!.lumWajah!),
            'luminansi_latar': h?.lumLatar == null ? '' : ResearchLogger.ms(h!.lumLatar!),
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
                        onPressed: _berjalan ? null : _periksaFolder,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Periksa Ulang'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'S01/registrasi/*.jpg   (siswa terdaftar)\n'
                    'S01/<kondisi>/*.jpg\n'
                    'TT01/<kondisi>/*.jpg   (tanpa registrasi = tidak terdaftar)\n'
                    'kondisi: ${ResearchConfig.kondisiBawaan.keys.join(', ')}',
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 11.5, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
          _kartuIsiFolder(),
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
          if (_peringatanJalan.isNotEmpty)
            _kartuPeringatan('Perlu diperbaiki', _peringatanJalan, Colors.red),
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

  /// Ringkasan isi folder: jumlah siswa, foto per kondisi, dan peringatan susunan
  Widget _kartuIsiFolder() {
    if (_galatFolder != null) {
      return _kartuPeringatan('Folder belum bisa dipakai', [_galatFolder!], Colors.red);
    }
    final isi = _isi;
    if (isi == null) return const SizedBox.shrink();
    final siswaTidakTerdaftar = isi.format == 'per_siswa'
        ? isi.uji
            .where((f) => f.label == labelTidakTerdaftar)
            .map((f) => f.relatif.split('/').first)
            .toSet()
            .length
        : null;
    return Column(
      children: [
        Card(
          color: Colors.indigo.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Isi folder (${isi.format == 'per_siswa' ? 'per siswa' : 'susunan lama'})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Siswa terdaftar: ${isi.galeri.length} '
                    '(${isi.jumlahFotoGaleri} foto registrasi)'),
                if (siswaTidakTerdaftar != null)
                  Text('Siswa tidak terdaftar: $siswaTidakTerdaftar'),
                Text('Foto uji/validasi: ${isi.uji.length} '
                    '(milik siswa tidak terdaftar: ${isi.jumlahTidakTerdaftar})'),
                ...isi.fotoPerKondisi.entries.map((e) => Text('  • ${e.key}: ${e.value} foto')),
              ],
            ),
          ),
        ),
        if (isi.peringatan.isNotEmpty)
          _kartuPeringatan('Periksa susunan folder', isi.peringatan, Colors.orange),
      ],
    );
  }

  Widget _kartuPeringatan(String judul, List<String> pesan, MaterialColor warna) {
    return Card(
      color: warna.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: warna.shade800, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$judul (${pesan.length})',
                    style: TextStyle(fontWeight: FontWeight.bold, color: warna.shade900)),
              ),
            ]),
            const SizedBox(height: 4),
            ...pesan.take(30).map((p) => Text('• $p', style: const TextStyle(fontSize: 12))),
            if (pesan.length > 30)
              Text('… dan ${pesan.length - 30} lainnya', style: const TextStyle(fontSize: 12)),
          ],
        ),
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

class _HasilWajah {
  final List<double>? embedding;
  final List<int>? box;
  final int jumlahWajah;
  final Map<String, double> waktu;
  final double? lumWajah;
  final double? lumLatar;
  _HasilWajah(this.embedding, this.box, this.jumlahWajah, this.waktu,
      {this.lumWajah, this.lumLatar});
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
    final bool terdaftar = baris['terdaftar'] == 1;
    if (baris['alasan'] == 'wajah_tidak_terdeteksi') {
      // Tanpa wajah = ditolak: genuine menjadi penolakan palsu, impostor ditolak dengan benar.
      // Latensi tidak dicatat karena pipeline berhenti di tahap deteksi.
      fta++;
      if (terdaftar) {
        genuine++;
        frT++;
        frM++;
      } else {
        impostor++;
      }
      return;
    }
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
