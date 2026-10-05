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
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/attendance_model.dart';
import '../../../core/ai/face_detector_service.dart';
import '../../../core/ai/face_embedding_service.dart';
import '../../../core/ai/face_matching_service.dart';
import '../../../core/ai/face_database_service.dart';

class AttendanceScreen extends StatefulWidget {
  final List<AttendanceRecord> records;
  final String classId;

  const AttendanceScreen({
    Key? key,
    required this.records,
    required this.classId,
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
  bool _useServerEngine = false; // false = On-Device + CLAHE, true = Server VPS YOLOv26 + CLAHE

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
  String? _serverStatusMessage;

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

      if (mounted) {
        setState(() {
          _isAiReady = true;
          _statusText = records.isNotEmpty
              ? '✅ Siap Pindai (${records.length} siswa dimuat)'
              : '⚠️ 0 Siswa (Daftarkan wajah dahulu)';
        });
      }

      // Begitu AI siap, otomatis jalankan continuous auto-scan!
      _startContinuousAutoScan();
    } catch (e) {
      if (mounted) setState(() => _statusText = '❌ Error: $e');
      debugPrint('[AI] Gagal inisialisasi: $e');
    }
  }

  // =========================================================================
  // KONTROL SCANNER OTOMATIS (CONTINUOUS AUTO-SCAN)
  // =========================================================================
  void _startContinuousAutoScan() {
    _autoScanTimer?.cancel();
    if (!_isAutoScan) return;

    // Mode On-Device super gesit: scan setiap 600ms (kurang dari 1 detik langsung terabsen!)
    // Mode Server: scan setiap 1400ms agar jaringan 4G tetap stabil & hemat bandwidth
    final int intervalMs = _useServerEngine ? 1400 : 600;

    _autoScanTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
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
  // EKSEKUSI JALUR SERVER VPS (YOLOv26 + CLAHE + ARCFACE)
  // =========================================================================
  Future<void> _runServerScan(String filePath) async {
    const String serverUrl = 'http://103.175.206.22:8001/api/scan-attendance';
    try {
      // 1. Kompresi & Resize Foto Kamera Sebelum Dikirim (Sangat Penting!)
      // Dari ukuran kamera asli ~1.7 MB (lambat di 4G) menjadi ~75 KB (terkirim kilat < 0.2 detik!)
      List<int> uploadBytes;
      try {
        final rawBytes = await File(filePath).readAsBytes();
        final decoded = img.decodeImage(rawBytes);
        if (decoded != null) {
          // Resolusi optimal 1280px agar wajah siswa yang berjarak 2-3 meter
          // atau berkelompok 5-6 orang tetap tajam & tidak pecah saat di-crop YOLO
          final int maxDim = decoded.width > decoded.height ? decoded.width : decoded.height;
          final resized = maxDim > 1280
              ? (decoded.width >= decoded.height
                  ? img.copyResize(decoded, width: 1280)
                  : img.copyResize(decoded, height: 1280))
              : decoded;
          uploadBytes = img.encodeJpg(resized, quality: 82);
        } else {
          uploadBytes = rawBytes;
        }
      } catch (_) {
        uploadBytes = await File(filePath).readAsBytes();
      }

      final request = http.MultipartRequest('POST', Uri.parse(serverUrl));
      if (widget.classId.isNotEmpty) {
        request.fields['class_id'] = widget.classId;
      }
      request.files.add(
        http.MultipartFile.fromBytes('file', uploadBytes, filename: 'scan.jpg'),
      );

      // Timeout diperpanjang ke 10 detik agar aman di jaringan 4G/seluler
      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List dynamicList = data['siswa_dikenali'] ?? [];
        final int faceCount = data['wajah_terdeteksi'] ?? 0;
        List<String> newlyRecognizedNames = [];

        for (var item in dynamicList) {
          final String nim = item['nim'] ?? '';
          final String nama = item['nama'] ?? '';

          final studentIndex = widget.records.indexWhere((r) {
            final recName = r.studentName.toLowerCase().trim();
            final srvName = nama.toLowerCase().trim();
            final srvFirstName = srvName.split(' ').first;
            final recFirstName = recName.split(' ').first;
            return r.studentId == nim ||
                recName == srvName ||
                (srvName.isNotEmpty && recName.contains(srvName)) ||
                (recName.isNotEmpty && srvName.contains(recName)) ||
                (srvFirstName.length >= 3 && srvFirstName == recFirstName);
          });

          if (studentIndex != -1 &&
              widget.records[studentIndex].status != AttendanceStatus.hadir) {
            widget.records[studentIndex].status = AttendanceStatus.hadir;
            final name = widget.records[studentIndex].studentName;
            newlyRecognizedNames.add(name);

            if (!_recognizedStudents.contains(name)) {
              _recognizedStudents.insert(0, name);
            }
          }
        }

        if (newlyRecognizedNames.isNotEmpty) {
          HapticFeedback.mediumImpact();
          if (mounted) {
            setState(() {
              if (newlyRecognizedNames.length == 1) {
                _latestRecognizedName =
                    "${newlyRecognizedNames.first} (YOLOv26 + CLAHE Server)";
              } else if (newlyRecognizedNames.length == 2) {
                _latestRecognizedName =
                    "${newlyRecognizedNames[0]} & ${newlyRecognizedNames[1]} (YOLO+CLAHE)";
              } else {
                _latestRecognizedName =
                    "${newlyRecognizedNames.take(2).join(', ')} (YOLO+CLAHE)";
              }
              _serverStatusMessage = "✅ Hadir: ${newlyRecognizedNames.first}";
            });
            _bannerTimer?.cancel();
            _bannerTimer = Timer(const Duration(milliseconds: 3000), () {
              if (mounted) setState(() => _latestRecognizedName = null);
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _serverStatusMessage = faceCount > 0
                  ? "🌐 Server YOLO: $faceCount wajah terlihat, mencocokkan..."
                  : "🌐 Server YOLO: Arahkan kamera ke wajah";
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _serverStatusMessage = "⚠️ Server Error ${response.statusCode}";
          });
        }
      }
    } catch (e) {
      debugPrint('[SERVER SCAN ERROR] $e');
      if (mounted) {
        setState(() {
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('timeout')) {
            _serverStatusMessage = "⏳ Jaringan 4G Lambat (Timeout)";
          } else if (errStr.contains('refused') || errStr.contains('failed to connect')) {
            _serverStatusMessage = "❌ Server 8001 Mati / Port Tertutup";
          } else {
            _serverStatusMessage = "❌ Gagal Menghubungi Server (Periksa Koneksi)";
          }
        });
      }
    }
  }

  // =========================================================================
  // SIKLUS DETEKSI & PENCOCOKAN WAJAH OTOMATIS (DUAL-ENGINE)
  // =========================================================================
  Future<void> _runAutoScanCycle() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isScanningCycle) return;

    _isScanningCycle = true;

    try {
      // 1. Ambil frame foto secara cepat
      XFile picture = await _controller!.takePicture();

      if (_useServerEngine) {
        // MODE 2: Eksekusi Komputasi Berat di Server VPS (YOLOv26 + CLAHE + ArcFace)
        await _runServerScan(picture.path);
      } else {
        // MODE 1: Eksekusi On-Device AI di HP (Google ML Kit + On-Device CLAHE + MobileFaceNet)
        final inputImage = InputImage.fromFilePath(picture.path);
        final faces = await _detectorService.detectFaces(inputImage);

        if (faces.isNotEmpty) {
          final imageBytes = await File(picture.path).readAsBytes();
          final rawImage = img.decodeImage(imageBytes);

          if (rawImage != null) {
            // Selaraskan orientasi rotasi kamera secara otomatis (aman untuk mode lanskap)
            final fullImage = img.bakeOrientation(rawImage);

            List<List<double>> allEmbeddings = [];
            List<List<int>> allBoxes = [];

            for (final face in faces) {
              final bbox = face.boundingBox;
              final croppedFace = _embeddingService.cropAndAlignFace(fullImage, bbox);
              // Ekstraksi embedding dengan On-Device CLAHE aktif di HP
              final embedding = _embeddingService.extractEmbedding(croppedFace);
              allEmbeddings.add(embedding);
              allBoxes.add([
                bbox.left.toInt(),
                bbox.top.toInt(),
                bbox.right.toInt(),
                bbox.bottom.toInt()
              ]);
            }

            // Pencocokan vektor embedding terhadap database
            final results = _matchingService.matchFaces(allEmbeddings, allBoxes);
            List<String> newlyRecognizedNames = [];

            for (var result in results) {
              if (result.nim != "Unknown") {
                final studentIndex = widget.records.indexWhere((r) {
                  final recName = r.studentName.toLowerCase().trim();
                  final resName = result.name.toLowerCase().trim();
                  final resFirstName = resName.split(' ').first;
                  final recFirstName = recName.split(' ').first;
                  return r.studentId == result.nim ||
                      recName == resName ||
                      (resName.isNotEmpty && recName.contains(resName)) ||
                      (recName.isNotEmpty && resName.contains(recName)) ||
                      (resFirstName.length >= 3 && resFirstName == recFirstName);
                });

                if (studentIndex != -1 &&
                    widget.records[studentIndex].status != AttendanceStatus.hadir) {
                  widget.records[studentIndex].status = AttendanceStatus.hadir;
                  final name = widget.records[studentIndex].studentName;
                  newlyRecognizedNames.add(name);

                  if (!_recognizedStudents.contains(name)) {
                    _recognizedStudents.insert(0, name);
                  }
                }
              }
            }

            // Notifikasi visual & getaran jika ada siswa (1 atau lebih) yang berhasil diabsen
            if (newlyRecognizedNames.isNotEmpty) {
              HapticFeedback.mediumImpact();
              if (mounted) {
                setState(() {
                  if (newlyRecognizedNames.length == 1) {
                    _latestRecognizedName = "${newlyRecognizedNames.first} (On-Device + CLAHE)";
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
      }

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
                              ? (_useServerEngine
                                  ? (_serverStatusMessage ?? "Mode Server YOLOv26 + CLAHE Aktif")
                                  : "Arahkan wajah siswa ke dalam kotak")
                              : "Auto-scan dijeda. Tekan tombol Play di bawah.",
                          style: TextStyle(
                            color: _useServerEngine &&
                                    _serverStatusMessage != null &&
                                    _serverStatusMessage!.startsWith("❌")
                                ? Colors.amberAccent
                                : (_useServerEngine &&
                                        _serverStatusMessage != null &&
                                        _serverStatusMessage!.startsWith("✅")
                                    ? Colors.greenAccent
                                    : Colors.white70),
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
                    ? (_useServerEngine &&
                            _serverStatusMessage != null &&
                            _serverStatusMessage!.startsWith("❌")
                        ? Colors.red.shade900.withOpacity(0.92)
                        : Colors.green.shade800.withOpacity(0.92))
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
                        ? (_useServerEngine
                            ? "🌐 Server YOLOv26: ${_serverStatusMessage ?? '103.175.206.22:8001'}"
                            : "🟢 Auto-Scan Aktif ($_statusText)")
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

          // Saklar Pilihan Mode (Dual-Engine: On-Device + CLAHE vs Server VPS YOLOv26)
          Positioned(
            top: 54,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() => _useServerEngine = false);
                      _startContinuousAutoScan();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: !_useServerEngine ? Colors.green.shade600 : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.bolt, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            "⚡ On-Device + CLAHE",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      setState(() => _useServerEngine = true);
                      _startContinuousAutoScan();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _useServerEngine ? Colors.blue.shade700 : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.cloud_sync, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            "🌐 Server YOLOv26",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Notifikasi Pop-Up Hijau Saat Siswa Terdeteksi
          if (_latestRecognizedName != null)
            Positioned(
              top: 98,
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
              // Baris Ringkasan Jumlah Siswa Hadir & Chip Siswa yang Sudah Terabsen
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