import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Wajib ditambah untuk cek status asli

import '../../features/auth/domain/entities/user_entity.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/home/admin_home_page.dart';
import '../../features/home/guru_home_page.dart';

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<UserEntity?>>(
      authStateChangesProvider,
      (_, __) => notifyListeners(),
    );
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authState = _ref.read(authStateChangesProvider);
    final authUser = FirebaseAuth.instance.currentUser; // Cek status asli dari Firebase Auth

    // --- ALAT DIAGNOSA ANTI NYANGKUT ---
    debugPrint('=== DIAGNOSA ROUTER ===');
    debugPrint('Lokasi Saat Ini: ${state.matchedLocation}');
    debugPrint('Loading: ${authState.isLoading}');
    debugPrint('Ada Error: ${authState.hasError}');
    if (authState.hasError) {
      debugPrint('🔥 DETAIL ERROR: ${authState.error}');
    }
    debugPrint('Data Firestore: ${authState.valueOrNull?.name}');
    debugPrint('Data Firebase Auth: ${authUser?.email}');
    debugPrint('=======================');

    final goingToSplash = state.matchedLocation == '/splash';
    final goingToLogin = state.matchedLocation == '/login';

    if (authState.isLoading) {
      return goingToSplash ? null : '/splash';
    }

    // [SOLUSI]: Jika Firebase Auth sudah berhasil masuk tapi data Firestore gagal dibaca (Error)
    if (authState.hasError && authUser != null) {
      // Kita paksa logout agar sesi tidak nyangkut abadi di memori HP/Emulator
      FirebaseAuth.instance.signOut();
      return goingToLogin ? null : '/login';
    }

    final user = authState.valueOrNull;
    final isLoggedIn = user != null;

    if (!isLoggedIn) {
      return goingToLogin ? null : '/login';
    }

    if (goingToSplash || goingToLogin) {
      return _homeRouteForRole(user.role);
    }

    return null;
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminHomePage()),
      GoRoute(path: '/guru', builder: (context, state) => const GuruHomePage()),
    ],
  );
});

String _homeRouteForRole(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return '/admin';
    case UserRole.guru:
      return '/guru';
    case UserRole.siswa:
      return '/siswa';
  }
}