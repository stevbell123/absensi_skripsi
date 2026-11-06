/// NIS siswa dari dokumen `classes/{classId}/students`.
///
/// Satu aturan yang sama dipakai oleh registrasi wajah (ID dokumen face_embeddings),
/// sinkronisasi templat per kelas, dan daftar hadir, agar hasil pengenalan wajah
/// selalu dicocokkan ke baris siswa yang benar lewat NIS (bukan lewat nama).
///
/// Urutan: `nisNip` (diisi impor CSV) → `nis` → `email` (impor CSV juga mengisi
/// `email` dengan NIS). Email asli (berisi '@') tidak dianggap NIS.
/// Mengembalikan string kosong bila tidak ada NIS.
String nisDariDataSiswa(Map<String, dynamic> data) {
  for (final kunci in const ['nisNip', 'nis', 'email']) {
    final nilai = (data[kunci] ?? '').toString().trim();
    if (nilai.isEmpty) continue;
    if (kunci == 'email' && nilai.contains('@')) continue;
    return nilai;
  }
  return '';
}
