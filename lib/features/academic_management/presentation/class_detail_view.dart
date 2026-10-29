import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Import Provider CSV-mu di sini
import 'import_csv_provider.dart'; 
// Import layar registrasi wajah AI
import 'RegisterStudentScreen.dart';

class ClassDetailView extends ConsumerStatefulWidget {
  final dynamic classData; 

  const ClassDetailView({super.key, required this.classData});

  @override
  ConsumerState<ClassDetailView> createState() => _ClassDetailViewState();
}

class _ClassDetailViewState extends ConsumerState<ClassDetailView> {
  
  // ===================================================================
  // FUNGSI IMPORT CSV TERBARU (Menggunakan Provider yang Anda miliki)
  // ===================================================================
  Future<void> _handleImportCSV() async {
    final classId = widget.classData.id;
    final className = widget.classData.name;

    // Menampilkan loading indikator
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (c) => const Center(child: CircularProgressIndicator())
    );
    
    try {
      final successCount = await ref.read(importCsvControllerProvider.notifier).importStudentsToClass(classId);
      
      if (context.mounted) {
        Navigator.pop(context); // Tutup loading dialog

        if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Berhasil mengimpor $successCount siswa ke kelas $className!'), backgroundColor: Colors.green)
          );
        } else {
          // Jika pengguna menekan tombol batal saat memilih file
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Proses dibatalkan atau data kosong.'), backgroundColor: Colors.orange)
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Tutup loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengimpor data: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final classId = widget.classData.id;
    final className = widget.classData.name; 

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50, // Latar belakang lebih bersih
        appBar: AppBar(
          title: Text('Data Kelas: $className', style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.amber, // Garis bawah tab berwarna emas
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'Daftar Siswa'),
              Tab(icon: Icon(Icons.calendar_month), text: 'Jadwal & Mapel'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ==========================================
            // TAB 1: DAFTAR SISWA (Dengan Desain Baru & AI)
            // ==========================================
            Column(
              children: [
                // TOMBOL IMPORT CSV DI BAGIAN ATAS (Lebih mudah diakses)
                Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 4, offset: const Offset(0, 2))]
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _handleImportCSV, 
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import Data Siswa (CSV)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
                
                const SizedBox(height: 8),

                // DAFTAR SISWA
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('classes').doc(classId).collection('students').orderBy('name').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.group_off_outlined, size: 80, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text('Belum ada siswa di kelas $className', style: TextStyle(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              const Text('Silakan tekan tombol Import di atas.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          final doc = snapshot.data!.docs[index];
                          final data = doc.data() as Map<String, dynamic>;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              // Avatar inisial nama (foto wajah tidak disimpan)
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.indigo.shade50,
                                child: Text(data['name'][0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 20))
                              ),
                              title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              subtitle: Text(data['email'] ?? data['nis'] ?? '-'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // TOMBOL AI ANDA
                                  IconButton(
                                    icon: const Icon(Icons.camera_front, color: Colors.indigo),
                                    tooltip: 'Daftarkan Wajah ke AI',
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => RegisterStudentScreen(
                                            initialNim: data['email'] ?? data['nis'] ?? '',
                                            initialName: data['name'],
                                            classId: classId, 
                                            studentDocId: doc.id, 
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // TOMBOL HAPUS
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: 'Hapus Siswa',
                                    onPressed: () => FirebaseFirestore.instance.collection('classes').doc(classId).collection('students').doc(doc.id).delete(),
                                  ),
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
            ),

            // ==========================================
            // TAB 2: JADWAL & MATA PELAJARAN (KODE ANDA TETAP AMAN)
            // ==========================================
            Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('schedules').where('classId', isEqualTo: classId).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Belum ada jadwal untuk kelas ini.'));

                      return ListView.builder(
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          final doc = snapshot.data!.docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.book, color: Colors.white)),
                              title: Text(data['subjectName'], style: const TextStyle(fontWeight: FontWeight.bold)),
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
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => _AddScheduleDialog(classId: classId, className: className),
                      );
                    },
                    icon: const Icon(Icons.add_alarm),
                    label: const Text('Tambah Jadwal Mapel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FORM TAMBAH JADWAL (KODE ANDA TETAP SAMA PERSIS)
// ============================================================================
class _AddScheduleDialog extends StatefulWidget {
  final String classId;
  final String className;
  const _AddScheduleDialog({required this.classId, required this.className});

  @override
  State<_AddScheduleDialog> createState() => _AddScheduleDialogState();
}

class _AddScheduleDialogState extends State<_AddScheduleDialog> {
  bool isLoading = true;
  List<QueryDocumentSnapshot> allTeachersData = []; 
  List<DropdownMenuItem<String>> filteredTeacherItems = [];
  
  final subjectController = TextEditingController(); 
  String? selectedTeacherId;
  String? selectedTeacherName;
  String selectedDay = 'Senin';
  final startTimeController = TextEditingController(text: '08:00');
  final endTimeController = TextEditingController(text: '09:30');
  final List<String> days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];

  @override
  void initState() {
    super.initState();
    _fetchTeachers();
    subjectController.addListener(() {
      _filterDropdownGuru(); 
    });
  }

  @override
  void dispose() {
    subjectController.dispose();
    startTimeController.dispose();
    endTimeController.dispose();
    super.dispose();
  }

  Future<void> _fetchTeachers() async {
    try {
      final usersSnap = await FirebaseFirestore.instance.collection('users').get();
      if (mounted) {
        setState(() {
          allTeachersData = usersSnap.docs.where((doc) {
            final data = doc.data();
            return (data['role'] ?? '').toString().toLowerCase() == 'guru';
          }).toList();
          isLoading = false;
        });
        _filterDropdownGuru();
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _filterDropdownGuru() {
    setState(() {
      filteredTeacherItems = allTeachersData.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final name = data['name'] ?? 'Tanpa Nama';
        final spec = data['specialty'] ?? 'Umum';
        return DropdownMenuItem<String>(
          value: doc.id,
          child: Text('$name ($spec)'), 
        );
      }).toList();

      if (selectedTeacherId != null) {
        final isStillExist = filteredTeacherItems.any((item) => item.value == selectedTeacherId);
        if (!isStillExist) {
          selectedTeacherId = null;
          selectedTeacherName = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));

    return AlertDialog(
      title: Text('Jadwal untuk ${widget.className}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: subjectController,
              decoration: const InputDecoration(labelText: 'Nama Mapel (Ketik manual, cth: matematika)'),
            ),
            const SizedBox(height: 10),

            if (filteredTeacherItems.isEmpty) 
              const Text('⚠️ Belum ada guru yang terdaftar di database.', style: TextStyle(color: Colors.red)),
            
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Pilih Guru Pengajar'),
              value: selectedTeacherId,
              items: filteredTeacherItems,
              onChanged: (val) {
                setState(() {
                  selectedTeacherId = val;
                  final dataGuru = allTeachersData.firstWhere((doc) => doc.id == val).data() as Map<String, dynamic>;
                  selectedTeacherName = dataGuru['name'];
                });
              },
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
                Expanded(child: TextField(controller: startTimeController, decoration: const InputDecoration(labelText: 'Mulai'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: endTimeController, decoration: const InputDecoration(labelText: 'Selesai'))),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(
          onPressed: () async {
            if (subjectController.text.isNotEmpty && selectedTeacherId != null) {
              await FirebaseFirestore.instance.collection('schedules').add({
                'classId': widget.classId,
                'className': widget.className,
                'subjectName': subjectController.text, 
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
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}