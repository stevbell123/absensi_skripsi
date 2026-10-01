import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../datasources/attendance_remote_datasource.dart';
import '../../auth/presentation/providers/auth_providers.dart';

// Provider untuk DataSource Absensi
final attendanceDataSourceProvider = Provider((ref) {
  return AttendanceRemoteDataSource(ref.watch(firestoreProvider));
});

// StateNotifier untuk mengelola aksi simpan
class SaveAttendanceController extends StateNotifier<AsyncValue<void>> {
  SaveAttendanceController(this._dataSource) : super(const AsyncData(null));
  final AttendanceRemoteDataSource _dataSource;

  Future<void> save(dynamic attendanceModel) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _dataSource.saveAttendance(attendanceModel));
  }
}

final saveAttendanceControllerProvider = StateNotifierProvider<SaveAttendanceController, AsyncValue<void>>((ref) {
  return SaveAttendanceController(ref.watch(attendanceDataSourceProvider));
});