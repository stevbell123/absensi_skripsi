import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_performance_view.dart'; 

// ============================================================================
// HALAMAN 1: MENAMPILKAN DAFTAR KELAS
// ============================================================================
class SemesterDetailView extends StatelessWidget {
  final String semesterId;
  final String semesterName;

  const SemesterDetailView({super.key, required this.semesterId, required this.semesterName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Semester: $semesterName'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('classes')
            .where('semesterId', isEqualTo: semesterId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Belum ada kelas di semester ini.'));
          }

          final classes = snapshot.data!.docs;

          return ListView.builder(
            itemCount: classes.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final doc = classes[index];
              final data = doc.data() as Map<String, dynamic>;
              final className = data['name'] ?? 'Tanpa Nama';
              final level = data['level'] ?? '-';

              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: const Icon(Icons.door_front_door, color: Colors.indigo),
                  ),
                  title: Text(className, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text('Tingkat: $level', style: const TextStyle(color: Colors.blue)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Navigasi memanggil Widget halaman kedua yang ada di bawah file ini
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => _SemesterStudentListView(
                          classId: doc.id,
                          className: className,
                          semesterId: semesterId,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// HALAMAN 2: MENAMPILKAN DAFTAR SISWA (Masih di dalam 1 file yang sama)
// ============================================================================
class _SemesterStudentListView extends StatelessWidget {
  final String classId;
  final String className;
  final String semesterId;

  const _SemesterStudentListView({
    required this.classId,
    required this.className,
    required this.semesterId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Siswa: $className'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('classes')
            .doc(classId)
            .collection('students')
            .orderBy('name') 
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Belum ada data siswa di kelas ini.'));
          }

          final students = snapshot.data!.docs;

          return ListView.builder(
            itemCount: students.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final doc = students[index];
              final student = doc.data() as Map<String, dynamic>;
              
              student['studentId'] = doc.id; 
              student['className'] = className; 
              student['classId'] = classId;

              return Card(
                elevation: 0.5,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      student['name'].toString()[0].toUpperCase(),
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(student['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Email/NIS: ${student['email'] ?? '-'}'),
                  trailing: const Icon(Icons.analytics, color: Colors.blue),
                  onTap: () {
                    // Navigasi ke halaman Rapor Mini
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StudentPerformanceView(
                          studentData: student,
                          semesterId: semesterId,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}