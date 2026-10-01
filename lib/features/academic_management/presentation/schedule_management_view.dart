import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'academic_providers.dart';

class ScheduleManagementView extends ConsumerWidget {
  const ScheduleManagementView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const _AddScheduleDialog(),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Buat Jadwal Baru'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('schedules').orderBy('day').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Belum ada jadwal pelajaran.'));

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            padding: const EdgeInsets.all(8.0),
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;

              return Card(
                elevation: 1,
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.access_time)),
                  title: Text('${data['subjectName']} - ${data['className']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Guru: ${data['teacherName']}\n${data['day']}, ${data['startTime']} - ${data['endTime']}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => FirebaseFirestore.instance.collection('schedules').doc(doc.id).delete(),
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

class _AddScheduleDialog extends ConsumerStatefulWidget {
  const _AddScheduleDialog();

  @override
  ConsumerState<_AddScheduleDialog> createState() => _AddScheduleDialogState();
}

class _AddScheduleDialogState extends ConsumerState<_AddScheduleDialog> {
  String? selectedSubjectId;
  String? selectedSubjectName;
  String? selectedClassId;
  String? selectedClassName;
  String? selectedTeacherId;
  String? selectedTeacherName;
  String selectedDay = 'Senin';
  
  final startTimeController = TextEditingController(text: '08:00');
  final endTimeController = TextEditingController(text: '09:30');

  final List<String> days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];

  @override
  Widget build(BuildContext context) {
    final subjectsAsync = ref.watch(subjectsStreamProvider);
    final classesAsync = ref.watch(classesStreamProvider);
    final usersAsync = ref.watch(usersStreamProvider);

    return AlertDialog(
      title: const Text('Buat Jadwal Pelajaran'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            classesAsync.when(
              data: (classes) => DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Pilih Kelas'),
                value: selectedClassId,
                items: classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedClassId = val;
                    selectedClassName = classes.firstWhere((c) => c.id == val).name;
                  });
                },
              ),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => const Text('Gagal memuat kelas'),
            ),
            const SizedBox(height: 10),

            subjectsAsync.when(
              data: (subjects) => DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Pilih Mata Pelajaran'),
                value: selectedSubjectId,
                items: subjects.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedSubjectId = val;
                    selectedSubjectName = subjects.firstWhere((s) => s.id == val).name;
                  });
                },
              ),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => const Text('Gagal memuat mapel'),
            ),
            const SizedBox(height: 10),

            usersAsync.when(
              data: (users) {
                final teachers = users.where((u) => u.role.toString().toLowerCase().contains('guru')).toList();
                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Pilih Guru Pengajar'),
                  value: selectedTeacherId,
                  items: teachers.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))).toList(),
                  onChanged: (val) {
                    setState(() {
                      selectedTeacherId = val;
                      selectedTeacherName = teachers.firstWhere((t) => t.id == val).name;
                    });
                  },
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => const Text('Gagal memuat guru'),
            ),
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Hari'),
              value: selectedDay,
              items: days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (val) => setState(() => selectedDay = val!),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(child: TextField(controller: startTimeController, decoration: const InputDecoration(labelText: 'Jam Mulai'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: endTimeController, decoration: const InputDecoration(labelText: 'Jam Selesai'))),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(
          onPressed: () async {
            if (selectedClassId != null && selectedSubjectId != null && selectedTeacherId != null) {
              await FirebaseFirestore.instance.collection('schedules').add({
                'classId': selectedClassId,
                'className': selectedClassName,
                'subjectId': selectedSubjectId,
                'subjectName': selectedSubjectName,
                'teacherId': selectedTeacherId,
                'teacherName': selectedTeacherName,
                'day': selectedDay,
                'startTime': startTimeController.text,
                'endTime': endTimeController.text,
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Simpan Jadwal'),
        ),
      ],
    );
  }
}