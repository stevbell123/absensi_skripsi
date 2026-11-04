import 'dart:math';

// CATATAN: BATAS_TERIMA perlu dikalibrasi ulang.
// Karena model yang digunakan adalah MobileFaceNet (berbeda dari dlib pada server),
// skala jarak (distance scale) akan berbeda.
// Disarankan untuk memulai dengan 1.0 dan melakukan pengujian.

class FaceRecord {
  final String nim;
  final String name;
  final List<double> embedding;

  // Embedding dari foto pendaftaran yang sama tetapi TANPA CLAHE.
  // Dipakai saat eksperimen CLAHE dimatikan, agar galeri dan foto uji
  // diproses dengan cara yang sama (null untuk data pendaftaran lama).
  final List<double>? embeddingTanpaClahe;

  FaceRecord({
    required this.nim,
    required this.name,
    required this.embedding,
    this.embeddingTanpaClahe,
  });
}

class MatchResult {
  final String nim;
  final String name;
  final double distance;
  final List<int> box; // [x1, y1, x2, y2]

  // --- Data mentah untuk analisis FAR / FRR / MIR (penelitian) ---
  // Kandidat terdekat SEBELUM disaring ambang/margin.
  final String rawNim;
  final String rawName;
  // Jarak kandidat terdekat kedua (999.0 jika database hanya berisi 1 siswa).
  final double secondDistance;
  // 'diterima' | 'tolak_ambang' | 'tolak_margin' | 'tolak_duplikat'
  final String alasan;
  // Indeks wajah pada list embedding masukan.
  final int faceIndex;

  MatchResult({
    required this.nim,
    required this.name,
    required this.distance,
    required this.box,
    this.rawNim = 'Unknown',
    this.rawName = 'Unknown',
    this.secondDistance = 999.0,
    this.alasan = 'diterima',
    this.faceIndex = 0,
  });
}

class FaceMatchingService {
  // Nilai awal dari tahap pengembangan. Nilai akhir ditetapkan dari data validasi
  // (Bab III Subbab 3.4.3) lalu dimasukkan ke sini sebelum Eksperimen 3.
  // batasTerima = ambang jarak maksimum untuk menerima kecocokan wajah (τ).
  // selisihMinimal = selisih minimal kandidat kedua dan pertama (δ), mencegah ambiguitas.
  static const double batasTerima = 1.0;
  static const double selisihMinimal = 0.06;

  // Konfigurasi aktif (bisa diubah oleh Mode Penelitian).
  // Nilai bawaan = perilaku normal aplikasi.
  double ambang = batasTerima;
  double margin = selisihMinimal;
  // false = hanya ambang jarak tunggal (pembanding RM 2)
  bool gunakanMargin = true;
  // true = cocokkan terhadap embedding galeri tanpa CLAHE (pembanding RM 1)
  bool gunakanGaleriTanpaClahe = false;

  List<FaceRecord> _database = [];

  // Memuat data wajah ke dalam memori
  void loadDatabase(List<FaceRecord> records) {
    _database = records;
  }

  // Mendapatkan jumlah siswa yang terdaftar di database
  int get totalSiswa => _database.length;

  // Jumlah siswa yang sudah punya embedding tanpa CLAHE (pendaftaran baru)
  int get totalSiswaTanpaClahe =>
      _database.where((r) => r.embeddingTanpaClahe != null).length;

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
    // Berisi Map dengan kunci: 'embeddingIndex', 'nim', 'name', 'distance', 'box',
    // ditambah data mentah 'rawNim', 'rawName', 'secondDistance', 'alasan'
    List<Map<String, dynamic>> candidates = [];

    // a. Untuk setiap embedding dari wajah yang terdeteksi, hitung jarak ke semua entri database
    for (int i = 0; i < embeddings.length; i++) {
      List<double> currentEmbedding = embeddings[i];
      List<int> currentBox = boxes[i];

      List<Map<String, dynamic>> distances = [];

      for (var record in _database) {
        final galeri =
            gunakanGaleriTanpaClahe ? record.embeddingTanpaClahe : record.embedding;
        if (galeri == null) continue; // Pendaftaran lama tanpa embedding non-CLAHE

        double dist = euclideanDistance(currentEmbedding, galeri);
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
        double secondBestDist =
            distances.length > 1 ? distances[1]['distance'] as double : 999.0;

        String alasan = 'diterima';
        if (bestDist > ambang) {
          // Tidak memenuhi BATAS_TERIMA (tidak cukup mirip)
          alasan = 'tolak_ambang';
        } else if (gunakanMargin &&
            distances.length > 1 &&
            (secondBestDist - bestDist) < margin) {
          // c. Terlalu ambigu (mirip dengan 2 orang sekaligus), sehingga ditolak
          alasan = 'tolak_margin';
        }

        final bool valid = alasan == 'diterima';
        candidates.add({
          'embeddingIndex': i,
          'nim': valid ? distances[0]['nim'] : 'Unknown',
          'name': valid ? distances[0]['name'] : 'Unknown',
          'distance': bestDist,
          'box': currentBox,
          'rawNim': distances[0]['nim'],
          'rawName': distances[0]['name'],
          'secondDistance': secondBestDist,
          'alasan': alasan,
        });
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

      String hasilNim = nim;
      String hasilNama = candidate['name'];
      String alasan = candidate['alasan'];

      // Jika NIM ini sudah dicocokkan dengan wajah lain sebelumnya (yang memiliki jarak lebih baik),
      // maka wajah saat ini ditandai sebagai 'Unknown'
      if (nim != 'Unknown') {
        if (matchedNims.contains(nim)) {
          hasilNim = 'Unknown';
          hasilNama = 'Unknown';
          alasan = 'tolak_duplikat';
        } else {
          matchedNims.add(nim);
        }
      }

      finalResults.add(MatchResult(
        nim: hasilNim,
        name: hasilNama,
        distance: candidate['distance'],
        box: candidate['box'],
        rawNim: candidate['rawNim'],
        rawName: candidate['rawName'],
        secondDistance: candidate['secondDistance'],
        alasan: alasan,
        faceIndex: idx,
      ));

      processedEmbeddingIndices.add(idx);
    }

    // f. Kembalikan hasil yang sudah divalidasi dan di-filter
    return finalResults;
  }
}
