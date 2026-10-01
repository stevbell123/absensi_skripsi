import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remoteDataSource);

  final AuthRemoteDataSource _remoteDataSource;

  @override
  Stream<UserEntity?> authStateChanges() {
    return _remoteDataSource.firebaseAuthStateChanges.asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;
      return _remoteDataSource.fetchUserData(firebaseUser.uid);
    });
  }

  @override
  Future<UserEntity> login({required String email, required String password}) async {
    try {
      final credential = await _remoteDataSource.signInWithEmailPassword(
        email: email,
        password: password,
      );
      final uid = credential.user?.uid;
      if (uid == null) {
        throw StateError('Login gagal: UID tidak ditemukan.');
      }
      return _remoteDataSource.fetchUserData(uid);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseAuthError(e));
    }
  }

  @override
  Future<void> logout() => _remoteDataSource.signOut();

  String _mapFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email atau password salah.';
      case 'user-disabled':
        return 'Akun ini telah dinonaktifkan. Hubungi admin sekolah.';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan login. Coba lagi beberapa saat.';
      case 'network-request-failed':
        return 'Tidak ada koneksi internet.';
      default:
        return 'Terjadi kesalahan saat login (${e.code}).';
    }
  }
}

/// Exception khusus auth supaya UI bisa menampilkan pesan yang ramah pengguna
/// alih-alih membocorkan detail FirebaseAuthException mentah.
class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
