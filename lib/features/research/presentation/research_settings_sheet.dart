// =========================================================================
// PANEL PENGATURAN MODE PENELITIAN
// =========================================================================
// Dibuka dari ikon 🧪 di halaman Input Absensi dan layar Pindai Wajah.
// Berisi saklar eksperimen, label kondisi cahaya, serta akses ke evaluasi
// dataset dan ekspor log.
// =========================================================================

import 'package:flutter/material.dart';
import '../research_config.dart';
import '../research_logger.dart';
import 'dataset_evaluation_page.dart';

Future<void> tampilkanPengaturanPenelitian(BuildContext context) async {
  await ResearchConfig.load();
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final kondisiLainController = TextEditingController(
    text: ResearchConfig.kondisiBawaan.containsKey(ResearchConfig.kondisiCahaya)
        ? ''
        : ResearchConfig.kondisiCahaya,
  );

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final bool aktif = ResearchConfig.aktif;
        final bool kondisiLain =
            !ResearchConfig.kondisiBawaan.containsKey(ResearchConfig.kondisiCahaya);

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.science, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text('Mode Penelitian',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saat mati, aplikasi berjalan normal (CLAHE + margin) dan tidak ada data yang dicatat.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktifkan Mode Penelitian',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Catat log wajah & sesi absensi'),
                    value: aktif,
                    onChanged: (v) => setSheet(() => ResearchConfig.aktif = v),
                  ),
                  const Divider(),

                  // --- RM 1 ---
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('CLAHE (RM 1)'),
                    subtitle: const Text('Mati = foto wajah tanpa peningkatan kontras'),
                    value: ResearchConfig.gunakanClahe,
                    onChanged: aktif
                        ? (v) => setSheet(() => ResearchConfig.gunakanClahe = v)
                        : null,
                  ),

                  // --- RM 2 ---
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Verifikasi Margin (RM 2)'),
                    subtitle: Text(
                      'Mati = ambang jarak tunggal saja\n'
                      'Ambang ${ResearchConfig.ambang} · margin ${ResearchConfig.margin}',
                    ),
                    isThreeLine: true,
                    value: ResearchConfig.gunakanMargin,
                    onChanged: aktif
                        ? (v) => setSheet(() => ResearchConfig.gunakanMargin = v)
                        : null,
                  ),
                  const SizedBox(height: 8),

                  // --- Kondisi Cahaya ---
                  const Text('Kondisi Pencahayaan Saat Ini',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ...ResearchConfig.kondisiBawaan.entries.map(
                        (e) => ChoiceChip(
                          label: Text(e.value),
                          selected: ResearchConfig.kondisiCahaya == e.key,
                          onSelected: aktif
                              ? (_) => setSheet(() => ResearchConfig.kondisiCahaya = e.key)
                              : null,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Lainnya'),
                        selected: kondisiLain,
                        onSelected: aktif
                            ? (_) => setSheet(() => ResearchConfig.kondisiCahaya =
                                _normalisasiKondisi(kondisiLainController.text))
                            : null,
                      ),
                    ],
                  ),
                  if (kondisiLain)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: kondisiLainController,
                        enabled: aktif,
                        decoration: const InputDecoration(
                          labelText: 'Nama kondisi (cth: lampu neon mati)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => ResearchConfig.kondisiCahaya = _normalisasiKondisi(v),
                      ),
                    ),
                  const Divider(height: 32),

                  // --- Alat Penelitian ---
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Evaluasi Dataset Foto (RM 1 & RM 2)'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        navigator.push(MaterialPageRoute(
                            builder: (_) => const DatasetEvaluationPage()));
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.share),
                          label: const Text('Bagikan Log CSV'),
                          onPressed: () async {
                            final ada = await ResearchLogger.bagikan();
                            if (!ada) {
                              messenger.showSnackBar(const SnackBar(
                                  content: Text('Belum ada log yang tercatat.')));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cloud_upload),
                          label: Text('Firestore (${ResearchLogger.jumlahAntreanFirestore})'),
                          onPressed: () async {
                            final n = await ResearchLogger.kirimKeFirestore();
                            setSheet(() {});
                            messenger.showSnackBar(SnackBar(
                                content: Text('$n baris terkirim ke Firestore. '
                                    'Sisa antrean: ${ResearchLogger.jumlahAntreanFirestore}')));
                          },
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Hapus Log CSV Lokal',
                        style: TextStyle(color: Colors.red)),
                    onPressed: () async {
                      final yakin = await showDialog<bool>(
                        context: ctx,
                        builder: (c) => AlertDialog(
                          title: const Text('Hapus log lokal?'),
                          content: const Text(
                              'File CSV di HP akan dihapus. Data yang sudah terkirim ke Firestore tetap ada. '
                              'Pastikan log sudah dibagikan/dicadangkan.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Batal')),
                            TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Hapus',
                                    style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (yakin == true) {
                        await ResearchLogger.hapusLogLokal();
                        messenger.showSnackBar(
                            const SnackBar(content: Text('Log CSV lokal dihapus.')));
                      }
                    },
                  ),
                  FutureBuilder(
                    future: ResearchLogger.folderLog(),
                    builder: (c, snap) => Text(
                      snap.hasData ? 'Lokasi log: ${snap.data!.path}' : '',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  kondisiLainController.dispose();
  await ResearchConfig.save();
}

String _normalisasiKondisi(String teks) {
  final hasil = teks.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return hasil.isEmpty ? 'lainnya' : hasil;
}
