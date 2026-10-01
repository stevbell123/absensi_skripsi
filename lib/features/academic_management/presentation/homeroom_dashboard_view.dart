import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'student_performance_view.dart'; // PASTI KAN NAMA FILE INI BENAR

class HomeroomDashboardView extends StatelessWidget {
  const HomeroomDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) return const Scaffold(body: Center(child: Text('Belum login.')));

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard Wali Kelas')),
      body: StreamBuilder<QuerySnapshot>(
        // Mencari kelas binaannya
        stream: FirebaseFirestore.instance.collection('classes').where('homeroomTeacherId', isEqualTo: currentUserId).snapshots(),
        builder: (context, classSnapshot) {
          if (classSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          if (!classSnapshot.hasData || classSnapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Anda belum ditugaskan menjadi Wali Kelas.\nHubungi Admin.', textAlign: TextAlign.center));
          }

          final classDoc = classSnapshot.data!.docs.first; 
          final classData = classDoc.data() as Map<String, dynamic>;
          final classId = classDoc.id;
          final className = classData['name'] ?? 'Kelas';
          final semesterId = classData['semesterId'] ?? '';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.indigo.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Kelas Binaan Anda:', style: TextStyle(color: Colors.indigo)),
                    Text(className.toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  ],
                ),
              ),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('classes').doc(classId).collection('students').orderBy('name').snapshots(),
                  builder: (context, studentSnapshot) {
                    if (studentSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (!studentSnapshot.hasData || studentSnapshot.data!.docs.isEmpty) return const Center(child: Text('Belum ada siswa di kelas ini.'));

                    final students = studentSnapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: students.length,
                      itemBuilder: (context, index) {
                        final doc = students[index];
                        final student = doc.data() as Map<String, dynamic>;
                        
                        student['studentId'] = doc.id;
                        student['classId'] = classId;
                        student['className'] = className;

                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Text(student['name'][0].toUpperCase(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(student['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Email/NIS: ${student['email'] ?? '-'}'),
                            trailing: const Icon(Icons.print, color: Colors.indigo), 
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => StudentPerformanceView(studentData: student, semesterId: semesterId),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}