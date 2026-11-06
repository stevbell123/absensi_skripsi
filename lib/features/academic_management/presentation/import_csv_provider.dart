import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart' as csv_pkg;
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../datasources/academic_remote_datasource.dart';
import 'academic_providers.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/domain/entities/user_entity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_csv_parser.dart';

/// Hasil impor siswa ke kelas.
class ImportStudentsResult {
  const ImportStudentsResult({required this.imported, required this.skipped});
  final int imported;

  /// Catatan baris yang dilewati, contoh "Baris 5: nama kosong".
  final List<String> skipped;
}

class ImportCsvController extends StateNotifier<AsyncValue<void>> {
  ImportCsvController(this._dataSource) : super(const AsyncData(null));
  final AcademicRemoteDataSource _dataSource;

  // ===================================================================
  // 1. FUNGSI LAMA (Agar tombol di Tab Pengguna tidak error)
  // ===================================================================
  Future<int> importUsersFromCsv() async {
    int successCount = 0;
    try {
      state = const AsyncLoading();
      
      fp.FilePickerResult? result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom, allowedExtensions: ['csv'],
      );

      if (result == null) {
        state = const AsyncData(null);
        return 0; 
      }

      final file = File(result.files.single.path!);
      final input = await file.readAsString();
      final List<List<dynamic>> rows = const csv_pkg.CsvToListConverter().convert(input);
      
      if (rows.length <= 1) throw Exception('File CSV kosong atau hanya berisi header.');

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 5) continue; 

        final name = row[0].toString();
        final email = row[1].toString();
        final password = row[2].toString();
        final roleString = row[3].toString().toLowerCase();
        final gender = row[4].toString();
        final classId = row.length >= 6 ? row[5].toString() : null;

        UserRole role = UserRole.siswa;
        if (roleString == 'guru') role = UserRole.guru;
        if (roleString == 'admin') role = UserRole.admin;

        final newUser = UserModel(
          id: '', 
          name: name, 
          email: email, 
          role: role, 
          rawRole: roleString, // <--- PERBAIKAN: Menambahkan rawRole
          gender: gender, 
          classId: classId, 
          createdAt: DateTime.now(),
        );

        await _dataSource.createUserByAdmin(email: email, password: password, userModel: newUser);
        successCount++;
      }
      
      state = const AsyncData(null);
      return successCount;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return 0;
    }
  }

  // ===================================================================
  // 2. FUNGSI BARU (Khusus dari dalam Detail Kelas)
  // ===================================================================
  /// Mengimpor siswa dari CSV ke sub-collection `classes/{id}/students`.
  ///
  /// Mengembalikan `null` bila pengguna membatalkan pemilihan berkas.
  /// Error (format CSV salah, izin Firestore, dll.) dilempar ke pemanggil
  /// supaya pesan aslinya tampil di layar.
  Future<ImportStudentsResult?> importStudentsToClass(String targetClassId) async {
    state = const AsyncLoading();
    try {
      final picked = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // cadangan bila path tidak tersedia (content:// di Android)
      );

      if (picked == null || picked.files.isEmpty) {
        state = const AsyncData(null);
        return null;
      }

      final pf = picked.files.single;
      final List<int> bytes;
      if (pf.bytes != null) {
        bytes = pf.bytes!;
      } else if (pf.path != null) {
        bytes = await File(pf.path!).readAsBytes();
      } else {
        throw const FormatException('Berkas tidak bisa dibaca. Coba salin berkas ke folder Download.');
      }

      final parsed = parseStudentCsv(decodeCsvBytes(bytes));

      final db = FirebaseFirestore.instance;
      final studentsRef = db.collection('classes').doc(targetClassId).collection('students');

      // Firestore membatasi 500 operasi per batch → kirim per 400.
      const chunkSize = 400;
      for (int start = 0; start < parsed.rows.length; start += chunkSize) {
        final batch = db.batch();
        for (final s in parsed.rows.skip(start).take(chunkSize)) {
          final docRef = studentsRef.doc();
          batch.set(docRef, {
            'id': docRef.id,
            'name': s.name,
            'email': s.id, // dipakai tampilan daftar siswa & registrasi wajah
            'nisNip': s.id, // dipakai sinkronisasi data wajah (face_database_service)
            'role': 'siswa',
            'gender': s.gender,
            'classId': targetClassId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      state = const AsyncData(null);
      return ImportStudentsResult(imported: parsed.rows.length, skipped: parsed.skipped);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final importCsvControllerProvider = StateNotifierProvider<ImportCsvController, AsyncValue<void>>((ref) {
  return ImportCsvController(ref.watch(academicDataSourceProvider));
});