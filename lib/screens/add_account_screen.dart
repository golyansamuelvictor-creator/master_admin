// ignore_for_file: curly_braces_in_flow_control_structures, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:master_admin/core/app_palette.dart';
import '../services/device_accounts.dart';

/// An error whose message is safe to show to the user as-is.
class _FriendlyException implements Exception {
  final String message;
  const _FriendlyException(this.message);
}

class AddAccountScreen extends StatefulWidget {
  final String? initialFullName;
  final String? initialScjId;
  final String? initialEmail;
  final String? initialPhone;
  final String? initialPassword;
  final String signUpMethod; // 'email', 'whatsapp', or 'google'
  final Map<String, dynamic>? memberData;

  const AddAccountScreen({
    super.key,
    this.initialFullName,
    this.initialScjId,
    this.initialEmail,
    this.initialPhone,
    this.initialPassword,
    this.signUpMethod = 'email',
    this.memberData,
  });

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _supabase = Supabase.instance.client;

  // Korean worker portfolio limits (matches the on-screen label).
  static const int _minPortfolio = 3;
  static const int _maxPortfolio = 5;

  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _usernameRe = RegExp(r'^[A-Za-z0-9._]{3,30}$');

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  // Password Visibility Toggles
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Dynamic Data Lists
  List<Map<String, dynamic>> _locationData = [];
  List<Map<String, dynamic>> _subLocationData = [];
  List<Map<String, dynamic>> _deptData = [];
  List<Map<String, dynamic>> _teamData = [];
  List<Map<String, dynamic>> _roleDataMap = [];
  List<Map<String, dynamic>> _officialDepts = [];
  List<Map<String, dynamic>> _subOfficialDepts = [];

  List<String> locations = [], subLocations = [], departments = [], teams = [], cellGroups = [];
  List<String> dynamicRoles = [];

  // Categories
  final List<String> accountTypeOptions = ["Worker", "Saint"];
  final List<String> unitCategoryOptions = ["Church Worker", "Location Worker"];

  String? selectedAccountType = "Worker";
  String selectedUnitCategory = "Location Worker";
  String? selectedChurchRole;
  String? selectedSecondaryRole; // optional second role in the unit (gives that role's duties too)
  String? selectedLocation;
  String? selectedSubLocation;
  String? selectedDept;
  String? selectedTeam;
  String? selectedCell;

  // 24 Department selection when Unit Category == "Church Worker"
  String? selectedOfficialDeptId;
  String? selectedOfficialDeptName;
  String? selectedOfficialDeptCode;
  String? selectedSubOfficialDeptId;
  String? selectedSubOfficialDeptName;
  String? selectedSubOfficialDeptCode;

  // Korean Worker Portfolio selection (ids stored as strings)
  final Set<String> _selectedPortfolioDeptIds = {};

  bool _isDualTeamSecretary = false;
  bool _isLoading = true; // initial data load
  bool _isSubmitting = false; // registration in progress

  bool get _isChurchWorker =>
      selectedAccountType == "Worker" && selectedUnitCategory == "Church Worker";

  bool get _isKoreanWorkerRole {
    final key = _convertRole(selectedChurchRole);
    return key.startsWith('church_') || key.startsWith('korean_worker_') || key.contains('korean');
  }

  bool get _isTeamLeaderRole {
    final key = _convertRole(selectedChurchRole);
    return key == 'team_leader' || key == 'assistant_team_leader';
  }

  bool get _isTheologyLocationDept {
    final dept = (selectedDept ?? '').trim().toLowerCase();
    return dept.contains('신학') || dept.contains('theology');
  }

  bool get _isPrefilledMember => widget.memberData != null;

  /// Text shown inside the role dropdown. An empty dropdown is drawn greyed-out
  /// by Flutter, which looked like a bug; now it says why it is empty.
  String get _roleHint {
    if (dynamicRoles.isNotEmpty) return 'Select role';
    if (_isChurchWorker && selectedOfficialDeptId == null) return 'Select a department first';
    return 'No roles available';
  }

  // The account already signed in on this device (if any). Creating the new
  // account signs Supabase in as it, so we switch back to this one afterwards
  // instead of leaving the device signed out.
  String? _previousUserId;

  @override
  void initState() {
    super.initState();
    if (widget.signUpMethod != 'google') _previousUserId = _supabase.auth.currentUser?.id;
    _prefillInitialData();
    _fetchInitialData();
  }

  /// Puts the device back on the account that was signed in before. Returns
  /// true when that account is active again.
  Future<bool> _returnToPreviousAccount() async {
    final prev = _previousUserId;
    if (prev == null) return false;
    if (_supabase.auth.currentUser?.id == prev) return true;
    return DeviceAccounts.restore(prev);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _userController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ==========================================
  // SMALL HELPERS
  // ==========================================
  String _str(dynamic v) => v?.toString().trim() ?? '';

  /// Member records may store several numbers (list or "a, b"); take the first.
  String _firstPhone(dynamic v) {
    if (v == null) return '';
    if (v is List) return v.isEmpty ? '' : v.first.toString().trim();
    var s = v.toString().trim();
    if (s.startsWith('[') && s.endsWith(']')) s = s.substring(1, s.length - 1);
    return s.split(RegExp(r'[,;]')).first.trim();
  }

  String _cleanPhone(String s) => s.replaceAll(RegExp(r'[\s\-().]'), '');

  bool _validPhone(String p, {required bool e164}) {
    if (e164) return RegExp(r'^\+\d{8,15}$').hasMatch(p);
    return RegExp(r'^\+?\d{7,15}$').hasMatch(p);
  }

  bool _isTopLevel(Map<String, dynamic> d) {
    final p = d['parent_id'];
    return p == null || p == '' || p == 0 || p == 'null';
  }

  /// Returns the existing entry matching [value] (case-insensitive), or adds it.
  String _matchOrAdd(List<String> list, String value) {
    final v = value.trim();
    final match = list.firstWhere((e) => e.toLowerCase().trim() == v.toLowerCase(), orElse: () => '');
    if (match.isNotEmpty) return match;
    list.add(v);
    return v;
  }

  String _normText(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  /// Finds the first department in [pool] whose code / name / English or Korean
  /// name equals one of the [candidates] (case, spaces and punctuation ignored).
  Map<String, dynamic> _findOfficialDeptByText(List<dynamic> candidates, List<Map<String, dynamic>> pool) {
    for (final c in candidates) {
      final t = _normText(_str(c));
      if (t.isEmpty) continue;
      for (final d in pool) {
        for (final k in const ['code', 'name', 'name_en', 'name_ko']) {
          if (_normText(_str(d[k])) == t) return d;
        }
      }
    }
    return {};
  }

  void _prefillInitialData() {
    _nameController.text =
        widget.initialFullName ?? widget.memberData?['english_name']?.toString() ?? widget.memberData?['korean_name']?.toString() ?? '';

    _idController.text = widget.initialScjId ?? widget.memberData?['scj_id']?.toString() ?? '';

    _emailController.text = widget.initialEmail ?? widget.memberData?['email_address']?.toString() ?? '';

    _phoneController.text = _firstPhone(widget.initialPhone ?? widget.memberData?['phone_numbers']);

    _passwordController.text = widget.initialPassword ?? '';
    _confirmPasswordController.text = widget.initialPassword ?? '';
  }

  Future<void> _fetchInitialData() async {
    try {
      await Future.wait([
        _fetchLocations(),
        _fetchRoles(),
        _fetchOfficialDepartments(),
      ]);

      if (widget.memberData != null && mounted) {
        await _autoSelectMemberUnits(widget.memberData!);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _autoSelectMemberUnits(Map<String, dynamic> data) async {
    try {
      final duty = _str(data['duty']).toLowerCase();
      selectedAccountType = (duty.contains('saint') || duty.contains('성도') || duty.isEmpty) ? "Saint" : "Worker";

      final loc = _str(data['location']);
      final isChurchLevel = loc.toLowerCase() == 'church' || loc == '교회';
      selectedUnitCategory = isChurchLevel ? "Church Worker" : "Location Worker";

      // Church-level members have no location chain; skipping it also stops
      // "Church" from being added to the location list.
      if (!isChurchLevel && loc.isNotEmpty) {
        selectedLocation = _matchOrAdd(locations, loc);
        await _fetchSubLocations(selectedLocation!, preserveSelection: true);

        final subLoc = _str(data['sub_location']);
        if (subLoc.isNotEmpty) {
          selectedSubLocation = _matchOrAdd(subLocations, subLoc);
          await _fetchDepartments(selectedSubLocation!, preserveSelection: true);

          final dept = _str(data['department']);
          if (dept.isNotEmpty) {
            selectedDept = _matchOrAdd(departments, dept);
            await _fetchTeams(selectedDept!, preserveSelection: true);

            final team = _str(data['team']);
            if (team.isNotEmpty) {
              selectedTeam = _matchOrAdd(teams, team);
              await _fetchCellGroups(selectedTeam!, preserveSelection: true);

              final cell = _str(data['cell_group']);
              if (cell.isNotEmpty) selectedCell = _matchOrAdd(cellGroups, cell);
            }
          }
        }
      }

      // Auto-select the official (24) department: first by id, then (church-level
      // members only) by matching the member's department text against the
      // department code / name / English / Korean name.
      Map<String, dynamic> deptMatch = {};
      if (data['official_dept_id'] != null) {
        final offId = data['official_dept_id'].toString();
        deptMatch = _officialDepts.firstWhere((d) => d['id']?.toString() == offId, orElse: () => {});
      }
      if (deptMatch.isEmpty && isChurchLevel) {
        deptMatch = _findOfficialDeptByText(
          [data['official_department'], data['department']],
          _officialDepts.where(_isTopLevel).toList(),
        );
      }

      if (deptMatch.isNotEmpty) {
        final offId = deptMatch['id'].toString();
        selectedOfficialDeptId = offId;
        selectedOfficialDeptName = (deptMatch['name_en'] ?? deptMatch['name'] ?? deptMatch['name_ko'])?.toString();
        selectedOfficialDeptCode = deptMatch['code']?.toString();
        _subOfficialDepts = _officialDepts.where((d) => d['parent_id']?.toString() == offId).toList();

        // Sub-department: by id, else by text among this department's children.
        Map<String, dynamic> subMatch = {};
        if (data['sub_dept_id'] != null) {
          final subId = data['sub_dept_id'].toString();
          subMatch = _subOfficialDepts.firstWhere((d) => d['id']?.toString() == subId, orElse: () => {});
        }
        if (subMatch.isEmpty && _subOfficialDepts.isNotEmpty) {
          subMatch = _findOfficialDeptByText(
            [data['sub_department'], data['sub_location'], data['team']],
            _subOfficialDepts,
          );
        }
        if (subMatch.isNotEmpty) {
          selectedSubOfficialDeptId = subMatch['id'].toString();
          selectedSubOfficialDeptName = (subMatch['name_en'] ?? subMatch['name'] ?? subMatch['name_ko'])?.toString();
          selectedSubOfficialDeptCode = subMatch['code']?.toString();
        }
      }
      debugPrint("Auto-fill dept: id=$selectedOfficialDeptId code=$selectedOfficialDeptCode sub=$selectedSubOfficialDeptId");

      _recomputeRoles();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Auto-fill units error: $e");
    }
  }

  Future<void> _fetchRoles() async {
    try {
      List<dynamic> data;
      try {
        // Preferred: roles linked to a department by id (app_roles.official_dept_id).
        data = await _supabase
            .from('app_roles')
            .select('role_key, display_name, category, Grouping, official_dept_id');
      } catch (_) {
        // That column doesn't exist (yet): use the original select + name matching.
        data = await _supabase.from('app_roles').select('role_key, display_name, category, Grouping');
      }
      if (!mounted) return;
      setState(() {
        _roleDataMap = List<Map<String, dynamic>>.from(data);
        _recomputeRoles();
      });
      debugPrint("Roles loaded: ${_roleDataMap.length}");
    } catch (e) {
      debugPrint("Role Fetch Error: $e");
    }
  }

  Future<void> _fetchOfficialDepartments() async {
    try {
      final data = await _supabase
          .from('official_departments')
          .select('id, name, name_ko, name_en, code, parent_id')
          .order('name');

      if (!mounted) return;
      setState(() {
        _officialDepts = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint("Official Dept Error: $e");
    }
  }

  // ==========================================
  // DYNAMIC ROLE MATCHING ENGINE
  // (logic unchanged; it no longer calls setState itself, so callers wrap it
  //  in their own setState instead of nesting setState calls)
  // ==========================================
// ==========================================
  // DYNAMIC ROLE MATCHING ENGINE
  // ==========================================

  bool _churchRoleMatches(Map<String, dynamic> r) {
    if (r['category'] != 'Worker') return false;

    final roleKey = (r['role_key'] ?? '').toString().toLowerCase();
    final roleGrouping = (r['Grouping'] ?? r['grouping'] ?? '').toString().trim();
    final roleOfficialDeptId = r['official_dept_id']?.toString();

    // If no department is selected yet, show church administrative roles
    if (selectedOfficialDeptId == null) {
      return roleGrouping == 'Church Main';
    }

    final effectiveDeptId = selectedSubOfficialDeptId ?? selectedOfficialDeptId;
    final effectiveDeptName = (selectedSubOfficialDeptName ?? selectedOfficialDeptName ?? '').toLowerCase();

    // 1. MATCH BY DIRECT official_dept_id IF AVAILABLE
    if (roleOfficialDeptId != null && roleOfficialDeptId.isNotEmpty) {
      return roleOfficialDeptId == effectiveDeptId;
    }

    // 2. SUB-GROUPS UNDER INTERNAL AFFAIRS (장년회, 부녀회, 청년회, 새신자, MOU)
    if (effectiveDeptId == '03100bbc-6897-4538-8533-c9f36fe74f41' || 
        effectiveDeptName.contains('장년') || effectiveDeptName.contains("men")) {
      return roleGrouping == '24-Dept MG' || roleKey.startsWith('mg_group_');
    }

    if (effectiveDeptId == 'fd7bc250-72b6-449b-b0eb-348483261c17' || 
        effectiveDeptName.contains('부녀') || effectiveDeptName.contains("women")) {
      return roleGrouping == '24-Dept WG' || roleKey.startsWith('wg_group_');
    }

    if (effectiveDeptId == '5c8a3f12-7e44-4829-9b93-8a123456789a' ||
        effectiveDeptName.contains('청년') || effectiveDeptName.contains('youth')) {
      return roleGrouping == '24-Dept YAG' || roleKey.startsWith('yag_group_');
    }

    if (effectiveDeptId == 'ccf31d7c-119d-4cba-82e0-b47540489d64' || 
        effectiveDeptName.contains('새신자') || effectiveDeptName.contains("new saint")) {
      return roleGrouping == '24-Dept New Saints' || roleKey.startsWith('new_saints_');
    }

    if (effectiveDeptId == '65d7451d-83d8-459d-81b8-b73fea7636cb' || 
        effectiveDeptName.contains('mou')) {
      return roleGrouping == '24-Dept MOU' || roleKey.startsWith('mou_dept_');
    }

    // 3. INTERNAL AFFAIRS MAIN (내무부) - When no sub-group is chosen
    if (effectiveDeptName.contains('내무') || effectiveDeptName.contains('internal')) {
      final isGroup = roleGrouping.contains('MG') ||
                      roleGrouping.contains('WG') ||
                      roleGrouping.contains('YAG') ||
                      roleGrouping.contains('New Saints') ||
                      roleGrouping.contains('MOU') ||
                      roleKey.startsWith('mg_') ||
                      roleKey.startsWith('wg_') ||
                      roleKey.startsWith('yag_') ||
                      roleKey.startsWith('new_saints_') ||
                      roleKey.startsWith('mou_');
      if (isGroup) return false;

      return roleGrouping.startsWith('24-Dept 3') || 
             roleKey.startsWith('internal_affairs_') || 
             roleKey.startsWith('ia_mgr_');
    }

    return false;
  }

  bool _locationRoleMatches(Map<String, dynamic> r) {
    final isWorker = r['category'] == 'Worker';
    final grouping = (r['Grouping'] ?? r['grouping'] ?? '').toString();
    final roleKey = r['role_key'].toString().toLowerCase();

    if (r['official_dept_id'] != null && r['official_dept_id'].toString().isNotEmpty) return false;

    final isChurchScope = grouping.startsWith('24-Dept') ||
        grouping == 'Church Main' ||
        roleKey.startsWith('church_') ||
        roleKey.startsWith('korean_');
    if (!isWorker || isChurchScope) return false;

    if (_isTheologyLocationDept) {
      return roleKey.startsWith('theo_') ||
          roleKey.contains('instructor') ||
          roleKey.contains('evangelist') ||
          roleKey.contains('helper');
    } else {
      if (roleKey.startsWith('theo_')) return false;
    }
    return true;
  }

  /// Recomputes [dynamicRoles]. Call inside a setState (or right before one).
  void _recomputeRoles() {
    if (selectedAccountType == null) return;

    if (selectedAccountType == "Saint") {
      dynamicRoles = _roleDataMap
          .where((r) => r['category'] == 'Saint')
          .map((e) => e['display_name'].toString())
          .toSet()
          .toList();
    } else if (_isChurchWorker) {
      dynamicRoles = _roleDataMap.where(_churchRoleMatches).map((e) => e['display_name'].toString()).toSet().toList();
    } else {
      dynamicRoles = _roleDataMap.where(_locationRoleMatches).map((e) => e['display_name'].toString()).toSet().toList();
    }

    if (!dynamicRoles.contains(selectedChurchRole)) selectedChurchRole = null;
    if (!dynamicRoles.contains(selectedSecondaryRole) || selectedSecondaryRole == selectedChurchRole) selectedSecondaryRole = null;
    _isDualTeamSecretary = false;
    debugPrint("Roles: total ${_roleDataMap.length}, shown ${dynamicRoles.length} "
        "(type=$selectedAccountType, dept=${selectedOfficialDeptCode ?? '-'})");
  }

  // ==========================================
  // CASCADING UNIT DATA
  // ==========================================
  Future<void> _fetchLocations() async {
    try {
      final data = await _supabase.from('locations').select('id, location');
      if (!mounted) return;
      setState(() {
        _locationData = List<Map<String, dynamic>>.from(data);
        locations = _locationData
            .map((e) => e['location'].toString())
            .where((loc) => loc.trim().toLowerCase() != 'church')
            .toList();
      });
    } catch (e) {
      debugPrint("Loc Error: $e");
    }
  }

  Future<void> _fetchSubLocations(String locName, {bool preserveSelection = false}) async {
    try {
      final loc = _locationData.firstWhere(
        (e) => e['location'].toString().toLowerCase().trim() == locName.toLowerCase().trim(),
        orElse: () => {},
      );
      if (loc.isEmpty) return;
      final data = await _supabase.from('sub_locations').select('id, name').eq('location_id', loc['id']);
      if (!mounted) return;
      setState(() {
        _subLocationData = List<Map<String, dynamic>>.from(data);
        subLocations = _subLocationData.map((e) => e['name'].toString()).toList();
        if (!preserveSelection) {
          selectedSubLocation = null;
          departments = [];
          teams = [];
          cellGroups = [];
        }
      });
    } catch (e) {
      debugPrint("Sub-loc Error: $e");
    }
  }

  Future<void> _fetchDepartments(String subName, {bool preserveSelection = false}) async {
    try {
      final sub = _subLocationData.firstWhere(
        (e) => e['name'].toString().toLowerCase().trim() == subName.toLowerCase().trim(),
        orElse: () => {},
      );
      if (sub.isEmpty) return;
      final data = await _supabase.from('departments').select('id, name').eq('sub_location_id', sub['id']);
      if (!mounted) return;
      setState(() {
        _deptData = List<Map<String, dynamic>>.from(data);
        departments = _deptData.map((e) => e['name'].toString()).toList();
        if (!preserveSelection) {
          selectedDept = null;
          teams = [];
          cellGroups = [];
        }
      });
    } catch (e) {
      debugPrint("Dept Error: $e");
    }
  }

  Future<void> _fetchTeams(String deptName, {bool preserveSelection = false}) async {
    try {
      final dept = _deptData.firstWhere(
        (e) => e['name'].toString().toLowerCase().trim() == deptName.toLowerCase().trim(),
        orElse: () => {},
      );
      if (dept.isEmpty) return;
      final data = await _supabase.from('teams').select('id, name').eq('dept_id', dept['id']);
      if (!mounted) return;
      setState(() {
        _teamData = List<Map<String, dynamic>>.from(data);
        teams = _teamData.map((e) => e['name'].toString()).toList();
        if (!preserveSelection) {
          selectedTeam = null;
          cellGroups = [];
        }
      });
    } catch (e) {
      debugPrint("Team Error: $e");
    }
  }

  Future<void> _fetchCellGroups(String teamName, {bool preserveSelection = false}) async {
    try {
      final team = _teamData.firstWhere(
        (e) => e['name'].toString().toLowerCase().trim() == teamName.toLowerCase().trim(),
        orElse: () => {},
      );
      if (team.isEmpty) return;
      final data = await _supabase.from('cell_groups').select('name').eq('team_id', team['id']);
      if (!mounted) return;
      setState(() {
        cellGroups = List<String>.from(data.map((e) => e['name'].toString()));
        if (!preserveSelection) selectedCell = null;
      });
    } catch (e) {
      debugPrint("Cell Error: $e");
    }
  }

  // Changing a level now clears everything below it immediately, so a failed
  // or slow fetch can no longer leave (and save) a stale sub-location, team or
  // cell group from the previous choice.
  void _onLocationChanged(String? v) {
    setState(() {
      selectedLocation = v;
      selectedSubLocation = null;
      selectedDept = null;
      selectedTeam = null;
      selectedCell = null;
      subLocations = [];
      departments = [];
      teams = [];
      cellGroups = [];
      _recomputeRoles();
    });
    if (v != null) _fetchSubLocations(v);
  }

  void _onSubLocationChanged(String? v) {
    setState(() {
      selectedSubLocation = v;
      selectedDept = null;
      selectedTeam = null;
      selectedCell = null;
      departments = [];
      teams = [];
      cellGroups = [];
      _recomputeRoles();
    });
    if (v != null) _fetchDepartments(v);
  }

  void _onDeptChanged(String? v) {
    setState(() {
      selectedDept = v;
      selectedTeam = null;
      selectedCell = null;
      teams = [];
      cellGroups = [];
      _recomputeRoles();
    });
    if (v != null) _fetchTeams(v);
  }

  void _onTeamChanged(String? v) {
    setState(() {
      selectedTeam = v;
      selectedCell = null;
      cellGroups = [];
    });
    if (v != null) _fetchCellGroups(v);
  }

  String _convertRole(String? displayName) {
    if (displayName == null) return 'member';
    final match = _roleDataMap.firstWhere(
      (element) => element['display_name'] == displayName,
      orElse: () => {'role_key': 'member'},
    );
    return match['role_key'].toString();
  }

  // ==========================================
  // VALIDATION
  // ==========================================
  String? _validateSelections() {
    if (dynamicRoles.isNotEmpty && selectedChurchRole == null) {
      return "Please select your assigned role.";
    }

    if (_isChurchWorker) {
      if (selectedOfficialDeptId == null) return "Please select your 24 Department.";
      if (_isKoreanWorkerRole) {
        final n = _selectedPortfolioDeptIds.length;
        if (n < _minPortfolio || n > _maxPortfolio) {
          return "Please select $_minPortfolio–$_maxPortfolio overseeing departments (selected: $n).";
        }
      }
    } else if (!_isPrefilledMember) {
      if (selectedLocation == null || selectedSubLocation == null || selectedDept == null) {
        return "Please select your location, sub-location and department.";
      }
    }
    return null;
  }

  // ==========================================
  // AUTH USER CREATION (with recovery)
  // ==========================================
  bool _looksLikeExistingUser(AuthException e) {
    final m = e.message.toLowerCase();
    return m.contains('already registered') || m.contains('already exists') || m.contains('already been registered');
  }

  /// Returns the user id to attach the profile to.
  /// - google: the current session
  /// - email/whatsapp: sign up; if the account already exists (e.g. a previous
  ///   attempt created it but the profile save failed) sign in instead so the
  ///   registration can be finished rather than getting stuck.
  Future<String> _createAuthUser({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final method = widget.signUpMethod;

    if (method == 'google') {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        throw const _FriendlyException("Google session expired. Please sign in again.");
      }
      return currentUser.id;
    }

    bool existing = false;
    try {
      final AuthResponse res = method == 'whatsapp'
          ? await _supabase.auth.signUp(phone: phone, password: password, data: {'full_name': name, 'email': email})
          : await _supabase.auth.signUp(email: email, password: password, data: {'full_name': name, 'phone': phone});

      if (res.user != null && res.session != null) return res.user!.id;

      // User returned with an empty identities list = this contact is taken.
      if (res.user != null && (res.user!.identities?.isEmpty ?? false)) {
        existing = true;
      } else if (res.user != null) {
        // Created, but the project requires confirmation before a session exists.
        throw _FriendlyException(
          method == 'whatsapp'
              ? "Your account was created but your WhatsApp number must be confirmed first. Confirm it, then sign in to finish registration."
              : "Your account was created but your email must be confirmed first. Check your inbox, confirm it, then sign in to finish registration.",
        );
      } else {
        throw const _FriendlyException("Sign-up failed. Please try again.");
      }
    } on AuthException catch (e) {
      if (!_looksLikeExistingUser(e)) rethrow;
      existing = true;
    }

    if (existing) {
      try {
        final AuthResponse res = method == 'whatsapp'
            ? await _supabase.auth.signInWithPassword(phone: phone, password: password)
            : await _supabase.auth.signInWithPassword(email: email, password: password);
        if (res.user != null) return res.user!.id;
      } on AuthException {
        // fall through to the friendly message below
      }
      throw const _FriendlyException(
        "An account with these contact details already exists. Please go back and sign in instead.",
      );
    }
    throw const _FriendlyException("Sign-up failed. Please try again.");
  }

  /// Stops a finished/pending registration from being overwritten (the upsert
  /// below would otherwise reset an approved account back to pending).
  Future<void> _ensureNoExistingProfile(String uid) async {
    final existing = await _supabase
        .from('profiles')
        .select('scj_id, is_approved, approval_status')
        .eq('id', uid)
        .maybeSingle();
    if (existing == null) return;

    final hasId = _str(existing['scj_id']).isNotEmpty;
    if (!hasId) return; // half-created row: safe to complete

    final status = _str(existing['approval_status']).toLowerCase();
    final approved = existing['is_approved'] == true || status == 'approved';
    throw _FriendlyException(
      approved
          ? "This account is already registered and approved. Please sign in."
          : "This account is already registered and awaiting approval.",
    );
  }

  String _friendlyError(Object e) {
    if (e is _FriendlyException) return e.message;
    if (e is AuthException) return e.message;
    if (e is PostgrestException) {
      debugPrint("Postgrest error ${e.code}: ${e.message}");
      if (e.code == '23505') return "An account with this SCJ ID or username already exists.";
      if (e.code == '42501') {
        return "You don't have permission to submit this registration. Please contact Church Administration.";
      }
      return "Couldn't save your registration. Please try again.";
    }
    debugPrint("Registration error: $e");
    return "Something went wrong. Check your connection and try again.";
  }

  // ==========================================
  // CONFIRM & SUBMIT ACCOUNT FOR APPROVAL
  // ==========================================
  Future<void> _saveAccount() async {
    if (_isSubmitting || _isLoading) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _cleanPhone(_phoneController.text);
    final username = _userController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty || selectedAccountType == null) {
      _showSnack("Please fill in your name and select an account type.");
      return;
    }
    // Previously nothing checked this, so an empty SCJ ID was saved as ''.
    if (_idController.text.trim().isEmpty) {
      _showSnack("Please enter your SCJ ID.");
      return;
    }
    if (email.isEmpty) {
      _showSnack("Please enter your email address.");
      return;
    }
    if (!_emailRe.hasMatch(email)) {
      _showSnack("Please enter a valid email address.");
      return;
    }
    if (phone.isEmpty) {
      _showSnack("Please enter your WhatsApp phone number.");
      return;
    }
    if (!_validPhone(phone, e164: widget.signUpMethod == 'whatsapp')) {
      _showSnack(widget.signUpMethod == 'whatsapp'
          ? "Phone must include the country code, e.g. +256772123456."
          : "Please enter a valid phone number.");
      return;
    }
    if (username.isNotEmpty && !_usernameRe.hasMatch(username)) {
      _showSnack("User name must be 3–30 characters: letters, numbers, dot or underscore.");
      return;
    }

    if (widget.signUpMethod != 'google') {
      if (password.isEmpty) {
        _showSnack("Please enter a password.");
        return;
      }
      if (password != confirmPassword) {
        _showSnack("Passwords do not match.");
        return;
      }
      if (password.length < 6) {
        _showSnack("Password must be at least 6 characters.");
        return;
      }
    }

    final selectionError = _validateSelections();
    if (selectionError != null) {
      _showSnack(selectionError);
      return;
    }

    setState(() => _isSubmitting = true);
    // Keep the current user's screens in place while the new account is created
    if (_previousUserId != null) RegistrationGuard.hold();
    try {
      final uid = await _createAuthUser(name: name, email: email, phone: phone, password: password);
      await _ensureNoExistingProfile(uid);

      if (!mounted) return;

      final primaryRoleKey = _convertRole(selectedChurchRole);
      final String? secondaryRoleKey = selectedSecondaryRole != null
          ? _convertRole(selectedSecondaryRole)
          : ((_isTeamLeaderRole && _isDualTeamSecretary) ? 'team_sec' : null);

      String locStr;
      String? subLocStr;
      String deptStr;
      String? teamStr;
      String? cellStr;
      String unitCategoryStr;

      if (selectedAccountType == "Saint") {
        unitCategoryStr = "Saint";
        locStr = selectedLocation ?? widget.memberData?['location'] ?? "N/A";
        subLocStr = selectedSubLocation ?? widget.memberData?['sub_location'] ?? "N/A";
        deptStr = selectedDept ?? widget.memberData?['department'] ?? "N/A";
        teamStr = selectedTeam ?? widget.memberData?['team'] ?? "N/A";
        cellStr = selectedCell ?? widget.memberData?['cell_group'] ?? "N/A";
      } else if (_isChurchWorker) {
        unitCategoryStr = "Church Worker";
        locStr = "Church";
        // Keep the department exactly as in the members table (e.g. 내무부). The
        // group (Men's Group, New Saints...) is stored separately in sub_dept_id.
        final memberDept = _str(widget.memberData?['department']);
        deptStr = memberDept.isNotEmpty
            ? memberDept
            : (selectedOfficialDeptName ?? (selectedChurchRole ?? "24 Department"));
        subLocStr = null;
        teamStr = null;
        cellStr = null;
      } else {
        unitCategoryStr = "Location Worker";
        locStr = selectedLocation ?? widget.memberData?['location'] ?? "N/A";
        subLocStr = selectedSubLocation ?? widget.memberData?['sub_location'] ?? "N/A";
        deptStr = selectedDept ?? widget.memberData?['department'] ?? "N/A";
        teamStr = selectedTeam ?? widget.memberData?['team'] ?? "N/A";
        cellStr = selectedCell ?? widget.memberData?['cell_group'] ?? "N/A";
      }

      String finalDepartment = deptStr;

       // If user selected Internal Affairs or any of its sub-groups:
       if (_isChurchWorker && (
       selectedOfficialDeptName?.contains('내무') == true ||
       selectedSubOfficialDeptName?.contains('장년') == true ||
       selectedSubOfficialDeptName?.contains('부녀') == true ||
       selectedSubOfficialDeptName?.contains('청년') == true ||
       selectedSubOfficialDeptName?.contains('새신자') == true ||
       selectedSubOfficialDeptName?.contains('mou') == true)) {
       finalDepartment = '내무부'; // Preserved in profiles table!
      }

       await _supabase.from('profiles').upsert({
       'id': uid,
       'account_type': selectedAccountType,
       'unit_category': unitCategoryStr,
       'role': primaryRoleKey,
       'secondary_role': secondaryRoleKey,
       'official_dept_id': _isChurchWorker ? selectedOfficialDeptId : null,
       'sub_dept_id': _isChurchWorker ? selectedSubOfficialDeptId : null,
       'location': locStr,
       'sub_location': subLocStr,
       'department': finalDepartment, // Stays '내무부'
       'team': teamStr,
       'cell_group': cellStr,
       'full_name': name,
       'scj_id': _idController.text.trim(),
       'phone': phone,
       'email': email,
       'is_approved': false,
       'approval_status': 'pending',
     });

      // The portfolio is secondary: if it fails, the registration itself is
      // already saved, so warn instead of failing (a retry would be blocked
      // by the "already registered" check).
      bool portfolioSaved = true;
      if (_isChurchWorker && _isKoreanWorkerRole && _selectedPortfolioDeptIds.isNotEmpty) {
        try {
          final rows = _selectedPortfolioDeptIds
              .map((dId) => {
                    'user_id': uid,
                    'executive_title': selectedChurchRole ?? "Korean Worker",
                    'official_dept_id': dId,
                  })
              .toList();

          await _supabase.from('korean_worker_portfolios').delete().eq('user_id', uid);
          await _supabase.from('korean_worker_portfolios').insert(rows);
        } catch (e) {
          debugPrint("Portfolio save error: $e");
          portfolioSaved = false;
        }
      }

      // Back to the account that was using this device, or signed out if none
      final backToPrevious = await _returnToPreviousAccount();
      RegistrationGuard.release();
      if (!backToPrevious) await _supabase.auth.signOut();

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.hourglass_top_rounded, color: AppPalette.fg(Colors.orange), size: 28),
              const SizedBox(width: 8),
              Text("Pending Approval", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text(
            "Your registration has been submitted successfully.\n\nYour account is now pending review and approval by Church Administration. Once approved, you will be notified via email ($email)."
            "${backToPrevious ? '\n\nThis device is still signed in with the account you were using. Once the new account is approved, switch to it from the account menu.' : ''}"
            "${portfolioSaved ? '' : '\n\nNote: your overseeing departments could not be saved. Please let Church Administration know.'}",
            style: GoogleFonts.merriweather(fontSize: 13, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(const Color(0xFF4A148C))),
              child: Text("OK", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      // If sign-up already switched the device to the new account, switch back
      await _returnToPreviousAccount();
      RegistrationGuard.release();
      _showSnack(_friendlyError(e));
    } finally {
      RegistrationGuard.release();
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.merriweather())),
    );
  }

  // ==========================================
  // BUILD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 900;
    const pPurple = Color(0xFF4A148C);
    final isGoogleSignUp = widget.signUpMethod == 'google';
    final isEmailSignUp = widget.signUpMethod == 'email';
    final busy = _isLoading || _isSubmitting;

    return PopScope(
      // Don't allow backing out mid-submit (that left half-created accounts).
      canPop: !_isSubmitting,
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white),
          elevation: 0.5,
          centerTitle: true,
          title: Text(
            "Complete Registration Details",
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w900,
              color: AppPalette.fg(pPurple),
              fontSize: isDesktop ? 20 : 17,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? width * 0.15 : 12, vertical: 14),
          child: Column(children: [
            // CARD 1: Unit Assignment
            _buildCard("1. Unit Assignment", [
              if (_isPrefilledMember) ...[
                _lockedInfoRow("Account Category", selectedAccountType ?? "Worker"),
                _lockedInfoRow("Unit Category", selectedUnitCategory),
              ] else ...[
                _sideBySideDropdown("Account Category", accountTypeOptions, selectedAccountType, (v) {
                  setState(() {
                    selectedAccountType = v;
                    _recomputeRoles();
                  });
                }),
                if (selectedAccountType == "Worker")
                  _sideBySideDropdown("Unit Category", unitCategoryOptions, selectedUnitCategory, (v) {
                    if (v != null) {
                      setState(() {
                        selectedUnitCategory = v;
                        selectedLocation = null;
                        selectedSubLocation = null;
                        selectedDept = null;
                        selectedTeam = null;
                        selectedCell = null;
                        subLocations = [];
                        departments = [];
                        teams = [];
                        cellGroups = [];
                        selectedOfficialDeptId = null;
                        selectedOfficialDeptName = null;
                        selectedOfficialDeptCode = null;
                        selectedSubOfficialDeptId = null;
                        selectedSubOfficialDeptName = null;
                        selectedSubOfficialDeptCode = null;
                        _subOfficialDepts = []; // was left stale before
                        _recomputeRoles();
                      });
                    }
                  }),
              ],
              if (_isChurchWorker) ...[
                _lockedInfoRow("Location", "Church (Auto-assigned)"),
                if (_isPrefilledMember && selectedOfficialDeptName != null) ...[
                  _lockedInfoRow("24 Department", selectedOfficialDeptName!),
                ] else ...[
                  _sideBySideOfficialDeptDropdown(
                    "24 Department",
                    _officialDepts.where(_isTopLevel).toList(),
                    selectedOfficialDeptId,
                    (val) {
                      setState(() {
                        selectedOfficialDeptId = val;
                        final match = _officialDepts.firstWhere(
                          (d) => d['id']?.toString() == val,
                          orElse: () => {},
                        );
                        selectedOfficialDeptName = (match['name_en'] ?? match['name'] ?? match['name_ko'])?.toString();
                        selectedOfficialDeptCode = match['code']?.toString();

                        _subOfficialDepts = _officialDepts.where((d) => d['parent_id']?.toString() == val).toList();
                        selectedSubOfficialDeptId = null;
                        selectedSubOfficialDeptName = null;
                        selectedSubOfficialDeptCode = null;
                        _recomputeRoles();
                      });
                    },
                  ),
                ],
                if (_subOfficialDepts.isNotEmpty)
                  _sideBySideOfficialDeptDropdown(
                    "Group / Sub-Dept",
                    _subOfficialDepts,
                    selectedSubOfficialDeptId,
                    (val) {
                      // '' = "None": stay in the main department itself.
                      final id = (val == null || val.isEmpty) ? null : val;
                      setState(() {
                        selectedSubOfficialDeptId = id;
                        final match = id == null
                            ? <String, dynamic>{}
                            : _subOfficialDepts.firstWhere(
                                (d) => d['id']?.toString() == id,
                                orElse: () => {},
                              );
                        selectedSubOfficialDeptName =
                            id == null ? null : (match['name_en'] ?? match['name'] ?? match['name_ko'])?.toString();
                        selectedSubOfficialDeptCode = id == null ? null : match['code']?.toString();
                        _recomputeRoles();
                      });
                    },
                    allowNone: true,
                    hint: "Optional: select group",
                  ),
              ] else if (_isPrefilledMember) ...[
                // Locked pre-filled units for Location members
                _lockedInfoRow("Location", selectedLocation ?? widget.memberData?['location'] ?? "N/A"),
                _lockedInfoRow("Sub-Location", selectedSubLocation ?? widget.memberData?['sub_location'] ?? "N/A"),
                _lockedInfoRow("Department", selectedDept ?? widget.memberData?['department'] ?? "N/A"),
                _lockedInfoRow("Team Number", selectedTeam ?? widget.memberData?['team'] ?? "N/A"),
                _lockedInfoRow("Cell Group", selectedCell ?? widget.memberData?['cell_group'] ?? "N/A"),
              ] else ...[
                _sideBySideDropdown("Location", locations, selectedLocation, _onLocationChanged),
                _sideBySideDropdown("Sub-Location", subLocations, selectedSubLocation, _onSubLocationChanged),
                _sideBySideDropdown("Department", departments, selectedDept, _onDeptChanged),
                _sideBySideDropdown("Team Number", teams, selectedTeam, _onTeamChanged),
                _sideBySideDropdown("Cell Group", cellGroups, selectedCell, (v) {
                  setState(() => selectedCell = v);
                }),
              ],
            ], pPurple),

            const SizedBox(height: 10),

            // CARD 2: Identity & Role Details
            _buildCard("2. Identity & Role Details", [
              _sideBySideDropdown("Assigned Role", dynamicRoles, selectedChurchRole, (v) {
                setState(() {
                  selectedChurchRole = v;
                  if (!_isTeamLeaderRole) _isDualTeamSecretary = false;
                  if (selectedSecondaryRole == v) selectedSecondaryRole = null;
                });
              }, hint: _roleHint),

              // Optional second role in the same unit; its duties are added to the
              // primary role's (Reports screen shows both sets of duties).
              if (selectedAccountType != "Saint" && selectedChurchRole != null && dynamicRoles.length > 1)
                _sideBySideDropdown(
                  "Secondary Role (optional)",
                  ["None", ...dynamicRoles.where((r) => r != selectedChurchRole)],
                  selectedSecondaryRole ?? "None",
                  (v) => setState(() {
                    selectedSecondaryRole = (v == null || v == "None") ? null : v;
                    if (selectedSecondaryRole != null) _isDualTeamSecretary = false;
                  }),
                ),

              if (!_isChurchWorker && _isTeamLeaderRole && selectedSecondaryRole == null)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppPalette.line(Colors.grey.withValues(alpha: 0.15))))),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          "Also assign Team Secretary (Dual Role)?",
                          style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 12, color: AppPalette.fg(Colors.purple[900])),
                        ),
                      ),
                      Switch(
                        value: _isDualTeamSecretary,
                        activeThumbColor: pPurple,
                        onChanged: (val) => setState(() => _isDualTeamSecretary = val),
                      ),
                    ],
                  ),
                ),

              if (_isChurchWorker && _isKoreanWorkerRole)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppPalette.line(Colors.grey.withValues(alpha: 0.15))))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Overseeing Portfolio (Select $_minPortfolio–$_maxPortfolio Departments): ${_selectedPortfolioDeptIds.length}/$_maxPortfolio",
                        style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _officialDepts.where(_isTopLevel).map((dept) {
                          final id = dept['id'].toString();
                          final isChecked = _selectedPortfolioDeptIds.contains(id);
                          return FilterChip(
                            label: Text(
                              dept['name_ko'] != null ? "${dept['name_ko']} (${dept['name_en'] ?? ''})" : (dept['name'] ?? ''),
                              style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                            selected: isChecked,
                            selectedColor: AppPalette.bg(pPurple.withValues(alpha: 0.2)),
                            onSelected: (selected) {
                              if (selected && _selectedPortfolioDeptIds.length >= _maxPortfolio) {
                                _showSnack("You can select at most $_maxPortfolio departments.");
                                return;
                              }
                              setState(() {
                                if (selected) {
                                  _selectedPortfolioDeptIds.add(id);
                                } else {
                                  _selectedPortfolioDeptIds.remove(id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

              if (_isPrefilledMember) ...[
                _lockedInfoRow("Full Names", _nameController.text),
                _lockedInfoRow("SCJ ID", _idController.text),
              ] else ...[
                _sideBySideField("Full Names", _nameController, Icons.person_outline),
                _sideBySideField("SCJ ID", _idController, Icons.badge_outlined),
              ],
              _sideBySideField("User Name", _userController, Icons.alternate_email),

              if (isGoogleSignUp) ...[
                _lockedInfoRow(
                  "Google Email (Verified)",
                  _emailController.text,
                  icon: const FaIcon(FontAwesomeIcons.google, size: 14, color: Color(0xFF4A148C)),
                ),
                _sideBySideField("WhatsApp Phone *", _phoneController, Icons.phone_android_outlined,
                    type: TextInputType.phone),
              ] else if (isEmailSignUp) ...[
                // Not verified yet (Supabase sends the confirmation), so it stays editable
                _sideBySideField("Email Address *", _emailController, Icons.email_outlined,
                    type: TextInputType.emailAddress),
                _sideBySideField("WhatsApp Phone *", _phoneController, Icons.phone_android_outlined,
                    type: TextInputType.phone),
              ] else ...[
                if (_phoneController.text.trim().isNotEmpty)
                  _lockedInfoRow(
                    "WhatsApp Phone",
                    _phoneController.text,
                    icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 14, color: Color(0xFF4A148C)),
                  )
                else
                  _sideBySideField("WhatsApp Phone *", _phoneController, Icons.phone_android_outlined,
                      type: TextInputType.phone),
                _sideBySideField("Email Address *", _emailController, Icons.email_outlined,
                    type: TextInputType.emailAddress),
              ],

              // Passwords with visibility toggles
              if (!isGoogleSignUp) ...[
                _sideBySidePasswordField(
                  "Password",
                  _passwordController,
                  _obscurePassword,
                  () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                _sideBySidePasswordField(
                  "Confirm Password",
                  _confirmPasswordController,
                  _obscureConfirmPassword,
                  () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ],
            ], pPurple),

            const SizedBox(height: 18),

            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    side: BorderSide(color: AppPalette.line(Colors.grey), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("Go back", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: busy ? null : _saveAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.bg(pPurple),
                    minimumSize: const Size(0, 42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            "Submit for Approval",
                            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.white), fontSize: 13.5),
                          ),
                        ),
                ),
              ),
            ]),
            const SizedBox(height: 30),
          ]),
        ),
      ),
    );
  }

  // ==========================================
  // UI HELPERS
  // ==========================================
  Widget _buildCard(String title, List<Widget> children, Color pP) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.line(pP.withValues(alpha: 0.18)), width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.025), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.merriweather(fontSize: 14.5, fontWeight: FontWeight.w900, color: AppPalette.fg(pP))),
        const Divider(height: 14),
        ...children
      ]),
    );
  }

  /// Shared "label on the left, control on the right" row.
  Widget _formRow({required Widget label, required Widget field}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppPalette.line(Colors.grey.withValues(alpha: 0.15))))),
      child: Row(children: [
        Expanded(flex: 2, child: label),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: field),
      ]),
    );
  }

  Widget _labelText(String text, {double size = 13}) => Text(
        text,
        style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: size),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  Widget _pickerBox(Widget child) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppPalette.bg(const Color(0xFFF3E5F5)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppPalette.line(Colors.purple.withValues(alpha: 0.15))),
        ),
        child: child,
      );

  InputDecoration _fieldDecoration(Widget prefix, {Widget? suffix}) => InputDecoration(
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: true,
        fillColor: AppPalette.bg(const Color(0xFFF3E5F5)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        isDense: true,
      );

  Widget _lockedInfoRow(String label, String value, {Widget? icon}) {
    return _formRow(
      label: Row(
        children: [
          if (icon != null) ...[icon, const SizedBox(width: 5)],
          Expanded(child: _labelText(label, size: 12.5)),
        ],
      ),
      field: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.purple.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppPalette.line(Colors.purple.withValues(alpha: 0.2))),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          value.isNotEmpty ? value : "Verified during sign-up",
          style: GoogleFonts.merriweather(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.fg(const Color(0xFF4A148C))),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _sideBySideDropdown(String label, List<String> items, String? val, Function(String?) onCh,
      {String? hint}) {
    // De-duplicated: a repeated name in the data used to crash DropdownButton.
    final unique = items.toSet().toList();
    return _formRow(
      label: _labelText(label),
      field: _pickerBox(
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isDense: true,
            alignment: Alignment.centerLeft,
            hint: hint == null
                ? null
                : Text(hint, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey[600]))),
            key: ValueKey("${label}_$val"),
            value: unique.contains(val) ? val : null,
            isExpanded: true,
            items: unique
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        e,
                        style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: onCh,
          ),
        ),
      ),
    );
  }

  Widget _sideBySideOfficialDeptDropdown(
    String label,
    List<Map<String, dynamic>> items,
    String? val,
    Function(String?) onCh, {
    bool allowNone = false,
    String? hint,
  }) {
    return _formRow(
      label: _labelText(label),
      field: _pickerBox(
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isDense: true,
            alignment: Alignment.centerLeft,
            hint: Text(
              items.isEmpty ? "Loading..." : (hint ?? "Select Department"),
              style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey[600])),
            ),
            value: items.any((e) => e['id']?.toString() == val) ? val : null,
            isExpanded: true,
            items: [
              if (allowNone)
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(
                    "None (main department)",
                    style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black54)),
                  ),
                ),
              ...items.map((e) => DropdownMenuItem<String>(
                    value: e['id']?.toString(),
                    child: Text(
                      e['name_ko'] != null && e['name_en'] != null
                          ? "${e['name_ko']} (${e['name_en']})"
                          : (e['name']?.toString() ?? ''),
                      style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            ],
            onChanged: items.isEmpty ? null : onCh,
          ),
        ),
      ),
    );
  }

  Widget _sideBySideField(String label, TextEditingController ctrl, IconData icon, {TextInputType? type}) {
    return _formRow(
      label: _labelText(label),
      field: SizedBox(
        height: 32,
        child: TextField(
          controller: ctrl,
          keyboardType: type,
          textAlign: TextAlign.start,
          style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold),
          decoration: _fieldDecoration(Icon(icon, size: 16, color: AppPalette.fg(Colors.purple))),
        ),
      ),
    );
  }

  Widget _sideBySidePasswordField(
    String label,
    TextEditingController ctrl,
    bool obscure,
    VoidCallback onToggle,
  ) {
    return _formRow(
      label: _labelText(label),
      field: SizedBox(
        height: 32,
        child: TextField(
          controller: ctrl,
          obscureText: obscure,
          textAlign: TextAlign.start,
          style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold),
          decoration: _fieldDecoration(
            Icon(Icons.lock_outline, size: 16, color: AppPalette.fg(Colors.purple)),
            suffix: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: 16,
                color: AppPalette.fg(Colors.grey[700]),
              ),
              onPressed: onToggle,
              tooltip: obscure ? 'Show password' : 'Hide password',
            ),
          ),
        ),
      ),
    );
  }
}