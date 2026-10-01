import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/academic_models.dart'; 
import 'class_detail_view.dart';

class ClassManagementView extends ConsumerStatefulWidget {
  const ClassManagementView({super.key});

  @override
  ConsumerState<ClassManagementView> createState() => _ClassManagementViewState();
}

class _ClassManagementViewState extends ConsumerState<ClassManagementView> {
  
  // ==========================================================
  // FUNGSI 1: TAMBAH KELAS
  // ==========================================================
  void _showAddClassDialog(BuildContext context) {
    final nameController = TextEditingController();
    final levelController = TextEditingController();
    String? selectedSemesterId;
    String? selectedWaliKelasId;
    String? selectedWaliKelasName;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Tambah Ruang Kelas', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nama Kelas (Contoh: IPA 1)', border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: levelController,
                      decoration: const InputDecoration(labelText: 'Tingkat (Contoh: 10)', border: OutlineInputBorder(), isDense: true),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('semesters').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final semesters = snapshot.data!.docs;
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Pilih Semester', border: OutlineInputBorder(), isDense: true),
                          value: selectedSemesterId,
                          items: semesters.map((s) => DropdownMenuItem(value: s.id, child: Text(s['name']))).toList(),
                          onChanged: (val) => setState(() => selectedSemesterId = val),
                        );
                      }
                    ),
                    const SizedBox(height: 12),

                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'guru').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final gurus = snapshot.data!.docs;
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Pilih Wali Kelas (Opsional)', border: OutlineInputBorder(), isDense: true),
                          value: selectedWaliKelasId,
                          items: gurus.map((g) {
                            final data = g.data() as Map<String, dynamic>;
                            return DropdownMenuItem(value: g.id, child: Text(data['name'] ?? 'Guru Tanpa Nama'));
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedWaliKelasId = val;
                              selectedWaliKelasName = (gurus.firstWhere((g) => g.id == val).data() as Map<String, dynamic>)['name'];
                            });
                          },
                        );
                      }
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: () {
                    if (nameController.text.isNotEmpty && selectedSemesterId != null) {
                      final docRef = FirebaseFirestore.instance.collection('classes').doc();
                      docRef.set({
                        'id': docRef.id,
                        'name': nameController.text.trim(),
                        'level': levelController.text.trim(),
                        'semesterId': selectedSemesterId,
                        'homeroomTeacherId': selectedWaliKelasId,
                        'homeroomTeacherName': selectedWaliKelasName,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kelas berhasil ditambahkan!'), backgroundColor: Colors.green));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama Kelas dan Semester wajib diisi!'), backgroundColor: Colors.red));
                    }
                  },
                  child: const Text('Simpan'),
                )
              ]
            );
          }
        );
      }
    );
  }

  // ==========================================================
  // FUNGSI 2: EDIT KELAS (GANTI WALI KELAS) -> SOLUSI GURU DEWI
  // ==========================================================
  void _showEditClassDialog(BuildContext context, String classId, Map<String, dynamic> currentData) {
    final nameController = TextEditingController(text: currentData['name']);
    final levelController = TextEditingController(text: currentData['level']?.toString() ?? '');
    String? selectedSemesterId = currentData['semesterId'];
    String? selectedWaliKelasId = currentData['homeroomTeacherId'];
    String? selectedWaliKelasName = currentData['homeroomTeacherName'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Kelas & Wali Kelas', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nama Kelas', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 12),
                    TextField(controller: levelController, decoration: const InputDecoration(labelText: 'Tingkat', border: OutlineInputBorder(), isDense: true), keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('semesters').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final semesters = snapshot.data!.docs;
                        
                        // Cek apakah semester lama masih ada di database
                        bool semesterExists = semesters.any((s) => s.id == selectedSemesterId);
                        if (!semesterExists) selectedSemesterId = null;

                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Pilih Semester', border: OutlineInputBorder(), isDense: true),
                          value: selectedSemesterId,
                          items: semesters.map((s) => DropdownMenuItem(value: s.id, child: Text(s['name']))).toList(),
                          onChanged: (val) => setState(() => selectedSemesterId = val),
                        );
                      }
                    ),
                    const SizedBox(height: 12),

                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'guru').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const CircularProgressIndicator();
                        final gurus = snapshot.data!.docs;

                        // KECERDASAN ANTI-CRASH: Cek apakah guru lama (ex: Dewi) sudah dihapus?
                        bool teacherExists = gurus.any((g) => g.id == selectedWaliKelasId);
                        if (!teacherExists && selectedWaliKelasId != null) {
                          selectedWaliKelasId = null; // Reset ke null agar dropdown tidak crash
                          selectedWaliKelasName = null;
                        }

                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Ganti Wali Kelas (Opsional)', border: OutlineInputBorder(), isDense: true),
                          value: selectedWaliKelasId,
                          items: gurus.map((g) {
                            final data = g.data() as Map<String, dynamic>;
                            return DropdownMenuItem(value: g.id, child: Text(data['name'] ?? 'Guru Tanpa Nama'));
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedWaliKelasId = val;
                              selectedWaliKelasName = (gurus.firstWhere((g) => g.id == val).data() as Map<String, dynamic>)['name'];
                            });
                          },
                        );
                      }
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  onPressed: () async {
                    if (nameController.text.isNotEmpty && selectedSemesterId != null) {
                      await FirebaseFirestore.instance.collection('classes').doc(classId).update({
                        'name': nameController.text.trim(),
                        'level': levelController.text.trim(),
                        'semesterId': selectedSemesterId,
                        'homeroomTeacherId': selectedWaliKelasId, // Update Guru Baru
                        'homeroomTeacherName': selectedWaliKelasName,
                      });
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perubahan kelas berhasil disimpan!'), backgroundColor: Colors.green));
                      }
                    }
                  },
                  child: const Text('Update Data'),
                )
              ]
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        onPressed: () => _showAddClassDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Kelas'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('classes').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Belum ada data kelas.'));

          final classes = snapshot.data!.docs;

          return ListView.builder(
            itemCount: classes.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) {
              final doc = classes[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final classId = doc.id;
              final className = data['name'] ?? 'Tanpa Nama';
              final level = data['level'] ?? '-';
              final semesterId = (data['semesterId'] ?? '').toString().trim();
              final waliKelasName = data['homeroomTeacherName'] ?? 'Belum Ditugaskan / Kosong'; // Peringatan jika kosong

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: const Icon(Icons.door_front_door, color: Colors.indigo),
                  ),
                  title: Text(className, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  
                  subtitle: semesterId.isEmpty 
                      ? Text('Tingkat: $level\nWali Kelas: $waliKelasName', style: const TextStyle(fontSize: 12, color: Colors.black87))
                      : FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('semesters').doc(semesterId).get(),
                          builder: (context, semSnapshot) {
                            if (semSnapshot.connectionState == ConnectionState.waiting) {
                              return Text('Tingkat: $level\nWali Kelas: $waliKelasName\nMemuat semester...', style: const TextStyle(fontSize: 12));
                            }
                            if (!semSnapshot.hasData || !semSnapshot.data!.exists) {
                              return Text('Tingkat: $level\nWali Kelas: $waliKelasName\nSemester Dihapus', style: const TextStyle(fontSize: 12, color: Colors.red));
                            }
                            
                            final semData = semSnapshot.data!.data() as Map<String, dynamic>;
                            final semName = semData['name'] ?? 'Unknown';
                            
                            return Text(
                              'Tingkat: $level\nWali Kelas: $waliKelasName\nSemester: $semName',
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            );
                          },
                        ),
                  
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ==========================================
                      // TOMBOL EDIT KELAS (PENSIL BIRU)
                      // ==========================================
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        tooltip: 'Edit Kelas & Ganti Wali',
                        onPressed: () => _showEditClassDialog(context, classId, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Hapus Kelas',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Hapus Kelas?', style: TextStyle(fontWeight: FontWeight.bold)),
                              content: Text('Yakin ingin menghapus kelas "$className"? Semua data jadwal di dalamnya bisa rusak.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(color: Colors.grey))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () {
                                    FirebaseFirestore.instance.collection('classes').doc(classId).delete();
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kelas berhasil dihapus.'), backgroundColor: Colors.green));
                                  },
                                  child: const Text('Hapus Permanen', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            )
                          );
                        },
                      ),
                    ],
                  ),
                  
                  onTap: () {
                    final classModelDummy = ClassModel(
                      id: classId,
                      name: className,
                      level: level.toString(), 
                      semesterId: semesterId,
                    );

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ClassDetailView(classData: classModelDummy),
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