import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'academic_providers.dart';
import '../models/academic_models.dart';

class SubjectView extends ConsumerWidget {
  const SubjectView({super.key});

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Mapel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Mapel (ex: Matematika)')),
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Kode (ex: MTK)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.isEmpty) return;
              ref.read(academicDataSourceProvider).addSubject(
                SubjectModel(id: '', name: nameCtrl.text, code: codeCtrl.text)
              );
              Navigator.pop(context);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(subjectsStreamProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _showAddDialog(context, ref), child: const Icon(Icons.add)),
      body: dataAsync.when(
        data: (list) => list.isEmpty 
          ? const Center(child: Text('Belum ada Mapel.'))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) => ListTile(title: Text(list[i].name), subtitle: Text(list[i].code)),
            ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}