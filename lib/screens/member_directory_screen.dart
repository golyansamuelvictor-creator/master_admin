// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'member_detail_screen.dart';

class MemberDirectoryScreen extends StatefulWidget {
  final String userRole, userLoc, userSub, userDept, userTeam, userCell;

  const MemberDirectoryScreen({
    super.key,
    required this.userRole,
    required this.userLoc,
    required this.userSub,
    required this.userDept,
    required this.userTeam,
    required this.userCell,
  });

  @override
  State<MemberDirectoryScreen> createState() => _MemberDirectoryScreenState();
}

class _MemberDirectoryScreenState extends State<MemberDirectoryScreen> {
  final _supabase = Supabase.instance.client;
  String _searchQuery = "";
  final TextEditingController _controller = TextEditingController();

  Future<List<dynamic>> _getFilteredMembers() async {
  // 1. QUERY: Using standardized column names
  var query = _supabase.from('members').select('''
    *,
    introduced_by:introduced_by_id(english_name)
  ''').or('english_name.ilike.%$_searchQuery%,scj_id.ilike.%$_searchQuery%');

  // 2. SECURITY FILTERS (Updated to match your standardized DB columns)
  
  // Everyone except Admin is locked to their Location
  if (widget.userRole != 'admin') {
    query = query.eq('location', widget.userLoc);
  }

  // Location/Sub-Location Leaders and below filter by Sub-Location
  if (['loc_leader', 'loc_sec', 'sub_loc_leader', 'dept_leader', 'team_leader', 'cell_leader'].contains(widget.userRole)) {
    query = query.eq('sub_location', widget.userSub);
  }

  // Dept Leaders and below filter by Department
  if (['dept_leader', 'team_leader', 'cell_leader'].contains(widget.userRole)) {
    query = query.eq('department', widget.userDept); // Changed from 'current_dept'
  }

  // Team Leaders and below filter by Team
  if (['team_leader', 'cell_leader'].contains(widget.userRole)) {
    query = query.eq('team', widget.userTeam); // Changed from 'team_number'
  }

  // Cell Leaders only see their Cell
  if (widget.userRole == 'cell_leader') {
    query = query.eq('cell_group', widget.userCell); // Changed from 'cell_number'
  }

  return await query.order('english_name');
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: AppBar(
        title: Text("Member Directory", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0.5,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: "Search in your authorized unit...",
                prefixIcon: const Icon(Icons.search, color: Color(0xFF4A148C)),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: _getFilteredMembers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                final members = snapshot.data ?? [];
                if (members.isEmpty) return Center(child: Text("No members found in your unit", style: GoogleFonts.merriweather(color: Colors.grey)));

                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    // Fetch the joined recruiter name
                    String recruiter = member['introduced_by']?['english_name'] ?? "Direct Enrollment";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF4A148C),
                          child: Text(member['english_name'][0], style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(member['english_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        // UPDATED SUBTITLE: Shows Recruiter Name
                        subtitle: Text("ID: ${member['scj_id']} • Intro by: $recruiter"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => MemberDetailScreen(member: member, userRole: widget.userRole))),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}