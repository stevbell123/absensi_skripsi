import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'module_detail_view.dart'; // PASTIKAN FILE INI NANTI DIBUAT/ADA

class ModulView extends StatefulWidget {
  const ModulView({super.key});

  @override
  State<ModulView> createState() => _ModulViewState();
}

class _ModulViewState extends State<ModulView> {
  bool _isAdmin = false;
  bool _isLoading = true;

  final List<int> _levels = const [1, 2, 3, 4, 5, 6];

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  // Cek apakah user yang sedang login adalah Admin
  Future<void> _checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _isAdmin = data['role'].toString().toLowerCase() == 'admin';
        });
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // PERUBAHAN: Baris ini akan menghilangkan tombol panah 'Back' secara paksa
        automaticallyImplyLeading: false, 
        title: const Text('Bank Modul Belajar', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      backgroundColor: Colors.grey.shade50,
      
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _levels.length,
              itemBuilder: (context, index) {
                final level = _levels[index];
                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.folder_outlined, color: Colors.indigo, size: 28),
                    ),
                    title: Text(
                      'Modul Kelas $level',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: const Text(
                      'Kelola dan unduh materi pembelajaran',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () {
                      // Masuk ke halaman detail modul, sekalian lempar status Admin-nya!
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ModuleDetailView(
                            level: level.toString(), 
                            isAdmin: _isAdmin,       
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}