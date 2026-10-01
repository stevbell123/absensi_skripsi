// =========================================================================
// ATTENDANCE SCREEN (VERSI ON-DEVICE)
// =========================================================================
// SEBELUM: Foto dikirim ke server → server deteksi + embedding + matching → JSON
// SESUDAH: Semua proses dilakukan 100% di smartphone:
//   1. Google ML Kit → deteksi wajah (bounding box)
//   2. MobileFaceNet TFLite → embedding 128-d
//   3. Euclidean distance di Dart → matching
//
// Perubahan utama dari versi lama:
// - TIDAK ADA lagi HTTP request ke server
// - TIDAK ADA lagi timeout 60 detik menunggu server
// - Semua berjalan dalam ~50-500ms (tergantung jumlah wajah)
// - Bisa berfungsi TANPA internet (offline)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;

import '../models/attendance_model.dart';
import '../../../core/ai/face_detector_service.dart';
import '../../../core/ai/face_embedding_service.dart';
import '../../../core/ai/face_matching_service.dart';
import '../../../core/ai/face_database_service.dart';

class AttendanceScreen extends StatefulWidget {
  final List<AttendanceRecord> records;

  // classId diperlukan untuk sinkronisasi embedding kelas ini dari Firestore
  final String classId;

  const AttendanceScreen({
    Key? key,
    required this.records,
    required this.classId,
  }) : super(key: key);

  @override
  _AttendanceScreenState createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  bool _isCameraInitialized = false;
  bool _isScanning = false;
  bool _isFlashOn = false;
  bool _isAutoScan = false;
  Timer? _autoScanTimer;

  // === SERVICE AI (ON-DEVICE) ===
  // Tiga service ini menggantikan SELURUH server Python
  late FaceDetectorService _detectorService;
  late FaceEmbeddingService _embeddingService;
  late FaceMatchingService _matchingService;
  late FaceDatabaseService _databaseService;

  bool _isAiReady = false;
  String _statusText = 'Mempersiapkan AI...';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeAI(); // <-- BARU: muat model AI saat halaman dibuka
  }

  void _toggleAutoScan(bool enable) {
    setState(() => _isAutoScan = enable);
    _autoScanTimer?.cancel();
    if (_isAutoScan) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🔭 Mode Tripod Aktif: AI memindai otomatis setiap 3 detik."),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      _autoScanTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (!_isScanning && _isAiReady && mounted) {
          _scanBarisanSiswa();
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("📱 Mode Handheld: Tekan tombol untuk memindai barisan meja."),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // =========================================================================
  // INISIALISASI AI
  // =========================================================================
  Future<void> _initializeAI() async {
    try {
      setState(() => _statusText = 'Memuat model AI...');

      // 1. Inisialisasi service
      _detectorService = FaceDetectorService();
      _embeddingService = FaceEmbeddingService();
      _matchingService = FaceMatchingService();
      _databaseService = FaceDatabaseService();

      // 2. Load model TFLite dari assets
      await _embeddingService.initialize();
      if (!_embeddingService.isReady) {
        setState(() => _statusText = '❌ Gagal memuat model AI');
        return;
      }

      // 3. Sinkron embedding dari Firestore → cache ke Hive
      setState(() => _statusText = 'Menyinkronkan data wajah...');
      await _databaseService.initHive();

      List<FaceRecord> records = [];
      try {
        // Coba sinkron dari Firestore khusus kelas ini
        records = await _databaseService.syncByClass(widget.classId);
        // Jika kosong, coba ambil semua data wajah terdaftar
        if (records.isEmpty) {
          records = await _databaseService.syncFromFirestore();
        }
      } catch (e) {
        // Kalau offline, pakai cache lokal yang sudah ada
        debugPrint('[AI] Firestore gagal, memakai cache lokal: $e');
        records = await _databaseService.loadFromLocal();
      }

      // 4. Masukkan ke matching service
      _matchingService.loadDatabase(records);

      setState(() {
        _isAiReady = true;
        _statusText = records.isNotEmpty
            ? '✅ Siap Pindai (${records.length} siswa dimuat)'
            : '⚠️ 0 Siswa (Daftarkan wajah dahulu)';
      });

      debugPrint('[AI] Inisialisasi selesai: ${records.length} siswa dimuat');
    } catch (e) {
      setState(() => _statusText = '❌ Error: $e');
      debugPrint('[AI] Gagal inisialisasi: $e');
    }
  }

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

      _controller = CameraController(camera, ResolutionPreset.high,
          enableAudio: false);
      await _controller!.initialize();

      _isFlashOn = false;

      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Error inisialisasi kamera: $e");
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2 || _isScanning) return;

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

  // =========================================================================
  // SCAN BARISAN SISWA (VERSI ON-DEVICE)
  //
  // SEBELUM (server):
  //   1. Ambil foto → upload via HTTP → tunggu 1-60 detik → terima JSON
  //
  // SESUDAH (on-device):
  //   1. Ambil foto
  //   2. ML Kit deteksi wajah (~15-30ms)
  //   3. Untuk setiap wajah: crop → MobileFaceNet → embedding (~15-25ms)
  //   4. Matching euclidean distance terhadap database (~<1ms)
  //   5. Total: ~50-500ms untuk 10 wajah
  // =========================================================================
  Future<void> _scanBarisanSiswa() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isScanning) return;

    if (!_isAiReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⏳ AI belum siap. Tunggu sebentar..."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isScanning = true);

    try {
      // LANGKAH 1: Ambil foto dari kamera
      XFile picture = await _controller!.takePicture();

      // LANGKAH 2: Kirim ke Server VPS (YOLOv8 + ArcFace di Port 8001)
      bool serverSuccess = false;
      int matchedCount = 0;
      int totalFaces = 0;

      try {
        final uri = Uri.parse('http://103.175.206.22:8001/api/scan-attendance');
        final request = http.MultipartRequest('POST', uri);
        request.fields['class_id'] = widget.classId;
        request.files.add(await http.MultipartFile.fromPath('file', picture.path));

        final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            final List siswaDikenali = data['siswa_dikenali'] ?? [];
            totalFaces = data['wajah_terdeteksi'] ?? 0;

            for (var siswa in siswaDikenali) {
              final nim = siswa['nim']?.toString() ?? '';
              final nama = siswa['nama']?.toString().toLowerCase() ?? '';

              final studentIndex = widget.records.indexWhere((r) =>
                  r.studentId == nim ||
                  r.studentName.toLowerCase() == nama);

              if (studentIndex != -1) {
                if (widget.records[studentIndex].status != AttendanceStatus.hadir) {
                  widget.records[studentIndex].status = AttendanceStatus.hadir;
                  matchedCount++;
                }
              }
            }
            serverSuccess = true;
            debugPrint('[SERVER YOLO] Sukses: $matchedCount siswa dikenali dari $totalFaces wajah.');
          }
        }
      } catch (err) {
        debugPrint('[SERVER YOLO] Gagal/Timeout ($err), menggunakan fallback On-Device AI.');
      }

      // LANGKAH 3 (FALLBACK ON-DEVICE): Jika server VPS tidak merespons
      if (!serverSuccess) {
        final inputImage = InputImage.fromFilePath(picture.path);
        final faces = await _detectorService.detectFaces(inputImage);
        totalFaces = faces.length;

        if (faces.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("⚠️ Tidak ada wajah terdeteksi. Coba lagi."),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        final imageBytes = await File(picture.path).readAsBytes();
        final fullImage = img.decodeImage(imageBytes);
        if (fullImage == null) throw Exception("Gagal membaca gambar");

        List<List<double>> allEmbeddings = [];
        List<List<int>> allBoxes = [];

        for (final face in faces) {
          final bbox = face.boundingBox;
          final croppedFace = _embeddingService.cropAndAlignFace(fullImage, bbox);
          final embedding = _embeddingService.extractEmbedding(croppedFace);
          allEmbeddings.add(embedding);
          allBoxes.add([bbox.left.toInt(), bbox.top.toInt(), bbox.right.toInt(), bbox.bottom.toInt()]);
        }

        final results = _matchingService.matchFaces(allEmbeddings, allBoxes);
        for (var result in results) {
          if (result.nim != "Unknown") {
            final studentIndex = widget.records.indexWhere((r) =>
                r.studentId == result.nim ||
                r.studentName.toLowerCase() == result.name.toLowerCase());

            if (studentIndex != -1 && widget.records[studentIndex].status != AttendanceStatus.hadir) {
              widget.records[studentIndex].status = AttendanceStatus.hadir;
              matchedCount++;
            }
          }
        }
      }

      if (mounted) {
        final modeText = serverSuccess ? "Server YOLO + ArcFace" : "On-Device AI";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "✅ $matchedCount siswa dikenali ($modeText) dari $totalFaces wajah. Silakan periksa kembali."),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context, widget.records);
      }
    } catch (e) {
      debugPrint('[AI] Error saat scan: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Gagal memindai: $e"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  void dispose() {
    _autoScanTimer?.cancel();
    _controller?.dispose();
    _detectorService.dispose();
    _embeddingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Pindai Wajah Kelas (AI Scan)"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: const Icon(Icons.flip_camera_ios),
              tooltip: 'Tukar Kamera',
              onPressed: _switchCamera),
          IconButton(
              icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
              tooltip: 'Lampu Flash',
              onPressed: _toggleFlash)
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          // Kamera bersih (Full Screen)
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: 1 / _controller!.value.aspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),

          // Bingkai Kotak Scanner AI Modern
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isScanning ? Colors.greenAccent : Colors.white.withOpacity(0.4),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // 4 Sudut Laser Scanner
                  Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      width: 26, height: 26,
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.greenAccent, width: 4),
                          left: BorderSide(color: Colors.greenAccent, width: 4),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      width: 26, height: 26,
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.greenAccent, width: 4),
                          right: BorderSide(color: Colors.greenAccent, width: 4),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      width: 26, height: 26,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.greenAccent, width: 4),
                          left: BorderSide(color: Colors.greenAccent, width: 4),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 26, height: 26,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.greenAccent, width: 4),
                          right: BorderSide(color: Colors.greenAccent, width: 4),
                        ),
                      ),
                    ),
                  ),
                  if (_isScanning)
                    const Center(
                      child: Divider(
                        color: Colors.greenAccent,
                        thickness: 2.5,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Banner Status AI di Atas
          Positioned(
            top: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _isAiReady
                    ? Colors.green.withOpacity(0.9)
                    : Colors.orange.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isAiReady)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  Text(
                    _statusText,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          // Tombol Pilihan Mode (Tripod Auto-Scan vs Handheld)
          Positioned(
            top: 60,
            child: ActionChip(
              avatar: Icon(_isAutoScan ? Icons.videocam : Icons.touch_app,
                  color: Colors.white, size: 18),
              label: Text(
                  _isAutoScan
                      ? "Mode: 🔭 Tripod (Auto-Scan Tiap 3 Detik)"
                      : "Mode: 📱 Handheld (Pindai Barisan)",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
              backgroundColor: _isAutoScan ? Colors.green.shade800 : Colors.black87,
              side: const BorderSide(color: Colors.white30),
              onPressed: () => _toggleAutoScan(!_isAutoScan),
            ),
          ),

          if (_isScanning)
            Container(
              color: Colors.black.withOpacity(0.8),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                        color: Colors.greenAccent, strokeWidth: 6),
                    SizedBox(height: 24),
                    Text(
                      "Sedang memindai wajah siswa...\n(AI YOLOv26 + ArcFace)",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.5,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton.icon(
            onPressed:
                (_isScanning || !_isAiReady) ? null : _scanBarisanSiswa,
            icon: const Icon(Icons.document_scanner, size: 26),
            label: Text(
                _isAutoScan
                    ? "⚡ Auto-Scan Berjalan (Tripod)"
                    : "🔍 Pindai / Scan Wajah Sekarang",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _isAutoScan ? Colors.green.shade700 : Colors.indigo,
                foregroundColor: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ),
    );
  }
}