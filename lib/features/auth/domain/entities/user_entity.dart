enum UserRole { admin, guru, siswa }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.admin: return 'Admin';
      case UserRole.guru: return 'Guru';
      case UserRole.siswa: return 'Siswa';
    }
  }

  static UserRole fromString(String value) {
    final cleanValue = value.trim().toLowerCase();
    
    // Trik meminjam jubah admin agar bisa login
    if (cleanValue == 'developer') {
      return UserRole.admin; 
    }
    
    return UserRole.values.firstWhere(
      (role) => role.name == cleanValue,
      orElse: () => throw ArgumentError('Role tidak dikenal: $value'),
    );
  }
}

class UserEntity {
  const UserEntity({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.rawRole, // <--- IDENTITAS ASLI DISIMPAN DI SINI
    this.gender, 
    this.nisNip,
    this.classId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String rawRole; // <--- IDENTITAS ASLI
  final String? gender; 
  final String? nisNip;
  final String? classId;
  final DateTime createdAt;
}