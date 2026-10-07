import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Service untuk mendeteksi wajah menggunakan Google ML Kit.
///
/// MENGAPA MENGGUNAKAN ML KIT DIBANDINGKAN YOLO UNTUK DETEKSI WAJAH ON-DEVICE?
/// 1. Zero Model Management: ML Kit dikelola oleh platform (seperti Google Play Services di Android),
///    sehingga kita tidak perlu mendownload, mengupdate, atau memuat model ML secara manual (seperti pada YOLO).
/// 2. Ukuran Aplikasi Lebih Kecil: Karena model disediakan oleh platform, ukuran aplikasi (APK/AAB) 
///    menjadi jauh lebih ringan dibandingkan dengan harus memaketkan model YOLO sendiri.
/// 3. Optimasi Perangkat Mobile: ML Kit sangat dioptimalkan untuk perangkat seluler, 
///    memanfaatkan akselerasi hardware (CPU/GPU/NPU) untuk meminimalkan latensi dan konsumsi daya.
/// 4. Fitur Spesifik Wajah: Model ini dilatih khusus untuk mendeteksi wajah, termasuk mengenali 
///    titik-titik landmark penting (mata, telinga, hidung, mulut) dengan sangat baik. 
///    Model object detection umum seperti YOLO biasanya memerlukan training tambahan dan penyesuaian 
///    untuk mencapai tingkat detail landmark wajah yang sama.
class FaceDetectorService {
  late final FaceDetector _faceDetector;

  /// Konstruktor untuk menginisialisasi [FaceDetectorService].
  FaceDetectorService() {
    // Inisialisasi FaceDetector dengan opsi yang diperlukan:
    // - enableContours: false karena kita tidak terlalu membutuhkan kontur seluruh wajah
    // - enableLandmarks: true untuk mendapatkan posisi fitur wajah (seperti mata dan mulut)
    // - performanceMode: accurate untuk akurasi pendeteksian tertinggi
    // - minFaceSize: 0.1 agar bisa mendeteksi wajah yang relatif kecil dalam gambar
    final options = FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false, // Hanya butuh bounding box, mempercepat deteksi hingga 2x lipat
      performanceMode: FaceDetectorMode.fast, // Mode fast ultra responsif (< 20ms) untuk live scanner
      minFaceSize: 0.04, // Diperkecil ke 0.04 (4% frame) agar peka mendeteksi wajah jauh (2.5 s.d. 3.5+ meter)
    );
    _faceDetector = FaceDetector(options: options);
  }

  /// Mendeteksi wajah dari sebuah [InputImage].
  /// Mengembalikan daftar [Face] yang terdeteksi.
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    try {
      final faces = await _faceDetector.processImage(inputImage);
      return faces;
    } catch (e) {
      // Tangkap dan tangani kesalahan saat proses deteksi wajah
      print('Error saat mendeteksi wajah: $e');
      return [];
    }
  }

  /// Mendeteksi wajah dari sebuah file gambar berdasarkan path-nya.
  /// Mengembalikan daftar [Face] yang terdeteksi.
  Future<List<Face>> detectFacesFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('Error: File gambar tidak ditemukan di $filePath');
        return [];
      }
      
      final inputImage = InputImage.fromFile(file);
      return await detectFaces(inputImage);
    } catch (e) {
      // Tangkap dan tangani kesalahan terkait pembacaan file
      print('Error saat membaca file gambar: $e');
      return [];
    }
  }

  /// Membersihkan resource yang digunakan oleh FaceDetector.
  /// Pastikan untuk memanggil metode ini ketika service tidak lagi digunakan.
  void dispose() {
    _faceDetector.close();
  }
}
