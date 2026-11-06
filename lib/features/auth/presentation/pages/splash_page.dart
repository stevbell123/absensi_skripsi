import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';

/// Ditampilkan sesaat saat GoRouter masih menunggu authStateChangesProvider
/// selesai loading (cek sesi login pertama kali saat app dibuka).
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlutterLogo(size: 64),
            SizedBox(height: 24),
            Text(AppConstants.appFullName, style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
