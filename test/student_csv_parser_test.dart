import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:siap_app/features/academic_management/presentation/student_csv_parser.dart';

void main() {
  test('format 2 kolom ID,Nama (CRLF) terbaca, jenis kelamin kosong', () {
    final r = parseStudentCsv('ID,Nama Lengkap Siswa\r\n2439,Siswa Satu\r\n0123,Siswa Dua\r\n');
    expect(r.rows.length, 2);
    expect(r.rows[0].id, '2439');
    expect(r.rows[0].name, 'Siswa Satu');
    expect(r.rows[0].gender, '');
    expect(r.rows[1].id, '0123', reason: 'nol di depan tidak boleh hilang');
    expect(r.skipped, isEmpty);
  });

  test('format lama Nama,Email,Gender tetap didukung', () {
    final r = parseStudentCsv('Nama,Email,Gender\nSiswa Satu,s1@sd.id,l\n');
    expect(r.rows.single.name, 'Siswa Satu');
    expect(r.rows.single.id, 's1@sd.id');
    expect(r.rows.single.gender, 'L');
  });

  test('pemisah titik koma, BOM, urutan kolom bebas, kolom No diabaikan', () {
    final r = parseStudentCsv('﻿No;Nama Siswa;Jenis Kelamin;NIS\n1;Siswa Satu;Perempuan;2440\n');
    expect(r.rows.single.id, '2440');
    expect(r.rows.single.name, 'Siswa Satu');
    expect(r.rows.single.gender, 'P');
  });

  test('baris kosong diabaikan, baris tanpa nama/ID ganda dilaporkan', () {
    final r = parseStudentCsv('ID,Nama\n1,A\n\n2,\n1,B\n3,C\n');
    expect(r.rows.map((s) => s.id), ['1', '3']);
    expect(r.skipped.length, 2);
  });

  test('hanya header atau kosong memberi pesan jelas', () {
    expect(() => parseStudentCsv('ID,Nama\n'), throwsFormatException);
    expect(() => parseStudentCsv(''), throwsFormatException);
    expect(() => parseStudentCsv('ID,Kelas\n1,IV\n'), throwsFormatException);
  });

  test('berkas ANSI (Latin-1) tetap terbaca', () {
    final bytes = latin1.encode('ID,Nama\n1,José\n');
    expect(parseStudentCsv(decodeCsvBytes(bytes)).rows.single.name, 'José');
  });
}
