import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// PASTIKAN NAMA IMPORT INI SESUAI DENGAN YANG ADA DI PROYEKMU
import '../../attendance/presentation/attendance_view.dart';
import 'nilai_view.dart'; 
import 'module_management_view.dart'; 
import 'homeroom_dashboard_view.dart'; 

class GuruMainNavigation extends StatefulWidget {
  const GuruMainNavigation({super.key});

  @override
  State<GuruMainNavigation> createState() => _GuruMainNavigationState();
}

class _GuruMainNavigationState extends State<GuruMainNavigation> {
  int _currentIndex = 0;
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) return const Scaffold(body: Center(child: Text('Sesi habis, silakan login.')));

    return StreamBuilder<QuerySnapshot>(
      // Cek apakah Guru ini terdaftar sebagai Wali Kelas di suatu kelas
      stream: FirebaseFirestore.instance.collection('classes').where('homeroomTeacherId', isEqualTo: currentUserId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        bool isWaliKelas = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        List<Widget> screens = [
          const AttendanceView(),         
          const NilaiView(),              
          const ModulView(),   
        ];
        
        List<BottomNavigationBarItem> navItems = [
          const BottomNavigationBarItem(icon: Icon(Icons.fact_check), label: 'Absensi'),
          const BottomNavigationBarItem(icon: Icon(Icons.grade), label: 'Nilai'),
          const BottomNavigationBarItem(icon: Icon(Icons.library_books), label: 'Modul'),
        ];

        // Jika Guru ini adalah Wali Kelas, tambahkan menu ke-4!
        if (isWaliKelas) {
          screens.add(const HomeroomDashboardView()); 
          navItems.add(const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'Wali Kelas'));
        }

        if (_currentIndex >= screens.length) {
          _currentIndex = 0; // Mencegah error jika menu berubah
        }

        return Scaffold(
          body: screens[_currentIndex],
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed, // Penting agar ikon Modul dkk tidak hilang walau > 3
            currentIndex: _currentIndex,
            selectedItemColor: Colors.indigo,
            unselectedItemColor: Colors.grey,
            onTap: (index) => setState(() => _currentIndex = index),
            items: navItems,
          ),
        );
      },
    );
  }
}