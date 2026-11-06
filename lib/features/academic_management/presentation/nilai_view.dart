import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; 

class NilaiView extends StatefulWidget {
  const NilaiView({super.key});

  @override
  State<NilaiView> createState() => _NilaiViewState();
}

class _NilaiViewState extends State<NilaiView> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  
  String? _selectedSemesterId;
  List<String> _validClassIds = []; 

  String? _selectedScheduleId;
  Map<String, dynamic>? _selectedScheduleData;
  List<QueryDocumentSnapshot> _students = [];
  
  DateTime _selectedDate = DateTime.now();
  
  // ========================================================
  // PERUBAHAN: VARIABEL KATEGORI & TOPIK
  // ========================================================
  String? _selectedCategory;
  final List<String> _categories = ['Tugas', 'Ulangan Harian', 'UTS', 'UAS', 'Bonus'];
  final TextEditingController _topicController = TextEditingController();
  
  final Map<String, TextEditingController> _gradeControllers = {};

  @override
  void initState() {
    super.initState();
    _fetchDefaultSemester(); 
  }

  Future<void> _fetchDefaultSemester() async {
    final snap = await FirebaseFirestore.instance.collection('semesters').where('status', isEqualTo: 'Aktif').get();
    if (snap.docs.isNotEmpty) {
      if (mounted) {
        setState(() => _selectedSemesterId = snap.docs.first.id);
        _fetchClassesForSemester(snap.docs.first.id);
      }
    }
  }

  Future<void> _fetchClassesForSemester(String semesterId) async {
    final snap = await FirebaseFirestore.instance.collection('classes').where('semesterId', isEqualTo: semesterId).get();
    if (mounted) {
      setState(() {
        _validClassIds = snap.docs.map((e) => e.id).toList();
        _selectedScheduleId = null;
        _selectedScheduleData = null;
        _students.clear();
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(), 
      helpText: 'Pilih Tanggal Penilaian',
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _fetchStudents() async {
    if (_selectedScheduleData == null) return;
    final classId = _selectedScheduleData!['classId'];
    List<QueryDocumentSnapshot> foundStudents = [];

    try {
      var snap1 = await FirebaseFirestore.instance.collection('classes').doc(classId).collection('students').get();
      if (snap1.docs.isNotEmpty) {
        foundStudents = snap1.docs;
      } else {
        var snap2 = await FirebaseFirestore.instance.collection('students').where('classId', isEqualTo: classId).get();
        if (snap2.docs.isNotEmpty) {
          foundStudents = snap2.docs;
        } else {
          var snap3 = await FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'siswa').where('classId', isEqualTo: classId).get();
          foundStudents = snap3.docs;
        }
      }

      foundStudents.sort((a, b) {
        final nameA = (a.data() as Map<String, dynamic>)['name']?.toString().toLowerCase() ?? '';
        final nameB = (b.data() as Map<String, dynamic>)['name']?.toString().toLowerCase() ?? '';
        return nameA.compareTo(nameB);
      });

      setState(() {
        _students = foundStudents;
        _gradeControllers.clear();
        for (var doc in _students) {
          _gradeControllers[doc.id] = TextEditingController();
        }
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengambil data siswa: $e')));
    }
  }

  Future<void> _saveGrades() async {
    FocusScope.of(context).unfocus();
    if (_selectedScheduleData == null) return;

    // VALIDASI KATEGORI
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih Kategori Nilai terlebih dahulu!'), backgroundColor: Colors.orange));
      return;
    }
    
    final classId = _selectedScheduleData!['classId'];
    final subjectName = _selectedScheduleData!['subjectName'];
    final topic = _topicController.text.trim();
    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
    
    // ID unik gabungan agar tidak bentrok
    final docId = 'grade_${classId}_${subjectName}_${formattedDate}_$_selectedCategory'; 

    Map<String, int> scoresToSave = {};
    for (var entry in _gradeControllers.entries) {
      final scoreText = entry.value.text.trim();
      if (scoreText.isNotEmpty) {
        scoresToSave[entry.key] = int.tryParse(scoreText) ?? 0;
      }
    }

    if (scoresToSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Belum ada nilai yang diinput!'), backgroundColor: Colors.orange));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('activity_grades').doc(docId).set({
        'classId': classId,
        'className': _selectedScheduleData!['className'],
        'subjectName': subjectName,
        'teacherId': currentUserId,
        
        // MENYIMPAN DATA DENGAN FORMAT BARU
        'category': _selectedCategory, 
        'topic': topic.isEmpty ? '-' : topic,
        'activityName': _selectedCategory, // Disamakan dengan kategori agar tidak error di widget lain
        
        'date': formattedDate,
        'scores': scoresToSave, 
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text('Nilai "$_selectedCategory" berhasil disimpan!')),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          )
        );
        setState(() {
          _topicController.clear();
          for (var controller in _gradeControllers.values) controller.clear();
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  void dispose() {
    _topicController.dispose();
    for (var controller in _gradeControllers.values) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) return const Scaffold(body: Center(child: Text('Belum login.')));

    return Scaffold(
      backgroundColor: Colors.grey.shade100, 
      appBar: AppBar(
        title: const Text('Input Nilai', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER CARD
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Column(
              children: [
                // 1. FILTER SEMESTER
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('semesters').orderBy('createdAt', descending: true).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();
                    final semesters = snapshot.data!.docs;

                    return DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: '1. Filter Semester',
                        labelStyle: TextStyle(color: Colors.indigo.shade400, fontWeight: FontWeight.w600),
                        filled: true,
                        fillColor: Colors.indigo.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.history, color: Colors.indigo),
                      ),
                      value: _selectedSemesterId,
                      items: semesters.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final isAktif = data['status'] == 'Aktif';
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text('${data['name']} ${isAktif ? '(Aktif)' : '(Arsip)'}', style: TextStyle(fontWeight: isAktif ? FontWeight.bold : FontWeight.normal)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedSemesterId = val);
                          _fetchClassesForSemester(val);
                        }
                      },
                    );
                  }
                ),
                const SizedBox(height: 12),

                // 2. PILIH JADWAL
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('schedules').where('teacherId', isEqualTo: currentUserId).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    
                    final allSchedules = snapshot.data?.docs ?? [];
                    final validSchedules = allSchedules.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return _validClassIds.contains(data['classId']);
                    }).toList();

                    if (validSchedules.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Tidak ada jadwal mengajar di semester ini.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      );
                    }

                    return DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: '2. Pilih Kelas & Mapel',
                        labelStyle: TextStyle(color: Colors.indigo.shade400, fontWeight: FontWeight.w600),
                        filled: true,
                        fillColor: Colors.indigo.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.school, color: Colors.indigo),
                      ),
                      value: _selectedScheduleId,
                      items: validSchedules.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text('${data['className']} - ${data['subjectName']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedScheduleId = val;
                          _selectedScheduleData = validSchedules.firstWhere((d) => d.id == val).data() as Map<String, dynamic>;
                        });
                        _fetchStudents();
                      },
                    );
                  }
                ),
                const SizedBox(height: 12),
                
                // 3. KATEGORI & TANGGAL
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: '3. Kategori Nilai',
                          labelStyle: TextStyle(color: Colors.indigo.shade400, fontWeight: FontWeight.w600),
                          filled: true,
                          fillColor: Colors.indigo.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          prefixIcon: const Icon(Icons.category, color: Colors.indigo),
                        ),
                        value: _selectedCategory,
                        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                        onChanged: (val) => setState(() => _selectedCategory = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: () => _selectDate(context),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: '4. Tanggal',
                            labelStyle: TextStyle(color: Colors.indigo.shade400, fontWeight: FontWeight.w600),
                            filled: true,
                            fillColor: Colors.indigo.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat('dd MMM').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const Icon(Icons.calendar_today, size: 18, color: Colors.indigo),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // 4. KETERANGAN / TOPIK
                TextField(
                  controller: _topicController,
                  decoration: InputDecoration(
                    labelText: '5. Keterangan Topik / Bab (Opsional)',
                    hintText: 'Cth: Gaya Gravitasi',
                    labelStyle: TextStyle(color: Colors.indigo.shade400, fontWeight: FontWeight.w600),
                    filled: true,
                    fillColor: Colors.indigo.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.description, color: Colors.indigo),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // DAFTAR MURID
          Expanded(
            child: _selectedScheduleId == null 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_ind, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('Tentukan Jadwal & Kategori terlebih dahulu.', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                    ],
                  ),
                )
              : _students.isEmpty
                ? const Center(child: Text('Belum ada siswa di kelas ini.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80, top: 8), 
                    itemCount: _students.length,
                    itemBuilder: (ctx, i) {
                      final student = _students[i].data() as Map<String, dynamic>;
                      final studentId = _students[i].id;
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 8, spreadRadius: 1, offset: const Offset(0, 2))],
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.indigo.shade50,
                              child: Text(student['name'][0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(student['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text('Siswa', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                            
                            SizedBox(
                              width: 70,
                              height: 50,
                              child: TextField(
                                controller: _gradeControllers[studentId],
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next, 
                                textAlign: TextAlign.center,
                                maxLength: 3,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo),
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: '-',
                                  hintStyle: TextStyle(color: Colors.grey.shade400),
                                  filled: true,
                                  fillColor: Colors.grey.shade100,
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _students.isNotEmpty 
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FloatingActionButton.extended(
              onPressed: _saveGrades,
              backgroundColor: Colors.indigo,
              elevation: 4,
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text('Simpan Nilai', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ) 
        : null,
    );
  }
}