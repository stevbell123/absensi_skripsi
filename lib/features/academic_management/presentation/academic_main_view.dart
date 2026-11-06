import 'package:flutter/material.dart';

// Import ini sekarang akan berfungsi karena class-nya sudah benar di file tujuannya
import 'semester_management_view.dart';
import 'class_management_view.dart';

class AcademicMainView extends StatelessWidget {
  const AcademicMainView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, 
      child: Column( 
        children: [
          const Material(
            color: Colors.white,
            elevation: 1, 
            child: TabBar(
              labelColor: Colors.indigo, 
              unselectedLabelColor: Colors.grey, 
              indicatorColor: Colors.indigo, 
              indicatorWeight: 3, 
              tabs: [
                Tab(text: 'Semester', icon: Icon(Icons.date_range)),
                Tab(text: 'Ruang Kelas', icon: Icon(Icons.meeting_room)),
              ],
            ),
          ),
          
          const Expanded(
            child: TabBarView(
              children: [
                SemesterManagementView(), 
                ClassManagementView(), 
              ],
            ),
          ),
        ],
      ),
    );
  }
}