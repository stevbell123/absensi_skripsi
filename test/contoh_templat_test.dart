import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:siap_app/core/ai/clahe_service.dart';
import 'package:siap_app/core/ai/face_embedding_service.dart';
import 'package:siap_app/features/research/contoh_templat.dart';

img.Image _citraUji() {
  final c = img.Image(width: 320, height: 400);
  for (final p in c) {
    p
      ..r = (p.x * 3 + p.y) % 256
      ..g = (p.y * 2) % 256
      ..b = (150 + p.x - p.y) % 256;
  }
  return c;
}

void main() {
  test('potongan (b) dan (c) sama persis dengan pipeline aplikasi', () {
    final foto = _citraUji();
    const bb = Rect.fromLTWH(37.6, 51.3, 140.2, 171.9);
    final hasil = buatContohTemplat(MasukanContohTemplat(
        fotoBytes: img.encodePng(foto), left: bb.left, top: bb.top, width: bb.width, height: bb.height));

    final cropAplikasi = FaceEmbeddingService().cropAndAlignFace(foto, bb);
    final claheAplikasi = ClaheService.applyClahe(cropAplikasi);
    final b = img.decodePng(hasil.berkas['b_potongan_112_tanpa_clahe.png']!)!;
    final c = img.decodePng(hasil.berkas['c_potongan_112_clahe.png']!)!;

    expect(b.width, 112);
    expect(c.height, 112);
    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        expect(b.getPixel(x, y), cropAplikasi.getPixel(x, y));
        expect(c.getPixel(x, y), claheAplikasi.getPixel(x, y));
      }
    }
    expect(hasil.kotakPotong, [16, 25, 199, 249]);
    expect(hasil.berkas.keys, containsAll(['gambar_3_10.png', 'a_foto_bounding_box.png']));
    final gabung = img.decodePng(hasil.berkas['gambar_3_10.png']!)!;
    expect(gabung.height, 560 + 30 + 70);
  });

  test('area potong dibatasi tepi citra', () {
    expect(kotakPotong(const Rect.fromLTWH(-12.4, 300.7, 95.5, 120.25), 320, 400), [0, 282, 98, 400]);
  });

  test('foto rusak memberi pesan jelas', () {
    expect(
        () => buatContohTemplat(MasukanContohTemplat(
            fotoBytes: img.encodePng(img.Image(width: 1, height: 1)).sublist(0, 10),
            left: 0, top: 0, width: 1, height: 1)),
        throwsFormatException);
  });
}
