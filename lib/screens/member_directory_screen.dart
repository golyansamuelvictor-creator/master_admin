// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'member_detail_screen.dart';
import 'package:master_admin/core/app_palette.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_menus.dart';

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

  Map<String, dynamic>? _roleMetadata;
  bool _loadingRole = true;
  bool _dualModeChurchView = false;

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

  // --- DUAL MODE DETERMINATION ---
  bool get _isInternalAffairs {
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
    final r = widget.userRole.toLowerCase();
    final d = widget.userDept.toLowerCase();
    return r.contains('internal_affairs') || r.startsWith('ia_') || d.contains('내무') || grouping.startsWith('24-Dept 3');
  }

  bool get _isEvangelismDept {
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
    final r = widget.userRole.toLowerCase();
    final d = widget.userDept.toLowerCase();
    return (r.contains('evang_dept') || d.contains('전도') || grouping.startsWith('24-Dept 5')) && !r.contains('loc_evang');
  }

  bool get _isEducationDept {
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
    final r = widget.userRole.toLowerCase();
    final d = widget.userDept.toLowerCase();
    return (r.contains('edu_dept') || d.contains('교육') || grouping.startsWith('24-Dept 4')) && !r.contains('loc_edu');
  }

  bool get _isAdministrationDept {
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
    final r = widget.userRole.toLowerCase();
    final d = widget.userDept.toLowerCase();
    return (r.contains('admin_dept') || d.contains('행정서무') || 
            grouping.startsWith('24-Dept 11') || grouping.startsWith('24-Dept 12') || grouping.startsWith('24-Dept 13')) &&
           r != 'admin';
  }

  bool get _hasDualMode {
    return _isInternalAffairs || _isAdministrationDept;
  }

  String _getDualModeTitle() {
    if (_isInternalAffairs) return "Internal Affairs";
    if (_isEvangelismDept) return "Evangelism";
    if (_isEducationDept) return "Education";
    if (_isAdministrationDept) return "Administration";
    return "Department";
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
    final role = widget.userRole.toLowerCase();

    // Guard: Location workers are strictly handled by Location Cascade
    final locLower = widget.userLoc.trim().toLowerCase();
    final bool isLocWorker = (locLower != 'church' && locLower != 'church workers' && locLower != 'church main') &&
        ((widget.userLoc.isNotEmpty && widget.userLoc != 'N/A') ||
         (widget.userSub.isNotEmpty && widget.userSub != 'N/A') ||
         (widget.userTeam.isNotEmpty && widget.userTeam != 'N/A') ||
         (widget.userCell.isNotEmpty && widget.userCell != 'N/A'));

    // ==============================================================
    // A. CHURCH-WIDE ADMIN / DUAL-MODE WORKERS IN CHURCH MODE
    // ==============================================================
    if (!isLocWorker && (scope == 'church' || (_hasDualMode && _dualModeChurchView) || role == 'admin' || role.startsWith('church_') || role.startsWith('korean_worker_'))) {
      return await query.order('english_name');
    }

    // ==============================================================
    // B. CHURCH WORKERS & 24 DEPARTMENTS (Grouping starts with '24-Dept')
    // ==============================================================
    if (!isLocWorker && (grouping.startsWith('24-Dept') || scope == 'church_department')) {
      void excludeChurchWorkers() {
        query = query
            .neq('location', 'Church Workers')
            .neq('location', 'Church Main')
            .neq('location', 'Church');
      }

      // 1. Men's Group (장년회) across all locations
      if (grouping == '24-Dept MG' || role.startsWith('mg_group')) {
        query = query.eq('department', '장년회').neq('location', 'Mou').neq('location', 'New Saints');
        excludeChurchWorkers();
      } 
      // 2. Women's Group (부녀회) across all locations
      else if (grouping == '24-Dept WG' || role.startsWith('wg_group')) {
        query = query.eq('department', '부녀회').neq('location', 'Mou').neq('location', 'New Saints');
        excludeChurchWorkers();
      } 
      // 3. Young Adults (청년회) across all locations
      else if (grouping == '24-Dept YAG' || role.startsWith('yag_group')) {
        query = query.eq('department', '청년회').neq('location', 'Mou').neq('location', 'New Saints');
        excludeChurchWorkers();
      } 
      // 4. NEW SAINTS (새신자) across all locations
      else if (grouping == '24-Dept New Saints' || role.startsWith('new_saints_dept') || widget.userDept == '새신자') {
        query = query.or('department.eq.새신자,department.ilike.%new saints%').neq('location', 'Mou');
        excludeChurchWorkers();
      } 
      // 5. THEOLOGY (신학부) across all locations
      else if (grouping.startsWith('24-Dept 18') || role.startsWith('theology_dept') || widget.userDept == '신학부' || widget.userDept.toLowerCase() == 'theology') {
        query = query.or('department.eq.신학부,department.ilike.%theology%').neq('location', 'Mou').neq('location', 'New Saints');
        excludeChurchWorkers();
      }
      // 6. MOU across all locations
      else if (grouping == '24-Dept MOU' || role.startsWith('mou_dept')) {
        query = query.eq('department', 'Mou').neq('location', 'Mou').neq('location', 'New Saints');
        excludeChurchWorkers();
      }
      // 7. Standard 24 Departments (Praise, Culture, ICT, Sports, IA Dept Mode, etc.)
      else {
        final officialDeptId = _roleMetadata?['official_dept_id'];
        if (officialDeptId != null) {
          query = query.eq('official_dept_id', officialDeptId);
        } else if (_isInternalAffairs) {
          query = query.or('department.eq.내무부,department.ilike.%internal affairs%');
        } else if (_isEvangelismDept) {
          // Strictly locked to Evangelism Department members
          query = query.or('department.eq.전도부,department.ilike.%evangelism%');
        } else if (_isEducationDept) {
          // Strictly locked to Education Department members
          query = query.or('department.eq.교육부,department.ilike.%education%');
        } else if (_isAdministrationDept) {
          query = query.or('department.eq.행정서무부,department.ilike.%admin%');
        } else if (widget.userDept.isNotEmpty && widget.userDept != 'N/A' && widget.userDept != 'Church') {
          query = query.eq('department', widget.userDept);
        } else {
          String deptKeyword = (_roleMetadata?['display_name_ko'] ?? '')
              .toString()
              .replaceAll(RegExp(r'(서무|부장|총무|과장)$'), '')
              .trim();
          if (deptKeyword.isNotEmpty) {
            query = query.eq('department', deptKeyword);
          }
        }
      }

      return await query.order('english_name');
    }

    // ==============================================================
    // C. LOCATION WORKER HIERARCHY (Strict 5-Tier Cascade)
    // ==============================================================
    final isCell = grouping.startsWith('Cell Group') || scope == 'cell' || role.contains('cell');
    final isTeam = grouping.startsWith('Team') || grouping == 'Location Team' || scope == 'team' || role.contains('team');
    final isDept = grouping.startsWith('Dept ') || scope == 'department' || role.startsWith('dept_');
    final isSubLoc = grouping.startsWith('Sub-Location') || scope == 'sub_location' || role.startsWith('sub_loc');
    final isLoc = grouping.startsWith('Location') || scope == 'location' || role.startsWith('loc_');

    // 1. Location
    if (isLoc || isSubLoc || isDept || isTeam || isCell) {
      if (widget.userLoc.isNotEmpty && widget.userLoc != 'N/A' && locLower != 'church') {
        query = query.eq('location', widget.userLoc);
      }
    }

    // 2. Sub-Location
    if (isSubLoc || isDept || isTeam || isCell) {
      if (widget.userSub.isNotEmpty && widget.userSub != 'N/A') {
        query = query.eq('sub_location', widget.userSub);
      }
    }

    // 3. Department
    if (isDept || isTeam || isCell) {
      if (widget.userDept.isNotEmpty && widget.userDept != 'N/A') {
        query = query.eq('department', widget.userDept);
      }
    }

    // 4. Team
    if (isTeam || isCell) {
      if (widget.userTeam.isNotEmpty && widget.userTeam != 'N/A') {
        query = query.eq('team', widget.userTeam);
      }
    }

    // 5. Cell Group
    if (isCell) {
      if (widget.userCell.isNotEmpty && widget.userCell != 'N/A') {
        query = query.eq('cell_group', widget.userCell);
      }
    }

    return await query.order('english_name');
  }

  @override
  void _openMember(dynamic member) => Navigator.push(
        context,
        MaterialPageRoute(builder: (c) => MemberDetailScreen(member: member, userRole: widget.userRole)),
      );

  void _memberMenu(Offset pos, dynamic member) {
    final name = (member['english_name'] ?? '').toString();
    final phone = (member['phone'] ?? '').toString().replaceAll(' ', '');
    final id = (member['scj_id'] ?? '').toString();
    showOfficeMenu(context, pos, [
      OfficeMenuItem("Open profile", icon: Icons.person_outline, onTap: () => _openMember(member)),
      const OfficeMenuItem.divider(),
      OfficeMenuItem("Copy name", icon: Icons.content_copy, onTap: name.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: name))),
      OfficeMenuItem("Copy SCJ ID", icon: Icons.badge_outlined, onTap: id.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: id))),
      OfficeMenuItem("Copy phone", icon: Icons.phone_outlined, onTap: phone.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: phone))),
      OfficeMenuItem("Call", icon: Icons.call_outlined, onTap: phone.isEmpty ? null : () => launchUrl(Uri.parse('tel:$phone'))),
      OfficeMenuItem("SMS", icon: Icons.sms_outlined, onTap: phone.isEmpty ? null : () => launchUrl(Uri.parse('sms:$phone'))),
      OfficeMenuItem("WhatsApp", icon: Icons.chat_outlined, onTap: phone.isEmpty ? null : () => launchUrl(Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}'), mode: LaunchMode.externalApplication)),
    ]);
  }

  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
      appBar: AppBar(
        title: Text(
          "Member Directory",
          style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: AppPalette.bg(Colors.white),
        foregroundColor: AppPalette.fg(Colors.black),
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // Dual Mode Switcher for IA, Evangelism, Education, Administration
          if (_hasDualMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.bg(Colors.purple.shade50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.line(Colors.purple.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _dualModeChurchView 
                          ? "${_getDualModeTitle()}: Church-Wide" 
                          : "${_getDualModeTitle()}: Department Only",
                      style: GoogleFonts.merriweather(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppPalette.fg(const Color(0xFF4A148C)),
                      ),
                    ),
                    Switch(
                      value: _dualModeChurchView,
                      activeThumbColor: const Color(0xFF4A148C),
                      onChanged: (val) {
                        setState(() => _dualModeChurchView = val);
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
                prefixIcon: Icon(Icons.search, color: AppPalette.fg(Color(0xFF4A148C))),
                filled: true,
                fillColor: AppPalette.bg(Colors.white),
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
                      style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey)),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final recruiter = member['introduced_by']?['english_name'] ?? "Direct Enrollment";

                    return OfficeRightClick(longPress: true, onMenu: (p) => _memberMenu(p, member), child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppPalette.bg(const Color(0xFF4A148C)),
                          child: Text(
                            (member['english_name'] != null && member['english_name'].isNotEmpty)
                                ? member['english_name'][0]
                                : "?",
                            style: TextStyle(color: AppPalette.fg(Colors.white)),
                          ),
                        ),
                        title: Text(
                          member['english_name'] ?? "No Name",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "ID: ${member['scj_id'] ?? '-'} • Dept: ${member['department'] ?? '-'} • Loc: ${member['location'] ?? '-'}\nIntro: $recruiter",
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
                    ));
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