// =========================================================================
// CONTOH TAHAPAN PEMBENTUKAN TEMPLAT (Gambar 3.10 Bab III)
// =========================================================================
// Membuat tiga citra dari satu foto anggota tim, memakai kode pipeline aplikasi
// yang sama dengan registrasi wajah:
//   (a) foto + bounding box ML Kit (hijau) + area potong padding 15% (kuning putus-putus)
//   (b) potongan wajah 112x112 tanpa CLAHE  → FaceEmbeddingService.cropAndAlignFace
//   (c) potongan wajah 112x112 setelah CLAHE → ClaheService.applyClahe
// Fungsi di berkas ini murni (tanpa plugin), sehingga bisa dijalankan di isolate
// latar belakang dan diuji dengan flutter test. Deteksi ML Kit dilakukan pemanggil.
// =========================================================================

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../../core/ai/clahe_service.dart';
import '../../core/ai/face_embedding_service.dart';

class MasukanContohTemplat {
  const MasukanContohTemplat({
    required this.fotoBytes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final Uint8List fotoBytes;

  /// Bounding box hasil ML Kit (piksel, koordinat citra yang sudah tegak)
  final double left, top, width, height;
}

class HasilContohTemplat {
  const HasilContohTemplat({
    required this.berkas,
    required this.lebarFoto,
    required this.tinggiFoto,
    required this.kotakPotong,
    required this.lumSebelum,
    required this.lumSesudah,
  });

  /// Nama berkas → isi PNG. Termasuk 'gambar_3_10.png' (tiga panel berdampingan).
  final Map<String, Uint8List> berkas;
  final int lebarFoto, tinggiFoto;

  /// Area potong setelah padding 15% dan pembatasan ke tepi citra: [kiri, atas, kanan, bawah]
  final List<int> kotakPotong;

  /// Rata-rata dan simpangan baku luminansi Y potongan 112x112
  final ({double rata, double sd}) lumSebelum, lumSesudah;
}

/// Area potong yang sama dengan FaceEmbeddingService.cropAndAlignFace (padding 15%, clamp ke tepi).
List<int> kotakPotong(Rect kotak, int lebarCitra, int tinggiCitra) {
  final px = kotak.width * 0.15, py = kotak.height * 0.15;
  final left = (kotak.left - px).floor();
  final top = (kotak.top - py).floor();
  final width = (kotak.width + px * 2).ceil();
  final height = (kotak.height + py * 2).ceil();
  return [
    left.clamp(0, lebarCitra),
    top.clamp(0, tinggiCitra),
    (left + width).clamp(0, lebarCitra),
    (top + height).clamp(0, tinggiCitra),
  ];
}

({double rata, double sd}) _statistikY(img.Image citra) {
  final nilai = <double>[
    for (final p in citra) 0.299 * p.r + 0.587 * p.g + 0.114 * p.b,
  ];
  final rata = nilai.reduce((a, b) => a + b) / nilai.length;
  final varian = nilai.map((v) => (v - rata) * (v - rata)).reduce((a, b) => a + b) / nilai.length;
  return (rata: rata, sd: sqrt(varian));
}

void _garisPutus(img.Image c, int x1, int y1, int x2, int y2, img.Color warna, int tebal) {
  final segmen = tebal * 6;
  if (y1 == y2) {
    for (int x = x1; x < x2; x += segmen * 2) {
      img.fillRect(c, x1: x, y1: y1, x2: min(x + segmen, x2), y2: y1 + tebal - 1, color: warna);
    }
  } else {
    for (int y = y1; y < y2; y += segmen * 2) {
      img.fillRect(c, x1: x1, y1: y, x2: x1 + tebal - 1, y2: min(y + segmen, y2), color: warna);
    }
  }
}

/// Fungsi tingkat atas agar bisa dipanggil lewat compute() di isolate latar belakang.
HasilContohTemplat buatContohTemplat(MasukanContohTemplat m) {
  img.Image? raw;
  try {
    raw = img.decodeImage(m.fotoBytes);
  } catch (_) {
    raw = null; // berkas rusak/terpotong dapat melempar galat saat didekode
  }
  if (raw == null) throw const FormatException('Foto tidak bisa dibaca.');
  final full = img.bakeOrientation(raw); // sama dengan mode evaluasi dan presensi

  final bbox = Rect.fromLTWH(m.left, m.top, m.width, m.height);
  final crop = FaceEmbeddingService().cropAndAlignFace(full, bbox);
  final clahe = ClaheService.applyClahe(crop);
  final potong = kotakPotong(bbox, full.width, full.height);

  // (a) foto + bounding box + area potong
  final a = full.clone();
  final tebal = max(2, (min(a.width, a.height) / 200).round());
  img.drawRect(a,
      x1: bbox.left.round(), y1: bbox.top.round(),
      x2: bbox.right.round(), y2: bbox.bottom.round(),
      color: img.ColorRgb8(0, 220, 0), thickness: tebal);
  final kuning = img.ColorRgb8(255, 210, 0);
  final (l, t, r, b) = (potong[0], potong[1], max(potong[0], potong[2] - 1), max(potong[1], potong[3] - 1));
  _garisPutus(a, l, t, r, t, kuning, tebal);
  _garisPutus(a, l, b - tebal + 1, r, b - tebal + 1, kuning, tebal);
  _garisPutus(a, l, t, l, b, kuning, tebal);
  _garisPutus(a, r - tebal + 1, t, r - tebal + 1, b, kuning, tebal);

  // Foto (a) diperkecil agar berkas tidak terlalu besar (sisi terpanjang 1600 px)
  final skala = min(1.0, 1600 / max(a.width, a.height));
  final aSimpan = skala < 1.0
      ? img.copyResize(a,
          width: (a.width * skala).round(),
          height: (a.height * skala).round(),
          interpolation: img.Interpolation.average)
      : a;

  // Gabungan tiga panel. (b) dan (c) diperbesar NEAREST agar piksel 112x112 tetap terlihat.
  const tinggi = 560, jarak = 30, bawah = 70;
  final aPanel = img.copyResize(a,
      height: tinggi, width: (a.width * tinggi / a.height).round(),
      interpolation: img.Interpolation.average);
  final bPanel = img.copyResize(crop, width: tinggi, height: tinggi, interpolation: img.Interpolation.nearest);
  final cPanel = img.copyResize(clahe, width: tinggi, height: tinggi, interpolation: img.Interpolation.nearest);
  final kanvas = img.Image(width: aPanel.width + 2 * tinggi + 4 * jarak, height: tinggi + jarak + bawah);
  img.fill(kanvas, color: img.ColorRgb8(255, 255, 255));
  int x = jarak;
  for (final (panel, label) in [(aPanel, '(a)'), (bPanel, '(b)'), (cPanel, '(c)')]) {
    img.compositeImage(kanvas, panel, dstX: x, dstY: jarak);
    img.drawString(kanvas, label,
        font: img.arial48, x: x + panel.width ~/ 2 - 36, y: jarak + tinggi + 12,
        color: img.ColorRgb8(0, 0, 0));
    x += panel.width + jarak;
  }

  Uint8List png(img.Image c) => img.encodePng(c);
  img.Image x4(img.Image c) =>
      img.copyResize(c, width: 448, height: 448, interpolation: img.Interpolation.nearest);

  return HasilContohTemplat(
    berkas: {
      'gambar_3_10.png': png(kanvas),
      'a_foto_bounding_box.png': png(aSimpan),
      'b_potongan_112_tanpa_clahe.png': png(crop),
      'c_potongan_112_clahe.png': png(clahe),
      'b_potongan_112_tanpa_clahe_x4.png': png(x4(crop)),
      'c_potongan_112_clahe_x4.png': png(x4(clahe)),
    },
    lebarFoto: full.width,
    tinggiFoto: full.height,
    kotakPotong: potong,
    lumSebelum: _statistikY(crop),
    lumSesudah: _statistikY(clahe),
  );
}
