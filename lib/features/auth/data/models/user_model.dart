import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.id,
    required super.name,
    required super.email,
    required super.role,
    required super.rawRole, // <--- TAMBAHAN
    super.gender, 
    super.nisNip,
    super.classId,
    required super.createdAt,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) throw StateError('Data user ${doc.id} kosong.');
    
    return UserModel(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: UserRoleX.fromString(data['role'] ?? 'siswa'),
      rawRole: data['role'] ?? 'siswa', // <--- MEMBACA DATABASE ASLI
      gender: data['gender'],
      nisNip: data['nisNip'],
      classId: data['classId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'role': role.name,
    'gender': gender, 
    'nisNip': nisNip,
    'classId': classId,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}