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

  // Internal Affairs toggle: true = Church View (All), false = Department View (IA only)
  bool _iaChurchView = false;
  Map<String, dynamic>? _roleMetadata;
  bool _loadingRole = true;

  @override
  void initState() {
    super.initState();
    _fetchRoleMetadata();
  }

  Future<void> _fetchRoleMetadata() async {
    try {
      final res = await _supabase
          .from('app_roles')
          .select('role_key, approval_scope, display_name_ko, "Grouping", official_dept_id')
          .eq('role_key', widget.userRole)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _roleMetadata = res;
          _loadingRole = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRole = false);
    }
  }

  bool get _isInternalAffairs {
    final grouping = _roleMetadata?['Grouping'] ?? '';
    return widget.userRole.contains('internal_affairs') ||
        widget.userRole.startsWith('ia_') ||
        grouping == '24-Dept 31' ||
        grouping == '24-Dept 32' ||
        grouping == '24-Dept 33' ||
        grouping == '24-Dept 34' ||
        grouping == '24-Dept 35' ||
        grouping == '24-Dept 36';
  }

  Future<List<dynamic>> _getFilteredMembers() async {
    var query = _supabase.from('members').select('''
      *,
      introduced_by:introduced_by_id(english_name)
    ''');

    // 1. Search Query
    if (_searchQuery.trim().isNotEmpty) {
      query = query.or('english_name.ilike.%$_searchQuery%,scj_id.ilike.%$_searchQuery%');
    }

    final scope = _roleMetadata?['approval_scope'] ?? '';
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();

    // ==============================================================
    // A. CHURCH-WIDE ADMIN / SECRETARY / IA CHURCH-MODE
    // ==============================================================
    if (scope == 'church' || (_isInternalAffairs && _iaChurchView)) {
      return await query.order('english_name');
    }

    // ==============================================================
    // B. CHURCH WORKERS & 24 DEPARTMENTS (Grouping starts with '24-Dept')
    // ==============================================================
    if (grouping.startsWith('24-Dept')) {
      // Helper closures to exclude church workers and special locations
      void excludeChurchWorkers() {
        query = query
            .neq('location', 'Church Workers')
            .neq('location', 'Church Main');
      }

      if (grouping == '24-Dept MG') {
        // Men's Group: 장년회 across all locations
        query = query
            .eq('department', '장년회')
            .neq('location', 'Mou')
            .neq('location', 'New Saints');
        excludeChurchWorkers();
      } else if (grouping == '24-Dept WG') {
        // Women's Group: 부녀회 across all locations
        query = query
            .eq('department', '부녀회')
            .neq('location', 'Mou')
            .neq('location', 'New Saints');
        excludeChurchWorkers();
      } else if (grouping == '24-Dept YAG') {
        // Young Adults: 청년회 across all locations
        query = query
            .eq('department', '청년회')
            .neq('location', 'Mou')
            .neq('location', 'New Saints');
        excludeChurchWorkers();
      } else if (grouping == '24-Dept New Saints') {
        // New Saints: 새신자 across all locations (excluding MOU & Church Workers)
        query = query
            .eq('department', '새신자')
            .neq('location', 'Mou');
        excludeChurchWorkers();
      } else if (grouping == '24-Dept MOU') {
        // MOU: department Mou across locations where department is Mou
        query = query
            .eq('department', 'Mou')
            .neq('location', 'Mou')
            .neq('location', 'New Saints');
        excludeChurchWorkers();
      } else if (_isInternalAffairs && !_iaChurchView) {
        // Internal Affairs Department View: only IA members
        final officialDeptId = _roleMetadata?['official_dept_id'];
        if (officialDeptId != null) {
          query = query.eq('official_dept_id', officialDeptId);
        } else {
          query = query.or('department.eq.내무부,department.eq.Internal Affairs');
        }
      } else {
        // Other 24 Departments (Culture, Praise, ICT, Finance, etc.)
        // Matches members assigned to their official 24-department
        final officialDeptId = _roleMetadata?['official_dept_id'];
        if (officialDeptId != null) {
          query = query.eq('official_dept_id', officialDeptId);
        } else if (widget.userDept.isNotEmpty) {
          query = query.eq('department', widget.userDept);
        }
      }

      return await query.order('english_name');
    }

    // ==============================================================
    // C. LOCATION WORKER HIERARCHY (Strict 5-Tier Cascade)
    // ==============================================================
    final isCell = grouping.startsWith('Cell Group') || scope == 'cell';
    final isTeam = grouping.startsWith('Team') || grouping == 'Location Team' || scope == 'team';
    final isDept = grouping.startsWith('Dept ') || scope == 'department';
    final isSubLoc = grouping.startsWith('Sub-Location') || scope == 'sub_location';
    final isLoc = grouping.startsWith('Location') || scope == 'location';

    // 1. Location constraint (All location workers: Loc, Sub-Loc, Dept, Team, Cell)
    if (isLoc || isSubLoc || isDept || isTeam || isCell) {
      if (widget.userLoc.isNotEmpty) {
        query = query.eq('location', widget.userLoc);
      }
    }

    // 2. Sub-Location constraint (Sub-Loc, Dept, Team, Cell)
    if (isSubLoc || isDept || isTeam || isCell) {
      if (widget.userSub.isNotEmpty) {
        query = query.eq('sub_location', widget.userSub);
      }
    }

    // 3. Department constraint (Dept, Team, Cell) - Missed previously
    if (isDept || isTeam || isCell) {
      if (widget.userDept.isNotEmpty) {
        query = query.eq('department', widget.userDept);
      }
    }

    // 4. Team constraint (Team, Cell)
    if (isTeam || isCell) {
      if (widget.userTeam.isNotEmpty) {
        query = query.eq('team', widget.userTeam);
      }
    }

    // 5. Cell constraint (Cell only)
    if (isCell) {
      if (widget.userCell.isNotEmpty) {
        query = query.eq('cell_group', widget.userCell);
      }
    }

    return await query.order('english_name');
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: AppBar(
        title: Text(
          "Member Directory",
          style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // Internal Affairs Mode Switcher
          if (_isInternalAffairs)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _iaChurchView ? "Mode: Church Reports (All)" : "Mode: Department Reports (IA Only)",
                      style: GoogleFonts.merriweather(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: const Color(0xFF4A148C),
                      ),
                    ),
                    Switch(
                      value: _iaChurchView,
                      activeThumbColor: const Color(0xFF4A148C),
                      onChanged: (val) {
                        setState(() => _iaChurchView = val);
                      },
                    ),
                  ],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: "Search by name or SCJ ID...",
                prefixIcon: const Icon(Icons.search, color: Color(0xFF4A148C)),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _getFilteredMembers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text("Error loading data: ${snapshot.error}"),
                  );
                }

                final members = snapshot.data ?? [];
                if (members.isEmpty) {
                  return Center(
                    child: Text(
                      "No members found in your authorized unit",
                      style: GoogleFonts.merriweather(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final recruiter = member['introduced_by']?['english_name'] ?? "Direct Enrollment";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF4A148C),
                          child: Text(
                            (member['english_name'] != null && member['english_name'].isNotEmpty)
                                ? member['english_name'][0]
                                : "?",
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          member['english_name'] ?? "No Name",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "ID: ${member['scj_id'] ?? '-'} • Dept: ${member['department'] ?? '-'} • Loc: ${member['location'] ?? '-'}\nIntro by: $recruiter",
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => MemberDetailScreen(
                              member: member,
                              userRole: widget.userRole,
                            ),
                          ),
                        ),
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