// lib/screens/bulk_enrollment_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BulkEnrollmentScreen extends StatefulWidget {
  final String loc, sub, dept, team; // Passed from selection screen
  const BulkEnrollmentScreen({super.key, required this.loc, required this.sub, required this.dept, required this.team});

  @override
  State<BulkEnrollmentScreen> createState() => _BulkEnrollmentScreenState();
}

class _BulkEnrollmentScreenState extends State<BulkEnrollmentScreen> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);
  bool _isSaving = false;

  // Each map represents one member row
  final List<Map<String, dynamic>> _memberList = [
    {'name': '', 'id_num': '', 'cell': '', 'duty': '구역원'}
  ];

  void _addRow() {
    setState(() => _memberList.add({'name': '', 'id_num': '', 'cell': '', 'duty': '구역원'}));
  }

  void _removeRow(int index) {
    if (_memberList.length > 1) setState(() => _memberList.removeAt(index));
  }

  Future<void> _saveAll() async {
    if (_memberList.any((m) => m['name'].isEmpty || m['cell'].isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all Name and Cell fields")));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final List<Map<String, dynamic>> finalData = _memberList.map((m) => {
        'english_name': m['name'],
        'id_number': m['id_num'],
        'cell_number': m['cell'],
        'duty_role': m['duty'],
        'location': widget.loc,
        'sub_location': widget.sub,
        'current_dept': widget.dept,
        'team_number': widget.team,
        'status': 'Active'
      }).toList();

      await _supabase.from('members').insert(finalData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("All Members Enrolled Successfully!")));
        Navigator.pop(context);
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("BATCH ENROLLMENT", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple)),
        centerTitle: true, backgroundColor: Colors.white, elevation: 0.5,
      ),
      body: Column(
        children: [
          _buildInfoBanner(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _memberList.length,
              itemBuilder: (context, index) => _memberRow(index),
            ),
          ),
          _buildFooterActions(),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() => Container(
    width: double.infinity, color: pPurple.withValues(alpha: 0.05), padding: const EdgeInsets.all(15),
    child: Text("Enrolling into: ${widget.loc} > ${widget.dept} > Team ${widget.team}", 
      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
  );

  Widget _memberRow(int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: pPurple, child: Text("${index + 1}", style: const TextStyle(color: Colors.white))),
            const SizedBox(width: 15),
            Expanded(flex: 3, child: TextField(decoration: const InputDecoration(labelText: "Full Name"), 
              onChanged: (v) => _memberList[index]['name'] = v)),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: TextField(decoration: const InputDecoration(labelText: "SCJ ID"), 
              onChanged: (v) => _memberList[index]['id_num'] = v)),
            const SizedBox(width: 10),
            Expanded(flex: 1, child: TextField(decoration: const InputDecoration(labelText: "Cell #"), 
              onChanged: (v) => _memberList[index]['cell'] = v)),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _removeRow(index)),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterActions() {
    return Container(
      padding: const EdgeInsets.all(25), color: Colors.white,
      child: Row(
        children: [
          OutlinedButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const Text("ADD ANOTHER ROW")),
          const Spacer(),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: pPurple, minimumSize: const Size(200, 50)),
            onPressed: _isSaving ? null : _saveAll,
            child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("ENROLL ALL NOW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}