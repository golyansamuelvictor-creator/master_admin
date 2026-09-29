// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class TaskManagerScreen extends StatefulWidget {
  const TaskManagerScreen({super.key});
  @override
  State<TaskManagerScreen> createState() => _TaskManagerScreenState();
}

class _TaskManagerScreenState extends State<TaskManagerScreen> {
  final _supabase = Supabase.instance.client;
  final Color pPurple = const Color(0xFF4A148C);
  bool _isLoading = true;
  List<dynamic> _tasks = [];

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  // ==========================================
  // CATEGORY 1: DATA LOGIC
  // ==========================================

  Future<void> _fetchTasks() async {
    setState(() => _isLoading = true);
    try {
      // Fetch tasks and join with the assigned leader's name
      final res = await _supabase.from('leader_tasks')
          .select('*, assigned_to:profiles(full_name, role)')
          .order('due_date');
      setState(() { _tasks = res as List; _isLoading = false; });
    } catch (e) {
      debugPrint("Task Error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateTaskStatus(String id, String newStatus) async {
    await _supabase.from('leader_tasks').update({'status': newStatus}).eq('id', id);
    _fetchTasks();
  }

  // ==========================================
  // CATEGORY 2: UI RENDERING
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("Leader Accountability Tasks", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple, fontSize: 18)),
        centerTitle: true, elevation: 0.5, backgroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: _tasks.length,
            itemBuilder: (c, i) => _buildTaskCard(_tasks[i]),
          ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: pPurple,
        onPressed: _showCreateTaskDialog,
        child: const Icon(Icons.add_task_rounded, color: Colors.white),
      ),
    );
  }

  Widget _buildTaskCard(dynamic task) {
    String status = task['status'];
    Color statusColor = status == 'Completed' ? Colors.green : status == 'In Progress' ? Colors.blue : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
            ),
            Text("Due: ${DateFormat('dd MMM').format(DateTime.parse(task['due_date']))}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
          const SizedBox(height: 12),
          Text(task['title'], style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 5),
          Text(task['description'] ?? "No description provided.", style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const Divider(height: 30),
          Row(children: [
            const Icon(Icons.person_outline, size: 14, color: Colors.blueGrey),
            const SizedBox(width: 8),
            Text("Assigned to: ${task['assigned_to']['full_name']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (status != 'Completed')
              TextButton(
                onPressed: () => _updateTaskStatus(task['id'], 'Completed'),
                child: const Text("Mark done", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ]),
        ]),
      ),
    );
  }

  // ==========================================
  // CATEGORY 3: CREATE TASK DIALOG
  // ==========================================

  void _showCreateTaskDialog() {
    final titleCtrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Assign new leader task"),
      content: TextField(controller: titleCtrl, decoration: const InputDecoration(hintText: "What needs to be done?")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
        ElevatedButton(onPressed: () async {
          // Simplifed: Assigns to current user for demo
          await _supabase.from('leader_tasks').insert({
            'title': titleCtrl.text,
            'due_date': DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 3))),
            'assigned_to': _supabase.auth.currentUser!.id
          });
          // ignore: use_build_context_synchronously
          Navigator.pop(c);
          _fetchTasks();
        }, child: const Text("Assign")),
      ],
    ));
  }
}