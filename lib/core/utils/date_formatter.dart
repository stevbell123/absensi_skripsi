import 'package:intl/intl.dart';

/// Helper format tanggal ala Indonesia. Dipakai mulai Fase 3 (absensi & rapor).
class DateFormatter {
  DateFormatter._();

  static final _fullDate = DateFormat('EEEE, d MMMM yyyy', 'id_ID');
  static final _shortDate = DateFormat('d/MM/yyyy', 'id_ID');
  static final _monthYear = DateFormat('MMMM yyyy', 'id_ID');

  static String full(DateTime date) => _fullDate.format(date);
  static String short(DateTime date) => _shortDate.format(date);
  static String monthYear(DateTime date) => _monthYear.format(date);
}
