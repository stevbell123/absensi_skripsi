// =========================================================================
// PEMBACA FOLDER DATASET (EVALUASI DATASET, RM 1 & RM 2)
// =========================================================================
// Dua susunan folder didukung:
//
// 1. Per siswa (utama):
//      <folder dipilih>/
//        S01/registrasi/*.jpg    → foto acuan; ada folder ini = siswa TERDAFTAR
//        S01/<kondisi>/*.jpg     → foto uji/validasi (memadai, low_light, backlight)
//        TT01/<kondisi>/*.jpg    → tanpa folder registrasi = siswa TIDAK TERDAFTAR
//      Nama folder dipakai sebagai kode siswa (bagian sebelum "_" bila ada) dan ikut
//      tercatat di log, jadi gunakan kode (S01, TT01), bukan NIS atau nama.
//
// 2. Lama (tetap dibaca):
//      galeri/<NIS>_<Nama>/*.jpg
//      uji/<kondisi>/<NIS>/*.jpg
//      uji/<kondisi>/tidak_terdaftar/*.jpg
//
// Nama berkas foto bebas; kondisi diambil dari nama subfolder.
// Kesalahan susunan dikumpulkan sebagai peringatan agar terlihat sebelum
// evaluasi dijalankan.
// =========================================================================

import 'dart:io';

const String labelTidakTerdaftar = 'tidak_terdaftar';
const String folderRegistrasi = 'registrasi';
const Set<String> ekstensiFoto = {'.jpg', '.jpeg', '.png'};

/// Satu siswa terdaftar beserta foto registrasinya
class OrangGaleri {
  final String nim;
  final String nama;
  final List<File> foto;
  OrangGaleri(this.nim, this.nama, this.foto);
}

/// Satu foto validasi/uji beserta labelnya
class FotoUji {
  final String kondisi;
  final String label; // NIS siswa terdaftar, atau [labelTidakTerdaftar]
  final File file;
  final String relatif;
  FotoUji(this.kondisi, this.label, this.file, this.relatif);
}

class IsiDataset {
  final String format; // 'per_siswa' atau 'lama'
  final List<OrangGaleri> galeri;
  final List<FotoUji> uji;
  final List<String> peringatan;
  IsiDataset(this.format, this.galeri, this.uji, this.peringatan);

  int get jumlahFotoGaleri => galeri.fold(0, (s, o) => s + o.foto.length);
  int get jumlahTidakTerdaftar => uji.where((f) => f.label == labelTidakTerdaftar).length;

  /// Jumlah foto per kondisi, misalnya {memadai: 30, low_light: 15, backlight: 15}
  Map<String, int> get fotoPerKondisi {
    final hasil = <String, int>{};
    for (final f in uji) {
      hasil[f.kondisi] = (hasil[f.kondisi] ?? 0) + 1;
    }
    return hasil;
  }
}

/// "12345_Budi Santoso" → nim "12345", nama "Budi Santoso"
({String nim, String nama}) parseOrang(String namaFolder) {
  final i = namaFolder.indexOf('_');
  if (i <= 0) return (nim: namaFolder, nama: namaFolder);
  return (nim: namaFolder.substring(0, i), nama: namaFolder.substring(i + 1));
}

String namaFolder(FileSystemEntity e) =>
    e.path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

List<Directory> subfolder(Directory dir) {
  final list = dir
      .listSync()
      .whereType<Directory>()
      .where((d) => !namaFolder(d).startsWith('.'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return list;
}

List<File> fotoDi(Directory dir) {
  final list = dir
      .listSync()
      .whereType<File>()
      .where((f) => ekstensiFoto.any((e) => f.path.toLowerCase().endsWith(e)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return list;
}

/// Membaca folder dataset. Melempar [FormatException] bila folder tidak dikenali.
IsiDataset bacaDataset(String folder, {Set<String> kondisiDikenal = const {}}) {
  final root = folder.replaceAll(RegExp(r'[\\/]+$'), '');
  final dir = Directory(root);
  if (!dir.existsSync()) {
    throw FormatException('Folder tidak ditemukan: $root');
  }
  String relatif(File f) => f.path.substring(root.length + 1).replaceAll('\\', '/');

  if (Directory('$root/galeri').existsSync() && Directory('$root/uji').existsSync()) {
    return _bacaLama(root, relatif);
  }
  return _bacaPerSiswa(dir, relatif, kondisiDikenal);
}

IsiDataset _bacaPerSiswa(
    Directory root, String Function(File) relatif, Set<String> kondisiDikenal) {
  final galeri = <OrangGaleri>[];
  final uji = <FotoUji>[];
  final peringatan = <String>[];
  final nimDipakai = <String>{};

  final folderSiswa = subfolder(root);
  if (folderSiswa.isEmpty) {
    throw const FormatException('Folder ini tidak berisi folder siswa. Pilih folder dataset_validasi '
        'atau dataset_uji yang berisi folder siswa (S01, S02, TT01, ...).');
  }

  for (final dirSiswa in folderSiswa) {
    final nama = namaFolder(dirSiswa);
    final orang = parseOrang(nama);
    final sub = subfolder(dirSiswa);
    final dirRegistrasi =
        sub.where((d) => namaFolder(d).toLowerCase() == folderRegistrasi).firstOrNull;
    final terdaftar = dirRegistrasi != null;

    final fotoLepas = fotoDi(dirSiswa).length;
    if (fotoLepas > 0) {
      peringatan.add('$nama: $fotoLepas foto tidak berada di subfolder kondisi, diabaikan');
    }

    if (terdaftar) {
      if (!nimDipakai.add(orang.nim)) {
        peringatan.add('$nama: NIS ${orang.nim} dipakai lebih dari satu folder');
      }
      if (nama.toUpperCase().startsWith('TT')) {
        peringatan.add('$nama: diawali "TT" tetapi punya folder registrasi, dianggap terdaftar');
      }
      final fotoRegistrasi = fotoDi(dirRegistrasi);
      if (fotoRegistrasi.isEmpty) {
        peringatan.add('$nama: folder registrasi kosong, siswa ini tidak bisa dikenali');
      } else {
        galeri.add(OrangGaleri(orang.nim, orang.nama, fotoRegistrasi));
      }
    }

    int jumlahFotoUji = 0;
    for (final dirKondisi in sub) {
      final kondisi = namaFolder(dirKondisi).toLowerCase();
      if (kondisi == folderRegistrasi) continue;
      if (kondisiDikenal.isNotEmpty && !kondisiDikenal.contains(kondisi)) {
        peringatan.add('$nama: subfolder "${namaFolder(dirKondisi)}" bukan kondisi yang dikenal '
            '(${kondisiDikenal.join(', ')}); cek ejaannya');
      }
      for (final f in fotoDi(dirKondisi)) {
        uji.add(FotoUji(kondisi, terdaftar ? orang.nim : labelTidakTerdaftar, f, relatif(f)));
        jumlahFotoUji++;
      }
    }
    if (jumlahFotoUji == 0) {
      peringatan.add('$nama: belum ada foto di subfolder kondisi');
    }
  }
  return IsiDataset('per_siswa', galeri, uji, peringatan);
}

IsiDataset _bacaLama(String root, String Function(File) relatif) {
  final galeri = <OrangGaleri>[];
  final uji = <FotoUji>[];
  final peringatan = <String>[];

  for (final dir in subfolder(Directory('$root/galeri'))) {
    final orang = parseOrang(namaFolder(dir));
    final foto = fotoDi(dir);
    if (foto.isEmpty) {
      peringatan.add('galeri/${namaFolder(dir)}: belum ada foto registrasi');
    } else {
      galeri.add(OrangGaleri(orang.nim, orang.nama, foto));
    }
  }
  for (final dirKondisi in subfolder(Directory('$root/uji'))) {
    final kondisi = namaFolder(dirKondisi);
    for (final dirOrang in subfolder(dirKondisi)) {
      final nama = namaFolder(dirOrang);
      final label = nama == labelTidakTerdaftar ? labelTidakTerdaftar : parseOrang(nama).nim;
      for (final f in fotoDi(dirOrang)) {
        uji.add(FotoUji(kondisi, label, f, relatif(f)));
      }
    }
  }
  return IsiDataset('lama', galeri, uji, peringatan);
}
