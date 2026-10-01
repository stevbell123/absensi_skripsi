import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../attendance/presentation/attendance_view.dart';
import '../academic_management/presentation/beranda_guru_view.dart';
import '../academic_management/presentation/module_management_view.dart';
import '../academic_management/presentation/homeroom_dashboard_view.dart';
import '../academic_management/presentation/profile_view.dart';

class GuruHomePage extends ConsumerStatefulWidget {
  const GuruHomePage({super.key});

  @override
  ConsumerState<GuruHomePage> createState() => _GuruHomePageState();
}

class _GuruHomePageState extends ConsumerState<GuruHomePage> {
  int _currentIndex = 1; 
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('Sesi habis, silakan login.')),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('classes')
          .where('homeroomTeacherId', isEqualTo: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        bool isWaliKelas = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        List<Widget> views = [
          const BerandaGuruView(), 
          const AttendanceView(),  
          const ModulView(),       
        ];

        List<NavigationDestination> destinations = [
          const NavigationDestination(
            icon: Icon(Icons.dashboard), 
            label: 'Beranda',
          ),
          const NavigationDestination(
            icon: Icon(Icons.fact_check), 
            label: 'Absensi',
          ),
          const NavigationDestination(
            icon: Icon(Icons.library_books), 
            label: 'Modul',
          ),
        ];

        if (isWaliKelas) {
          views.add(const HomeroomDashboardView());
          destinations.add(
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings), 
              label: 'Wali Kelas',
            ),
          );
        }

        views.add(const ProfileView());
        destinations.add(
          const NavigationDestination(
            icon: Icon(Icons.person_outline), 
            selectedIcon: Icon(Icons.person), 
            label: 'Profil',
          ),
        );

        if (_currentIndex >= views.length) {
          _currentIndex = 1;
        }

        return PopScope(
          canPop: false, 
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            
            final bool shouldExit = await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text(
                  'Keluar Aplikasi?', 
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                content: const Text('Apakah Anda yakin ingin keluar dari Portal Guru?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false), 
                    child: const Text('Batal'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Keluar', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ) ?? false;

            if (shouldExit) {
              SystemNavigator.pop(); 
            }
          },
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Portal Guru', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            body: views[_currentIndex],
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) => setState(() => _currentIndex = index),
              destinations: destinations,
            ),
          ),
        );
      },
    );
  }
}