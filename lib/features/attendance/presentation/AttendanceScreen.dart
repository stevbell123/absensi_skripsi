// =========================================================================
// ATTENDANCE SCREEN (SCANNER OTOMATIS REAL-TIME ON-DEVICE)
// =========================================================================
// FITUR:
// 1. Live Continuous Auto-Scan: Begitu menu dibuka, kamera otomatis
//    memindai wajah siswa secara berulang tanpa perlu menekan tombol jepret.
// 2. Animasi Laser Scanner: Garis laser hijau bergerak naik-turun memberi
//    tampilan live scanner modern kelas industri.
// 3. Fast On-Device Inference: ML Kit + MobileFaceNet berjalan dalam ~50-100ms.
// 4. Real-Time Feedback: Getaran haptic + notifikasi pop-up saat siswa terdeteksi.
// 5. Multi-Student Queue: Mendukung absensi banyak siswa secara beruntun.
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:async';

import '../models/attendance_model.dart';
import '../../../core/ai/face_detector_service.dart';
import '../../../core/ai/face_embedding_service.dart';
import '../../../core/ai/face_matching_service.dart';
import '../../../core/ai/face_database_service.dart';
import '../../research/research_config.dart';
import '../../research/research_logger.dart';

class AttendanceScreen extends StatefulWidget {
  final List<AttendanceRecord> records;
  final String classId;
  // ID sesi absensi (Mode Penelitian) agar log wajah bisa dikaitkan dengan log sesi
  final String? sesiId;

  const AttendanceScreen({
    Key? key,
    required this.records,
    required this.classId,
    this.sesiId,
  }) : super(key: key);

  @override
  _AttendanceScreenState createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  bool _isCameraInitialized = false;
  bool _isScanningCycle = false;
  bool _isFlashOn = false;
  bool _isAutoScan = true; // Auto-scan aktif secara default

  Timer? _autoScanTimer;
  Timer? _bannerTimer;

  // Animasi Laser Scanner
  late AnimationController _laserController;
  late Animation<double> _laserAnimation;

  // Layanan AI (On-Device)
  late FaceDetectorService _detectorService;
  late FaceEmbeddingService _embeddingService;
  late FaceMatchingService _matchingService;
  late FaceDatabaseService _databaseService;

  bool _isAiReady = false;
  String _statusText = 'Mempersiapkan AI...';

  // Daftar siswa yang terabsen pada sesi ini
  final List<String> _recognizedStudents = [];
  String? _latestRecognizedName;

  // Penghitung pemindaian gagal berturut-turut (Bab III: 5 kali gagal = tidak dikenali).
  // Siklus tanpa wajah terdeteksi juga dihitung gagal.
  static const int _batasGagal = 5;
  int _gagalBeruntun = 0;
  String? _namaSiklusTerakhir; // nama yang diterima pada siklus terakhir

  int get _hadirCount =>
      widget.records.where((r) => r.status == AttendanceStatus.hadir).length;

  @override
  void initState() {
    super.initState();

    // Inisialisasi animasi laser scanner
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.05, end: 0.95).animate(
      CurvedAnimation(parent: _laserController, curve: Curves.easeInOut),
    );

    // Kumpulkan siswa yang sudah berstatus hadir sebelumnya
    for (var r in widget.records) {
      if (r.status == AttendanceStatus.hadir && !_recognizedStudents.contains(r.studentName)) {
        _recognizedStudents.add(r.studentName);
      }
    }

    _initializeCamera();
    _initializeAI();
  }

  // =========================================================================
  // INISIALISASI AI ON-DEVICE & LOAD DATABASE SISWA
  // =========================================================================
  Future<void> _initializeAI() async {
    try {
      setState(() => _statusText = 'Memuat model AI...');

      _detectorService = FaceDetectorService();
      _embeddingService = FaceEmbeddingService();
      _matchingService = FaceMatchingService();
      _databaseService = FaceDatabaseService();

      await _embeddingService.initialize();
      if (!_embeddingService.isReady) {
        setState(() => _statusText = '❌ Gagal memuat model AI');
        return;
      }

      setState(() => _statusText = 'Menyinkronkan data wajah...');
      await _databaseService.initHive();

      List<FaceRecord> records = [];
      try {
        records = await _databaseService.syncByClass(widget.classId);
        if (records.isEmpty) {
          records = await _databaseService.syncFromFirestore();
        }
      } catch (e) {
        debugPrint('[AI] Offline / Error Firestore, memakai cache lokal Hive: $e');
        records = await _databaseService.loadFromLocal();
      }

      _matchingService.loadDatabase(records);
      await ResearchConfig.load();
      ResearchConfig.terapkanKe(_matchingService);

      if (mounted) {
        setState(() {
          _isAiReady = true;
          _statusText = _teksStatusSiap();
        });
      }

      // Begitu AI siap, otomatis jalankan continuous auto-scan!
      _startContinuousAutoScan();
    } catch (e) {
      if (mounted) setState(() => _statusText = '❌ Error: $e');
      debugPrint('[AI] Gagal inisialisasi: $e');
    }
  }

  String _teksStatusSiap() {
    final total = _matchingService.totalSiswa;
    if (total == 0) return '⚠️ 0 Siswa (Daftarkan wajah dahulu)';
    if (!ResearchConfig.efektifClahe) {
      // Mode tanpa CLAHE hanya bisa memakai siswa yang didaftarkan ulang (punya embedding non-CLAHE)
      return '🧪 Tanpa CLAHE: ${_matchingService.totalSiswaTanpaClahe}/$total siswa siap';
    }
    return '✅ Siap Pindai ($total siswa dimuat)';
  }

  /// Mencari siswa di daftar hadir untuk hasil pengenalan wajah.
  /// Logika pencocokan nama longgar dipertahankan; 'cocokVia' dicatat agar
  /// pengaruhnya terhadap MIR bisa dianalisis terpisah.
  ({int index, String cocokVia}) _cariSiswa(String nim, String nama) {
    final resName = nama.toLowerCase().trim();
    final resFirstName = resName.split(' ').first;
    final index = widget.records.indexWhere((r) {
      final recName = r.studentName.toLowerCase().trim();
      final recFirstName = recName.split(' ').first;
      return r.studentId == nim ||
          recName == resName ||
          (resName.isNotEmpty && recName.contains(resName)) ||
          (recName.isNotEmpty && resName.contains(recName)) ||
          (resFirstName.length >= 3 && resFirstName == recFirstName);
    });
    if (index == -1) return (index: -1, cocokVia: 'tidak_ada');
    return (
      index: index,
      cocokVia: widget.records[index].studentId == nim ? 'nim' : 'nama',
    );
  }

  // =========================================================================
  // KONTROL SCANNER OTOMATIS (CONTINUOUS AUTO-SCAN)
  // =========================================================================
  void _startContinuousAutoScan() {
    _autoScanTimer?.cancel();
    if (!_isAutoScan) return;

    // Scan on-device setiap 600ms (kurang dari 1 detik langsung terabsen!)
    _autoScanTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!_isScanningCycle && _isAiReady && _isCameraInitialized && _isAutoScan && mounted) {
        _runAutoScanCycle();
      }
    });
  }

  void _toggleAutoScan(bool enable) {
    setState(() => _isAutoScan = enable);
    if (_isAutoScan) {
      _startContinuousAutoScan();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("▶️ Auto-Scan Aktif: Arahkan kamera ke siswa."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _autoScanTimer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⏸ Auto-Scan Dijeda."),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // =========================================================================
  // SIKLUS DETEKSI & PENCOCOKAN WAJAH OTOMATIS (ON-DEVICE)
  // =========================================================================
  Future<void> _runAutoScanCycle() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isScanningCycle) return;

    _isScanningCycle = true;
    bool adaDiterima = false;
    String? namaDiterima;

    try {
      // 1. Ambil frame foto secara cepat
      XFile picture = await _controller!.takePicture();

      // Eksekusi On-Device AI di HP (Google ML Kit + On-Device CLAHE + MobileFaceNet)
      // Stopwatch mengukur latensi tiap tahap untuk analisis RM 1 (Mode Penelitian)
      final bool gunakanClahe = ResearchConfig.efektifClahe;
      final sw = Stopwatch()..start();

      final inputImage = InputImage.fromFilePath(picture.path);
      final faces = await _detectorService.detectFaces(inputImage);
      final double tDeteksi = sw.elapsedMicroseconds / 1000.0;

      if (faces.isNotEmpty) {
        sw..reset()..start();
        final imageBytes = await File(picture.path).readAsBytes();
        final rawImage = img.decodeImage(imageBytes);

        if (rawImage != null) {
          // Selaraskan orientasi rotasi kamera secara otomatis (aman untuk mode lanskap)
          final fullImage = img.bakeOrientation(rawImage);
          final double tDecode = sw.elapsedMicroseconds / 1000.0;

          List<List<double>> allEmbeddings = [];
          List<List<int>> allBoxes = [];
          final List<Map<String, double>> waktuPerWajah = [];

          // Mode Penelitian: hanya wajah terbesar yang diproses, sama dengan mode evaluasi
          final wajahDiproses = List<Face>.from(faces);
          if (ResearchConfig.aktif && wajahDiproses.length > 1) {
            wajahDiproses.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
                .compareTo(a.boundingBox.width * a.boundingBox.height));
            wajahDiproses.removeRange(1, wajahDiproses.length);
          }

          for (final face in wajahDiproses) {
            final bbox = face.boundingBox;
            sw..reset()..start();
            final croppedFace = _embeddingService.cropAndAlignFace(fullImage, bbox);
            final waktu = <String, double>{'crop_ms': sw.elapsedMicroseconds / 1000.0};
            // Ekstraksi embedding dengan On-Device CLAHE (bisa dimatikan di Mode Penelitian)
            final embedding = _embeddingService.extractEmbedding(
              croppedFace,
              applyClahe: gunakanClahe,
              waktu: waktu,
            );
            waktuPerWajah.add(waktu);
            allEmbeddings.add(embedding);
            allBoxes.add([
              bbox.left.toInt(),
              bbox.top.toInt(),
              bbox.right.toInt(),
              bbox.bottom.toInt()
            ]);
          }

          // Pencocokan vektor embedding terhadap database
          sw..reset()..start();
          final results = _matchingService.matchFaces(allEmbeddings, allBoxes);
          final double tMatching = sw.elapsedMicroseconds / 1000.0;
          final diterima = results.where((r) => r.nim != 'Unknown');
          adaDiterima = diterima.isNotEmpty;
          if (adaDiterima) namaDiterima = diterima.first.name;
          List<String> newlyRecognizedNames = [];
          final List<Map<String, dynamic>> logWajah = [];

          final double tFrame = tDeteksi +
              tDecode +
              waktuPerWajah.fold<double>(
                  0,
                  (s, w) =>
                      s + (w['crop_ms'] ?? 0.0) + (w['clahe_ms'] ?? 0.0) + (w['embedding_ms'] ?? 0.0)) +
              tMatching;

          for (var result in results) {
            final pencarian = result.nim != "Unknown"
                ? _cariSiswa(result.nim, result.name)
                : (index: -1, cocokVia: '');

            if (ResearchConfig.aktif) {
              final w = waktuPerWajah[result.faceIndex];
              logWajah.add({
                'waktu': ResearchLogger.waktuSekarang(),
                'sumber': 'live',
                'sesi_id': widget.sesiId ?? '',
                'kondisi_cahaya': ResearchConfig.kondisiCahaya,
                'clahe': gunakanClahe ? 1 : 0,
                'mode_verifikasi': ResearchConfig.labelVerifikasi,
                'ambang': _matchingService.ambang,
                'margin': _matchingService.margin,
                'jumlah_wajah': faces.length,
                'indeks_wajah': result.faceIndex,
                ...ResearchLogger.kolomKeputusan(result,
                    ambang: _matchingService.ambang, margin: _matchingService.margin),
                'nim_daftar_hadir': pencarian.index != -1
                    ? widget.records[pencarian.index].studentId
                    : '',
                'cocok_via': pencarian.cocokVia,
                't_deteksi_ms': ResearchLogger.ms(tDeteksi),
                't_decode_ms': ResearchLogger.ms(tDecode),
                't_crop_ms': ResearchLogger.ms(w['crop_ms'] ?? 0.0),
                't_clahe_ms': ResearchLogger.ms(w['clahe_ms'] ?? 0.0),
                't_embedding_ms': ResearchLogger.ms(w['embedding_ms'] ?? 0.0),
                't_matching_ms': ResearchLogger.ms(tMatching),
                't_frame_ms': ResearchLogger.ms(tFrame),
              });
            }

            if (result.nim != "Unknown") {
              final studentIndex = pencarian.index;

              if (studentIndex != -1 &&
                  widget.records[studentIndex].status != AttendanceStatus.hadir) {
                widget.records[studentIndex].status = AttendanceStatus.hadir;
                widget.records[studentIndex].waktu = DateTime.now();
                widget.records[studentIndex].jarak = result.distance;
                final name = widget.records[studentIndex].studentName;
                newlyRecognizedNames.add(name);

                if (!_recognizedStudents.contains(name)) {
                  _recognizedStudents.insert(0, name);
                }
              }
            }
          }

          if (logWajah.isNotEmpty) {
            unawaited(ResearchLogger.catatWajah(logWajah));
          }

          // Notifikasi visual & getaran jika ada siswa (1 atau lebih) yang berhasil diabsen
          if (newlyRecognizedNames.isNotEmpty) {
            HapticFeedback.mediumImpact();
            if (mounted) {
              setState(() {
                if (newlyRecognizedNames.length == 1) {
                  _latestRecognizedName = gunakanClahe
                      ? "${newlyRecognizedNames.first} (On-Device + CLAHE)"
                      : "${newlyRecognizedNames.first} (On-Device)";
                } else if (newlyRecognizedNames.length == 2) {
                  _latestRecognizedName = "${newlyRecognizedNames[0]} & ${newlyRecognizedNames[1]}";
                } else {
                  _latestRecognizedName = "${newlyRecognizedNames.take(2).join(', ')} +${newlyRecognizedNames.length - 2} lainnya";
                }
              });
              _bannerTimer?.cancel();
              _bannerTimer = Timer(const Duration(milliseconds: 3000), () {
                if (mounted) setState(() => _latestRecognizedName = null);
              });
            }
          }
        }
      }

      _perbaruiGagalBeruntun(adaDiterima, namaDiterima);

      // Bersihkan file sementara kamera agar hemat penyimpanan
      try {
        final f = File(picture.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('[AI AUTO-SCAN] Siklus scan info: $e');
    } finally {
      if (mounted) {
        setState(() => _isScanningCycle = false);
      }
    }
  }

  void _perbaruiGagalBeruntun(bool adaDiterima, String? nama) {
    if (!mounted) return;
    final sebelumnya = _gagalBeruntun;
    setState(() {
      _gagalBeruntun = adaDiterima ? 0 : (_gagalBeruntun + 1).clamp(0, _batasGagal);
      _namaSiklusTerakhir = adaDiterima ? nama : null;
    });
    if (sebelumnya < _batasGagal && _gagalBeruntun == _batasGagal) {
      HapticFeedback.vibrate();
    }
  }

  /// Tombol "Siswa berikutnya": mulai hitungan gagal dari nol untuk siswa baru
  void _siswaBerikutnya() {
    setState(() {
      _gagalBeruntun = 0;
      _namaSiklusTerakhir = null;
    });
  }

  String get _teksHasilPindai {
    if (_namaSiklusTerakhir != null) return "1 siswa: $_namaSiklusTerakhir";
    if (_gagalBeruntun >= _batasGagal) return "Tidak dikenali (gagal $_batasGagal/$_batasGagal)";
    return "0 siswa (gagal $_gagalBeruntun/$_batasGagal)";
  }

  // =========================================================================
  // INISIALISASI & KONTROL KAMERA
  // =========================================================================
  Future<void> _initializeCamera([int cameraIndex = -1]) async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) return;

      if (cameraIndex == -1) {
        _selectedCameraIndex = _cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.back);
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
      } else {
        _selectedCameraIndex = cameraIndex;
      }

      final camera = _cameras[_selectedCameraIndex];

      if (_controller != null) {
        await _controller!.dispose();
      }

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();

      _isFlashOn = false;

      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Error inisialisasi kamera: $e");
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2 || _isScanningCycle) return;

    setState(() => _isCameraInitialized = false);

    final currentDirection = _cameras[_selectedCameraIndex].lensDirection;
    final newIndex =
        _cameras.indexWhere((c) => c.lensDirection != currentDirection);

    if (newIndex != -1) {
      await _initializeCamera(newIndex);
    } else {
      await _initializeCamera((_selectedCameraIndex + 1) % _cameras.length);
    }
  }

  void _toggleFlash() {
    if (_controller != null && _controller!.value.isInitialized) {
      setState(() {
        _isFlashOn = !_isFlashOn;
        _controller!
            .setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      });
    }
  }

  @override
  void dispose() {
    _autoScanTimer?.cancel();
    _bannerTimer?.cancel();
    _laserController.dispose();
    _controller?.dispose();
    _detectorService.dispose();
    _embeddingService.dispose();
    super.dispose();
  }

  // Helper untuk membuat 4 sudut kotak scanner
  Widget _buildCorner(Alignment alignment,
      {bool top = false, bool bottom = false, bool left = false, bool right = false}) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border(
            top: top ? const BorderSide(color: Colors.greenAccent, width: 4.5) : BorderSide.none,
            bottom: bottom ? const BorderSide(color: Colors.greenAccent, width: 4.5) : BorderSide.none,
            left: left ? const BorderSide(color: Colors.greenAccent, width: 4.5) : BorderSide.none,
            right: right ? const BorderSide(color: Colors.greenAccent, width: 4.5) : BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.greenAccent),
              SizedBox(height: 16),
              Text(
                "Membuka Scanner AI...",
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final boxW = isLandscape ? screenW * 0.84 : screenW * 0.92;
    final boxH = isLandscape ? screenH * 0.58 : 380.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Pindai Wajah Kelas (AI Auto-Scan)"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            tooltip: 'Tukar Kamera',
            onPressed: _switchCamera,
          ),
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Lampu Flash',
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          // Live Camera Preview (Layar Penuh & Bersih)
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: 1 / _controller!.value.aspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),

          // Bingkai Kotak Scanner AI dengan Animasi Garis Laser (Adaptif Vertikal/Horizontal)
          Center(
            child: Container(
              width: boxW,
              height: boxH,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withOpacity(0.35),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  _buildCorner(Alignment.topLeft, top: true, left: true),
                  _buildCorner(Alignment.topRight, top: true, right: true),
                  _buildCorner(Alignment.bottomLeft, bottom: true, left: true),
                  _buildCorner(Alignment.bottomRight, bottom: true, right: true),

                  // Garis Laser Hijau Melayang Naik-Turun
                  if (_isAutoScan)
                    AnimatedBuilder(
                      animation: _laserAnimation,
                      builder: (context, child) {
                        return Align(
                          alignment: Alignment(0, (_laserAnimation.value * 2) - 1),
                          child: Container(
                            width: double.infinity,
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.greenAccent,
                                  Colors.white,
                                  Colors.greenAccent,
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent.withOpacity(0.85),
                                  blurRadius: 12,
                                  spreadRadius: 2.5,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  // Label Panduan di Bawah Kotak
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _isAutoScan
                              ? "Arahkan wajah siswa ke dalam kotak"
                              : "Auto-scan dijeda. Tekan tombol Play di bawah.",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Banner Status Auto-Scan di Bagian Atas
          Positioned(
            top: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _isAutoScan
                    ? Colors.green.shade800.withOpacity(0.92)
                    : Colors.orange.shade900.withOpacity(0.92),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isAutoScan ? Icons.radar : Icons.pause_circle_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isAutoScan
                        ? "🟢 Auto-Scan Aktif ($_statusText)"
                        : "⏸ Auto-Scan Dijeda",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Notifikasi Pop-Up Hijau Saat Siswa Terdeteksi
          if (_latestRecognizedName != null)
            Positioned(
              top: 54,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.greenAccent.withOpacity(0.6),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        "🎉 $_latestRecognizedName (Hadir)!",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.black.withOpacity(0.92),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Label konfigurasi pengenalan wajah yang sedang aktif.
              // Mode Penelitian hanya diatur dari Developer Control Panel; di sini guru hanya melihat penandanya.
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: ResearchConfig.aktif ? Colors.amber.shade800 : Colors.green.shade600,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(ResearchConfig.aktif ? Icons.science : Icons.bolt,
                        size: 15, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      ResearchConfig.aktif
                          ? "Mode Penelitian · ${ResearchConfig.labelKonfigurasi}"
                          : "⚡ On-Device + CLAHE",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Hasil pemindaian terakhir + penghitung gagal berturut-turut
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _teksHasilPindai,
                        style: TextStyle(
                          color: _namaSiklusTerakhir != null
                              ? Colors.greenAccent
                              : _gagalBeruntun >= _batasGagal
                                  ? Colors.redAccent
                                  : Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _siswaBerikutnya,
                      icon: const Icon(Icons.skip_next, size: 18),
                      label: const Text("Siswa berikutnya"),
                      style: TextButton.styleFrom(foregroundColor: Colors.amberAccent),
                    ),
                  ],
                ),
              ),

              // 2. Baris Ringkasan Jumlah Siswa Hadir & Chip Siswa yang Sudah Terabsen
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade800,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Hadir: $_hadirCount / ${widget.records.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _recognizedStudents.isEmpty
                          ? const Text(
                              "Menunggu deteksi wajah...",
                              style: TextStyle(color: Colors.white54, fontSize: 12.5),
                            )
                          : SizedBox(
                              height: 30,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _recognizedStudents.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 6),
                                itemBuilder: (context, index) {
                                  return Chip(
                                    avatar: const Icon(Icons.check_circle,
                                        color: Colors.greenAccent, size: 14),
                                    label: Text(
                                      _recognizedStudents[index],
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    backgroundColor: Colors.white12,
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              // Baris Tombol Aksi: Jeda/Lanjut, Scan Manual & Selesai
              Row(
                children: [
                  // Tombol Play / Pause Auto-Scan
                  IconButton(
                    onPressed: () => _toggleAutoScan(!_isAutoScan),
                    icon: Icon(
                      _isAutoScan
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: _isAutoScan ? Colors.amberAccent : Colors.greenAccent,
                      size: 40,
                    ),
                    tooltip: _isAutoScan ? 'Jeda Auto-Scan' : 'Lanjutkan Auto-Scan',
                  ),
                  const SizedBox(width: 8),

                  // Tombol Utama: Selesai & Simpan Absensi
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _autoScanTimer?.cancel();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                "✅ Selesai! $_hadirCount siswa berhasil tercatat hadir."),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        Navigator.pop(context, widget.records);
                      },
                      icon: const Icon(Icons.check_circle, size: 22),
                      label: Text(
                        "Selesai Absen ($_hadirCount Hadir)",
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}