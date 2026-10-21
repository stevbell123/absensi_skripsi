import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'attendance_providers.dart';
import '../widgets/pdf_export_service.dart';
import '../models/attendance_model.dart';
import 'AttendanceScreen.dart';
import '../../research/research_config.dart';
import '../../research/research_logger.dart';
import '../../research/presentation/research_settings_sheet.dart';

class AttendanceView extends ConsumerStatefulWidget {
  const AttendanceView({super.key});

  @override
  ConsumerState<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends ConsumerState<AttendanceView> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  
  String? _selectedScheduleId;
  Map<String, dynamic>? _selectedScheduleData;
  DateTime _selectedDate = DateTime.now();
  List<AttendanceRecord> _records = [];
  bool _isLoadingData = false;
  bool _isSubstituteMode = false;

  // --- Mode Penelitian (RM 3): pencatatan sesi absensi wajah vs manual ---
  // Sesi dimulai saat daftar siswa tampil dan berakhir saat "Simpan Absensi".
  // Jika scan wajah dipakai, status hasil scan disimpan untuk menghitung koreksi guru.
  String? _sesiId;
  DateTime? _sesiMulai;
  Duration _durasiScan = Duration.zero;
  Map<String, AttendanceStatus>? _statusSetelahScan;

  String get _formattedDate => DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    ResearchConfig.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _mulaiSesi() {
    _sesiId = 'sesi_${DateTime.now().millisecondsSinceEpoch}';
    _sesiMulai = DateTime.now();
    _durasiScan = Duration.zero;
    _statusSetelahScan = null;
  }

  Future<void> _catatSesi() async {
    if (!ResearchConfig.aktif || _sesiMulai == null) return;

    final selesai = DateTime.now();
    final scan = _statusSetelahScan;
    final bool pakaiWajah = scan != null;
    final int n = _records.length;

    int koreksiTotal = 0, jadiHadir = 0, batalHadir = 0;
    if (scan != null) {
      for (final r in _records) {
        final statusScan = scan[r.studentId];
        if (statusScan == null) continue;
        if (statusScan != r.status) koreksiTotal++;
        final scanHadir = statusScan == AttendanceStatus.hadir;
        final akhirHadir = r.status == AttendanceStatus.hadir;
        if (!scanHadir && akhirHadir) jadiHadir++; // terlewat oleh scan
        if (scanHadir && !akhirHadir) batalHadir++; // salah ditandai hadir oleh scan
      }
    }

    double detik(Duration d) => double.parse((d.inMilliseconds / 1000).toStringAsFixed(1));

    await ResearchLogger.catatSesi({
      'sesi_id': _sesiId,
      'waktu_mulai': _sesiMulai!.toIso8601String(),
      'waktu_selesai': selesai.toIso8601String(),
      'metode': pakaiWajah ? 'wajah' : 'manual',
      'kelas': _selectedScheduleData?['className'] ?? '',
      'mapel': _selectedScheduleData?['subjectName'] ?? '',
      'tanggal': _formattedDate,
      'jumlah_siswa': n,
      'durasi_total_detik': detik(selesai.difference(_sesiMulai!)),
      'durasi_scan_detik': pakaiWajah ? detik(_durasiScan) : '',
      'hadir_hasil_scan':
          scan != null ? scan.values.where((s) => s == AttendanceStatus.hadir).length : '',
      'hadir_akhir': _records.where((r) => r.status == AttendanceStatus.hadir).length,
      'koreksi_total': pakaiWajah ? koreksiTotal : '',
      'koreksi_jadi_hadir': pakaiWajah ? jadiHadir : '',
      'koreksi_batal_hadir': pakaiWajah ? batalHadir : '',
      'akurasi_scan_persen': pakaiWajah && n > 0
          ? double.parse(((n - jadiHadir - batalHadir) * 100 / n).toStringAsFixed(2))
          : '',
      'kondisi_cahaya': ResearchConfig.kondisiCahaya,
      'clahe': pakaiWajah ? (ResearchConfig.efektifClahe ? 1 : 0) : '',
      'mode_verifikasi': pakaiWajah ? ResearchConfig.labelVerifikasi : '',
    });
    _sesiMulai = null;
  }

  int _getDayOfWeek(String dayName) {
    switch (dayName.toLowerCase().trim()) {
      case 'senin': return DateTime.monday;
      case 'selasa': return DateTime.tuesday;
      case 'rabu': return DateTime.wednesday;
      case 'kamis': return DateTime.thursday;
      case 'jumat': return DateTime.friday;
      case 'sabtu': return DateTime.saturday;
      case 'minggu': return DateTime.sunday;
      default: return 0;
    }
  }

  Future<void> _fetchAttendanceData() async {
    if (_selectedScheduleId == null || _selectedScheduleData == null) return;
    setState(() => _isLoadingData = true);
    
    try {
      final dataSource = ref.read(attendanceDataSourceProvider);
      final classId = _selectedScheduleData!['classId'];
      
      final existingData = await dataSource.getAttendance(_selectedScheduleId!, _formattedDate);
      
      if (existingData != null) {
        setState(() => _records = existingData.records);
      } else {
        final students = await dataSource.getStudentsByClass(classId);
        setState(() {
          _records = students.map((s) => AttendanceRecord(
            studentId: s.id,
            studentName: s.name,
            status: AttendanceStatus.alpa
          )).toList();
        });
      }
      _mulaiSesi();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e')));
      setState(() => _records = []);
    } finally {
      setState(() => _isLoadingData = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    if (_selectedScheduleData == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih jadwal mapel terlebih dahulu!')));
      return;
    }

    final targetDayString = _selectedScheduleData!['day'] as String;
    final targetDayInt = _getDayOfWeek(targetDayString);

    if (targetDayInt == 0) return;

    DateTime initialValidDate = DateTime.now();
    while (initialValidDate.weekday != targetDayInt) {
      initialValidDate = initialValidDate.subtract(const Duration(days: 1));
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialValidDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(), 
      selectableDayPredicate: (DateTime val) => val.weekday == targetDayInt, 
      helpText: 'Pilih Tanggal (Hanya Hari $targetDayString)',
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchAttendanceData();
    }
  }

  Future<void> _saveData() async {
    if (_selectedScheduleId == null || _records.isEmpty) return;
    
    final model = AttendanceModel(
      id: '', 
      scheduleId: _selectedScheduleId!,
      classId: _selectedScheduleData!['classId'], 
      className: _selectedScheduleData!['className'],
      subjectName: _selectedScheduleData!['subjectName'],
      date: _formattedDate, 
      records: _records,
    );
    
    final docId = '${model.scheduleId}_${model.date}';
    final dataToSave = model.toMap();
    if (_isSubstituteMode) dataToSave['recordedBySubstitute'] = currentUserId;

    try {
      await FirebaseFirestore.instance.collection('attendance').doc(docId).set(dataToSave, SetOptions(merge: true));
      // Catat sesi SEBELUM status direset di bawah
      await _catatSesi();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tersimpan!'), backgroundColor: Colors.green));
        setState(() {
          for (var record in _records) {
            record.status = AttendanceStatus.alpa;
          }
        });
      }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) return const Scaffold(body: Center(child: Text('Belum login.')));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      // APPBAR DIHAPUS AGAR TIDAK DOUBLE!
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER KUSTOM SEBAGAI PENGGANTI APPBAR
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Input Absensi',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.science,
                      color: ResearchConfig.aktif ? Colors.orange : Colors.grey),
                  tooltip: ResearchConfig.aktif
                      ? 'Mode Penelitian aktif (sesi dicatat)'
                      : 'Mode Penelitian',
                  onPressed: () async {
                    await tampilkanPengaturanPenelitian(context);
                    if (mounted) setState(() {});
                  },
                ),
                if (_records.isNotEmpty && _selectedScheduleData != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.print, color: Colors.indigo),
                      tooltip: 'Cetak PDF',
                      onPressed: () {
                        final model = AttendanceModel(
                          id: '', 
                          scheduleId: _selectedScheduleId!,
                          classId: _selectedScheduleData!['classId'],
                          className: _selectedScheduleData!['className'],
                          subjectName: _selectedScheduleData!['subjectName'], 
                          date: _formattedDate, 
                          records: _records
                        );
                        PdfExportService.generateAndPrintAttendance(model);
                      },
                    ),
                  ),
              ],
            ),
          ),
          
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200)
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Mode Guru Pengganti', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Aktifkan jika mewakili absen guru lain'),
                    value: _isSubstituteMode,
                    activeColor: Colors.orange,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (bool value) {
                      setState(() {
                        _isSubstituteMode = value;
                        _selectedScheduleId = null;
                        _selectedScheduleData = null;
                        _records.clear();
                      });
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        flex: 5, 
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _isSubstituteMode 
                            ? FirebaseFirestore.instance.collection('schedules').snapshots()
                            : FirebaseFirestore.instance.collection('schedules').where('teacherId', isEqualTo: currentUserId).snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) return const CircularProgressIndicator();
                            final schedules = snapshot.data?.docs ?? [];
                            if (schedules.isEmpty) {
                              return DropdownButtonFormField<String>(
                                isExpanded: true, 
                                decoration: const InputDecoration(labelText: 'Pilih Jadwal', border: OutlineInputBorder()),
                                items: const [],
                                onChanged: null,
                                hint: const Text('Belum ada jadwal', style: TextStyle(color: Colors.red)),
                              );
                            }

                            return DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: 'Pilih Jadwal', border: OutlineInputBorder()),
                              value: _selectedScheduleId,
                              isExpanded: true,
                              items: schedules.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return DropdownMenuItem<String>(
                                  value: doc.id,
                                  child: Text('${data['className']} - ${data['subjectName']}'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedScheduleId = val;
                                  _selectedScheduleData = schedules.firstWhere((d) => d.id == val).data() as Map<String, dynamic>;
                                  _selectedDate = DateTime.now(); 
                                });
                                _fetchAttendanceData();
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 4, 
                        child: InkWell(
                          onTap: () => _selectDate(context),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Tanggal', border: OutlineInputBorder()),
                            child: Text(DateFormat('dd MMM yyyy').format(_selectedDate), style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Absen Otomatis via AI'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                      ),
                      onPressed: _selectedScheduleId == null || _records.isEmpty ? null : () async {
                        final mulaiScan = DateTime.now();
                        final updatedRecords = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AttendanceScreen(
                              records: _records,
                              classId: _selectedScheduleData!['classId'], // Diperlukan untuk sinkronisasi embedding wajah kelas ini
                              sesiId: _sesiId,
                            ),
                          ),
                        );

                        if (updatedRecords != null) {
                          setState(() {
                            _records = updatedRecords;
                          });
                        }

                        // Simpan status hasil scan (sebelum dikoreksi guru) untuk RM 3
                        _durasiScan += DateTime.now().difference(mulaiScan);
                        _statusSetelahScan = {for (final r in _records) r.studentId: r.status};
                      },
                    ),
                  ),

                ],
              ),
            ),
          ),
          
          Expanded(
            child: _isLoadingData 
              ? const Center(child: CircularProgressIndicator())
              : _selectedScheduleId == null 
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.checklist_rtl, size: 60, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('Pilih jadwal terlebih dahulu.', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                : _records.isEmpty
                  ? const Center(child: Text('Belum ada siswa di kelas ini.'))
                  : ListView.builder(
                      itemCount: _records.length,
                      itemBuilder: (ctx, i) {
                        final record = _records[i];
                        return Card(
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200)
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(record.studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 12),
                                SegmentedButton<AttendanceStatus>(
                                  segments: AttendanceStatus.values.map((s) => ButtonSegment(value: s, label: Text(s.label))).toList(),
                                  selected: {record.status},
                                  onSelectionChanged: (Set<AttendanceStatus> newSelection) {
                                    setState(() => record.status = newSelection.first);
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
      bottomNavigationBar: _records.isNotEmpty ? Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _saveData, 
          icon: const Icon(Icons.save), 
          label: const Text('Simpan Absensi', style: TextStyle(fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.indigo,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
          ),
        ),
      ) : null,
    );
  }
}