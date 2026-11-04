// =========================================================================
// HALAMAN CONTOH TAHAPAN TEMPLAT (Gambar 3.10 Bab III)
// =========================================================================
// Dibuka dari panel Mode Penelitian (akun developer). Memakai deteksi ML Kit
// dan aturan foto registrasi yang sama dengan RegisterStudentScreen, lalu
// menyimpan gambar ke folder aplikasi: .../files/penelitian/contoh_templat/<waktu>/
// Foto yang dipakai HARUS wajah anggota tim peneliti, bukan siswa.
// =========================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/ai/face_detector_service.dart';
import '../contoh_templat.dart';
import '../research_logger.dart';

class ContohTemplatPage extends StatefulWidget {
  const ContohTemplatPage({super.key});

  @override
  State<ContohTemplatPage> createState() => _ContohTemplatPageState();
}

class _ContohTemplatPageState extends State<ContohTemplatPage> {
  final FaceDetectorService _detector = FaceDetectorService();
  bool _memproses = false;
  String? _galat;
  HasilContohTemplat? _hasil;
  String? _folderHasil;
  String _info = '';

  @override
  void dispose() {
    _detector.dispose();
    super.dispose();
  }

  Future<void> _ambilFoto(ImageSource sumber) async {
    final foto = await ImagePicker().pickImage(source: sumber);
    if (foto == null) return;
    setState(() {
      _memproses = true;
      _galat = null;
      _hasil = null;
    });
    try {
      // 1. Deteksi wajah ML Kit (opsi sama dengan aplikasi: fast, minFaceSize 0.1)
      final faces = await _detector.detectFaces(InputImage.fromFilePath(foto.path));
      if (faces.isEmpty) {
        throw const FormatException('Wajah tidak terdeteksi. Gunakan foto lain.');
      }
      // 2. Aturan foto registrasi (RegisterStudentScreen): wajah terbesar,
      //    tolak bila wajah kedua >= 35% luas wajah utama
      faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
          .compareTo(a.boundingBox.width * a.boundingBox.height));
      final utama = faces.first.boundingBox;
      if (faces.length > 1) {
        final kedua = faces[1].boundingBox;
        if (kedua.width * kedua.height >= 0.35 * utama.width * utama.height) {
          throw const FormatException('Ada lebih dari 1 wajah. Gunakan foto yang hanya berisi 1 orang.');
        }
      }

      // 3. Crop + CLAHE + penyusunan gambar di isolate latar belakang
      final hasil = await compute(
        buatContohTemplat,
        MasukanContohTemplat(
          fotoBytes: await foto.readAsBytes(),
          left: utama.left,
          top: utama.top,
          width: utama.width,
          height: utama.height,
        ),
      );

      // 4. Simpan ke folder aplikasi (tidak dikirim ke cloud)
      final waktu = DateTime.now();
      final cap = '${waktu.year}${_dua(waktu.month)}${_dua(waktu.day)}_'
          '${_dua(waktu.hour)}${_dua(waktu.minute)}${_dua(waktu.second)}';
      final folder = Directory('${(await ResearchLogger.folderLog()).path}/contoh_templat/$cap');
      await folder.create(recursive: true);
      for (final e in hasil.berkas.entries) {
        await File('${folder.path}/${e.key}').writeAsBytes(e.value);
      }
      final info = [
        'Gambar 3.10 - Contoh Tahapan Pembentukan Templat Wajah',
        'Dibuat        : ${waktu.toIso8601String()}',
        'Detektor      : Google ML Kit Face Detection (mode fast, minFaceSize 0.1)',
        'Wajah terdeteksi: ${faces.length} (dipakai wajah terbesar)',
        'Ukuran foto   : ${hasil.lebarFoto} x ${hasil.tinggiFoto} piksel',
        'Bounding box  : kiri ${utama.left.toStringAsFixed(1)}, atas ${utama.top.toStringAsFixed(1)}, '
            'lebar ${utama.width.toStringAsFixed(1)}, tinggi ${utama.height.toStringAsFixed(1)}',
        'Area potong   : ${hasil.kotakPotong} (padding 15%, bikubik ke 112 x 112)',
        'Luminansi Y   : tanpa CLAHE ${hasil.lumSebelum.rata.toStringAsFixed(1)} '
            '(SD ${hasil.lumSebelum.sd.toStringAsFixed(1)}) -> setelah CLAHE '
            '${hasil.lumSesudah.rata.toStringAsFixed(1)} (SD ${hasil.lumSesudah.sd.toStringAsFixed(1)})',
        'CLAHE         : grid 8 x 8, clip limit 2.0, kanal Y BT.601, rasio Y\'/Y',
      ].join('\n');
      await File('${folder.path}/info.txt').writeAsString('$info\n');

      if (!mounted) return;
      setState(() {
        _hasil = hasil;
        _folderHasil = folder.path;
        _info = info;
      });
    } catch (e) {
      if (mounted) setState(() => _galat = e is FormatException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  static String _dua(int n) => n.toString().padLeft(2, '0');

  Future<void> _bagikan() async {
    final folder = _folderHasil;
    if (folder == null) return;
    final nama = ['gambar_3_10.png', 'a_foto_bounding_box.png', 'b_potongan_112_tanpa_clahe.png',
        'c_potongan_112_clahe.png', 'info.txt'];
    await Share.shareXFiles([for (final n in nama) XFile('$folder/$n')],
        text: 'Gambar 3.10 - Contoh Tahapan Pembentukan Templat Wajah');
  }

  @override
  Widget build(BuildContext context) {
    final hasil = _hasil;
    return Scaffold(
      appBar: AppBar(title: const Text('Contoh Tahapan Templat')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Untuk Gambar 3.10 Bab III. Gunakan foto WAJAH ANGGOTA TIM, bukan siswa.\n'
                'Foto: wajah lurus, tanpa penutup, ekspresi netral, cahaya memadai, jarak 0,8-1 m.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galeri'),
                  onPressed: _memproses ? null : () => _ambilFoto(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Kamera'),
                  onPressed: _memproses ? null : () => _ambilFoto(ImageSource.camera),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_memproses) const Center(child: CircularProgressIndicator()),
          if (_galat != null)
            Text('❌ $_galat', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          if (hasil != null) ...[
            Image.memory(hasil.berkas['gambar_3_10.png']!, filterQuality: FilterQuality.none),
            const SizedBox(height: 8),
            const Text('(a) foto + bounding box ML Kit (hijau) dan area potong 15% (kuning) · '
                '(b) 112×112 tanpa CLAHE · (c) 112×112 setelah CLAHE',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            SelectableText(_info, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            const SizedBox(height: 8),
            Text('Tersimpan di: $_folderHasil',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Bagikan Gambar (Quick Share)'),
              onPressed: _bagikan,
            ),
          ],
        ],
      ),
    );
  }
}
