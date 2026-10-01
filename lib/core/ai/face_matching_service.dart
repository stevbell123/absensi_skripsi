import 'dart:math';

// CATATAN: BATAS_TERIMA perlu dikalibrasi ulang.
// Karena model yang digunakan adalah MobileFaceNet (berbeda dari dlib pada server),
// skala jarak (distance scale) akan berbeda. 
// Disarankan untuk memulai dengan 1.0 dan melakukan pengujian.

class FaceRecord {
  final String nim;
  final String name;
  final List<double> embedding;

  FaceRecord({
    required this.nim,
    required this.name,
    required this.embedding,
  });
}

class MatchResult {
  final String nim;
  final String name;
  final double distance;
  final List<int> box; // [x1, y1, x2, y2]

  MatchResult({
    required this.nim,
    required this.name,
    required this.distance,
    required this.box,
  });
}

class FaceMatchingService {
  // Ambang batas jarak maksimum untuk menerima kecocokan wajah.
  // Nilai lebih rendah = lebih ketat (harus sangat mirip).
  // Mulai dari 1.0 dan sesuaikan berdasarkan pengujian dengan MobileFaceNet.
  static const double batasTerima = 1.0; 

  // Selisih minimal antara kecocokan terbaik (pertama) dan kedua.
  // Mencegah ambiguitas (wajah yang mirip dengan dua orang di database).
  static const double selisihMinimal = 0.06;

  List<FaceRecord> _database = [];

  // Memuat data wajah ke dalam memori
  void loadDatabase(List<FaceRecord> records) {
    _database = records;
  }

  // Mendapatkan jumlah siswa yang terdaftar di database
  int get totalSiswa => _database.length;

  // Menghitung jarak Euclidean antara dua vektor embedding.
  // Jarak yang lebih rendah menunjukkan kemiripan yang lebih tinggi.
  static double euclideanDistance(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 999.0;
    if (a.length != b.length) {
      // Jika dimensi tidak cocok (misal 512-d server vs 192-d mobile),
      // gunakan perbandingan irisan dimensi agar tidak crash
      final minLen = min(a.length, b.length);
      double sum = 0.0;
      for (int i = 0; i < minLen; i++) {
        double diff = a[i] - b[i];
        sum += diff * diff;
      }
      return sqrt(sum);
    }
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      double diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }

  // Menghitung Cosine Similarity (sebagai alternatif jika dibutuhkan).
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final minLen = min(a.length, b.length);
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < minLen; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  // Melakukan pencocokan wajah dari input (embeddings dan kotak wajah) dengan database.
  List<MatchResult> matchFaces(List<List<double>> embeddings, List<List<int>> boxes) {
    List<MatchResult> finalResults = [];
    
    if (_database.isEmpty || embeddings.isEmpty) {
      return finalResults;
    }

    // List untuk menyimpan semua kandidat kecocokan potensial (sebelum difilter)
    // Berisi Map dengan kunci: 'embeddingIndex', 'nim', 'name', 'distance', 'box'
    List<Map<String, dynamic>> candidates = [];

    // a. Untuk setiap embedding dari wajah yang terdeteksi, hitung jarak ke semua entri database
    for (int i = 0; i < embeddings.length; i++) {
      List<double> currentEmbedding = embeddings[i];
      List<int> currentBox = boxes[i];
      
      List<Map<String, dynamic>> distances = [];

      for (var record in _database) {
        double dist = euclideanDistance(currentEmbedding, record.embedding);
        distances.add({
          'nim': record.nim,
          'name': record.name,
          'distance': dist,
        });
      }

      // Urutkan berdasarkan jarak terdekat (paling mirip)
      distances.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      // b. Temukan kecocokan terbaik dan periksa apakah memenuhi BATAS_TERIMA
      if (distances.isNotEmpty) {
        double bestDist = distances[0]['distance'];
        
        if (bestDist <= batasTerima) {
          bool valid = true;

          // c. Cek SELISIH_MINIMAL jika ada lebih dari 1 kandidat di database
          if (distances.length > 1) {
            double secondBestDist = distances[1]['distance'];
            if ((secondBestDist - bestDist) < selisihMinimal) {
              // Terlalu ambigu (mirip dengan 2 orang sekaligus), sehingga ditolak
              valid = false;
            }
          }

          if (valid) {
            candidates.add({
              'embeddingIndex': i,
              'nim': distances[0]['nim'],
              'name': distances[0]['name'],
              'distance': bestDist,
              'box': currentBox,
            });
          } else {
            // Ambiguitas
            candidates.add({
              'embeddingIndex': i,
              'nim': 'Unknown',
              'name': 'Unknown',
              'distance': bestDist,
              'box': currentBox,
            });
          }
        } else {
          // Tidak memenuhi BATAS_TERIMA (tidak cukup mirip)
          candidates.add({
            'embeddingIndex': i,
            'nim': 'Unknown',
            'name': 'Unknown',
            'distance': bestDist,
            'box': currentBox,
          });
        }
      }
    }

    // d. Urutkan semua kandidat yang valid berdasarkan jarak (terbaik lebih dulu)
    candidates.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    // e. Terapkan penugasan unik: satu siswa hanya dapat cocok dengan satu wajah terdeteksi
    // untuk mencegah duplikasi (satu siswa muncul di 2 wajah berbeda)
    Set<String> matchedNims = {};
    Set<int> processedEmbeddingIndices = {};

    for (var candidate in candidates) {
      int idx = candidate['embeddingIndex'];
      String nim = candidate['nim'];

      // Jika wajah ini sudah diproses, abaikan
      if (processedEmbeddingIndices.contains(idx)) {
        continue;
      }

      if (nim != 'Unknown') {
        // Jika NIM ini sudah dicocokkan dengan wajah lain sebelumnya (yang memiliki jarak lebih baik),
        // maka wajah saat ini ditandai sebagai 'Unknown'
        if (matchedNims.contains(nim)) {
          finalResults.add(MatchResult(
            nim: 'Unknown',
            name: 'Unknown',
            distance: candidate['distance'],
            box: candidate['box'],
          ));
        } else {
          // Cocok dan valid
          matchedNims.add(nim);
          finalResults.add(MatchResult(
            nim: nim,
            name: candidate['name'],
            distance: candidate['distance'],
            box: candidate['box'],
          ));
        }
      } else {
        // Memang dari awal sudah 'Unknown' (tidak lolos threshold atau ambigu)
        finalResults.add(MatchResult(
          nim: 'Unknown',
          name: 'Unknown',
          distance: candidate['distance'],
          box: candidate['box'],
        ));
      }
      
      processedEmbeddingIndices.add(idx);
    }

    // f. Kembalikan hasil yang sudah divalidasi dan di-filter
    return finalResults;
  }
}
