import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'academic_providers.dart';
import '../models/academic_models.dart';

class SemesterView extends ConsumerWidget {
  const SemesterView({super.key});

  void _showAddSemesterDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final yearCtrl = TextEditingController();
    bool isActive = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Tambah Semester Baru'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Semester',
                    hintText: 'Contoh: Ganjil / Genap',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: yearCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tahun Ajaran',
                    hintText: 'Contoh: 2026/2027',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Status Aktif'),
                  subtitle: const Text('Apakah ini semester berjalan?'),
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  onChanged: (val) => setState(() => isActive = val),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () async {
                  // Validasi sederhana
                  if (nameCtrl.text.isEmpty || yearCtrl.text.isEmpty) return;

                  final newSemester = SemesterModel(
                    id: '', // Kosongkan, Firestore akan membuat ID otomatis
                    name: nameCtrl.text,
                    academicYear: yearCtrl.text,
                    isActive: isActive,
                  );

                  // Panggil fungsi addSemester dari provider
                  await ref.read(academicDataSourceProvider).addSemester(newSemester);
                  
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semestersAsync = ref.watch(semestersStreamProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSemesterDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: semestersAsync.when(
        data: (semesters) {
          // Tampilkan Empty State jika data kosong
          if (semesters.isEmpty) {
            return const Center(
              child: Text(
                'Belum ada data semester.\nKlik tombol + untuk menambahkan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: semesters.length,
            itemBuilder: (context, index) {
              final sem = semesters[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text('${sem.name} - ${sem.academicYear}'),
                  subtitle: Text(sem.isActive ? 'Semester Aktif' : 'Tidak Aktif'),
                  trailing: Switch(
                    value: sem.isActive,
                    onChanged: (val) async {
                      // Update status aktif ke Firestore
                      final updatedSemester = SemesterModel(
                        id: sem.id,
                        name: sem.name,
                        academicYear: sem.academicYear,
                        isActive: val,
                      );
                      await ref.read(academicDataSourceProvider).updateSemester(updatedSemester);
                    },
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }
}