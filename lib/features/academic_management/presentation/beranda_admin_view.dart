import 'dart:convert'; 
import 'dart:io';
import 'package:flutter/services.dart'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart'; // TAMBAHAN: Package untuk import file JSON

// PENTING: Sesuaikan path import ini dengan lokasi file riwayat_backup_page.dart Anda
import 'riwayat_backup_page.dart'; 

class BerandaAdminView extends StatefulWidget {
  const BerandaAdminView({super.key});

  @override
  State<BerandaAdminView> createState() => _BerandaAdminViewState();
}

class _BerandaAdminViewState extends State<BerandaAdminView> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  
  String _getTodayString() {
    int weekday = DateTime.now().weekday;
    switch (weekday) {
      case 1: return 'Senin'; case 2: return 'Selasa'; case 3: return 'Rabu';
      case 4: return 'Kamis'; case 5: return 'Jumat'; case 6: return 'Sabtu';
      case 7: return 'Minggu'; default: return 'Senin';
    }
  }

  // =====================================================================
  // 1. FITUR PROFIL & LOGOUT
  // =====================================================================
  void _showProfileMenu(String nama, String email, String role) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.indigo.shade100,
                child: Text(nama.isNotEmpty ? nama[0].toUpperCase() : '?', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.indigo)),
              ),
              const SizedBox(height: 16),
              Text(nama, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(email, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(12)),
                child: Text(role.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
              ),
              const Divider(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.logout),
                  label: const Text('Keluar (Log Out)', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.pop(context); 
                    await FirebaseAuth.instance.signOut(); 
                  },
                ),
              )
            ],
          ),
        );
      },
    );
  }

  // =====================================================================
  // 2. FITUR BACKUP REAL-TIME (KHUSUS DEVELOPER)
  // =====================================================================
  Future<void> _exportRealDatabase() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

    try {
      Map<String, dynamic> backupData = {};
      List<String> collections = ['users', 'classes', 'schedules', 'attendance', 'modules'];
      
      for (String col in collections) {
        var snapshot = await FirebaseFirestore.instance.collection(col).get();
        // Modifikasi kecil: Simpan ID dokumen agar saat Restore susunannya tidak berantakan
        backupData[col] = snapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data();
          data['id'] = doc.id; // Menyisipkan ID ke dalam data
          return data.map((key, value) => MapEntry(key, value.toString()));
        }).toList();
      }

      String jsonBackup = jsonEncode(backupData);
      
      final directory = await getTemporaryDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final File file = File('${directory.path}/Backup_SIAP_$timestamp.json');
      
      await file.writeAsString(jsonBackup);

      if (mounted) Navigator.pop(context); 

      await Share.shareXFiles([XFile(file.path)], text: 'Backup Database SIAP Tgl: ${DateTime.now().toString()}');
      
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal Backup: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // =====================================================================
  // 3. FITUR WIPE DATA (RESET OPERASIONAL HARIAN)
  // =====================================================================
  Future<void> _wipeDataDaily() async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    try {
      final db = FirebaseFirestore.instance;
      final schedules = await db.collection('schedules').where('isAbsent', isEqualTo: true).get();
      
      WriteBatch batch = db.batch();
      for (var doc in schedules.docs) {
        batch.update(doc.reference, {
          'isAbsent': false,
          'substituteTeacherId': null,
          'substituteTeacherName': null,
        });
      }
      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seluruh jadwal guru berhasil di-reset ke normal!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal reset: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // =====================================================================
  // 4. FITUR IMPORT (RESTORE DATABASE) - FITUR BARU
  // =====================================================================
  Future<void> _importDatabaseFromJson() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        // Tampilkan loading screen
        showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

        File file = File(result.files.single.path!);
        String jsonString = await file.readAsString();
        Map<String, dynamic> backupData = jsonDecode(jsonString);
        
        FirebaseFirestore db = FirebaseFirestore.instance;
        WriteBatch batch = db.batch(); // Menggunakan Batch agar proses restore instan

        for (String collectionName in backupData.keys) {
          List<dynamic> documents = backupData[collectionName];
          
          for (var doc in documents) {
            Map<String, dynamic> docData = Map<String, dynamic>.from(doc);
            String? docId = docData['id']; // Ambil ID asli
            docData.remove('id'); // Hapus atribut ID agar tidak masuk sebagai kolom data
            
            DocumentReference docRef;
            if (docId != null) {
              docRef = db.collection(collectionName).doc(docId); // Kembalikan dengan ID asli
            } else {
              docRef = db.collection(collectionName).doc(); // Buat ID baru jika tidak ada
            }
            batch.set(docRef, docData);
          }
        }

        await batch.commit(); // Eksekusi Injeksi Data

        if (mounted) {
          Navigator.pop(context); // Tutup loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Data berhasil dipulihkan (Restore Sukses)!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tutup loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Gagal Restore: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showSubstituteDialog(String scheduleId, String originalTeacherId, String originalTeacherName) async {
    String? selectedSubstituteId;
    String? selectedSubstituteName;
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Tunjuk Guru Pengganti', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Guru Asli: $originalTeacherName', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  const Text('Pilih guru yang sedang kosong/tersedia:'),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'guru').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const CircularProgressIndicator();
                      final availableTeachers = snapshot.data!.docs.where((doc) => doc.id != originalTeacherId).toList();
                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Pilih Guru'),
                        value: selectedSubstituteId,
                        items: availableTeachers.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem(value: doc.id, child: Text(data['name'] ?? 'Tanpa Nama'));
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedSubstituteId = val;
                            selectedSubstituteName = (availableTeachers.firstWhere((d) => d.id == val).data() as Map<String, dynamic>)['name'];
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                  onPressed: () async {
                    if (selectedSubstituteId != null) {
                      await FirebaseFirestore.instance.collection('schedules').doc(scheduleId).update({'isAbsent': true, 'substituteTeacherId': selectedSubstituteId, 'substituteTeacherName': selectedSubstituteName});
                      if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengganti ditugaskan!'), backgroundColor: Colors.green)); }
                    }
                  },
                  child: const Text('Tugaskan', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _markAsAbsent(String scheduleId) async {
    await FirebaseFirestore.instance.collection('schedules').doc(scheduleId).update({'isAbsent': true, 'substituteTeacherId': null, 'substituteTeacherName': null});
  }

  Future<void> _resetSchedule(String scheduleId) async {
    await FirebaseFirestore.instance.collection('schedules').doc(scheduleId).update({'isAbsent': false, 'substituteTeacherId': null, 'substituteTeacherName': null});
  }

  @override
  Widget build(BuildContext context) {
    final today = _getTodayString();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: currentUserId == null 
      ? const Center(child: CircularProgressIndicator())
      : StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
        builder: (context, userSnapshot) {
          
          String userName = 'Memuat...';
          String userEmail = '';
          String rawRole = 'admin';

          if (userSnapshot.hasData && userSnapshot.data!.exists) {
            final data = userSnapshot.data!.data() as Map<String, dynamic>;
            userName = data['name'] ?? 'Admin';
            userEmail = data['email'] ?? '';
            rawRole = data['role'] ?? 'admin';
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                decoration: const BoxDecoration(
                  color: Colors.indigo,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Operasional Hari Ini', style: TextStyle(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('Hari $today', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => _showProfileMenu(userName, userEmail, rawRole),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white24,
                        child: Text(
                          userName[0].toUpperCase(), 
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // ==========================================================
              // PANEL DEVELOPER 
              // ==========================================================
              if (rawRole == 'developer')
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber, width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.2), blurRadius: 8, spreadRadius: 1)]
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.terminal, color: Colors.amber),
                          SizedBox(width: 8),
                          Text('DEVELOPER CONTROL PANEL', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Status: SuperUser (God Mode)\nDatabase: Realtime Sync Active', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                      const SizedBox(height: 16),
                      // TOMBOL 1: BACKUP DATABASE (KUNING)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                          ),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Export Database Asli (JSON)', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: _exportRealDatabase, 
                        ),
                      ),
                      const SizedBox(height: 8),
                      // TOMBOL 2: RIWAYAT BACKUP OTOMATIS (BIRU)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade800,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                          ),
                          icon: const Icon(Icons.history),
                          label: const Text('Lihat Riwayat Backup Server', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const RiwayatBackupPage()),
                            );
                          }, 
                        ),
                      ),
                      const SizedBox(height: 8),
                      // TOMBOL 3: WIPE DATA (MERAH)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade900,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                          ),
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('WIPE DATA: Reset Jadwal', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: _wipeDataDaily, 
                        ),
                      ),
                      const SizedBox(height: 8),
                      // TOMBOL 4: IMPORT DATA RESTORE (HIJAU) - TAMBAHAN BARU
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                          ),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('IMPORT DATA: Restore JSON', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: _importDatabaseFromJson, 
                        ),
                      ),
                    ],
                  ),
                ),
              // ==========================================================

              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text('Pantauan Jadwal Kelas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              ),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('schedules').where('day', isEqualTo: today).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_busy, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text('Tidak ada jadwal kelas untuk hari $today', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                          ],
                        ),
                      );
                    }

                    final schedules = snapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: schedules.length,
                      itemBuilder: (context, index) {
                        final doc = schedules[index];
                        final data = doc.data() as Map<String, dynamic>;
                        
                        final scheduleId = doc.id;
                        final className = data['className'] ?? 'Kelas';
                        final subjectName = data['subjectName'] ?? 'Mapel';
                        final teacherName = data['teacherName'] ?? 'Guru';
                        final teacherId = data['teacherId'] ?? '';
                        
                        final isAbsent = data['isAbsent'] ?? false;
                        final substituteName = data['substituteTeacherName'];
                        
                        Color statusColor = Colors.green;
                        String statusText = 'Normal';
                        IconData statusIcon = Icons.check_circle;

                        if (isAbsent && substituteName == null) {
                          statusColor = Colors.red;
                          statusText = 'Guru Kosong (Butuh Pengganti)';
                          statusIcon = Icons.warning;
                        } else if (isAbsent && substituteName != null) {
                          statusColor = Colors.orange;
                          statusText = 'Digantikan oleh $substituteName';
                          statusIcon = Icons.swap_horiz;
                        }

                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text('$className - $subjectName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), overflow: TextOverflow.ellipsis),
                                    ),
                                    const SizedBox(width: 8), 
                                    Chip(
                                      backgroundColor: statusColor.withOpacity(0.1),
                                      label: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(statusIcon, color: statusColor, size: 16),
                                          const SizedBox(width: 4),
                                          Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)), 
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('Guru Utama: $teacherName', style: const TextStyle(fontSize: 14, color: Colors.black87)),
                                const Divider(height: 24),
                                
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (!isAbsent) ...[
                                      OutlinedButton.icon(
                                        onPressed: () => _markAsAbsent(scheduleId),
                                        icon: const Icon(Icons.person_off, color: Colors.red),
                                        label: const Text('Tandai Kosong', style: TextStyle(color: Colors.red)),
                                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                                      ),
                                    ] else if (isAbsent && substituteName == null) ...[
                                      ElevatedButton.icon(
                                        onPressed: () => _showSubstituteDialog(scheduleId, teacherId, teacherName),
                                        icon: const Icon(Icons.person_add),
                                        label: const Text('Tunjuk Pengganti'),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(onPressed: () => _resetSchedule(scheduleId), child: const Text('Batalkan', style: TextStyle(color: Colors.grey))),
                                    ] else ...[
                                      TextButton.icon(onPressed: () => _resetSchedule(scheduleId), icon: const Icon(Icons.refresh), label: const Text('Kembalikan ke Normal')),
                                    ]
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}