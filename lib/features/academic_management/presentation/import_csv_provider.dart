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
  Future<int> importStudentsToClass(String targetClassId) async {
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

      final db = FirebaseFirestore.instance;
      // Gunakan WriteBatch agar proses simpan 100 data sekaligus tidak berat
      WriteBatch batch = db.batch();

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 3) continue; 

        final name = row[0].toString();
        final identifier = row[1].toString(); 
        final gender = row[2].toString().toUpperCase();

        // 1. KUNCI PERBAIKAN: Arahkan tepat ke sub-collection 'students' di dalam kelas!
        final docRef = db.collection('classes').doc(targetClassId).collection('students').doc(); 

        // 2. Masukkan ke dalam antrean batch
        batch.set(docRef, {
          'id': docRef.id,
          'name': name,
          'email': identifier,
          'role': 'siswa',
          'gender': gender,
          'classId': targetClassId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        successCount++;
      }
      
      // 3. Eksekusi simpan semua data secara serentak!
      await batch.commit();

      state = const AsyncData(null);
      return successCount;
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      return 0;
    }
  }
}

final importCsvControllerProvider = StateNotifierProvider<ImportCsvController, AsyncValue<void>>((ref) {
  return ImportCsvController(ref.watch(academicDataSourceProvider));
});