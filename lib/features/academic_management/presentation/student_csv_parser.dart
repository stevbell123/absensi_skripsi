import 'dart:convert';

import 'package:csv/csv.dart' as csv_pkg;

/// Satu baris siswa hasil baca CSV.
class StudentCsvRow {
  const StudentCsvRow({required this.id, required this.name, required this.gender});

  /// ID/NIS siswa, selalu teks (nol di depan tidak hilang).
  final String id;
  final String name;

  /// 'L', 'P', atau '' bila kolom jenis kelamin tidak ada/kosong.
  final String gender;
}

/// Hasil baca CSV: baris yang valid + catatan baris yang dilewati.
class StudentCsvParseResult {
  const StudentCsvParseResult({required this.rows, required this.skipped});

  final List<StudentCsvRow> rows;

  /// Contoh: "Baris 5: nama kosong".
  final List<String> skipped;
}

/// Mengubah byte berkas jadi teks. Coba UTF-8 dulu, bila gagal (CSV dari
/// Excel versi lama biasanya ANSI/Windows-1252) pakai Latin-1.
String decodeCsvBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

String _norm(String header) =>
    header.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

const _idHeaders = {
  'id', 'nis', 'nisn', 'nim', 'nisnip', 'nip', 'noinduk', 'nomorinduk',
  'idsiswa', 'email', 'identifier',
};
const _genderHeaders = {'jk', 'lp', 'jeniskelamin', 'kelamin', 'gender', 'sex'};

bool _isNameHeader(String h) => h.contains('nama') || h == 'name';
bool _isIdHeader(String h) => _idHeaders.contains(h) || h.startsWith('nis');
bool _isGenderHeader(String h) => _genderHeaders.contains(h) || h.contains('kelamin');

String _normGender(String raw) {
  final g = raw.trim().toUpperCase();
  if (g.isEmpty) return '';
  if (g == 'L' || g.startsWith('LAKI') || g == 'M' || g == 'MALE' || g == 'PRIA') return 'L';
  if (g == 'P' || g.startsWith('PEREMPUAN') || g == 'F' || g == 'FEMALE' || g == 'WANITA') return 'P';
  return g;
}

/// Membaca CSV daftar siswa.
///
/// - Kolom dikenali dari **header** (urutan bebas): ID/NIS, Nama, Jenis Kelamin
///   (jenis kelamin opsional).
/// - Bila header tidak dikenali, dipakai susunan lama: Nama, ID/email, Jenis Kelamin.
/// - Pemisah `,` atau `;` dan akhir baris LF/CRLF dikenali otomatis.
///
/// Melempar [FormatException] dengan pesan yang jelas bila berkas tidak bisa dipakai.
StudentCsvParseResult parseStudentCsv(String input) {
  var text = input;
  if (text.startsWith('﻿')) text = text.substring(1);
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  if (text.trim().isEmpty) {
    throw const FormatException('Berkas CSV kosong.');
  }

  final firstLine = text.split('\n').first;
  final delimiter =
      ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? ';' : ',';

  final rows = csv_pkg.CsvToListConverter(
    fieldDelimiter: delimiter,
    eol: '\n',
    shouldParseNumbers: false,
  ).convert(text);

  if (rows.length <= 1) {
    throw const FormatException('Berkas CSV hanya berisi header, belum ada data siswa.');
  }

  final header = rows.first.map((c) => _norm(c.toString())).toList();
  int nameCol = header.indexWhere(_isNameHeader);
  int idCol = header.indexWhere(_isIdHeader);
  int genderCol = header.indexWhere(_isGenderHeader);

  if (nameCol < 0 && idCol < 0) {
    // Header tidak dikenali → susunan lama: Nama, ID/email, Jenis Kelamin.
    if (header.length < 2) {
      throw FormatException(
          'Header CSV tidak dikenali: "${rows.first.join(delimiter)}". '
          'Gunakan header misalnya: ID,Nama Lengkap Siswa,Jenis Kelamin');
    }
    nameCol = 0;
    idCol = 1;
    genderCol = header.length >= 3 ? 2 : -1;
  } else if (nameCol < 0) {
    throw const FormatException('Kolom nama tidak ditemukan di header (contoh: "Nama Lengkap Siswa").');
  } else if (idCol < 0) {
    throw const FormatException('Kolom ID/NIS tidak ditemukan di header (contoh: "ID" atau "NIS").');
  }

  String cell(List<dynamic> row, int col) =>
      (col >= 0 && col < row.length) ? row[col].toString().trim() : '';

  final result = <StudentCsvRow>[];
  final skipped = <String>[];
  final seenIds = <String>{};

  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    final lineNo = i + 1;
    if (row.every((c) => c.toString().trim().isEmpty)) continue; // baris kosong

    final id = cell(row, idCol);
    final name = cell(row, nameCol);
    if (name.isEmpty) {
      skipped.add('Baris $lineNo: nama kosong');
      continue;
    }
    if (id.isEmpty) {
      skipped.add('Baris $lineNo ($name): ID kosong');
      continue;
    }
    if (!seenIds.add(id)) {
      skipped.add('Baris $lineNo ($name): ID $id ganda di berkas');
      continue;
    }
    result.add(StudentCsvRow(id: id, name: name, gender: _normGender(cell(row, genderCol))));
  }

  if (result.isEmpty) {
    throw FormatException('Tidak ada baris siswa yang valid. ${skipped.join('; ')}');
  }

  return StudentCsvParseResult(rows: result, skipped: skipped);
}
