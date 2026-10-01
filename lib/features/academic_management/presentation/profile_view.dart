import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_providers.dart';
import '../../auth/presentation/pages/login_page.dart';

class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key});

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  final currentUser = FirebaseAuth.instance.currentUser;

  // ==========================================================
  // FUNGSI GANTI PASSWORD (KHUSUS ADMIN)
  // ==========================================================
  void _changePasswordDialog(BuildContext context) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text(
              'Ganti Password', 
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Konfirmasi password lama Anda untuk keamanan.', 
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password Lama',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password Baru',
                    border: OutlineInputBorder(),
                    helperText: 'Minimal 6 karakter',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text('Batal', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber, 
                  foregroundColor: Colors.black,
                ),
                onPressed: isLoading ? null : () async {
                  if (oldPasswordController.text.isEmpty) return;
                  if (newPasswordController.text.length < 6) return;
                  
                  setState(() => isLoading = true);
                  try {
                    if (currentUser != null && currentUser!.email != null) {
                      AuthCredential credential = EmailAuthProvider.credential(
                        email: currentUser!.email!, 
                        password: oldPasswordController.text,
                      );
                      await currentUser!.reauthenticateWithCredential(credential);
                      await currentUser!.updatePassword(newPasswordController.text);
                      
                      if (context.mounted) {
                        Navigator.pop(context); 
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Password berhasil diubah!'), 
                            backgroundColor: Colors.green,
                          )
                        );
                      }
                    }
                  } on FirebaseAuthException catch (e) {
                    setState(() => isLoading = false);
                    String errorMsg = 'Terjadi kesalahan';
                    if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                      errorMsg = 'Password lama salah!';
                    } else if (e.message != null) {
                      errorMsg = e.message!;
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal: $errorMsg'), backgroundColor: Colors.red)
                      );
                    }
                  }
                },
                child: isLoading 
                    ? const SizedBox(
                        width: 16, height: 16, 
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      ) 
                    : const Text('Simpan Password'),
              ),
            ],
          );
        }
      ),
    );
  }

  // ==========================================================
  // FUNGSI INBOX BANTUAN (KHUSUS GURU)
  // ==========================================================
  void _showGuruInboxDialog(BuildContext context, String nama, String nip) {
    final messageController = TextEditingController(text: 'Halo Admin, tolong bantu reset password saya.');
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.support_agent, color: Colors.indigo),
                SizedBox(width: 8),
                Text('Pusat Bantuan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sesuai aturan keamanan, Guru tidak diizinkan mengubah password secara mandiri.', 
                  style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: messageController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Pesan untuk Admin',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text('Batal', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo, 
                  foregroundColor: Colors.white,
                ),
                onPressed: isLoading ? null : () async {
                  setState(() => isLoading = true);
                  try {
                    await FirebaseFirestore.instance.collection('laporan_bantuan').add({
                      'nama': nama,
                      'nomor_induk': nip.isEmpty ? 'Tidak Ada NIP' : nip,
                      'pesan': messageController.text.trim(),
                      'status': 'Menunggu',
                      'tanggal': FieldValue.serverTimestamp(),
                    });
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Laporan terkirim!'), 
                          backgroundColor: Colors.green,
                        )
                      );
                    }
                  } catch (e) {
                    setState(() => isLoading = false);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red)
                      );
                    }
                  }
                },
                child: isLoading 
                    ? const SizedBox(
                        width: 16, height: 16, 
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ) 
                    : const Text('Kirim ke Admin'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Center(child: Text('Tidak ada user login.'));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Saya', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Data profil tidak ditemukan.'));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final String nama = userData['name'] ?? 'Tanpa Nama';
          final String email = userData['email'] ?? 'Tidak ada email';
          final String role = userData['role'] ?? 'guru';
          final String nip = userData['nip'] ?? ''; 

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.indigo.shade100,
                  child: Text(
                    nama[0].toUpperCase(),
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                color: Colors.grey.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: const Text('Nama', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        subtitle: Text(nama, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.email),
                        title: const Text('Email', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        subtitle: Text(email, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.badge),
                        title: const Text('Role', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        subtitle: Text(role.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                color: Colors.grey.shade100,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Ganti Password', style: TextStyle(fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        if (role == 'admin' || role == 'developer') {
                          _changePasswordDialog(context);
                        } else {
                          _showGuruInboxDialog(context, nama, nip);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('Keluar Aplikasi', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      onTap: () async {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (c) => const Center(child: CircularProgressIndicator()),
                        );
                        try {
                          await FirebaseFirestore.instance.terminate();
                          await FirebaseFirestore.instance.clearPersistence();
                          await ref.read(authRepositoryProvider).logout();
                          
                          if (context.mounted) {
                            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => const LoginPage()), 
                              (route) => false,
                            );
                          }
                        } catch (e) {
                          if (context.mounted) Navigator.pop(context); 
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}