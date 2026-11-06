import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';

class BerandaGuruView extends StatefulWidget {
  const BerandaGuruView({super.key});

  @override
  State<BerandaGuruView> createState() => _BerandaGuruViewState();
}

class _BerandaGuruViewState extends State<BerandaGuruView> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  String _getTodayString() {
    int weekday = DateTime.now().weekday;
    switch (weekday) {
      case 1: return 'Senin';
      case 2: return 'Selasa';
      case 3: return 'Rabu';
      case 4: return 'Kamis';
      case 5: return 'Jumat';
      case 6: return 'Sabtu';
      case 7: return 'Minggu';
      default: return 'Senin';
    }
  }

  Future<void> _ajukanIzin(String scheduleId) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Izin', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Apakah Anda yakin tidak bisa hadir pada kelas ini? Sistem akan memberitahu Admin untuk mencarikan guru pengganti.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('schedules').doc(scheduleId).update({
                'isAbsent': true,
                'substituteTeacherId': null,
                'substituteTeacherName': null,
              });
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Izin diajukan!'), backgroundColor: Colors.green));
              }
            },
            child: const Text('Ya, Ajukan Izin', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _getTodayString();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.indigo,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Selamat Datang,', style: TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('Dashboard Guru', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Jadwal Hari $today', style: const TextStyle(color: Colors.white, fontSize: 15)),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  
                  // WIDGET GRAFIK CAROUSEL (BISA DIGESER)
                  if (currentUserId != null)
                    _DashboardChartsCarousel(currentUserId: currentUserId!),
                  
                  const SizedBox(height: 24),
                  
                  // DAFTAR JADWAL HARI INI
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
                    child: Text(
                      '📅 Jadwal Mengajar Hari Ini',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ),
                  
                  currentUserId == null 
                    ? const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('Silakan login.')))
                    : StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('schedules')
                            .where('teacherId', isEqualTo: currentUserId)
                            .where('day', isEqualTo: today)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                          
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.event_available, size: 64, color: Colors.grey.shade300),
                                    const SizedBox(height: 16),
                                    Text('Tidak ada jadwal mengajar hari ini.', style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
                                  ],
                                ),
                              ),
                            );
                          }

                          final schedules = snapshot.data!.docs;

                          return ListView.builder(
                            shrinkWrap: true, 
                            physics: const NeverScrollableScrollPhysics(), 
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: schedules.length,
                            itemBuilder: (context, index) {
                              final doc = schedules[index];
                              final data = doc.data() as Map<String, dynamic>;
                              
                              final className = data['className'] ?? 'Kelas';
                              final subjectName = data['subjectName'] ?? 'Mapel';
                              final isAbsent = data['isAbsent'] ?? false;
                              final substituteName = data['substituteTeacherName'];
                              
                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('$className - $subjectName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          if (isAbsent)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                                              child: Text(substituteName != null ? 'Diganti: $substituteName' : 'Menunggu Pengganti', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                                            )
                                          else
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                                              child: const Text('Terjadwal', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      if (!isAbsent)
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: () => _ajukanIzin(doc.id),
                                            icon: const Icon(Icons.sick, color: Colors.red, size: 18),
                                            label: const Text('Saya Berhalangan Hadir', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// WIDGET KHUSUS UNTUK CAROUSEL GRAFIK (SLIDER)
// ============================================================================
class _DashboardChartsCarousel extends StatefulWidget {
  final String currentUserId;
  const _DashboardChartsCarousel({required this.currentUserId});

  @override
  State<_DashboardChartsCarousel> createState() => _DashboardChartsCarouselState();
}

class _DashboardChartsCarouselState extends State<_DashboardChartsCarousel> {
  final PageController _pageController = PageController();
  // INI ADALAH KUNCI RAHASIA AGAR GRAFIK TIDAK REFRESH
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(0); 

  @override
  void dispose() {
    _pageController.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('classes').where('homeroomTeacherId', isEqualTo: widget.currentUserId).snapshots(),
      builder: (context, classSnap) {
        bool isWaliKelas = false;
        String? waliClassId;
        String? waliClassName;

        if (classSnap.hasData && classSnap.data!.docs.isNotEmpty) {
          isWaliKelas = true;
          final doc = classSnap.data!.docs.first;
          waliClassId = doc.id;
          waliClassName = (doc.data() as Map<String, dynamic>)['name'] ?? 'Kelas';
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('schedules').where('teacherId', isEqualTo: widget.currentUserId).snapshots(),
          builder: (context, scheduleSnap) {
            
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('attendance').snapshots(),
              builder: (context, attendanceSnap) {
                if (attendanceSnap.connectionState == ConnectionState.waiting) return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
                
                final allAttendance = attendanceSnap.data?.docs ?? [];
                
                Map<String, int> totalHadirMapel = {};
                Map<String, int> totalSiswaMapel = {};
                
                if (scheduleSnap.hasData) {
                  List<String> myScheduleIds = scheduleSnap.data!.docs.map((d) => d.id).toList();
                  
                  for (var doc in allAttendance) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (myScheduleIds.contains(data['scheduleId'])) {
                      String label = "${data['className']} \n ${data['subjectName']}";
                      
                      if (!totalHadirMapel.containsKey(label)) {
                        totalHadirMapel[label] = 0;
                        totalSiswaMapel[label] = 0;
                      }

                      List<dynamic> records = data['records'] ?? [];
                      totalSiswaMapel[label] = totalSiswaMapel[label]! + records.length;
                      totalHadirMapel[label] = totalHadirMapel[label]! + records.where((r) => r['status'] == 'hadir').length;
                    }
                  }
                }

                Map<String, int> totalHadirWali = {};
                Map<String, int> totalSiswaWali = {};

                if (isWaliKelas && waliClassId != null) {
                  for (var doc in allAttendance) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['classId'] == waliClassId) {
                      String subject = data['subjectName'] ?? 'Mapel';
                      
                      if (!totalHadirWali.containsKey(subject)) {
                        totalHadirWali[subject] = 0;
                        totalSiswaWali[subject] = 0;
                      }

                      List<dynamic> records = data['records'] ?? [];
                      totalSiswaWali[subject] = totalSiswaWali[subject]! + records.length;
                      totalHadirWali[subject] = totalHadirWali[subject]! + records.where((r) => r['status'] == 'hadir').length;
                    }
                  }
                }

                List<Widget> chartPages = [
                  KeepAliveChartCard(
                    key: const ValueKey('chart_mapel'), // Kunci Identitas Grafik
                    title: "📊 Kehadiran Mapel Saya",
                    hadirData: totalHadirMapel,
                    siswaData: totalSiswaMapel,
                    barColor: Colors.indigo,
                  ),
                ];

                if (isWaliKelas) {
                  chartPages.add(
                    KeepAliveChartCard(
                      key: const ValueKey('chart_wali'), // Kunci Identitas Grafik
                      title: "👑 Pantauan Kelas Wali ($waliClassName)",
                      hadirData: totalHadirWali,
                      siswaData: totalSiswaWali,
                      barColor: Colors.teal,
                    ),
                  );
                }

                return Column(
                  children: [
                    SizedBox(
                      height: 320,
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (index) => _currentPageNotifier.value = index, // Hanya mengubah memori titik, BUKAN mereset grafik
                        children: chartPages,
                      ),
                    ),
                    if (chartPages.length > 1)
                      // Pembungkus khusus untuk indikator titik
                      ValueListenableBuilder<int>(
                        valueListenable: _currentPageNotifier,
                        builder: (context, currentPage, child) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(chartPages.length, (index) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                height: 8,
                                width: currentPage == index ? 24 : 8,
                                decoration: BoxDecoration(
                                  color: currentPage == index ? Colors.indigo : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            }),
                          );
                        }
                      )
                  ],
                );
              },
            );
          },
        );
      }
    );
  }
}

// ============================================================================
// WIDGET KARTU GRAFIK YANG DIKUNCI (ANTI-REFRESH)
// ============================================================================
class KeepAliveChartCard extends StatefulWidget {
  final String title;
  final Map<String, int> hadirData;
  final Map<String, int> siswaData;
  final Color barColor;

  const KeepAliveChartCard({
    Key? key,
    required this.title,
    required this.hadirData,
    required this.siswaData,
    required this.barColor,
  }) : super(key: key);

  @override
  State<KeepAliveChartCard> createState() => _KeepAliveChartCardState();
}

class _KeepAliveChartCardState extends State<KeepAliveChartCard> with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.hadirData.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 50, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 5),
            const Text("Belum ada data absensi.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    List<BarChartGroupData> barGroups = [];
    List<String> labels = widget.hadirData.keys.toList();
    
    for (int i = 0; i < labels.length; i++) {
      String key = labels[i];
      double percentage = widget.siswaData[key]! == 0 ? 0 : (widget.hadirData[key]! / widget.siswaData[key]!) * 100;
      
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: percentage,
              color: percentage >= 80 ? widget.barColor : (percentage >= 50 ? Colors.orange : Colors.red),
              width: 20,
              borderRadius: BorderRadius.circular(4),
              backDrawRodData: BackgroundBarChartRodData(show: true, toY: 100, color: Colors.grey.shade100),
            )
          ],
        )
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.barColor)),
          const SizedBox(height: 24),
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: 100,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => Colors.black87,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${labels[groupIndex].replaceAll('\n', ' ')}\n${rod.toY.toInt()}% Hadir',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value % 25 != 0) return const SizedBox.shrink();
                        return Text('${value.toInt()}%', style: TextStyle(color: Colors.grey.shade600, fontSize: 11));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < labels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              labels[index],
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 9, fontWeight: FontWeight.w600),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                barGroups: barGroups,
              ),
              swapAnimationDuration: Duration.zero,
            ),
          ),
        ],
      ),
    );
  }
}