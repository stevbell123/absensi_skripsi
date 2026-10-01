import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../datasources/academic_remote_datasource.dart';
import '../models/academic_models.dart';
import '../../auth/data/models/user_model.dart';
import '../../auth/presentation/providers/auth_providers.dart';

final academicDataSourceProvider = Provider((ref) => AcademicRemoteDataSource(ref.watch(firestoreProvider)));

final semestersStreamProvider = StreamProvider((ref) => ref.watch(academicDataSourceProvider).getSemesters());
final subjectsStreamProvider = StreamProvider((ref) => ref.watch(academicDataSourceProvider).getSubjects());
final classesStreamProvider = StreamProvider((ref) => ref.watch(academicDataSourceProvider).getClasses());
final schedulesStreamProvider = StreamProvider((ref) => ref.watch(academicDataSourceProvider).getSchedules());
final usersStreamProvider = StreamProvider((ref) => ref.watch(academicDataSourceProvider).getUsers());

class CreateUserController extends StateNotifier<AsyncValue<void>> {
  CreateUserController(this._dataSource) : super(const AsyncData(null));
  final AcademicRemoteDataSource _dataSource;

  Future<void> createUser({required String email, required String password, required UserModel userModel}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _dataSource.createUserByAdmin(email: email, password: password, userModel: userModel));
  }
}

final createUserControllerProvider = StateNotifierProvider<CreateUserController, AsyncValue<void>>((ref) {
  return CreateUserController(ref.watch(academicDataSourceProvider));
});

// ==========================================
// TAMBAHAN BARU: Provider Khusus Siswa per Kelas
// ==========================================
final studentsByClassProvider = StreamProvider.family<List<UserModel>, String>((ref, classId) {
  final db = FirebaseFirestore.instance;
  return db.collection('users')
      .where('role', isEqualTo: 'siswa') // Hanya menarik user dengan role 'siswa'
      .where('classId', isEqualTo: classId) // Yang ID kelasnya cocok
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => UserModel.fromFirestore(doc))
          .toList());
});