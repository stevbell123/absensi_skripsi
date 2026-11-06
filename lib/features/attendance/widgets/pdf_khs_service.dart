import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfKhsService {
  // Fungsi ini sekarang difokuskan HANYA untuk mencetak laporan absensi
  static Future<void> printKHS({
    required String studentName,
    required String className,
    required String semesterName,
    required Map<String, Map<String, int>> attendanceData, 
    // gradesData sengaja dibiarkan (meskipun tidak dipakai) agar tidak perlu 
    // mengubah kode pemanggil di file student_performance_view.dart
    required Map<String, double> gradesData, 
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // --- BAGIAN JUDUL DOKUMEN ---
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'LAPORAN REKAPITULASI ABSENSI', 
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Semester: $semesterName', 
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)
                    ),
                    pw.SizedBox(height: 24),
                  ],
                ),
              ),
              
              // --- BAGIAN DATA DIRI SISWA ---
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  color: PdfColors.grey100,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.SizedBox(width: 80, child: pw.Text('Nama Siswa', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                        pw.Text(':  $studentName'),
                      ]
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      children: [
                        pw.SizedBox(width: 80, child: pw.Text('Kelas', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                        pw.Text(':  $className'),
                      ]
                    ),
                  ],
                )
              ),
              pw.SizedBox(height: 32),

              // --- TABEL NILAI AKADEMIK DIHAPUS ---
              // (Kode lama pembentuk tabel nilai sudah dihilangkan)

              // --- TABEL DATA ABSENSI ---
              pw.Text('DATA KEHADIRAN PER MATA PELAJARAN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo800)),
              pw.SizedBox(height: 12),
              
              pw.Table.fromTextArray(
                headers: ['Mata Pelajaran', 'Hadir', 'Izin', 'Sakit', 'Alpa'],
                data: attendanceData.isNotEmpty 
                  ? attendanceData.entries.map((entry) {
                      final stats = entry.value;
                      return [
                        entry.key.toUpperCase(), 
                        stats['hadir'].toString(), 
                        stats['izin'].toString(), 
                        stats['sakit'].toString(), 
                        stats['alpa'].toString()
                      ];
                    }).toList()
                  : [['-', '0', '0', '0', '0']],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo600),
                cellAlignment: pw.Alignment.center, // Pusatkan teks angka
                cellAlignments: {0: pw.Alignment.centerLeft}, // Nama mapel tetap rata kiri
                rowDecoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
                ),
                cellPadding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              ),

              pw.SizedBox(height: 60),
              
              // --- BAGIAN TANDA TANGAN ---
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Mengetahui,'), 
                      pw.Text('Orang Tua / Wali'), 
                      pw.SizedBox(height: 70), 
                      pw.Text('( ...................................... )')
                    ]
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Wali Kelas'), 
                      pw.SizedBox(height: 85), 
                      pw.Text('( ...................................... )')
                    ]
                  ),
                ],
              )
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Laporan_Absensi_${studentName.replaceAll(' ', '_')}.pdf',
    );
  }
}