import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class InboxAdminView extends StatelessWidget {
  const InboxAdminView({super.key});

  Future<void> _selesaikanLaporan(BuildContext context, String docId) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tandai Selesai?'),
        content: const Text('Apakah Anda sudah mereset akun pengguna ini di tab Pengguna?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya, Selesai'),
          ),
        ],
      ),
    );

    if (konfirmasi == true) {
      await FirebaseFirestore.instance.collection('laporan_bantuan').doc(docId).update({'status': 'Selesai'});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laporan ditandai selesai!'), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Kotak Masuk Laporan', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true, // Diubah menjadi true agar tombol panah kembali (back) muncul
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Mengambil data dari terbaru ke terlama
        stream: FirebaseFirestore.instance.collection('laporan_bantuan').orderBy('tanggal', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('Belum ada laporan masuk.', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                ],
              ),
            );
          }

          final laporan = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: laporan.length,
            itemBuilder: (context, index) {
              final doc = laporan[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final isMenunggu = data['status'] == 'Menunggu';
              final tanggalDate = (data['tanggal'] as Timestamp?)?.toDate();
              final waktuStr = tanggalDate != null ? DateFormat('dd MMM yyyy, HH:mm').format(tanggalDate) : '-';

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isMenunggu ? Colors.red.shade200 : Colors.green.shade200, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(data['nama'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isMenunggu ? Colors.red.shade100 : Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8)
                            ),
                            child: Text(
                              data['status'] ?? '-', 
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isMenunggu ? Colors.red.shade900 : Colors.green.shade900)
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('ID: ${data['nomor_induk'] ?? '-'}', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                      Text(waktuStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const Divider(height: 24),
                      const Text('Pesan Keluhan:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(data['pesan'] ?? '-', style: const TextStyle(fontSize: 14)),
                      
                      if (isMenunggu) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            onPressed: () => _selesaikanLaporan(context, doc.id),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Tandai Selesai'),
                          ),
                        )
                      ]
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