// ignore_for_file: curly_braces_in_flow_control_structures, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:master_admin/core/app_palette.dart';

class ApprovalCockpit extends StatefulWidget {
  final String role, unitName, selectedDuty;
  const ApprovalCockpit({
    super.key,
    required this.role,
    required this.unitName,
    required this.selectedDuty,
  });

  @override
  State<ApprovalCockpit> createState() => _ApprovalCockpitState();
}

class _ApprovalCockpitState extends State<ApprovalCockpit> {
  final _supabase = Supabase.instance.client;
  static const Color _brandPurple = Color(0xFF4A148C);

  // Which unit columns a reviewer's scope is matched on.
  // Chain: cell group -> team -> department -> sub-location -> location -> church department (24).
  static const Map<String, List<String>> _scopeColumns = {
    'church': [],
    'church_department': ['department'], // one of the 24 church departments, all locations
    'location': ['location'],
    'sub_location': ['location', 'sub_location'],
    'department': ['location', 'sub_location', 'department'],
    'team': ['location', 'sub_location', 'department', 'team'],
  };

  bool _isLoading = true;
  String? _scopeMessage; // why nothing is shown (not a reviewer / profile incomplete / error)

  // The signed-in reviewer
  int _level = 0; // 1 = first reviewer after the cell leader, 2 = next ...
  Map<int, Set<String>> _levelScopes = {}; // approval level -> scopes that sit at that level
  String _scope = 'team';
  Map<String, String> _unit = {}; // cleaned location / sub_location / department / team

  List<Map<String, dynamic>> _pendingBatches = [];
  List<Map<String, dynamic>> _approvedBatches = [];

  // Currently inspected report batch
  Map<String, dynamic>? _selectedReport;
  List<dynamic> _inspectedLogs = [];
  List<dynamic> _inspectedImages = [];
  bool _isLoadingDetails = false;
  bool _isSaving = false;

  // ---- theme helpers ----
  ColorScheme get _cs => Theme.of(context).colorScheme;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _accent => _isDark ? _cs.primary : _brandPurple;
  Color get _cardBorder => _cs.onSurface.withValues(alpha: _isDark ? 0.25 : 0.55);

  @override
  void initState() {
    super.initState();
    _loadAllReports();
  }

  String _getTableName() {
    String d = widget.selectedDuty;
    if (d == 'Service Attendance Status') return 'logs_service_attendance_status';
    if (d == 'Cell Group Service') return 'logs_cell_service';
    if (d == 'Offering Status') return 'logs_offering';
    if (d == 'Evangelism' || d == 'Evangelism Part') return 'logs_evangelism';
    if (d == 'Morning Light') return 'logs_morning_light';
    if (d == 'All Saints Education') return 'logs_all_saints_education';
    if (d.contains('Visitations')) return 'logs_visitations';
    if (d == 'Workers Education') return 'logs_workers_education';
    if (d == 'Workers Daily Participation') return 'logs_workers_participation';
    return 'logs_service_attendance_status';
  }

  // ==========================================
  // SMALL HELPERS
  // ==========================================
  /// Lower-cased, trimmed; "N/A" counts as empty.
  String _clean(dynamic v) {
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'n/a' ? '' : s;
  }

  String _escapeLike(String s) => s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  void _showMsg(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? Colors.red.shade800 : Colors.green.shade800,
      content: Text(m),
    ));
  }

  // ==========================================
  // WHO IS REVIEWING? (level + unit scope)
  // ==========================================
  /// Returns false (and sets [_scopeMessage]) when this user may not review anything.
  Future<bool> _resolveReviewer() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _scopeMessage = "You are signed out. Please sign in again.";
      return false;
    }

    final prof = await _supabase
        .from('profiles')
        .select('role, location, sub_location, department, team')
        .eq('id', user.id)
        .maybeSingle();

    final roleKey = (prof?['role'] ?? widget.role).toString().toLowerCase();
    _unit = {
      'location': _clean(prof?['location']),
      'sub_location': _clean(prof?['sub_location']),
      'department': _clean(prof?['department']),
      'team': _clean(prof?['team']),
    };

    int? level;
    String? scope;
    final Map<int, Set<String>> levelScopes = {};
    bool configured = false;

    // 1) Preferred: the approval chain configured in app_roles.
    try {
      final r = await _supabase
          .from('app_roles')
          .select('approval_level, approval_scope')
          .eq('role_key', roleKey)
          .maybeSingle();
      level = (r?['approval_level'] as num?)?.toInt();
      scope = r?['approval_scope']?.toString().toLowerCase();

      final all = await _supabase
          .from('app_roles')
          .select('approval_level, approval_scope')
          .not('approval_level', 'is', null);
      for (final row in (all as List)) {
        final lv = (row['approval_level'] as num?)?.toInt();
        final sc = row['approval_scope']?.toString().toLowerCase();
        if (lv != null && sc != null && _scopeColumns.containsKey(sc)) {
          levelScopes.putIfAbsent(lv, () => <String>{}).add(sc);
        }
      }
      configured = levelScopes.isNotEmpty;
    } catch (e) {
      debugPrint("app_roles approval columns not available yet: $e");
    }

    if (!configured) {
      // 2) Nothing configured yet: team 1 -> department 2 -> sub-location 3 -> location 4,
      //    guessed from the role key. Church-department reviewers need the app_roles setup.
      levelScopes.addAll({
        1: {'team'},
        2: {'department'},
        3: {'sub_location'},
        4: {'location'},
      });
      if (roleKey.contains('sub_location') || roleKey.contains('sublocation')) {
        level = 3;
        scope = 'sub_location';
      } else if (roleKey.contains('team')) {
        level = 1;
        scope = 'team';
      } else if (roleKey.contains('dept') || roleKey.contains('department')) {
        level = 2;
        scope = 'department';
      } else if (roleKey.contains('location')) {
        level = 4;
        scope = 'location';
      } else {
        level = 0;
      }
    } else if (level == null || scope == null || !(levelScopes[level]?.contains(scope) ?? false)) {
      level = 0; // a chain is configured but this role isn't part of it -> not a reviewer
    }

    final int lvl = level;
    final String scp = scope ?? 'team';

    if (lvl <= 0) {
      _scopeMessage =
          "Your role (${roleKey.replaceAll('_', ' ')}) is not set up to approve reports. "
          "Ask an administrator to set approval_level and approval_scope for this role.";
      return false;
    }

    // Never widen the scope: if the profile is missing a unit the scope needs, show nothing.
    String? missing;
    for (final c in _scopeColumns[scp]!) {
      if (c != 'sub_location' && _unit[c]!.isEmpty) missing = c;
    }
    if (missing != null) {
      _scopeMessage = "Your profile has no $missing set, so reports can't be matched to your unit. "
          "Please contact Church Administration.";
      return false;
    }

    _level = lvl;
    _scope = scp;
    _levelScopes = levelScopes;
    return true;
  }

  /// Final guard on every row: is this member inside the reviewer's units?
  bool _inScope(Map<String, dynamic> m) {
    for (final c in _scopeColumns[_scope] ?? const <String>[]) {
      if (_clean(m[c]) != _unit[c]) return false;
    }
    return true;
  }

  bool _isChurchBatch(Map<String, dynamic> m) {
    final loc = _clean(m['location']);
    return loc == 'church' || loc == '교회';
  }

  /// Does an approval level of this scope exist on this report's route?
  bool _levelApplies(String scope, Map<String, dynamic> m) {
    final church = _isChurchBatch(m);
    switch (scope) {
      case 'team':
        return !church && _clean(m['team']).isNotEmpty;
      case 'department':
        return !church && _clean(m['department']).isNotEmpty;
      case 'sub_location':
        return !church && _clean(m['sub_location']).isNotEmpty;
      case 'location':
        return !church && _clean(m['location']).isNotEmpty;
      case 'church_department':
        return _clean(m['department']).isNotEmpty;
      default:
        return true; // 'church'
    }
  }

  /// The approval levels this particular report passes through, lowest first.
  /// Levels that don't exist for its unit path are skipped (no team -> no team level;
  /// Church workers go straight to their church department).
  List<int> _chainFor(Map<String, dynamic> m) {
    final levels = _levelScopes.keys.toList()..sort();
    return [
      for (final lv in levels)
        if (_levelScopes[lv]!.any((s) => _levelApplies(s, m))) lv
    ];
  }

  // ==========================================
  // LOAD REPORTS (only this reviewer's units, only reports that reached them)
  // ==========================================
  Future<void> _loadAllReports() async {
    setState(() {
      _isLoading = true;
      _scopeMessage = null;
    });
    final tableName = _getTableName();

    try {
      final ok = await _resolveReviewer();
      if (!ok) {
        if (mounted) {
          setState(() {
            _pendingBatches = [];
            _approvedBatches = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Narrow the query on the server (case-insensitive), then re-check every row below.
      var query = _supabase.from(tableName).select('*, members!inner(*)');
      for (final c in _scopeColumns[_scope] ?? const <String>[]) {
        if (c == 'sub_location') continue; // compared after loading (blank / "N/A" are the same)
        query = query.ilike('members.$c', _escapeLike(_unit[c]!));
      }

      final res = await query.order('created_at', ascending: false).limit(500);
      final List<dynamic> logs = res as List<dynamic>;

      // Group individual member logs into report batches: date + cell + its full unit path
      // (so "Cell 1" of two different teams is never merged into one report).
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final raw in logs) {
        final l = Map<String, dynamic>.from(raw as Map);
        final m = l['members'] is Map ? Map<String, dynamic>.from(l['members'] as Map) : <String, dynamic>{};
        if (!_inScope(m)) continue;

        final rDate = l['report_date']?.toString() ?? 'No Date';
        final unit = (l['unit_name'] ?? m['cell_group'] ?? widget.unitName).toString();
        final key = [
          rDate,
          unit,
          _clean(m['location']),
          _clean(m['sub_location']),
          _clean(m['department']),
          _clean(m['team']),
        ].join('::');
        grouped.putIfAbsent(key, () => []).add(l);
      }

      final List<Map<String, dynamic>> pending = [];
      final List<Map<String, dynamic>> approved = [];

      grouped.forEach((key, batchLogs) {
        final first = batchLogs.first;
        final m0 = first['members'] is Map ? Map<String, dynamic>.from(first['members'] as Map) : <String, dynamic>{};

        // This report only passes through the levels that exist for its unit path.
        final chain = _chainFor(m0);
        if (!chain.contains(_level)) return; // this reviewer isn't on this report's route
        final int idx = chain.indexOf(_level);
        final int lastLevel = chain.last;
        final int prevLevel = idx == 0 ? 0 : chain[idx - 1];

        // The batch is only as far along as its least-advanced row.
        bool flagged = false;
        int level = 1 << 30;
        for (final l in batchLogs) {
          final st = (l['verification_status'] ?? 'pending').toString().toLowerCase();
          if (st == 'flagged') flagged = true;
          int lv = (l['approval_level'] as num?)?.toInt() ?? 0;
          if (st == 'approved' && lv == 0) lv = 1000; // old rows approved before levels existed
          if (lv < level) level = lv;
        }

        // awaiting  = the previous level on its route approved it: it is this reviewer's turn
        // flagged   = returned to the submitter for correction (not forwarded anywhere)
        // forwarded = this reviewer approved it, higher levels still to go
        // final     = approved by the last level on its route
        // other     = hasn't reached this reviewer yet -> hidden
        final String state = flagged
            ? 'flagged'
            : level >= lastLevel
                ? 'final'
                : level >= _level
                    ? 'forwarded'
                    : level >= prevLevel
                        ? 'awaiting'
                        : 'other';

        final unitName = (first['unit_name'] ?? m0['cell_group'] ?? widget.unitName).toString();
        final unitPath = [m0['location'], m0['sub_location'], m0['department'], m0['team']]
            .where((e) => e != null && e.toString().trim().isNotEmpty)
            .join(' › ');

        final batchData = <String, dynamic>{
          'key': key,
          'report_date': first['report_date'],
          'unit_name': unitName,
          'unit_context': unitPath,
          'state': state,
          'level': level,
          'is_last': _level == lastLevel,
          'submitted_at': DateTime.tryParse(first['created_at']?.toString() ?? ''),
          'approved_at': DateTime.tryParse(first['updated_at']?.toString() ?? ''),
          'correction_note': first['correction_note'],
          'total_members': batchLogs.length,
          'logs': batchLogs,
        };

        if (state == 'awaiting') {
          pending.add(batchData);
        } else if (state == 'flagged' && idx == 0) {
          // Only the first reviewer sees returned reports; they are NOT forwarded upwards.
          pending.add(batchData);
        } else if (state == 'forwarded' || state == 'final') {
          approved.add(batchData);
        }
      });

      pending.sort((a, b) {
        final da = a['submitted_at'] as DateTime? ?? DateTime(2020);
        final db = b['submitted_at'] as DateTime? ?? DateTime(2020);
        return db.compareTo(da);
      });
      approved.sort((a, b) {
        final da = a['approved_at'] as DateTime? ?? DateTime(2020);
        final db = b['approved_at'] as DateTime? ?? DateTime(2020);
        return db.compareTo(da);
      });

      if (mounted) {
        setState(() {
          _pendingBatches = pending;
          _approvedBatches = approved;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Cockpit Load Error: $e");
      if (mounted) {
        setState(() {
          _scopeMessage = "Couldn't load reports. Pull down to retry.";
          _isLoading = false;
        });
      }
    }
  }

  // ==========================================
  // INSPECTION (photos + logs)
  // ==========================================
  Future<void> _openReportInspection(Map<String, dynamic> batch) async {
  setState(() {
    _selectedReport = batch;
    _isLoadingDetails = true;
    _inspectedLogs = batch['logs'] as List<dynamic>;
    _inspectedImages = [];
  });

  try {
    final duty = widget.selectedDuty.trim() == 'Evangelism Part' 
        ? 'Evangelism' 
        : widget.selectedDuty.trim();

    // Query by report_date, normalized duty_name, and unit_name
    final imgRes = await _supabase
        .from('report_evidence')
        .select()
        .eq('report_date', batch['report_date'])
        .ilike('duty_name', _escapeLike(duty))
        .eq('unit_name', batch['unit_name']);

    if (mounted) {
      setState(() {
        _inspectedImages = List<dynamic>.from(imgRes as List);
        _isLoadingDetails = false;
      });
    }
  } catch (e) {
    debugPrint("Evidence fetch error: $e");
    if (mounted) {
      setState(() {
        _inspectedImages = [];
        _isLoadingDetails = false;
      });
    }
  }
}

  String? _imageUrl(dynamic row) {
    if (row is! Map) return null;
    final v = row['image_url'] ?? row['url'] ?? row['photo_url'] ?? row['file_url'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  // ==========================================
  // APPROVE / FLAG
  // ==========================================
  Future<void> _processApproval(bool isApproved, {String? note}) async {
    final b = _selectedReport;
    if (b == null || _isSaving) return;
    if (b['state'] != 'awaiting') {
      _showMsg("This report isn't waiting for your approval.", error: true);
      return;
    }

    // Update exactly this report's rows (before, every report of that date was updated).
    final ids = (b['logs'] as List).map((l) => (l as Map)['id']).where((i) => i != null).toList();
    if (ids.isEmpty) {
      _showMsg("Couldn't identify this report's rows. Please refresh and try again.", error: true);
      return;
    }

    final tableName = _getTableName();
    final bool isFinal = b['is_last'] == true;

    setState(() => _isSaving = true);
    try {
      await _supabase.from(tableName).update({
        // Only the last level marks it 'approved' (that is what gets compiled);
        // earlier levels keep it 'pending' so it moves on to the next reviewer.
        'verification_status': isApproved ? (isFinal ? 'approved' : 'pending') : 'flagged',
        'approval_level': isApproved ? _level : 0,
        'flagged_for_correction': !isApproved,
        'correction_note': note,
        'updated_at': DateTime.now().toIso8601String(),
      }).inFilter('id', ids);

      _showMsg(isApproved
          ? (isFinal ? "Report fully approved" : "Report approved and forwarded to the next level")
          : "Report returned for correction (not forwarded)");

      if (mounted) setState(() => _selectedReport = null);
      await _loadAllReports();
    } catch (e) {
      debugPrint("Approval Update Error: $e");
      _showMsg("Couldn't save your decision. Please try again.", error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return "Unknown";
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt.toLocal());
  }

  // ==========================================
  // BUILD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppPalette.bg(Theme.of(context).scaffoldBackgroundColor),
        appBar: AppBar(
          title: Text(
            "QC Approval Cockpit",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(_accent), fontSize: 17),
          ),
          centerTitle: true,
          backgroundColor: AppPalette.bg(_cs.surface),
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () {
              if (_selectedReport != null) {
                setState(() => _selectedReport = null);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          bottom: (_selectedReport == null && _scopeMessage == null)
              ? TabBar(
                  labelColor: _accent,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: _accent,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.pending_actions_rounded, size: 17),
                          const SizedBox(width: 8),
                          Text("Pending Reports (${_pendingBatches.length})"),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_outlined, size: 17),
                          const SizedBox(width: 8),
                          Text("Approved Reports (${_approvedBatches.length})"),
                        ],
                      ),
                    ),
                  ],
                )
              : null,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _scopeMessage != null
                ? _buildMessage(_scopeMessage!)
                : _selectedReport != null
                    ? _buildInspectionView()
                    : Column(
                        children: [
                          _buildScopeBanner(),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildReportsList(_pendingBatches, isPendingTab: true),
                                _buildReportsList(_approvedBatches, isPendingTab: false),
                              ],
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildMessage(String text) => RefreshIndicator(
        onRefresh: _loadAllReports,
        child: ListView(
          padding: const EdgeInsets.all(30),
          children: [
            const SizedBox(height: 60),
            Icon(Icons.lock_outline_rounded, size: 48, color: AppPalette.fg(Colors.grey.shade500)),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppPalette.fg(Colors.grey.shade600), height: 1.5)),
          ],
        ),
      );

  Widget _buildScopeBanner() {
    final unitPath = (_scopeColumns[_scope] ?? const <String>[])
        .map((c) => _unit[c] ?? '')
        .where((e) => e.isNotEmpty)
        .join(' › ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: AppPalette.bg(_accent.withValues(alpha: 0.08)),
      child: Text(
        "Level $_level reviewer · ${_scope.replaceAll('_', ' ')} scope${unitPath.isEmpty ? '' : ' · $unitPath'}",
        style: TextStyle(fontSize: 11, color: AppPalette.fg(_accent), fontWeight: FontWeight.w600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // --- List View for Pending & Approved Folders ---
  Widget _buildReportsList(List<Map<String, dynamic>> batches, {required bool isPendingTab}) {
    if (batches.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAllReports,
        child: ListView(
          children: [
            const SizedBox(height: 90),
            Center(
              child: Icon(
                isPendingTab ? Icons.check_circle_outline_rounded : Icons.folder_open_rounded,
                size: 50,
                color: AppPalette.fg(Colors.grey.shade400),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                isPendingTab
                    ? "Clear! No reports awaiting your approval."
                    : "No approved reports found for ${widget.selectedDuty}.",
                style: TextStyle(color: AppPalette.fg(Colors.grey.shade600), fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: batches.length,
        itemBuilder: (context, i) {
          final b = batches[i];
          final String state = b['state'] as String;
          final bool isFinal = state == 'final';
          final bool isForwarded = state == 'forwarded';
          final bool isFlagged = state == 'flagged';
          final MaterialColor tone = (isFinal || isForwarded)
              ? Colors.green
              : isFlagged
                  ? Colors.red
                  : Colors.orange;
          final String chip = isFinal
              ? "Approved"
              : isForwarded
                  ? "Approved · forwarded"
                  : isFlagged
                      ? "Flagged"
                      : "Awaiting your approval";

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppPalette.bg(_cs.surface),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppPalette.line(_cardBorder), width: 1.0),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () => _openReportInspection(b),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            b['unit_name'],
                            style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.fg(_accent)),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppPalette.bg(tone.withValues(alpha: 0.12)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppPalette.line(tone.shade300)),
                          ),
                          child: Text(
                            chip,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.fg(_isDark ? tone.shade200 : tone.shade800)),
                          ),
                        ),
                      ],
                    ),
                    if ((b['unit_context'] as String).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(b['unit_context'], style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade600))),
                    ],
                    const Divider(height: 18),
                    Row(
                      children: [
                        Icon(Icons.event_note_rounded, size: 15, color: AppPalette.fg(Colors.blueGrey)),
                        const SizedBox(width: 6),
                        Text("Activity Date: ${b['report_date']}",
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text("${b['total_members']} Entries", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade600))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.upload_file_rounded, size: 15, color: AppPalette.fg(Colors.blueGrey)),
                        const SizedBox(width: 6),
                        Text("Date of Submission: ${_formatDate(b['submitted_at'])}",
                            style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
                      ],
                    ),
                    if (isFinal || isForwarded) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 15, color: AppPalette.fg(Colors.green.shade600)),
                          const SizedBox(width: 6),
                          Text("Date of Approval: ${_formatDate(b['approved_at'])}",
                              style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.green.shade600), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                    if (isFlagged && b['correction_note'] != null) ...[
                      const SizedBox(height: 6),
                      Text("Correction Note: ${b['correction_note']}",
                          style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.red.shade400), fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text("Tap to Inspect & Audit →",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(_accent))),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Detailed Inspection View for QC Review ---
  Widget _buildInspectionView() {
    final b = _selectedReport!;
    final String state = b['state'] as String;
    final bool isDone = state == 'final' || state == 'forwarded';

    final absentees = _inspectedLogs
        .where((l) => ["Absentee", "CS Absentee", "No", "ASE Absence"].contains(l['status_detail'] ?? l['attendance_realtime']))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppPalette.bg(_cs.surface),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppPalette.line(_cardBorder), width: 1.0),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Inspecting: ${b['unit_name']}",
                    style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.fg(_accent))),
                if ((b['unit_context'] as String).isNotEmpty)
                  Text(b['unit_context'], style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
                const SizedBox(height: 4),
                Text("Duty: ${widget.selectedDuty}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text("Activity Date: ${b['report_date']}", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade600))),
                Text("Date of Submission: ${_formatDate(b['submitted_at'])}",
                    style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade600))),
                if (isDone)
                  Text("Date of Approval: ${_formatDate(b['approved_at'])}",
                      style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.green.shade600), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _sectionHeader(Icons.camera_alt_rounded, "Physical Evidence (Photos)"),
          _buildEvidenceGallery(),
          const SizedBox(height: 20),

          _sectionHeader(Icons.rule_folder_rounded, "Data Consistency Audit (Absentees)"),
          _buildAbsenteeList(absentees),
          const SizedBox(height: 24),

          if (state == 'awaiting')
            _buildDecisionFooter()
          else if (state == 'flagged')
            _infoBox(Icons.flag_rounded, Colors.red,
                "This report was returned to the submitter for correction. It will come back to you once it is corrected and resubmitted.")
          else
            _infoBox(Icons.verified_rounded, Colors.green,
                state == 'final'
                    ? "This report has been fully approved and verified."
                    : "You approved this report. It has been forwarded to the next level."),
        ],
      ),
    );
  }

  Widget _infoBox(IconData icon, MaterialColor tone, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.bg(tone.withValues(alpha: 0.10)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.line(tone.shade300)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppPalette.fg(tone.shade400), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppPalette.fg(tone.shade400))),
            ),
          ],
        ),
      );

  Widget _sectionHeader(IconData icon, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, color: AppPalette.fg(_accent), size: 18),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );

  void _openFullImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.bg(Colors.black),
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Icon(Icons.broken_image_rounded, color: AppPalette.fg(Colors.white54), size: 48)),
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: IconButton(
                icon: Icon(Icons.close_rounded, color: AppPalette.fg(Colors.white)),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvidenceGallery() {
    if (_isLoadingDetails) {
      return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
    }
    if (_inspectedImages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.orange.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.line(Colors.orange.shade300)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppPalette.fg(Colors.orange), size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text("No photos were uploaded with this report.",
                  style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.orange), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _inspectedImages.length,
        itemBuilder: (c, i) {
          final url = _imageUrl(_inspectedImages[i]);
          return GestureDetector(
            onTap: url == null ? null : () => _openFullImage(url),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              width: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppPalette.line(_cardBorder), width: 1.0),
                color: AppPalette.bg(_cs.surfaceContainerHighest),
              ),
              clipBehavior: Clip.antiAlias,
              child: url == null
                  ? Center(child: Icon(Icons.image_not_supported_rounded, color: AppPalette.fg(Colors.grey), size: 36))
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (ctx, child, progress) =>
                          progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      errorBuilder: (_, __, ___) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_rounded, color: AppPalette.fg(Colors.grey), size: 36),
                            SizedBox(height: 6),
                            Text("Photo can't be opened", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey))),
                          ],
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAbsenteeList(List<dynamic> abs) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.bg(_cs.surface),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppPalette.line(_cardBorder), width: 1.0),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            title: Text("Total Absentees: ${abs.length}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: const Text("Cross-check these reasons with the evidence photo.", style: TextStyle(fontSize: 11)),
            trailing: Icon(Icons.warning_amber_rounded, color: AppPalette.fg(abs.isEmpty ? Colors.green : Colors.orange)),
          ),
          const Divider(height: 0),
          ...abs.map((l) {
            final m = l['members'] is Map ? l['members'] as Map : const {};
            final name = (m['english_name'] ?? m['korean_name'] ?? 'Unknown member').toString();
            return ListTile(
              dense: true,
              leading: CircleAvatar(backgroundColor: AppPalette.bg(Colors.redAccent), radius: 4),
              title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: Text(
                l['reason_notes'] ?? l['situation_notes'] ?? "No reason provided",
                style: TextStyle(
                  color: AppPalette.fg((l['reason_notes'] == null && l['situation_notes'] == null) ? Colors.red : Colors.grey.shade600),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            );
          }),
          if (abs.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text("No absentees to verify for this unit.", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey))),
            ),
        ],
      ),
    );
  }

  Widget _buildDecisionFooter() {
    final bool isFinal = _selectedReport?['is_last'] == true;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppPalette.line(Colors.red), width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _isSaving ? null : _showFlagDialog,
            icon: Icon(Icons.flag_rounded, color: AppPalette.fg(Colors.red), size: 18),
            label: Text("Flag for Correction", style: TextStyle(color: AppPalette.fg(Colors.red), fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.bg(Colors.green.shade700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _isSaving ? null : () => _processApproval(true),
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(Icons.verified_rounded, color: AppPalette.fg(Colors.white), size: 18),
            label: Text(isFinal ? "Approve Report" : "Approve & Forward",
                style: TextStyle(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  void _showFlagDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Flag Report for Correction", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: "Enter reason for rejection (e.g., photo mismatch)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(Colors.red.shade700)),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return; // a reason is required so the submitter knows what to fix
              final note = ctrl.text.trim();
              Navigator.pop(c);
              _processApproval(false, note: note);
            },
            child: Text("Return Report", style: TextStyle(color: AppPalette.fg(Colors.white))),
          ),
        ],
      ),
    );
  }
}