import 'dart:math';
import 'package:image/image.dart' as img;

/// =========================================================================
/// SERVICE PRA-PEMROSESAN CITRA: ON-DEVICE CLAHE
/// (Contrast Limited Adaptive Histogram Equalization)
/// =========================================================================
/// Modul pengolahan citra digital berbasis pure Dart berkecepatan tinggi (~3-5 ms).
/// Bertugas mengelevasi kontras adaptif pada kanal Luminansi (Y) secara lokal
/// untuk mengatasi bayangan tajam (shadows) dan backlight di ruang kelas,
/// tanpa mendistorsi rona warna asli kulit atau mengamplifikasi noise.
/// =========================================================================
class ClaheService {
  /// Batas ambang kliping kontras standar (sesuai kalibrasi skripsi)
  static const double defaultClipLimit = 2.0;

  /// Jumlah blok kisi kontekstual (8x8 grid tiles)
  static const int defaultGridSize = 8;

  /// Menerapkan CLAHE pada citra wajah secara cepat dan efisien.
  /// Parameter [src] adalah objek img.Image beresolusi 112x112 piksel.
  static img.Image applyClahe(
    img.Image src, {
    double clipLimit = defaultClipLimit,
    int gridSize = defaultGridSize,
  }) {
    final int width = src.width;
    final int height = src.height;

    // Buat citra tujuan dengan dimensi yang sama
    final img.Image dst = img.Image(width: width, height: height);

    // 1. Ekstrak kanal Luminansi Y untuk setiap piksel
    // Formula standar ITU-R BT.601: Y = 0.299*R + 0.587*G + 0.114*B
    final List<int> luminanceMap = List<int>.filled(width * height, 0);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = src.getPixel(x, y);
        final int yVal = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            .round()
            .clamp(0, 255);
        luminanceMap[y * width + x] = yVal;
      }
    }

    // 2. Hitung dimensi tiap blok tile
    final int tileW = max(1, width ~/ gridSize);
    final int tileH = max(1, height ~/ gridSize);

    // 3. Bangun Cumulative Distribution Function (CDF) terklip untuk tiap tile
    final List<List<int>> tileCdfs = [];
    for (int ty = 0; ty < gridSize; ty++) {
      for (int tx = 0; tx < gridSize; tx++) {
        final int startX = tx * tileW;
        final int endX = (tx == gridSize - 1) ? width : min(startX + tileW, width);
        final int startY = ty * tileH;
        final int endY = (ty == gridSize - 1) ? height : min(startY + tileH, height);
        final int tilePixelCount = max(1, (endX - startX) * (endY - startY));

        // a. Hitung histogram 256 bin untuk tile ini
        final List<int> hist = List<int>.filled(256, 0);
        for (int py = startY; py < endY; py++) {
          for (int px = startX; px < endX; px++) {
            final int val = luminanceMap[py * width + px];
            hist[val]++;
          }
        }

        // b. Terapkan batasan kliping kontras (Clip Limit)
        final int actualClipLimit = max(1, (clipLimit * (tilePixelCount / 256.0)).round());
        int excess = 0;
        for (int i = 0; i < 256; i++) {
          if (hist[i] > actualClipLimit) {
            excess += hist[i] - actualClipLimit;
            hist[i] = actualClipLimit;
          }
        }

        // c. Distribusikan piksel berlebih (excess) secara merata ke seluruh bin
        final int bonusPerBin = excess ~/ 256;
        final int remainder = excess % 256;
        for (int i = 0; i < 256; i++) {
          hist[i] += bonusPerBin;
          if (i < remainder) {
            hist[i]++;
          }
        }

        // d. Bentuk CDF ternormalisasi [0..255]
        final List<int> cdf = List<int>.filled(256, 0);
        int sum = 0;
        final double scale = 255.0 / tilePixelCount;
        for (int i = 0; i < 256; i++) {
          sum += hist[i];
          cdf[i] = (sum * scale).round().clamp(0, 255);
        }

        tileCdfs.add(cdf);
      }
    }

    // 4. Terapkan interpolasi bilinear antar-tile untuk menghilangkan efek kotak
    for (int y = 0; y < height; y++) {
      // Posisi y relatif terhadap pusat tile
      final double yPos = (y - (tileH / 2.0)) / tileH;
      int ty1 = yPos.floor();
      int ty2 = ty1 + 1;
      final double yWeight = yPos - ty1;

      ty1 = ty1.clamp(0, gridSize - 1);
      ty2 = ty2.clamp(0, gridSize - 1);

      for (int x = 0; x < width; x++) {
        final double xPos = (x - (tileW / 2.0)) / tileW;
        int tx1 = xPos.floor();
        int tx2 = tx1 + 1;
        final double xWeight = xPos - tx1;

        tx1 = tx1.clamp(0, gridSize - 1);
        tx2 = tx2.clamp(0, gridSize - 1);

        final int originalY = luminanceMap[y * width + x];

        // Ambil nilai CDF dari 4 tile terdekat
        final int cdf11 = tileCdfs[ty1 * gridSize + tx1][originalY];
        final int cdf12 = tileCdfs[ty1 * gridSize + tx2][originalY];
        final int cdf21 = tileCdfs[ty2 * gridSize + tx1][originalY];
        final int cdf22 = tileCdfs[ty2 * gridSize + tx2][originalY];

        // Interpolasi horizontal atas & bawah
        final double topInterp = cdf11 * (1.0 - xWeight) + cdf12 * xWeight;
        final double bottomInterp = cdf21 * (1.0 - xWeight) + cdf22 * xWeight;

        // Interpolasi vertikal
        final int newY = (topInterp * (1.0 - yWeight) + bottomInterp * yWeight)
            .round()
            .clamp(0, 255);

        // 5. Rekonstruksi warna RGB dengan menjaga rasio warna asli
        final pixel = src.getPixel(x, y);
        int finalR, finalG, finalB;

        if (originalY == 0) {
          finalR = newY;
          finalG = newY;
          finalB = newY;
        } else {
          final double ratio = newY / originalY;
          finalR = (pixel.r * ratio).round().clamp(0, 255);
          finalG = (pixel.g * ratio).round().clamp(0, 255);
          finalB = (pixel.b * ratio).round().clamp(0, 255);
        }

        dst.setPixelRgb(x, y, finalR, finalG, finalB);
      }
    }

    return dst;
  }
}
