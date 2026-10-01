import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../academic_management/presentation/academic_main_view.dart';
import '../academic_management/presentation/user_management_view.dart';
import '../academic_management/presentation/beranda_admin_view.dart';
import '../academic_management/presentation/module_management_view.dart'; 
import '../academic_management/presentation/profile_view.dart'; 
import '../academic_management/presentation/inbox_admin_view.dart'; 

final unreadReportsProvider = StreamProvider.autoDispose<int>((ref) {
  return FirebaseFirestore.instance
      .collection('laporan_bantuan')
      .where('status', isEqualTo: 'Menunggu')
      .snapshots()
      .map((snapshot) => snapshot.docs.length);
});

class AdminHomePage extends ConsumerStatefulWidget {
  const AdminHomePage({super.key});

  @override
  ConsumerState<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends ConsumerState<AdminHomePage> {
  int _currentIndex = 0;

  final List<Widget> _views = [
    const BerandaAdminView(),
    const AcademicMainView(), 
    const ModulView(), 
    const ProfileView(), 
  ];

  // --- FUNGSI BARU: POP-UP TENTANG APLIKASI ---
  void _showAboutApp(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.indigo, size: 28),
              SizedBox(width: 10),
              Text('Tentang Aplikasi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sistem Informasi Akademik Pintar (SIAP)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 12),
              Text(
                'Aplikasi ini dirancang dan dikembangkan secara khusus sebagai bagian dari instrumen penelitian untuk Tugas Akhir.',
                style: TextStyle(fontSize: 14, height: 1.4),
                textAlign: TextAlign.justify,
              ),
              SizedBox(height: 20),
              Text(
                'Tim Pengembang:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                '• Steven David Malau\n• Wan Saka Nasa\n• William Patar Marpaung', 
                style: TextStyle(fontSize: 14, height: 1.6)
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }
  // --------------------------------------------

  @override
  Widget build(BuildContext context) {
    final unreadCountAsync = ref.watch(unreadReportsProvider);
    final unreadCount = unreadCountAsync.valueOrNull ?? 0;

    return PopScope(
      canPop: false, 
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        final bool shouldExit = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Keluar Aplikasi?', style: TextStyle(fontWeight: FontWeight.bold)),
            content: const Text('Apakah Anda yakin ingin keluar dari Dashboard Admin?'),
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
          title: const Text('Dashboard Admin', style: TextStyle(fontWeight: FontWeight.bold)),
          leading: Builder(
            builder: (context) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                      ),
                    ),
                ],
              );
            }
          ),
        ),
        
        drawer: Drawer(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    UserAccountsDrawerHeader(
                      decoration: const BoxDecoration(color: Colors.indigo),
                      currentAccountPicture: CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Icon(Icons.admin_panel_settings, size: 45, color: Colors.indigo.shade700),
                      ),
                      accountName: const Text('Administrator', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      accountEmail: const Text('Sistem Informasi Akademik', style: TextStyle(fontSize: 13, color: Colors.white70)),
                    ),
                    
                    ListTile(
                      leading: const Icon(Icons.people_outline, color: Colors.black87),
                      title: const Text('Manajemen Pengguna', style: TextStyle(fontWeight: FontWeight.w500)),
                      onTap: () {
                        Navigator.pop(context); 
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const UserManagementView()));
                      },
                    ),
                    
                    ListTile(
                      leading: const Icon(Icons.mark_email_unread_outlined, color: Colors.black87),
                      title: const Text('Inbox Laporan', style: TextStyle(fontWeight: FontWeight.w500)),
                      trailing: unreadCount > 0 
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        : null,
                      onTap: () {
                        Navigator.pop(context); 
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const InboxAdminView()));
                      },
                    ),
                    
                    const Divider(thickness: 1, height: 24),
                    
                    // --- TOMBOL TENTANG APLIKASI ---
                    ListTile(
                      leading: const Icon(Icons.info_outline, color: Colors.black54),
                      title: const Text('Tentang Aplikasi', style: TextStyle(color: Colors.black54)),
                      onTap: () {
                        Navigator.pop(context); // Menutup drawer dulu
                        _showAboutApp(context); // Lalu memunculkan pop-up
                      },
                    ),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('SIAP App v0.1.0', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
        
        body: _views[_currentIndex],
        
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected, 
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'Beranda'),
            NavigationDestination(icon: Icon(Icons.school), label: 'Akademik'),
            NavigationDestination(icon: Icon(Icons.library_books), label: 'Modul'), 
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
          ],
        ),
      ),
    );
  }
}