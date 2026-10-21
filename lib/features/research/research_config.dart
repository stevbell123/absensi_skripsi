// =========================================================================
// KONFIGURASI MODE PENELITIAN (RM 1 – RM 3)
// =========================================================================
// Menyimpan saklar eksperimen yang dipakai layar absensi & evaluasi dataset:
// - CLAHE on/off                       → RM 1 (pengaruh CLAHE)
// - Verifikasi margin on/off           → RM 2 (margin vs ambang tunggal)
// - Kondisi pencahayaan (label)        → RM 1
// - Pencatatan sesi absensi            → RM 3 (wajah vs manual)
//
// Selama Mode Penelitian MATI, nilai efektif selalu sama dengan perilaku
// normal aplikasi (CLAHE + margin aktif), sehingga absensi harian tidak berubah.
// Konfigurasi disimpan di Hive agar tidak hilang saat aplikasi ditutup.
// =========================================================================

import 'package:hive/hive.dart';
import '../../core/ai/face_matching_service.dart';

class ResearchConfig {
  static const String _boxName = 'research_config';

  /// Kondisi pencahayaan bawaan (nilai yang ditulis ke log → label tampilan)
  static const Map<String, String> kondisiBawaan = {
    'terang': 'Terang normal',
    'redup': 'Redup',
    'backlight': 'Backlight',
    'samping_bayangan': 'Cahaya samping/bayangan',
  };

  static bool aktif = false;
  static bool gunakanClahe = true;
  static bool gunakanMargin = true;
  static String kondisiCahaya = 'terang';

  static bool _sudahDimuat = false;

  // Nilai yang benar-benar dipakai sistem
  static bool get efektifClahe => aktif ? gunakanClahe : true;
  static bool get efektifMargin => aktif ? gunakanMargin : true;
  static double get ambang => FaceMatchingService.batasTerima;
  static double get margin => FaceMatchingService.selisihMinimal;

  static String get labelVerifikasi => efektifMargin ? 'margin' : 'tunggal';

  /// Label ringkas konfigurasi, contoh: "CLAHE + margin"
  static String get labelKonfigurasi =>
      '${efektifClahe ? "CLAHE" : "Tanpa CLAHE"} + '
      '${efektifMargin ? "margin" : "ambang tunggal"}';

  static Future<void> load() async {
    if (_sudahDimuat) return;
    try {
      final box = await Hive.openBox(_boxName);
      aktif = box.get('aktif', defaultValue: false) as bool;
      gunakanClahe = box.get('gunakanClahe', defaultValue: true) as bool;
      gunakanMargin = box.get('gunakanMargin', defaultValue: true) as bool;
      kondisiCahaya = box.get('kondisiCahaya', defaultValue: 'terang') as String;
      _sudahDimuat = true;
    } catch (e) {
      print('[ResearchConfig] Gagal memuat konfigurasi: $e');
    }
  }

  static Future<void> save() async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.putAll({
        'aktif': aktif,
        'gunakanClahe': gunakanClahe,
        'gunakanMargin': gunakanMargin,
        'kondisiCahaya': kondisiCahaya,
      });
    } catch (e) {
      print('[ResearchConfig] Gagal menyimpan konfigurasi: $e');
    }
  }

  /// Menerapkan konfigurasi efektif ke service pencocokan wajah
  static void terapkanKe(FaceMatchingService service) {
    service.ambang = ambang;
    service.margin = margin;
    service.gunakanMargin = efektifMargin;
    service.gunakanGaleriTanpaClahe = !efektifClahe;
  }
}
