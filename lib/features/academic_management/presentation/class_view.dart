import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'academic_providers.dart';
import '../models/academic_models.dart';

class ClassView extends ConsumerWidget {
  const ClassView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(classesStreamProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final nameCtrl = TextEditingController();
          final levelCtrl = TextEditingController();
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Tambah Kelas'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama (ex: X IPA 1)')),
                  TextField(controller: levelCtrl, decoration: const InputDecoration(labelText: 'Tingkat (ex: 10)')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                FilledButton(
                  onPressed: () {
                    // Validasi sederhana
                    if (nameCtrl.text.isEmpty || levelCtrl.text.isEmpty) return;
                    
                    ref.read(academicDataSourceProvider).addClass(
                      ClassModel(
                        id: '', 
                        name: nameCtrl.text, 
                        level: levelCtrl.text, 
                        semesterId: '' // Dikosongkan sementara sampai kita buat fitur dropdown relasi semester
                      )
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Simpan'),
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: dataAsync.when(
        data: (list) => list.isEmpty 
          ? const Center(child: Text('Belum ada Kelas.'))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) => ListTile(
                title: Text(list[i].name), 
                subtitle: Text('Tingkat: ${list[i].level}'),
                leading: const CircleAvatar(
                  child: Icon(Icons.meeting_room, size: 20),
                ),
              ),
            ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}