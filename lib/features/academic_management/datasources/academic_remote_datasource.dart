import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/academic_models.dart';
import '../../auth/data/models/user_model.dart';
import '../../../../core/constants/app_constants.dart';

class AcademicRemoteDataSource {
  AcademicRemoteDataSource(this._firestore);
  final FirebaseFirestore _firestore;

  // SEMESTER
  Stream<List<SemesterModel>> getSemesters() => _firestore.collection('semesters').snapshots().map((s) => s.docs.map((d) => SemesterModel.fromFirestore(d)).toList());
  Future<void> addSemester(SemesterModel data) => _firestore.collection('semesters').add(data.toMap());
  Future<void> updateSemester(SemesterModel data) => _firestore.collection('semesters').doc(data.id).update(data.toMap());

  // SUBJECT (MAPEL)
  Stream<List<SubjectModel>> getSubjects() => _firestore.collection('subjects').snapshots().map((s) => s.docs.map((d) => SubjectModel.fromFirestore(d)).toList());
  Future<void> addSubject(SubjectModel data) => _firestore.collection('subjects').add(data.toMap());

  // CLASS (KELAS)
  Stream<List<ClassModel>> getClasses() => _firestore.collection('classes').snapshots().map((s) => s.docs.map((d) => ClassModel.fromFirestore(d)).toList());
  Future<void> addClass(ClassModel data) => _firestore.collection('classes').add(data.toMap());

  // SCHEDULE (JADWAL)
  Stream<List<ScheduleModel>> getSchedules() => _firestore.collection('schedules').snapshots().map((s) => s.docs.map((d) => ScheduleModel.fromFirestore(d)).toList());
  Future<void> addSchedule(ScheduleModel data) => _firestore.collection('schedules').add(data.toMap());

  // USER
  Stream<List<UserModel>> getUsers() => _firestore.collection(AppConstants.usersCollection).snapshots().map((s) => s.docs.map((d) => UserModel.fromFirestore(d)).toList());
  
  Future<void> createUserByAdmin({required String email, required String password, required UserModel userModel}) async {
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(name: 'SecondaryApp', options: Firebase.app().options);
      final cred = await FirebaseAuth.instanceFor(app: secondaryApp).createUserWithEmailAndPassword(email: email, password: password);
      final uid = cred.user?.uid;
      if (uid != null) await _firestore.collection(AppConstants.usersCollection).doc(uid).set(userModel.toMap());
    } finally {
      await secondaryApp?.delete();
    }
  }
}