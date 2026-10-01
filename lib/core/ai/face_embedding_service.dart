import 'dart:math';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Layanan untuk menghasilkan embedding wajah (128-dimensi) menggunakan MobileFaceNet via TFLite.
/// 
/// Mengapa menggunakan MobileFaceNet?
/// - Ukuran model kecil (sekitar 5MB) sehingga ringan dijalankan di perangkat mobile.
/// - Menghasilkan vektor 128 dimensi, format yang sama dengan dlib.
/// - Eksekusi cepat dan efisien untuk real-time inference.
class FaceEmbeddingService {
  static const String modelPath = 'assets/models/mobilefacenet.tflite';
  Interpreter? _interpreter;

  bool get isReady => _interpreter != null;

  /// Menginisialisasi interpreter TFLite dengan model MobileFaceNet dari assets.
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);
    } catch (e) {
      print('Gagal memuat model MobileFaceNet: $e');
    }
  }

  /// Memotong area wajah dari gambar asli dan menyiapkannya untuk inferensi.
  img.Image cropAndAlignFace(img.Image fullImage, Rect boundingBox) {
    // Menambahkan 15% padding di sekitar bounding box agar seluruh elemen wajah tertangkap
    final double paddingX = boundingBox.width * 0.15;
    final double paddingY = boundingBox.height * 0.15;

    final int left = (boundingBox.left - paddingX).floor();
    final int top = (boundingBox.top - paddingY).floor();
    final int width = (boundingBox.width + paddingX * 2).ceil();
    final int height = (boundingBox.height + paddingY * 2).ceil();

    // Membatasi koordinat crop agar tidak melewati batas dimensi gambar (clamp to image bounds)
    final int clampedLeft = left.clamp(0, fullImage.width);
    final int clampedTop = top.clamp(0, fullImage.height);
    final int clampedRight = (left + width).clamp(0, fullImage.width);
    final int clampedBottom = (top + height).clamp(0, fullImage.height);

    final int finalWidth = clampedRight - clampedLeft;
    final int finalHeight = clampedBottom - clampedTop;

    // Memotong regio wajah (crop face region)
    img.Image croppedFace = img.copyCrop(
      fullImage,
      x: clampedLeft,
      y: clampedTop,
      width: finalWidth,
      height: finalHeight,
    );

    // Mengubah ukuran gambar menjadi 112x112 sesuai input yang dibutuhkan MobileFaceNet
    return img.copyResize(croppedFace, width: 112, height: 112);
  }

  /// Mengekstraksi vektor embedding dari gambar wajah berukuran 112x112.
  List<double> extractEmbedding(img.Image faceImage) {
    if (_interpreter == null) {
      throw Exception('FaceEmbeddingService: Interpreter belum diinisialisasi');
    }

    // Pastikan ukuran gambar adalah 112x112
    img.Image resizedImage = faceImage;
    if (resizedImage.width != 112 || resizedImage.height != 112) {
      resizedImage = img.copyResize(resizedImage, width: 112, height: 112);
    }

    // Membuat tensor input shape [1, 112, 112, 3]
    var input = List.generate(
      1,
      (i) => List.generate(
        112,
        (y) => List.generate(
          112,
          (x) => List.filled(3, 0.0),
        ),
      ),
    );

    // Mengapa normalisasi nilai piksel ke rentang [-1, 1]?
    // Karena model MobileFaceNet dilatih menggunakan input gambar yang dinormalisasi dengan cara ini.
    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final img.Pixel pixel = resizedImage.getPixel(x, y);
        // Divide by 127.5 then subtract 1
        input[0][y][x][0] = (pixel.r - 127.5) / 127.5;
        input[0][y][x][1] = (pixel.g - 127.5) / 127.5;
        input[0][y][x][2] = (pixel.b - 127.5) / 127.5;
      }
    }

    // Tensor output memiliki shape [1, 128]
    var output = List.generate(1, (i) => List.filled(128, 0.0));

    // Menjalankan inferensi model
    _interpreter!.run(input, output);

    List<double> embedding = output[0];

    // L2 Normalization (Normalisasi output embedding ke unit length)
    // Mengapa kita melakukan L2 normalisasi?
    // Agar panjang vektor menjadi 1. Dengan begitu, vektor berada di permukaan hypersphere
    // dan cosine similarity antar dua vektor dapat dihitung cukup dengan dot product saja,
    // yang membuat perbandingan dua wajah menjadi sangat cepat.
    double sum = 0.0;
    for (int i = 0; i < embedding.length; i++) {
      sum += embedding[i] * embedding[i];
    }
    double norm = sqrt(sum);
    
    if (norm > 0) {
      for (int i = 0; i < embedding.length; i++) {
        embedding[i] = embedding[i] / norm;
      }
    }

    return embedding;
  }

  /// Membersihkan resource interpreter dari memori
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
