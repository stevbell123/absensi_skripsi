class AppConstants {
  AppConstants._();

  static const String appName = 'SIAP';
  static const String appFullName = 'Sistem Informasi Akademik Pintar';

  // Nama koleksi Firestore
  static const String usersCollection = 'users';
  static const String semestersCollection = 'semesters';
  static const String classesCollection = 'classes';
  static const String subjectsCollection = 'subjects';
  static const String schedulesCollection = 'schedules';
  static const String attendanceCollection = 'attendance';
  static const String gradesCollection = 'grades';
  static const String reportCardsCollection = 'reportCards';
  static const String learningMaterialsCollection = 'learningMaterials';
  static const String riskPredictionsCollection = 'riskPredictions';

  // ---------- Cloudinary (BRANKAS RAHASIA) ----------
  // AKUN 1
  static const String cloudName1 = String.fromEnvironment('CLOUD_NAME_1', defaultValue: 'k1aez8t7');
  static const String uploadPreset1 = String.fromEnvironment('UPLOAD_PRESET_1', defaultValue: 'iettsh78');
  
  // AKUN 2
  static const String cloudName2 = String.fromEnvironment('CLOUD_NAME_2', defaultValue: 'injkgkog');
  static const String uploadPreset2 = String.fromEnvironment('UPLOAD_PRESET_2', defaultValue: 'preset_3');
  
  // AKUN 3
  static const String cloudName3 = String.fromEnvironment('CLOUD_NAME_3', defaultValue: 'qhrbgivc');
  static const String uploadPreset3 = String.fromEnvironment('UPLOAD_PRESET_3', defaultValue: 'preset_2');
}