// =========================================================================
// REGISTER STUDENT SCREEN (VERSI ON-DEVICE)
// =========================================================================
// SEBELUM: Foto dikirim ke server /register → server deteksi + simpan embedding
// SESUDAH: Semua proses dilakukan 100% di smartphone:
//   1. Google ML Kit → deteksi wajah (pastikan tepat 1 wajah)
//   2. MobileFaceNet TFLite → embedding 128-d
//   3. Simpan embedding ke Firestore koleksi 'face_embeddings'
//   4. Foto thumbnail disimpan ke Firestore (base64, sama seperti sebelumnya)
//
// Perubahan utama:
// - TIDAK ADA lagi HTTP request ke server
// - Embedding dihitung langsung di HP
// - Jika ada 3 variasi foto, embedding dirata-ratakan (sama seperti server)
// - Bisa berfungsi TANPA server Python aktif
// =========================================================================

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../core/ai/face_detector_service.dart';
import '../../../core/ai/face_embedding_service.dart';
import '../../../core/ai/face_database_service.dart';

class RegisterStudentScreen extends StatefulWidget {
  final String initialNim;
  final String initialName;
  final String classId;
  final String studentDocId;

  const RegisterStudentScreen({
    Key? key,
    this.initialNim = '',
    this.initialName = '',
    this.classId = '',
    this.studentDocId = '',
  }) : super(key: key);

  @override
  State<RegisterStudentScreen> createState() => _RegisterStudentScreenState();
}

class _RegisterStudentScreenState extends State<RegisterStudentScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  bool _isCameraInitialized = false;
  bool _isLoading = false;

  bool _isFlashOn = false;
  bool _isExposureLocked = false;

  final TextEditingController _nimController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  // === SERVICE AI (ON-DEVICE) ===
  late FaceDetectorService _detectorService;
  late FaceEmbeddingService _embeddingService;
  late FaceDatabaseService _databaseService;

  bool _isAiReady = false;
  String _aiStatusText = 'Memuat model AI...';



  @override
  void initState() {
    super.initState();
    _nimController.text = widget.initialNim;
    _nameController.text = widget.initialName;
    _initializeCamera();
    _initializeAI();
  }

  // =========================================================================
  // INISIALISASI AI
  // Hanya perlu load model MobileFaceNet (~5MB, <1 detik)
  // Tidak perlu sinkron database karena ini registrasi, bukan pencocokan
  // =========================================================================
  Future<void> _initializeAI() async {
    try {
      _detectorService = FaceDetectorService();
      _embeddingService = FaceEmbeddingService();
      _databaseService = FaceDatabaseService();

      await _embeddingService.initialize();
      await _databaseService.initHive();

      if (_embeddingService.isReady) {
        setState(() {
          _isAiReady = true;
          _aiStatusText = '✅ AI siap';
        });
      } else {
        setState(() => _aiStatusText = '❌ Gagal memuat model');
      }
    } catch (e) {
      setState(() => _aiStatusText = '❌ Error: $e');
      debugPrint('[AI] Gagal inisialisasi: $e');
    }
  }

  Future<void> _initializeCamera([int cameraIndex = -1]) async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      if (cameraIndex == -1) {
        _selectedCameraIndex = _cameras
            .indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
      } else {
        _selectedCameraIndex = cameraIndex;
      }

      final camera = _cameras[_selectedCameraIndex];
      if (_controller != null) await _controller!.dispose();

      _controller = CameraController(camera, ResolutionPreset.high,
          enableAudio: false);
      await _controller!.initialize();

      _isFlashOn = false;
      _isExposureLocked = false;

      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Error inisialisasi kamera: $e");
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2 || _isLoading) return;
    setState(() => _isCameraInitialized = false);
    final currentDirection = _cameras[_selectedCameraIndex].lensDirection;
    final newIndex =
        _cameras.indexWhere((c) => c.lensDirection != currentDirection);
    await _initializeCamera(
        newIndex != -1 ? newIndex : (_selectedCameraIndex + 1) % _cameras.length);
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

  void _toggleExposureLock() async {
    if (_controller != null && _controller!.value.isInitialized) {
      setState(() => _isExposureLocked = !_isExposureLocked);
      if (_isExposureLocked) {
        await _controller!.setExposureMode(ExposureMode.locked);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("🔒 Cahaya Dikunci")));
        }
      } else {
        await _controller!.setExposureMode(ExposureMode.auto);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("🔓 Cahaya Otomatis")));
        }
      }
    }
  }

  // =========================================================================
  // SIMPAN THUMBNAIL KE FIRESTORE (sama seperti versi lama)
  // =========================================================================
  Future<void> _savePhotoToFirestore(String imagePath) async {
    if (widget.classId.isEmpty || widget.studentDocId.isEmpty) return;
    try {
      final bytes = await XFile(imagePath).readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage != null) {
        img.Image resizedImage = img.copyResize(originalImage, width: 150);
        List<int> compressedBytes = img.encodeJpg(resizedImage, quality: 70);
        String base64String = base64Encode(compressedBytes);

        await FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('students')
            .doc(widget.studentDocId)
            .update({'photoBase64': base64String});
      }
    } catch (e) {
      debugPrint("Gagal update foto Base64 ke Firestore: $e");
    }
  }

  // =========================================================================
  // DETEKSI + EMBEDDING SATU FOTO (BARU — ON-DEVICE)
  //
  // Menggantikan HTTP POST ke server /register.
  // Langkah:
  //   1. ML Kit deteksi wajah di foto
  //   2. Validasi: harus tepat 1 wajah
  //   3. Crop → MobileFaceNet → embedding 128-d
  //   4. Simpan embedding ke list sementara
  //
  // Mengembalikan 2 embedding dari foto yang sama: dengan CLAHE (dipakai
  // absensi normal) dan tanpa CLAHE (pembanding eksperimen RM 1).
  // =========================================================================
  Future<({List<double> denganClahe, List<double> tanpaClahe})?> _processOnePhoto(
      String filePath) async {
    // 1. Deteksi wajah menggunakan ML Kit
    final inputImage = InputImage.fromFilePath(filePath);
    final faces = await _detectorService.detectFaces(inputImage);

    if (faces.isEmpty) {
      _showError("Wajah tidak terdeteksi. Posisikan wajah di dalam bingkai oval.");
      return null;
    }

    // Urutkan wajah berdasarkan luas bounding box terbesar (wajah utama/dominan siswa)
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));

    final dominantFace = faces.first;
    final dominantArea = dominantFace.boundingBox.width * dominantFace.boundingBox.height;

    // Filter cerdas anti-objek latar belakang:
    // Jika terdeteksi lebih dari 1 wajah (misal: foto di dinding, pantulan, orang jauh di belakang),
    // periksa apakah wajah kedua cukup besar (>= 35% ukuran wajah utama).
    // Jika wajah kedua kecil, abaikan karena itu hanya noise latar belakang.
    if (faces.length > 1) {
      final secondaryArea = faces[1].boundingBox.width * faces[1].boundingBox.height;
      if (secondaryArea >= 0.35 * dominantArea) {
        _showError("Ada lebih dari 1 orang di depan kamera. Pastikan hanya 1 siswa di dalam bingkai.");
        return null;
      }
      debugPrint('[AI] Terdeteksi ${faces.length} wajah. Mengabaikan ${faces.length - 1} wajah kecil di latar belakang.');
    }

    // 2. Baca gambar untuk di-crop
    final imageBytes = await File(filePath).readAsBytes();
    final fullImage = img.decodeImage(imageBytes);
    if (fullImage == null) {
      _showError("Gagal membaca gambar.");
      return null;
    }

    // 3. Crop dan hitung embedding berdasarkan wajah dominan siswa
    final croppedFace = _embeddingService.cropAndAlignFace(
      fullImage,
      dominantFace.boundingBox,
    );
    final embedding = _embeddingService.extractEmbedding(croppedFace);
    final embeddingTanpaClahe =
        _embeddingService.extractEmbedding(croppedFace, applyClahe: false);

    debugPrint('[AI] Embedding dominan berhasil dihitung (${embedding.length}-d)');
    return (denganClahe: embedding, tanpaClahe: embeddingTanpaClahe);
  }

  // =========================================================================
  // SINKRONISASI SERVER VPS DI LATAR BELAKANG (ASINKRON)
  // =========================================================================
  Future<void> _syncToServer(String imagePath, String nim, String name) async {
    // 1. Coba kirim ke Port 8001 (Server Baru: YOLOv26 + ArcFace)
    try {
      final uri = Uri.parse('http://103.175.206.22:8001/api/register-student');
      final request = http.MultipartRequest('POST', uri);
      request.fields['nim'] = nim;
      request.fields['nama'] = name;
      request.fields['class_id'] = widget.classId;
      request.files.add(await http.MultipartFile.fromPath('file', imagePath));
      final res = await request.send().timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        debugPrint('[SERVER 8001] ✅ Sukses sinkronisasi siswa ke server 8001.');
        return;
      }
    } catch (e) {
      debugPrint('[SERVER 8001] Info server 8001: $e');
    }

    // 2. Fallback kirim ke Port 8000 (Server Lama: YOLO + dlib)
    try {
      final uri = Uri.parse('http://103.175.206.22:8000/register');
      final request = http.MultipartRequest('POST', uri);
      request.fields['nim'] = nim;
      request.fields['name'] = name;
      request.fields['variasi'] = '1';
      request.files.add(await http.MultipartFile.fromPath('file', imagePath));
      final res = await request.send().timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        debugPrint('[SERVER 8000] ✅ Sukses sinkronisasi siswa ke server 8000.');
      }
    } catch (e) {
      debugPrint('[SERVER 8000] Info server 8000: $e');
    }
  }

  // =========================================================================
  // PINDAI & DAFTARKAN WAJAH (SEKALI PINDAI / SCAN)
  // =========================================================================
  Future<void> _registerFace() async {
    final nim = _nimController.text.trim();
    final name = _nameController.text.trim();

    if (nim.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ ID/NIM dan Nama tidak boleh kosong!")));
      return;
    }
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isLoading) return;
    if (!_isAiReady) {
      _showError("AI belum siap. Tunggu sebentar...");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Ambil foto dari kamera
      XFile picture = await _controller!.takePicture();

      // 2. Deteksi wajah & ekstrak embedding secara on-device
      final embedding = await _processOnePhoto(picture.path);
      if (embedding == null) {
        setState(() => _isLoading = false);
        return;
      }

      // 3. Simpan embedding ke database lokal (Hive) & Firestore (Cloud)
      await _databaseService.saveEmbedding(
        nim,
        name,
        embedding.denganClahe,
        embeddingTanpaClahe: embedding.tanpaClahe,
      );

      // 4. Simpan thumbnail foto siswa ke Firestore (non-fatal jika permission tertutup)
      try {
        await _savePhotoToFirestore(picture.path);
      } catch (fe) {
        debugPrint('[FIRESTORE] Gagal simpan thumbnail foto siswa: $fe');
      }

      // 5. Sinkronkan ke server VPS di background
      _syncToServer(picture.path, nim, name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Berhasil! Wajah $name ($nim) berhasil dipindai & terdaftar."),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showError("Gagal mendaftarkan wajah: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =========================================================================
  // DAFTAR VIA GALERI (1 Foto, on-device)
  // =========================================================================
  Future<void> _pickFromGallery() async {
    final nim = _nimController.text.trim();
    final name = _nameController.text.trim();

    if (nim.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ ID/NIM dan Nama tidak boleh kosong!")));
      return;
    }
    if (!_isAiReady) {
      _showError("AI belum siap. Tunggu sebentar...");
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() => _isLoading = true);

      // Proses on-device
      final embedding = await _processOnePhoto(image.path);
      if (embedding == null) {
        setState(() => _isLoading = false);
        return;
      }

      // 1. Simpan embedding ke Hive lokal & Firestore
      await _databaseService.saveEmbedding(
        nim,
        name,
        embedding.denganClahe,
        embeddingTanpaClahe: embedding.tanpaClahe,
      );

      // 2. Simpan thumbnail foto ke Firestore
      try {
        await _savePhotoToFirestore(image.path);
      } catch (fe) {
        debugPrint('[FIRESTORE] Gagal simpan thumbnail dari galeri: $fe');
      }

      // 3. Sinkronkan ke server VPS di background
      _syncToServer(image.path, nim, name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("✅ Berhasil! Wajah $name ($nim) berhasil didaftarkan dari Galeri."),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ $message"), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _nimController.dispose();
    _nameController.dispose();
    _detectorService.dispose();
    _embeddingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Registrasi Wajah AI"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
                _isExposureLocked
                    ? Icons.brightness_auto
                    : Icons.brightness_auto_outlined,
                color: _isExposureLocked ? Colors.indigo : Colors.black87),
            onPressed: _toggleExposureLock,
          ),
          IconButton(
              icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off,
                  color: Colors.black87),
              onPressed: _toggleFlash),
          IconButton(
              icon: const Icon(Icons.flip_camera_ios,
                  color: Colors.black87, size: 28),
              onPressed: _switchCamera),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // === PREVIEW KAMERA DENGAN OVAL SCANNER FRAME ===
            Container(
              width: double.infinity,
              height: 400,
              color: Colors.black,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller!.value.previewSize!.height,
                        height: _controller!.value.previewSize!.width,
                        child: LayoutBuilder(builder: (context, constraints) {
                          return GestureDetector(
                            onTapDown: (details) async {
                              if (_controller == null ||
                                  !_controller!.value.isInitialized) return;
                              final offset = Offset(
                                  details.localPosition.dx / constraints.maxWidth,
                                  details.localPosition.dy /
                                      constraints.maxHeight);
                              await _controller!.setFocusPoint(offset);
                              if (!_isExposureLocked) {
                                await _controller!.setExposurePoint(offset);
                              }
                            },
                            child: CameraPreview(_controller!),
                          );
                        }),
                      ),
                    ),
                  ),

                  // Bingkai Oval Scanner Target Wajah
                  Container(
                    width: 220,
                    height: 290,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isAiReady ? Colors.greenAccent : Colors.white,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(140),
                      boxShadow: [
                        BoxShadow(
                          color: (_isAiReady ? Colors.greenAccent : Colors.white)
                              .withOpacity(0.2),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),

                  // Label Panduan di Bawah Bingkai
                  Positioned(
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.face, color: Colors.greenAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            "Posisikan wajah di dalam bingkai oval",
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // === STATUS AI ===
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: _isAiReady ? Colors.green.shade50 : Colors.orange.shade50,
              child: Text(
                _aiStatusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _isAiReady
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
              ),
            ),

            // === PANDUAN PINDAI ===
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.qr_code_scanner, color: Colors.indigo, size: 20),
                      SizedBox(width: 8),
                      Text("Panduan Pindai Wajah Siswa:",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                              fontSize: 14)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text("1. Arahkan wajah siswa tepat di dalam bingkai oval.",
                      style: TextStyle(fontSize: 13, color: Colors.black87)),
                  SizedBox(height: 4),
                  Text("2. Pastikan pencahayaan cukup dan wajah siswa menatap lurus.",
                      style: TextStyle(fontSize: 13, color: Colors.black87)),
                  SizedBox(height: 4),
                  Text("3. Tekan tombol 'Pindai & Daftarkan Wajah' di bawah.",
                      style: TextStyle(fontSize: 13, color: Colors.black87)),
                ],
              ),
            ),

            // === FORM NIM + NAMA ===
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  TextField(
                    controller: _nimController,
                    decoration: InputDecoration(
                      labelText: 'ID / NIM / Email Siswa',
                      prefixIcon: const Icon(Icons.badge),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Nama Lengkap Siswa',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // === TOMBOL PINDAI WAJAH + GALERI ===
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          onPressed:
                              (_isLoading || !_isAiReady) ? null : _registerFace,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.document_scanner, size: 22),
                          label: const Text(
                              "Pindai & Daftarkan Wajah",
                              style:
                                  TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 15),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed:
                              (_isLoading || !_isAiReady) ? null : _pickFromGallery,
                          child: const Icon(Icons.photo_library, color: Colors.indigo),
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Colors.indigo, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}