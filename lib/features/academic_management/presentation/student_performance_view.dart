import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../attendance/widgets/pdf_khs_service.dart'; // Pastikan path ini benar

class StudentPerformanceView extends StatelessWidget {
  final Map<String, dynamic> studentData;
  final String semesterId;

  const StudentPerformanceView({super.key, required this.studentData, required this.semesterId});

  @override
  Widget build(BuildContext context) {
    final studentName = studentData['name'] ?? 'Siswa';
    final className = studentData['className'] ?? '';
    final studentId = studentData['studentId'] ?? '';
    final classId = studentData['classId'] ?? '';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(studentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(className, style: const TextStyle(fontSize: 14)),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('attendance')
            .where('classId', isEqualTo: classId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          // 1. Menghitung Absensi dari Database
          Map<String, Map<String, int>> subjectAttendance = {};
          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final subjectName = data['subjectName'] ?? 'Umum';
              final records = data['records'] as List<dynamic>? ?? [];
              
              for (var record in records) {
                if (record['studentId'] == studentId) {
                  final status = record['status'].toString().toLowerCase();
                  if (!subjectAttendance.containsKey(subjectName)) {
                    subjectAttendance[subjectName] = {'hadir': 0, 'izin': 0, 'sakit': 0, 'alpa': 0};
                  }
                  
                  if (status == 'hadir') {
                    subjectAttendance[subjectName]!['hadir'] = subjectAttendance[subjectName]!['hadir']! + 1;
                  } else if (status == 'izin') {
                    subjectAttendance[subjectName]!['izin'] = subjectAttendance[subjectName]!['izin']! + 1;
                  } else if (status == 'sakit') {
                    subjectAttendance[subjectName]!['sakit'] = subjectAttendance[subjectName]!['sakit']! + 1;
                  } else if (status == 'alpa') {
                    subjectAttendance[subjectName]!['alpa'] = subjectAttendance[subjectName]!['alpa']! + 1;
                  }
                }
              }
            }
          }

          if (subjectAttendance.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('Belum ada riwayat absensi.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                ],
              ),
            );
          }

          // 2. Tampilan Layar (Tombol Cetak + Daftar Absensi)
          return Column(
            children: [
              // --- TOMBOL CETAK PDF ---
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: Colors.indigo,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    try {
                      // Panggil fungsi cetak PDF, bagian nilai dikosongkan (Map kosong {})
                      PdfKhsService.printKHS(
                        studentName: studentName,
                        className: className,
                        semesterName: semesterId, 
                        attendanceData: subjectAttendance,
                        gradesData: {}, // <--- RAHASIANYA DI SINI, DATA NILAI DIKOSONGKAN
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Gagal mencetak PDF: $e'), backgroundColor: Colors.red)
                      );
                    }
                  },
                  icon: const Icon(Icons.print, color: Colors.white),
                  label: const Text('Cetak Laporan Absensi (PDF)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),

              // --- DAFTAR KARTU ABSENSI ---
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  children: subjectAttendance.entries.map((entry) {
                    final subject = entry.key;
                    final stats = entry.value;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200)
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject.toUpperCase(), 
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)
                            ),
                            const Divider(height: 30),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildMiniStat('Hadir', stats['hadir']!, Colors.green),
                                _buildMiniStat('Izin', stats['izin']!, Colors.blue),
                                _buildMiniStat('Sakit', stats['sakit']!, Colors.orange),
                                _buildMiniStat('Alpa', stats['alpa']!, Colors.red),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Komponen pembuat indikator lingkaran angka
  Widget _buildMiniStat(String title, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1), 
            shape: BoxShape.circle
          ),
          child: Text(
            count.toString(), 
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title, 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)
        ),
      ],
    );
  }
}