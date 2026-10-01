import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/attendance_model.dart';
import '../../../../core/constants/app_constants.dart';

class PdfExportService {
  static Future<void> generateAndPrintAttendance(AttendanceModel attendance) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(AppConstants.appName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Laporan Absensi Kelas: ${attendance.className}', style: const pw.TextStyle(fontSize: 16)),
              pw.Text('Mata Pelajaran: ${attendance.subjectName}', style: const pw.TextStyle(fontSize: 16)),
              pw.Text('Tanggal: ${attendance.date}', style: const pw.TextStyle(fontSize: 14)),
              pw.SizedBox(height: 24),
              pw.Table.fromTextArray(
                headers: ['No', 'Nama Siswa', 'Status Kehadiran'],
                data: List<List<String>>.generate(
                  attendance.records.length,
                  (index) {
                    final record = attendance.records[index];
                    return [
                      (index + 1).toString(),
                      record.studentName,
                      record.status.label,
                    ];
                  },
                ),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Absensi_${attendance.className}_${attendance.subjectName}_${attendance.date}.pdf',
    );
  }
}