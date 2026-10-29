// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'member_detail_screen.dart';
import 'package:master_admin/core/app_palette.dart';
import 'package:master_admin/core/app_sizes.dart';
import 'package:master_admin/widgets/compact_card.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_menus.dart';
import '../core/group_scope.dart';

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
  List<String> _subDeptNames = const [];

  // Loaded once per scope; search and unit filters work on this list, so
  // typing no longer reloads every member from the server.
  Future<List<dynamic>>? _membersFuture;
  final Map<String, String?> _filters = {'book_of_life': null, 'location': null, 'sub_location': null, 'department': null, 'team': null, 'cell_group': null};
  static const Map<String, String> _filterLabels = {
    'book_of_life': 'Group',
    'location': 'Location',
    'sub_location': 'Sub-location',
    'department': 'Department',
    'team': 'Team',
    'cell_group': 'Cell group',
  };

  @override
  void initState() {
    super.initState();
    _fetchRoleMetadata();
  }

  Future<void> _fetchRoleMetadata() async {
    try {
      final results = await Future.wait<dynamic>([
        _supabase
            .from('app_roles')
            .select('role_key, approval_scope, display_name_ko, "Grouping", official_dept_id')
            .eq('role_key', widget.userRole)
            .maybeSingle(),
        GroupScope.myDeptNames(),
      ]);
      if (mounted) {
        setState(() {
          _roleMetadata = results[0] as Map<String, dynamic>?;
          _subDeptNames = results[1] as List<String>;
          _loadingRole = false;
          _membersFuture = _getFilteredMembers();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingRole = false;
          _membersFuture = _getFilteredMembers();
        });
      }
    }
  }

  /// Men's, Women's, Young Adults, New Saints, Theology or MOU leader:
  /// sees their own group across the church, with no Church / Department toggle.
  String? get _groupDept => GroupScope.detect(
        grouping: (_roleMetadata?['Grouping'] ?? '').toString(),
        role: widget.userRole,
        subDeptNames: _subDeptNames,
      );

  // --- DUAL MODE DETERMINATION ---
  bool get _isInternalAffairs {
    final grouping = (_roleMetadata?['Grouping'] ?? '').toString();
    final r = widget.userRole.toLowerCase();
    final d = widget.userDept.toLowerCase();
    if (_groupDept != null) return false;
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
            GroupScope.isAdministrationGrouping(grouping)) &&
           r != 'admin';
  }

  bool get _hasDualMode {
    if (_groupDept != null) return false;
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

    // Church-wide group leaders (Men's, Women's, Young Adults, New Saints,
    // Theology, MOU): their own group across the church.
    // MOU workers are often saved under an MOU branch location (MOUWakiso …),
    // which made them look like location workers and listed that location's
    // members; MOU always lists the members whose department is MOU.
    final group = _groupDept;
    if (group != null && (!isLocWorker || group == 'MOU')) {
      return await GroupScope.filter(query, group).order('english_name');
    }

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

  void _openMember(dynamic member) => Navigator.push(
        context,
        MaterialPageRoute(builder: (c) => MemberDetailScreen(member: member, userRole: widget.userRole)),
      );

  void _memberMenu(Offset pos, dynamic member) {
    final name = (member['english_name'] ?? '').toString();
    final rawPhone = member['phone'] ?? member['phone_numbers'];
    final phone = (rawPhone is List ? (rawPhone.isEmpty ? '' : rawPhone.first) : (rawPhone ?? '')).toString().replaceAll(' ', '');
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

  String _v(dynamic m, String k) => (m[k] ?? '').toString().trim();

  /// Members matching the search and every chosen filter, except [skip]
  /// (used to work out the choices still possible in that filter).
  List<dynamic> _apply(List<dynamic> all, {String? skip}) {
    final q = _searchQuery.trim().toLowerCase();
    return all.where((m) {
      if (q.isNotEmpty) {
        final hay = '${_v(m, 'english_name')} ${_v(m, 'korean_name')} ${_v(m, 'scj_id')}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      for (final e in _filters.entries) {
        if (e.key == skip || e.value == null) continue;
        if (_v(m, e.key) != e.value) return false;
      }
      return true;
    }).toList();
  }

  Widget _filterChip(String key, List<dynamic> all) {
    final selected = _filters[key];
    final options = _apply(all, skip: key).map((m) => _v(m, key)).where((v) => v.isNotEmpty && v.toLowerCase() != 'n/a').toSet().toList()..sort();
    if (options.length <= 1 && selected == null) return const SizedBox.shrink();
    const purple = Color(0xFF4A148C);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: tr("Filter by ${_filterLabels[key]}"),
        onSelected: (v) => setState(() => _filters[key] = v == '__all' ? null : v),
        itemBuilder: (_) => [
          PopupMenuItem(value: '__all', child: Text("All ${_filterLabels[key]!.toLowerCase()}s")),
          const PopupMenuDivider(),
          for (final o in options) CheckedPopupMenuItem(value: o, checked: o == selected, child: Text(o)),
        ],
        child: Chip(
          avatar: Icon(selected == null ? Icons.filter_list_rounded : Icons.check_circle_rounded, size: 18, color: AppPalette.fg(selected == null ? purple : Colors.white)),
          label: Text(selected == null ? _filterLabels[key]! : "${_filterLabels[key]}: $selected",
              style: TextStyle(fontWeight: FontWeight.w600, color: AppPalette.fg(selected == null ? purple : Colors.white))),
          backgroundColor: AppPalette.bg(selected == null ? purple.withValues(alpha: 0.07) : purple),
          side: BorderSide(color: AppPalette.line(purple.withValues(alpha: 0.25))),
          deleteIcon: selected == null ? null : const Icon(Icons.close, size: 16, color: Colors.white),
          onDeleted: selected == null ? null : () => setState(() => _filters[key] = null),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final group = _groupDept;

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
        actions: [
          IconButton(
            tooltip: tr("Reload"),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() => _membersFuture = _getFilteredMembers()),
          ),
        ],
      ),
      body: Column(
        children: [
          if (group != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 10, AppSizes.gutter, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppPalette.bg(Colors.purple.shade50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.line(Colors.purple.shade200)),
                ),
                child: Text("${GroupScope.label(group)}: members across the church",
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.w600, fontSize: 13, color: AppPalette.fg(const Color(0xFF4A148C)))),
              ),
            ),
          // Dual Mode Switcher for Internal Affairs and Administration (not group leaders)
          if (_hasDualMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 10, AppSizes.gutter, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.bg(Colors.purple.shade50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.line(Colors.purple.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dualModeChurchView ? "${_getDualModeTitle()}: Church-Wide" : "${_getDualModeTitle()}: Department Only",
                        style: GoogleFonts.merriweather(fontWeight: FontWeight.w600, fontSize: 13, color: AppPalette.fg(const Color(0xFF4A148C))),
                      ),
                    ),
                    Switch(
                      value: _dualModeChurchView,
                      activeThumbColor: const Color(0xFF4A148C),
                      onChanged: (val) {
                        setState(() {
                          _dualModeChurchView = val;
                          _filters.updateAll((_, __) => null);
                          _membersFuture = _getFilteredMembers();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 12, AppSizes.gutter, 6),
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: tr("Search by name or SCJ ID..."),
                prefixIcon: Icon(Icons.search, color: AppPalette.fg(const Color(0xFF4A148C))),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _controller.clear();
                          _searchQuery = '';
                        }),
                      ),
                filled: true,
                fillColor: AppPalette.bg(Colors.white),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _membersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("Error loading data: ${snapshot.error}", textAlign: TextAlign.center)));
                }

                final all = snapshot.data ?? [];
                final members = _apply(all);
                final anyFilter = _filters.values.any((v) => v != null);
                return Column(children: [
                  // Filters in the middle; they scroll sideways when they don't fit
                  SizedBox(
                    height: 48,
                    child: Center(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: AppSizes.gutter),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          for (final k in _filters.keys) _filterChip(k, all),
                          if (anyFilter)
                            TextButton.icon(
                              onPressed: () => setState(() => _filters.updateAll((_, __) => null)),
                              icon: const Icon(Icons.clear_all_rounded, size: 18),
                              label: const Text("Clear filters"),
                            ),
                        ]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 0, AppSizes.gutter, 6),
                    child: Center(
                      child: Text(
                        members.length == all.length ? "${all.length} members" : "${members.length} of ${all.length} members",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.fg(Colors.grey.shade700)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: members.isEmpty
                        ? Center(
                            child: Text(
                              all.isEmpty ? "No members found in your authorized unit" : "No members match these filters",
                              style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey)),
                            ),
                          )
                        : CardGrid(
                            padding: const EdgeInsets.fromLTRB(AppSizes.gutter, 0, AppSizes.gutter, 24),
                            extent: AppSizes.listCard,
                            itemCount: members.length,
                            itemBuilder: (context, index) {
                              final member = members[index];
                              final recruiter = member['introduced_by']?['english_name'] ?? "Direct Enrollment";
                              final unit = [
                                _v(member, 'sub_location'),
                                _v(member, 'team'),
                                _v(member, 'cell_group'),
                              ].where((x) => x.isNotEmpty && x.toLowerCase() != 'n/a').join(' › ');
                              final name = _v(member, 'english_name');

                              return OfficeRightClick(
                                longPress: true,
                                onMenu: (p) => _memberMenu(p, member),
                                child: Tooltip(
                                  message: "ID: ${member['scj_id'] ?? '-'} • Dept: ${member['department'] ?? '-'} • Loc: ${member['location'] ?? '-'}"
                                      "${unit.isEmpty ? '' : '\n$unit'}\nIntro: $recruiter",
                                  waitDuration: const Duration(milliseconds: 600),
                                  child: CompactCard(
                                    leading: CircleAvatar(
                                      radius: 17,
                                      backgroundColor: AppPalette.bg(const Color(0xFF4A148C)),
                                      child: Text(name.isNotEmpty ? name[0] : "?", style: TextStyle(color: AppPalette.fg(Colors.white), fontSize: 13)),
                                    ),
                                    title: name.isEmpty ? "No Name" : name,
                                    subtitle: [
                                      "ID ${member['scj_id'] ?? '-'}",
                                      member['location'] ?? '-',
                                      member['department'] ?? '-',
                                      if (unit.isNotEmpty) unit,
                                      "Intro: $recruiter",
                                    ].join(' • '),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openMember(member),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
