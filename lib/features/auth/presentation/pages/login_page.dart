import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <--- TAMBAHAN UNTUK DATABASE TIKET BANTUAN

import '../../../../core/constants/app_constants.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_text_field.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    await ref.read(loginControllerProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    final state = ref.read(loginControllerProvider);
    if (state.hasError) {
      final error = state.error;
      final message = error is AuthFailure ? error.message : 'Terjadi kesalahan. Coba lagi.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    // Kalau sukses, GoRouter redirect otomatis pindah ke home sesuai role
    // begitu authStateChangesProvider emit user baru — tidak perlu navigasi manual.
  }

  // ==========================================================
  // FUNGSI UNTUK MENGIRIM LAPORAN BANTUAN KE ADMIN
  // ==========================================================
  Future<void> _showHelpdeskDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final idController = TextEditingController(); // Untuk NIS / NIP
    final messageController = TextEditingController();
    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false, // User tidak bisa asal klik di luar untuk menutup (harus via tombol Batal)
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
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Lupa password atau email tidak aktif? Kirim laporan ke Admin untuk di-reset.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 16),
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nama Lengkap', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 12),
                  TextField(controller: idController, decoration: const InputDecoration(labelText: 'NIS (Siswa) / NIP (Guru)', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 12),
                  TextField(controller: messageController, maxLines: 3, decoration: const InputDecoration(labelText: 'Pesan / Keluhan', border: OutlineInputBorder(), isDense: true)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                onPressed: isLoading ? null : () async {
                  if (nameController.text.isEmpty || idController.text.isEmpty || messageController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Harap isi semua data!'), backgroundColor: Colors.red));
                    return;
                  }
                  
                  setState(() => isLoading = true);
                  try {
                    // Menyimpan data laporan ke tabel 'laporan_bantuan'
                    await FirebaseFirestore.instance.collection('laporan_bantuan').add({
                      'nama': nameController.text.trim(),
                      'nomor_induk': idController.text.trim(),
                      'pesan': messageController.text.trim(),
                      'status': 'Menunggu', // Status default saat baru dikirim
                      'tanggal': FieldValue.serverTimestamp(),
                    });
                    
                    if (context.mounted) {
                      Navigator.pop(context); // Tutup dialog
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Laporan berhasil dikirim ke Admin!'), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    setState(() => isLoading = false);
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
                  }
                },
                child: isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Kirim Laporan'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginControllerProvider);
    final isLoading = loginState.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppConstants.appFullName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    AuthTextField(
                      controller: _emailController,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Email wajib diisi';
                        }
                        if (!value.contains('@')) return 'Format email tidak valid';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _passwordController,
                      label: 'Password',
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Password wajib diisi';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Masuk'),
                    ),
                    const SizedBox(height: 8), // Sedikit jarak sebelum tombol Bantuan
                    
                    // ==========================================
                    // TOMBOL PUSAT BANTUAN DITAMBAHKAN DI SINI
                    // ==========================================
                    TextButton.icon(
                      onPressed: () => _showHelpdeskDialog(context),
                      icon: const Icon(Icons.help_outline, size: 18),
                      label: const Text('Lupa Password / Butuh Bantuan?'),
                    ),
                    
                    const SizedBox(height: 12),
                    Text(
                      'Akun dibuat oleh admin sekolah. Hubungi admin jika belum punya akun.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}