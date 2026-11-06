import '../entities/user_entity.dart';

abstract class AuthRepository {
  /// Stream user yang sedang login berikut data profilnya dari Firestore.
  /// Emit `null` kalau belum login / setelah logout.
  Stream<UserEntity?> authStateChanges();

  Future<UserEntity> login({required String email, required String password});

  Future<void> logout();
}
