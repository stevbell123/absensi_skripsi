import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../attendance/widgets/pdf_viewer_screen.dart';

// Pastikan path ini sesuai dengan lokasi AppConstants di project Anda
import '../../../../core/constants/app_constants.dart';

class ModuleDetailView extends StatefulWidget {
  final String level;
  final bool isAdmin; 
  const ModuleDetailView({super.key, required this.level, required this.isAdmin});

  @override
  State<ModuleDetailView> createState() => _ModuleDetailViewState();
}

class _ModuleDetailViewState extends State<ModuleDetailView> {
  bool _isUploading = false;

  // =======================================================
  // FUNGSI 1: UPLOAD FILE KE CLOUDINARY
  // PERUBAHAN: Sekarang mengembalikan Map berisi URL dan Nama Cloud
  // =======================================================
  Future<Map<String, String>?> _uploadToCloudinary(File file) async {
    final List<Map<String, String>> cloudinaryAccounts = [
      {
        'cloudName': AppConstants.cloudName1,    
        'uploadPreset': AppConstants.uploadPreset1,
      },
      {
        'cloudName': AppConstants.cloudName2, 
        'uploadPreset': AppConstants.uploadPreset2,  
      },
      {
        'cloudName': AppConstants.cloudName3, 
        'uploadPreset': AppConstants.uploadPreset3,  
      },
    ];

    final random = Random();
    final selectedAccount = cloudinaryAccounts[random.nextInt(cloudinaryAccounts.length)];

    final String cloudName = selectedAccount['cloudName']!;
    final String uploadPreset = selectedAccount['uploadPreset']!;
    
    debugPrint('SIAP DEBUG: Mengunggah modul menggunakan akun Cloudinary: $cloudName');
        
    final Uri uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/raw/upload');
    
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    
    if (response.statusCode == 200) {
      final responseData = await response.stream.bytesToString();
      final jsonMap = json.decode(responseData);
      
      // Mengembalikan URL File DAN Nama Cloud yang dipakai
      return {
        'url': jsonMap['secure_url'],
        'cloudName': cloudName,
      }; 
    } else {
      debugPrint('Cloudinary Error: ${response.statusCode}');
      return null;
    }
  }

  // =======================================================
  // FUNGSI 2: PILIH FILE DAN SIMPAN KE FIRESTORE
  // =======================================================
  Future<void> _pickAndUploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'], 
    );

    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      String fileName = result.files.single.name;

      setState(() => _isUploading = true);

      try {
        // PERUBAHAN: Menerima data Map (URL dan Cloud Name)
        Map<String, String>? uploadData = await _uploadToCloudinary(file);

        if (uploadData != null) {
          String downloadUrl = uploadData['url']!;
          String usedCloudName = uploadData['cloudName']!;

          await FirebaseFirestore.instance.collection('modules').add({
            'title': fileName,
            'fileUrl': downloadUrl,       
            'level': widget.level,
            // PERUBAHAN: Menyimpan rekam jejak akun cloud ke database        
            'uploadedVia': usedCloudName, 
            'createdAt': FieldValue.serverTimestamp(),
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Modul berhasil diunggah!'), backgroundColor: Colors.green)
            );
          }
        } else {
          throw Exception("Gagal mendapatkan link dari Cloudinary.");
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Terjadi kesalahan: $e'), backgroundColor: Colors.red)
          );
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }

  // =======================================================
  // FUNGSI 3: HAPUS MODUL DARI DATABASE
  // =======================================================
  Future<void> _hapusModul(String docId, String title) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Modul', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Apakah Anda yakin ingin menghapus modul "$title"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Batal')
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx); 
              
              await FirebaseFirestore.instance.collection('modules').doc(docId).delete();
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Modul berhasil dihapus!'), backgroundColor: Colors.green)
                );
              }
            },
            child: const Text('Ya, Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Modul Kelas ${widget.level}')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('modules')
                  .where('level', isEqualTo: widget.level)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Folder Kelas Ini Masih Kosong.'));

                final modules = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: modules.length,
                  itemBuilder: (context, index) {
                    final doc = modules[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final title = data['title'] ?? 'Tanpa Nama';
                    
                    // Mengambil data rekam jejak cloud (jika modul lama belum punya, berikan teks default)
                    final uploadedVia = data['uploadedVia'] ?? 'Tidak diketahui';
                    
                    return ListTile(
                      leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      title: Text(title),
                      
                      // PERUBAHAN: Modifikasi Subtitle agar menampilkan info cloud khusus untuk Admin
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Buka Modul'),
                          if (widget.isAdmin) // Hanya muncul jika yang login adalah Admin
                            Text(
                              'Server: $uploadedVia', 
                              style: const TextStyle(fontSize: 11, color: Colors.indigo, fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                      
                      trailing: widget.isAdmin 
                        ? IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _hapusModul(doc.id, title),
                          )
                        : null,

                      onTap: () {
                        final String? fileUrl = data['fileUrl'];
                        if (fileUrl != null && fileUrl.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PdfViewerScreen(
                                pdfUrl: fileUrl,
                                pdfTitle: title,
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link modul tidak ditemukan.'), backgroundColor: Colors.orange)
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
          
          if (widget.isAdmin)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                  onPressed: _isUploading ? null : _pickAndUploadFile,
                  icon: _isUploading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.upload_file, color: Colors.white),
                  label: Text(
                    _isUploading ? 'Mengunggah...' : 'Upload Modul (Admin)',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
