// Uji pembaca folder dataset (lib/features/research/dataset_reader.dart).
// Jalankan: flutter test test/dataset_reader_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siap_app/features/research/dataset_reader.dart';

const kondisi = {'memadai', 'low_light', 'backlight'};

late Directory tmp;

/// Membuat [n] berkas foto palsu di [folder] (isi tidak penting untuk pembaca folder)
void foto(String folder, int n, {String awalan = 'IMG'}) {
  Directory('${tmp.path}/$folder').createSync(recursive: true);
  for (var i = 1; i <= n; i++) {
    File('${tmp.path}/$folder/${awalan}_$i.jpg').writeAsBytesSync([0]);
  }
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('dataset_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('dataset_uji per siswa: Budi, Siti terdaftar dan Rina tidak terdaftar', () {
    foto('2024001_Budi/registrasi', 1);
    foto('2024001_Budi/memadai', 5);
    foto('2024001_Budi/low_light', 3);
    foto('2024001_Budi/backlight', 2);
    foto('2024016_Siti/registrasi', 1);
    foto('2024016_Siti/memadai', 5);
    foto('2024016_Siti/low_light', 2);
    foto('2024016_Siti/backlight', 3);
    foto('TT01_Rina/memadai', 5);
    foto('TT01_Rina/low_light', 3);
    foto('TT01_Rina/backlight', 2);
    // Berkas pengingat dari skrip pembuat folder harus diabaikan
    File('${tmp.path}/2024001_Budi/memadai/ISI_5_FOTO.txt').writeAsStringSync('x');

    final isi = bacaDataset(tmp.path, kondisiDikenal: kondisi);

    expect(isi.format, 'per_siswa');
    expect(isi.galeri.map((o) => o.nim), ['2024001', '2024016']);
    expect(isi.galeri.map((o) => o.nama), ['Budi', 'Siti']);
    expect(isi.jumlahFotoGaleri, 2);
    expect(isi.uji.length, 30);
    expect(isi.fotoPerKondisi, {'memadai': 15, 'low_light': 8, 'backlight': 7});
    expect(isi.jumlahTidakTerdaftar, 10);
    expect(isi.uji.where((f) => f.label == '2024001').length, 10);
    expect(isi.uji.where((f) => f.label == '2024016').length, 10);
    // Foto registrasi tidak ikut menjadi foto uji
    expect(isi.uji.any((f) => f.relatif.contains('/registrasi/')), isFalse);
    expect(isi.uji.first.relatif, startsWith('2024001_Budi/'));
    expect(isi.peringatan, isEmpty);
  });

  test('dataset_validasi per siswa: kondisi berbeda antarsiswa tetap terbaca', () {
    foto('2024001_Budi/registrasi', 1);
    foto('2024001_Budi/memadai', 1);
    foto('2024001_Budi/low_light', 1);
    foto('2024016_Siti/registrasi', 1);
    foto('2024016_Siti/memadai', 1);
    foto('2024016_Siti/backlight', 1);
    foto('TT01_Rina/memadai', 1);
    foto('TT01_Rina/backlight', 1);

    final isi = bacaDataset(tmp.path, kondisiDikenal: kondisi);

    expect(isi.galeri.length, 2);
    expect(isi.uji.length, 6);
    expect(isi.fotoPerKondisi, {'memadai': 3, 'low_light': 1, 'backlight': 2});
    expect(isi.jumlahTidakTerdaftar, 2);
    expect(isi.peringatan, isEmpty);
  });

  test('nama berkas asli kamera dan ekstensi huruf besar tetap terbaca', () {
    Directory('${tmp.path}/2024001_Budi Santoso/registrasi').createSync(recursive: true);
    File('${tmp.path}/2024001_Budi Santoso/registrasi/20261117_073102.JPG').writeAsBytesSync([0]);
    Directory('${tmp.path}/2024001_Budi Santoso/memadai').createSync(recursive: true);
    File('${tmp.path}/2024001_Budi Santoso/memadai/20261117_073210.jpeg').writeAsBytesSync([0]);

    final isi = bacaDataset(tmp.path, kondisiDikenal: kondisi);

    expect(isi.galeri.single.nim, '2024001');
    expect(isi.galeri.single.nama, 'Budi Santoso');
    expect(isi.uji.single.label, '2024001');
  });

  test('kesalahan susunan muncul sebagai peringatan', () {
    foto('2024001_Budi/registrasi', 0); // registrasi kosong
    foto('2024001_Budi/memadai', 2);
    foto('2024002_Ani/registrasi', 1);
    foto('2024002_Ani/lowlight', 2); // salah ejaan kondisi
    foto('2024002_Ani', 1, awalan: 'lepas'); // foto di luar subfolder kondisi
    foto('2024003_Dodi/registrasi', 1); // belum ada foto kondisi

    final isi = bacaDataset(tmp.path, kondisiDikenal: kondisi);
    final teks = isi.peringatan.join('\n');

    expect(teks, contains('2024001_Budi: folder registrasi kosong'));
    expect(teks, contains('"lowlight" bukan kondisi yang dikenal'));
    expect(teks, contains('2024002_Ani: 1 foto tidak berada di subfolder kondisi'));
    expect(teks, contains('2024003_Dodi: belum ada foto di subfolder kondisi'));
    // Budi tidak masuk galeri karena registrasinya kosong
    expect(isi.galeri.map((o) => o.nim), ['2024002', '2024003']);
  });

  test('susunan lama tetap terbaca dan folder tidak_terdaftar berlabel benar', () {
    foto('galeri/2024001_Budi', 1);
    foto('uji/memadai/2024001', 2);
    foto('uji/memadai/tidak_terdaftar', 3);

    final isi = bacaDataset(tmp.path, kondisiDikenal: kondisi);

    expect(isi.format, 'lama');
    expect(isi.galeri.single.nim, '2024001');
    expect(isi.uji.where((f) => f.label == 'tidak_terdaftar').length, 3);
    expect(isi.uji.where((f) => f.label == '2024001').length, 2);
  });

  test('folder kosong atau tidak ada memberi pesan yang jelas', () {
    expect(() => bacaDataset(tmp.path),
        throwsA(isA<FormatException>().having((e) => e.message, 'pesan', contains('folder siswa'))));
    expect(() => bacaDataset('${tmp.path}/tidak_ada'),
        throwsA(isA<FormatException>().having((e) => e.message, 'pesan', contains('tidak ditemukan'))));
  });
}
