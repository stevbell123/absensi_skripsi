import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/attendance_model.dart';
import '../../auth/data/models/user_model.dart';

class AttendanceRemoteDataSource {
  AttendanceRemoteDataSource(this._firestore);
  final FirebaseFirestore _firestore;

  // PERBAIKAN: Mengambil siswa langsung dari dalam koleksi classes -> students
  Future<List<UserModel>> getStudentsByClass(String classId) async {
    final snapshot = await _firestore
        .collection('classes')
        .doc(classId)
        .collection('students')
        .get();
        
    return snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
  }

  // PERBAIKAN: Menggunakan scheduleId (Jadwal Mapel), bukan sekadar classId
  Future<AttendanceModel?> getAttendance(String scheduleId, String dateString) async {
    final docId = '${scheduleId}_$dateString';
    final doc = await _firestore.collection('attendance').doc(docId).get();
    if (doc.exists) return AttendanceModel.fromFirestore(doc);
    return null;
  }

  // PERBAIKAN: Menyimpan data absensi menggunakan scheduleId
  Future<void> saveAttendance(AttendanceModel attendance) async {
    final docId = '${attendance.scheduleId}_${attendance.date}';
    await _firestore.collection('attendance').doc(docId).set(attendance.toMap(), SetOptions(merge: true));
  }
}