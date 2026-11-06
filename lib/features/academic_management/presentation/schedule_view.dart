import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'academic_providers.dart';

class ScheduleView extends ConsumerWidget {
  const ScheduleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(schedulesStreamProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Form Jadwal akan butuh Dropdown Kelas & Mapel'))),
        child: const Icon(Icons.add),
      ),
      body: dataAsync.when(
        data: (list) => list.isEmpty 
          ? const Center(child: Text('Belum ada Jadwal.'))
          : ListView.builder(itemCount: list.length, itemBuilder: (ctx, i) => ListTile(title: Text(list[i].day))),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}