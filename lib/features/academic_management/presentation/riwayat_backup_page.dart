import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class RiwayatBackupPage extends StatefulWidget {
  const RiwayatBackupPage({Key? key}) : super(key: key);

  @override
  State<RiwayatBackupPage> createState() => _RiwayatBackupPageState();
}

class _RiwayatBackupPageState extends State<RiwayatBackupPage> {
  List<dynamic> riwayatBackup = [];
  bool isLoading = true;

  // URL SUDAH DIGANTI KE SERVER HUGGING FACE ANDA
final String serverUrl = "http://103.175.206.22:8000";

  @override
  void initState() {
    super.initState();
    fetchBackupList();
  }

  Future<void> fetchBackupList() async {
    try {
      final response = await http.get(Uri.parse("$serverUrl/list-backup"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          riwayatBackup = data['data'];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint("Gagal mengambil data: $e");
    }
  }

  Future<void> downloadFile(String namaFile) async {
    final url = Uri.parse("$serverUrl/download-backup/$namaFile");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengunduh $namaFile')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Riwayat Backup Server"),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : riwayatBackup.isEmpty
              ? const Center(
                  child: Text(
                    "Belum ada backup otomatis yang tersimpan.",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: riwayatBackup.length,
                  itemBuilder: (context, index) {
                    String namaFile = riwayatBackup[index];
                    // Memotong string untuk mendapatkan tanggal saja (Asumsi format: backup_sistem_YYYY-MM-DD.json)
                    String tanggal = namaFile.replaceAll("backup_sistem_", "").replaceAll(".json", "");

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Icon(Icons.verified_user, color: Colors.white),
                        ),
                        title: Text(
                          "Backup: $tanggal",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(namaFile),
                        trailing: IconButton(
                          icon: const Icon(Icons.cloud_download, color: Colors.blue),
                          onPressed: () => downloadFile(namaFile),
                          tooltip: "Unduh JSON",
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}