// =========================================================================
// RIWAYAT BACKUP (KHUSUS DEVELOPER)
// =========================================================================
// Menampilkan backup yang tersimpan di Cloud Firestore (koleksi 'backups').
// Setiap backup bisa dibagikan sebagai berkas JSON, dipulihkan, atau dihapus.
// Data yang sama juga terlihat di Firebase Console → Firestore → backups.
// =========================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/backup/backup_service.dart';

class RiwayatBackupPage extends StatefulWidget {
  const RiwayatBackupPage({Key? key}) : super(key: key);

  @override
  State<RiwayatBackupPage> createState() => _RiwayatBackupPageState();
}

class _RiwayatBackupPageState extends State<RiwayatBackupPage> {
  final BackupService _backupService = BackupService();

  String _formatTanggal(DateTime? waktu) =>
      waktu == null ? 'Menyimpan...' : DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(waktu);

  String _formatUkuran(int karakter) => karakter >= 1000000
      ? '${(karakter / 1000000).toStringAsFixed(1)} MB'
      : '${(karakter / 1000).toStringAsFixed(0)} KB';

  /// Menjalankan proses dengan layar loading, lalu menampilkan hasil/galatnya
  Future<void> _jalankan(Future<String> Function() proses) async {
    showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
    try {
      final pesan = await proses();
      if (!mounted) return;
      Navigator.pop(context);
      if (pesan.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Gagal: $e'), backgroundColor: Colors.red));
    }
  }

  Future<bool> _konfirmasi(String judul, String isi, String tombol, Color warna) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: Text(isi),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tombol, style: TextStyle(color: warna, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return yakin == true;
  }

  Future<void> _pulihkan(InfoBackup b) async {
    final yakin = await _konfirmasi(
      'Pulihkan backup?',
      'Data dari backup ${_formatTanggal(b.dibuatPada)} akan ditulis ulang ke database.\n\n'
          '• Dokumen dengan ID yang sama akan DITIMPA.\n'
          '• Dokumen yang dibuat setelah backup ini tidak dihapus.\n'
          '• Akun login (Firebase Authentication) tidak ikut dipulihkan.',
      'Pulihkan',
      Colors.orange.shade800,
    );
    if (!yakin) return;
    await _jalankan(() async {
      final n = await _backupService.pulihkanDariRiwayat(b.id);
      return '✅ Restore selesai: $n dokumen dipulihkan.';
    });
  }

  Future<void> _hapus(InfoBackup b) async {
    final yakin = await _konfirmasi(
      'Hapus backup?',
      'Backup ${_formatTanggal(b.dibuatPada)} akan dihapus permanen dari Firestore.',
      'Hapus',
      Colors.red,
    );
    if (!yakin) return;
    await _jalankan(() async {
      await _backupService.hapusBackup(b.id);
      return 'Backup dihapus.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Riwayat Backup"),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<InfoBackup>>(
        stream: _backupService.riwayat(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Gagal memuat riwayat: ${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final daftar = snapshot.data!;
          if (daftar.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Belum ada backup.\nTekan "BACKUP KE FIRESTORE" di Developer Control Panel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: daftar.length,
            itemBuilder: (context, index) {
              final b = daftar[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.green,
                            child: Icon(Icons.verified_user, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_formatTanggal(b.dibuatPada),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('Oleh ${b.dibuatOleh}',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
                                Text('${b.totalDokumen} dokumen · ${_formatUkuran(b.ukuranKarakter)}',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('JSON'),
                            onPressed: () => _jalankan(() async {
                              await _backupService.bagikanSebagaiJson(b.id, tanggal: b.dibuatPada);
                              return '';
                            }),
                          ),
                          TextButton.icon(
                            icon: Icon(Icons.restore, size: 18, color: Colors.orange.shade800),
                            label: Text('Pulihkan', style: TextStyle(color: Colors.orange.shade800)),
                            onPressed: () => _pulihkan(b),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Hapus backup',
                            onPressed: () => _hapus(b),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
