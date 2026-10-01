import 'package:cloud_firestore/cloud_firestore.dart';

enum AttendanceStatus { hadir, izin, sakit, alpa }

extension AttendanceStatusX on AttendanceStatus {
  String get label {
    switch (this) {
      case AttendanceStatus.hadir: return 'Hadir';
      case AttendanceStatus.izin: return 'Izin';
      case AttendanceStatus.sakit: return 'Sakit';
      case AttendanceStatus.alpa: return 'Alpa';
    }
  }
}

class AttendanceRecord {
  AttendanceRecord({required this.studentId, required this.studentName, required this.status});
  final String studentId;
  final String studentName; 
  AttendanceStatus status;

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      studentId: map['studentId'] ?? '',
      studentName: map['studentName'] ?? '',
      status: AttendanceStatus.values.firstWhere((e) => e.name == map['status'], orElse: () => AttendanceStatus.alpa),
    );
  }

  Map<String, dynamic> toMap() => {
    'studentId': studentId,
    'studentName': studentName,
    'status': status.name,
  };
}

class AttendanceModel {
  const AttendanceModel({
    required this.id,
    required this.scheduleId,
    required this.classId,
    required this.className,
    required this.subjectName,
    required this.date,
    required this.records,
  });

  final String id;
  final String scheduleId;
  final String classId;
  final String className;
  final String subjectName;
  final String date; 
  final List<AttendanceRecord> records;

  factory AttendanceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final recordsData = data['records'] as List<dynamic>? ?? [];
    return AttendanceModel(
      id: doc.id,
      scheduleId: data['scheduleId'] ?? '',
      classId: data['classId'] ?? '',
      className: data['className'] ?? '',
      subjectName: data['subjectName'] ?? '',
      date: data['date'] ?? '',
      records: recordsData.map((e) => AttendanceRecord.fromMap(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'scheduleId': scheduleId,
    'classId': classId,
    'className': className,
    'subjectName': subjectName,
    'date': date,
    'records': records.map((e) => e.toMap()).toList(),
  };
}