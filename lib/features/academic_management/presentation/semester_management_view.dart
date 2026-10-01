import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'semester_detail_view.dart'; 

class SemesterManagementView extends StatefulWidget {
  const SemesterManagementView({super.key});

  @override
  State<SemesterManagementView> createState() => _SemesterManagementViewState();
}

class _SemesterManagementViewState extends State<SemesterManagementView> {

  void _addSemesterDialog(BuildContext context) {
    final nameController = TextEditingController();
    bool autoGenerateClasses = true; 

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
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nama Semester (cth: Genap 2026)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                  child: SwitchListTile(
                    title: const Text('Generate Kelas Otomatis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Salin semua kelas dari semester sebelumnya ke semester ini.', style: TextStyle(fontSize: 12)),
                    value: autoGenerateClasses,
                    activeColor: Colors.indigo,
                    onChanged: (bool value) {
                      setState(() => autoGenerateClasses = value);
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: () async {
                  if (nameController.text.isEmpty) return;
                  
                  // KUNCI ANTI NYANGKUT: Simpan Navigator & Messenger di awal
                  final navigator = Navigator.of(ctx, rootNavigator: true);
                  final messenger = ScaffoldMessenger.of(ctx);
                  
                  showDialog(
                    context: ctx, 
                    barrierDismissible: false, 
                    builder: (c) => const Center(child: CircularProgressIndicator())
                  );

                  try {
                    final db = FirebaseFirestore.instance;

                    QuerySnapshot oldSemesters = await db.collection('semesters').where('status', isEqualTo: 'Aktif').get();
                    String? oldSemesterId;
                    if (oldSemesters.docs.isNotEmpty) {
                      oldSemesterId = oldSemesters.docs.first.id;
                      await db.collection('semesters').doc(oldSemesterId).update({'status': 'Arsip'});
                    }

                    DocumentReference newSemesterRef = await db.collection('semesters').add({
                      'name': nameController.text.trim(),
                      'status': 'Aktif',
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    if (autoGenerateClasses && oldSemesterId != null) {
                      QuerySnapshot oldClasses = await db.collection('classes').where('semesterId', isEqualTo: oldSemesterId).get();
                      
                      for (var oldClass in oldClasses.docs) {
                        Map<String, dynamic> classData = oldClass.data() as Map<String, dynamic>;
                        classData['semesterId'] = newSemesterRef.id;
                        classData['createdAt'] = FieldValue.serverTimestamp();
                        classData.remove('id'); 
                        
                        DocumentReference newlyCreatedClass = await db.collection('classes').add(classData);
                        await newlyCreatedClass.update({'id': newlyCreatedClass.id});
                      }
                    }

                    navigator.pop(); // Tutup Loading
                    navigator.pop(); // Tutup Form
                    messenger.showSnackBar(const SnackBar(content: Text('Semester & Kelas berhasil dibuat!'), backgroundColor: Colors.green));

                  } catch (e) {
                    navigator.pop(); // Tutup Loading
                    messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                },
                child: const Text('Simpan & Generate', style: TextStyle(color: Colors.white)),
              )
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSemesterDialog(context),
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Tambah Semester', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('semesters').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  const Text('Tidak ada semester.\nSilakan tambah baru.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ],
              )
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              bool isAktif = data['status'] == 'Aktif';

              return Card(
                elevation: isAktif ? 3 : 1, 
                color: isAktif ? Colors.white : Colors.grey.shade100, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isAktif ? Colors.indigo.shade50 : Colors.grey.shade300, 
                      shape: BoxShape.circle
                    ),
                    child: Icon(Icons.school, color: isAktif ? Colors.indigo : Colors.grey.shade600),
                  ),
                  title: Text(data['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isAktif ? Colors.black : Colors.grey.shade700)),
                  subtitle: Text(
                    isAktif ? 'Semester Sedang Aktif' : 'Riwayat (Arsip)', 
                    style: TextStyle(color: isAktif ? Colors.green : Colors.grey, fontWeight: FontWeight.w600)
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isAktif) 
                        IconButton(
                          icon: const Icon(Icons.archive, color: Colors.orange),
                          tooltip: 'Arsipkan Semester',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Arsipkan Semester?'),
                                content: Text('Semester "${data['name']}" akan dipindahkan ke Arsip.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                    onPressed: () {
                                      FirebaseFirestore.instance.collection('semesters').doc(doc.id).update({'status': 'Arsip'});
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text('Arsipkan', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              )
                            );
                          },
                        )
                      else ...[
                        IconButton(
                          icon: const Icon(Icons.restore, color: Colors.blue),
                          tooltip: 'Aktifkan Kembali',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Aktifkan Semester?'),
                                content: Text('Jadikan semester "${data['name']}" aktif kembali?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                                    onPressed: () {
                                      FirebaseFirestore.instance.collection('semesters').doc(doc.id).update({'status': 'Aktif'});
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text('Aktifkan', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              )
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Hapus Semester',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Hapus Semester Permanen?'),
                                content: Text('Anda yakin ingin menghapus semester beserta SEMUA data di dalamnya?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                                  
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () async {
                                      // KUNCI ANTI NYANGKUT: Simpan Navigator & Messenger di awal sebelum async
                                      final navigator = Navigator.of(context, rootNavigator: true);
                                      final messenger = ScaffoldMessenger.of(context);

                                      // 1. Tutup dialog konfirmasi (pilih "Hapus")
                                      Navigator.pop(ctx);
                                      
                                      // 2. Munculkan Loading Screen
                                      showDialog(
                                        context: context, 
                                        barrierDismissible: false, 
                                        builder: (c) => const Center(child: CircularProgressIndicator())
                                      );

                                      try {
                                        final db = FirebaseFirestore.instance;
                                        final semesterId = doc.id;
                                        
                                        // 3. Hapus kelas, siswa, dan jadwal terkait
                                        final classesSnap = await db.collection('classes').where('semesterId', isEqualTo: semesterId).get();
                                        for (var classDoc in classesSnap.docs) {
                                          final classId = classDoc.id;
                                          
                                          final studentsSnap = await db.collection('classes').doc(classId).collection('students').get();
                                          for (var studentDoc in studentsSnap.docs) {
                                            await studentDoc.reference.delete();
                                          }

                                          final schedulesSnap = await db.collection('schedules').where('classId', isEqualTo: classId).get();
                                          for (var scheduleDoc in schedulesSnap.docs) {
                                            await scheduleDoc.reference.delete();
                                          }
                                          
                                          await classDoc.reference.delete();
                                        }
                                        
                                        // 4. Hapus semester
                                        await db.collection('semesters').doc(semesterId).delete();
                                        
                                        // 5. Tutup Loading dengan aman (walau layar di belakangnya sudah hancur)
                                        navigator.pop(); 
                                        messenger.showSnackBar(
                                          const SnackBar(content: Text('Sapu Bersih Sukses! Data dihapus.'), backgroundColor: Colors.green)
                                        );
                                      } catch (e) {
                                        navigator.pop(); 
                                        messenger.showSnackBar(
                                          SnackBar(content: Text('Gagal menghapus data: $e'), backgroundColor: Colors.red)
                                        );
                                      }
                                    },
                                    child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              )
                            );
                          },
                        ),
                      ],
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => SemesterDetailView(semesterId: doc.id, semesterName: data['name'])));
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