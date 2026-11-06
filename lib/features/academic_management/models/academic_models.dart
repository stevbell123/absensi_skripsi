import 'package:cloud_firestore/cloud_firestore.dart';

class SemesterModel {
  const SemesterModel({required this.id, required this.name, required this.academicYear, required this.isActive});
  final String id, name, academicYear;
  final bool isActive;

  factory SemesterModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SemesterModel(
      id: doc.id,
      name: data['name'] ?? '',
      academicYear: data['academicYear'] ?? '',
      isActive: data['isActive'] ?? false,
    );
  }
  Map<String, dynamic> toMap() => {'name': name, 'academicYear': academicYear, 'isActive': isActive};
}

class SubjectModel {
  const SubjectModel({required this.id, required this.name, required this.code});
  final String id, name, code;

  factory SubjectModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubjectModel(
      id: doc.id, name: data['name'] ?? '', code: data['code'] ?? '',
    );
  }
  Map<String, dynamic> toMap() => {'name': name, 'code': code};
}

class ClassModel {
  const ClassModel({required this.id, required this.name, required this.level, this.homeroomTeacherId, required this.semesterId});
  final String id, name, level, semesterId;
  final String? homeroomTeacherId;

  factory ClassModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ClassModel(
      id: doc.id, name: data['name'] ?? '', level: data['level'] ?? '',
      homeroomTeacherId: data['homeroomTeacherId'], semesterId: data['semesterId'] ?? '',
    );
  }
  Map<String, dynamic> toMap() => {'name': name, 'level': level, 'homeroomTeacherId': homeroomTeacherId, 'semesterId': semesterId};
}

class ScheduleModel {
  const ScheduleModel({required this.id, required this.classId, required this.subjectId, required this.teacherId, required this.day, required this.startTime, required this.endTime, required this.semesterId});
  final String id, classId, subjectId, teacherId, day, startTime, endTime, semesterId;

  factory ScheduleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ScheduleModel(
      id: doc.id, classId: data['classId'] ?? '', subjectId: data['subjectId'] ?? '',
      teacherId: data['teacherId'] ?? '', day: data['day'] ?? '',
      startTime: data['startTime'] ?? '', endTime: data['endTime'] ?? '', semesterId: data['semesterId'] ?? '',
    );
  }
  Map<String, dynamic> toMap() => {'classId': classId, 'subjectId': subjectId, 'teacherId': teacherId, 'day': day, 'startTime': startTime, 'endTime': endTime, 'semesterId': semesterId};
}