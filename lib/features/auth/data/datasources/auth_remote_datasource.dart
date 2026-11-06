import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../models/user_model.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource({
    required FirebaseAuth firebaseAuth,
    required FirebaseFirestore firestore,
  })  : _firebaseAuth = firebaseAuth,
        _firestore = firestore;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;

  Stream<User?> get firebaseAuthStateChanges =>
      _firebaseAuth.authStateChanges().map((u) {
        debugPrint('SIAP DEBUG: raw firebaseUser = ${u?.uid ?? "null"}');
        return u;
      });

  Future<UserModel> fetchUserData(String uid) async {
    debugPrint('SIAP DEBUG: fetchUserData START uid=$uid');
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 10));
    debugPrint('SIAP DEBUG: fetchUserData DONE exists=${doc.exists}');
    if (!doc.exists) {
      throw StateError(
        'Akun berhasil login tapi data profil belum ada di Firestore. '
        'Hubungi admin untuk melengkapi data user (koleksi "users").',
      );
    }
    return UserModel.fromFirestore(doc);
  }

  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) {
    return _firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _firebaseAuth.signOut();
}