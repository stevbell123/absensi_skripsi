import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class UserManagementView extends ConsumerStatefulWidget {
  const UserManagementView({super.key});

  @override
  ConsumerState<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends ConsumerState<UserManagementView> {
  
  Future<String?> _registerAuthUser(String email, String password) async {
    FirebaseApp tempApp = await Firebase.initializeApp(
      name: 'tempAuthCreation',
      options: Firebase.app().options,
    );
    
    try {
      UserCredential userCredential = await FirebaseAuth.instanceFor(app: tempApp)
          .createUserWithEmailAndPassword(email: email, password: password);
      
      final uid = userCredential.user!.uid;
      await tempApp.delete();
      return uid; 
    } catch (e) {
      await tempApp.delete();
      throw Exception(e.toString());
    }
  }

  void _showAddStaffDialog(BuildContext context) {
    final nameController = TextEditingController();
    final nipController = TextEditingController(); 
    final emailController = TextEditingController();
    final passwordController = TextEditingController(); 
    final specialtyController = TextEditingController();
    String selectedRole = 'guru';
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Tambah Akun Staff', 
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController, 
                      decoration: const InputDecoration(labelText: 'Nama Lengkap'), 
                      enabled: !isProcessing,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nipController, 
                      decoration: const InputDecoration(
                        labelText: 'NIP / ID Pegawai', 
                        helperText: 'Wajib untuk identifikasi reset password',
                      ), 
                      enabled: !isProcessing,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: emailController, 
                      decoration: const InputDecoration(
                        labelText: 'Email Login', 
                        helperText: 'Gunakan email berbeda jika mereset akun',
                      ), 
                      keyboardType: TextInputType.emailAddress, 
                      enabled: !isProcessing,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController, 
                      decoration: const InputDecoration(
                        labelText: 'Password Login', 
                        helperText: 'Minimal 6 karakter',
                      ), 
                      obscureText: true, 
                      enabled: !isProcessing,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Role / Posisi'),
                      value: selectedRole,
                      items: const [
                        DropdownMenuItem(value: 'guru', child: Text('Guru')), 
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: isProcessing ? null : (val) => setState(() => selectedRole = val!),
                    ),
                    const SizedBox(height: 10),
                    if (selectedRole == 'guru')
                      TextField(
                        controller: specialtyController, 
                        decoration: const InputDecoration(labelText: 'Guru Mapel Apa?'), 
                        enabled: !isProcessing,
                      ),
                  ],
                ),
              ),
              actions: [
                if (!isProcessing) 
                  TextButton(
                    onPressed: () => Navigator.pop(context), 
                    child: const Text('Batal', style: TextStyle(color: Colors.grey)),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo, 
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isProcessing ? null : () async {
                    if (nameController.text.isNotEmpty && 
                        nipController.text.isNotEmpty && 
                        emailController.text.isNotEmpty && 
                        passwordController.text.length >= 6) {
                      
                      setState(() => isProcessing = true);
                      
                      try {
                        final String newUid = await _registerAuthUser(
                          emailController.text.trim(), 
                          passwordController.text.trim(),
                        ) ?? '';
                        
                        await FirebaseFirestore.instance.collection('users').doc(newUid).set({
                          'id': newUid,
                          'nip': nipController.text.trim(),
                          'name': nameController.text.trim(),
                          'email': emailController.text.trim(),
                          'role': selectedRole,
                          'specialty': selectedRole == 'guru' ? specialtyController.text.trim() : null,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Staff berhasil didaftarkan!'), 
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() => isProcessing = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Form tidak lengkap! Pastikan NIP terisi.'), 
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  child: isProcessing 
                      ? const SizedBox(
                          width: 20, height: 20, 
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ) 
                      : const Text('Simpan'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _hapusAkun(String uid, String nama) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Akun?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Yakin ingin mencabut akses untuk $nama?\n\nMereka tidak akan bisa login lagi ke dalam aplikasi setelah ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Akses akun berhasil dicabut!'), 
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal menghapus: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Ya, Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // --- PERBAIKAN: TAMBAHKAN APPBAR ---
      appBar: AppBar(
        title: const Text('Manajemen Pengguna', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true, // Akan memunculkan tombol 'Back' otomatis
      ),
      // ------------------------------------
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        onPressed: () => _showAddStaffDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Staff'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(), 
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Belum ada data Guru atau Admin.'));
          }

          final staffOnly = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final role = (data['role'] ?? '').toString().toLowerCase();
            return role != 'siswa' && role != 'developer';
          }).toList();

          if (staffOnly.isEmpty) {
            return const Center(child: Text('Belum ada data Guru atau Admin.'));
          }

          return ListView.builder(
            itemCount: staffOnly.length,
            padding: const EdgeInsets.all(8.0),
            itemBuilder: (context, index) {
              final doc = staffOnly[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final String uid = doc.id;
              final String name = data['name'] ?? 'Tanpa Nama';
              final String email = data['email'] ?? 'Tidak ada email';
              final String role = (data['role'] ?? 'guru').toString().toLowerCase();
              final bool isGuru = role == 'guru';
              
              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isGuru ? Colors.green.shade100 : Colors.orange.shade100,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?', 
                      style: TextStyle(
                        color: isGuru ? Colors.green.shade900 : Colors.orange.shade900, 
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(email), 
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200, 
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          role.toUpperCase(), 
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Hapus Akses Login',
                        onPressed: () => _hapusAkun(uid, name),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}