// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});
  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final _supabase = Supabase.instance.client;

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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

  final List<String> accountTypeOptions = ["Worker", "Saint"];
  
  String? selectedAccountType = "Worker";
  String? selectedChurchRole;
  String? selectedLocation;
  String? selectedSubLocation;
  String? selectedDept;
  String? selectedTeam;
  String? selectedCell;

  // 24 Department selection when Location == "Church"
  String? selectedOfficialDeptId;
  String? selectedSubOfficialDeptId;

  // Korean Worker Portfolio selection
  final Set<String> _selectedPortfolioDeptIds = {};

  // Team Leader + Team Secretary dual role
  bool _isDualTeamSecretary = false;
  bool _isLoading = false;

  bool get _isChurchLocation => selectedLocation?.trim().toLowerCase() == 'church';

  bool get _isKoreanWorkerRole {
    final key = _convertRole(selectedChurchRole);
    return key.startsWith('church_') || key.startsWith('korean_worker_');
  }

  bool get _isTeamLeaderRole {
    final key = _convertRole(selectedChurchRole);
    return key == 'team_leader' || key == 'assistant_team_leader';
  }

  @override
  void initState() { 
    super.initState(); 
    _fetchInitialData(); 
  }

  Future<void> _fetchInitialData() async {
    await Future.wait([
      _fetchLocations(),
      _fetchRoles(),
      _fetchOfficialDepartments(),
    ]);
  }

  Future<void> _fetchRoles() async {
    try {
      final data = await _supabase.from('app_roles').select('role_key, display_name, category');
      if (!mounted) return;
      setState(() {
        _roleDataMap = List<Map<String, dynamic>>.from(data);
        _updateVisibleRoles();
      });
    } catch (e) { debugPrint("Role Fetch Error: $e"); }
  }

  Future<void> _fetchOfficialDepartments() async {
    try {
      final data = await _supabase.from('official_departments').select('id, name, code, parent_id').order('name');
      if (!mounted) return;
      setState(() {
        _officialDepts = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) { debugPrint("Official Dept Error: $e"); }
  }

  void _updateVisibleRoles() {
    if (selectedAccountType == null) return;
    setState(() {
      if (_isChurchLocation) {
        // Show 24 Department and Korean Worker roles
        dynamicRoles = _roleDataMap
            .where((r) => r['category'] == selectedAccountType &&
                          (r['role_key'].toString().contains('_dept_') || 
                           r['role_key'].toString().startsWith('ia_mgr') ||
                           r['role_key'].toString().startsWith('church_') ||
                           r['role_key'].toString().startsWith('korean_worker_')))
            .map((e) => e['display_name'].toString())
            .toList();
      } else {
        // Standard Region Roles (Location, Sub-location, Dept, Team, Cell)
        dynamicRoles = _roleDataMap
            .where((r) => r['category'] == selectedAccountType &&
                          !r['role_key'].toString().startsWith('church_') &&
                          !r['role_key'].toString().startsWith('korean_worker_'))
            .map((e) => e['display_name'].toString())
            .toList();
      }
      selectedChurchRole = null;
      _isDualTeamSecretary = false;
    });
  }

  Future<void> _fetchLocations() async {
    try {
      final data = await _supabase.from('locations').select('id, location');
      if (!mounted) return;
      setState(() { 
        _locationData = List<Map<String, dynamic>>.from(data); 
        locations = _locationData.map((e) => e['location'].toString()).toList(); 
      });
    } catch (e) { debugPrint("Loc Error: $e"); }
  }

  Future<void> _fetchSubLocations(String locName) async {
    try {
      final locId = _locationData.firstWhere((e) => e['location'] == locName)['id'];
      final data = await _supabase.from('sub_locations').select('id, name').eq('location_id', locId);
      if (!mounted) return;
      setState(() { 
        _subLocationData = List<Map<String, dynamic>>.from(data); 
        subLocations = _subLocationData.map((e) => e['name'].toString()).toList(); 
        selectedSubLocation = null; departments = []; teams = []; cellGroups = [];
      });
    } catch (e) { debugPrint("Sub-loc Error: $e"); }
  }

  Future<void> _fetchDepartments(String subName) async {
    try {
      final subId = _subLocationData.firstWhere((e) => e['name'] == subName)['id'];
      final data = await _supabase.from('departments').select('id, name').eq('sub_location_id', subId);
      if (!mounted) return;
      setState(() { 
        _deptData = List<Map<String, dynamic>>.from(data); 
        departments = _deptData.map((e) => e['name'].toString()).toList(); 
        selectedDept = null; teams = []; cellGroups = [];
      });
    } catch (e) { debugPrint("Dept Error: $e"); }
  }

  Future<void> _fetchTeams(String deptName) async {
    try {
      final deptId = _deptData.firstWhere((e) => e['name'] == deptName)['id'];
      final data = await _supabase.from('teams').select('id, name').eq('dept_id', deptId);
      if (!mounted) return;
      setState(() { 
        _teamData = List<Map<String, dynamic>>.from(data); 
        teams = _teamData.map((e) => e['name'].toString()).toList(); 
        selectedTeam = null; cellGroups = [];
      });
    } catch (e) { debugPrint("Team Error: $e"); }
  }

  Future<void> _fetchCellGroups(String teamName) async {
    try {
      final teamId = _teamData.firstWhere((e) => e['name'] == teamName)['id'];
      final data = await _supabase.from('cell_groups').select('name').eq('team_id', teamId);
      if (!mounted) return;
      setState(() { 
        cellGroups = List<String>.from(data.map((e) => e['name'].toString())); 
        selectedCell = null; 
      });
    } catch (e) { debugPrint("Cell Error: $e"); }
  }

  String _convertRole(String? displayName) {
    if (displayName == null) return 'member';
    final match = _roleDataMap.firstWhere(
      (element) => element['display_name'] == displayName,
      orElse: () => {'role_key': 'member'}
    );
    return match['role_key'];
  }

  Future<void> _saveAccount() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty || _nameController.text.isEmpty || selectedAccountType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Missing details"))); 
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await _supabase.auth.signUp(
        email: _emailController.text.trim(), 
        password: _passwordController.text.trim()
      );

      if (!mounted) return;
      if (res.user?.id != null) {
        final uid = res.user!.id;
        final primaryRoleKey = _convertRole(selectedChurchRole);
        final secondaryRoleKey = (_isTeamLeaderRole && _isDualTeamSecretary) ? 'team_sec' : null;

        String locStr = selectedLocation ?? "N/A";
        String? subLocStr;
        String deptStr;
        String? teamStr;
        String? cellStr;

        if (_isChurchLocation) {
          // 24 Department / Korean Worker assignment
          final deptObj = _officialDepts.firstWhere((d) => d['id'] == selectedOfficialDeptId, orElse: () => {});
          deptStr = deptObj['name'] ?? (selectedChurchRole ?? "24 Department");
          subLocStr = null;
          teamStr = null;
          cellStr = null;
        } else {
          // Standard Region assignment
          subLocStr = selectedSubLocation ?? "N/A";
          deptStr = selectedDept ?? "N/A";
          teamStr = selectedTeam ?? "N/A";
          cellStr = selectedCell ?? "N/A";
        }

        // 1. Upsert into existing profiles table
        await _supabase.from('profiles').upsert({
          'id': uid,
          'account_type': selectedAccountType,
          'role': primaryRoleKey,
          'secondary_role': secondaryRoleKey,
          'official_dept_id': _isChurchLocation ? selectedOfficialDeptId : null,
          'sub_dept_id': _isChurchLocation ? selectedSubOfficialDeptId : null,
          'location': locStr,
          'sub_location': subLocStr,
          'department': deptStr,
          'team': teamStr,
          'cell_group': cellStr,
          'full_name': _nameController.text.trim(),
          'id_number': _idController.text.trim(),
          'username': _userController.text.trim(),
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
        });

        // 2. If Korean Worker with portfolio selection, save to korean_worker_portfolios
        if (_isChurchLocation && _isKoreanWorkerRole && _selectedPortfolioDeptIds.isNotEmpty) {
          final rows = _selectedPortfolioDeptIds.map((dId) => {
            'user_id': uid,
            'executive_title': selectedChurchRole ?? "Korean Worker",
            'official_dept_id': dId,
          }).toList();

          await _supabase.from('korean_worker_portfolios').insert(rows);
        }

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account created successfully!")));
        await _supabase.auth.signOut();
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) { 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); 
    } finally { 
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width; 
    bool isDesktop = width > 900; 
    const pPurple = Color(0xFF4A148C);

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: AppBar(
        backgroundColor: Colors.white, 
        elevation: 0.5, 
        centerTitle: true, 
        title: Text("Enter account details", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple, fontSize: isDesktop ? 22 : 18))
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? width * 0.15 : 15, vertical: 20),
        child: Column(children: [
          
          // CARD 1: Unit Assignment
          _buildCard("1. Unit Assignment", [
            _sideBySideDropdown("Location", locations, selectedLocation, (v) { 
              setState(() {
                selectedLocation = v;
                _updateVisibleRoles();
              }); 
              if (v != null && !_isChurchLocation) {
                _fetchSubLocations(v);
              }
            }),

            // If Location == "Church": Direct 24 Department selector
            if (_isChurchLocation) ...[
              _sideBySideOfficialDeptDropdown("24 Department", _officialDepts.where((d) => d['parent_id'] == null).toList(), selectedOfficialDeptId, (val) {
                setState(() {
                  selectedOfficialDeptId = val;
                  _subOfficialDepts = _officialDepts.where((d) => d['parent_id'] == val).toList();
                  selectedSubOfficialDeptId = null;
                });
              }),
              if (_subOfficialDepts.isNotEmpty)
                _sideBySideOfficialDeptDropdown("Sub-Department", _subOfficialDepts, selectedSubOfficialDeptId, (val) {
                  setState(() => selectedSubOfficialDeptId = val);
                }),
            ]
            // If Location != "Church": Standard Region Cascades
            else ...[
              _sideBySideDropdown("Sub-Location", subLocations, selectedSubLocation, (v) { setState(() => selectedSubLocation = v); if (v != null) _fetchDepartments(v); }),
              _sideBySideDropdown("Department", departments, selectedDept, (v) { setState(() => selectedDept = v); if (v != null) _fetchTeams(v); }),
              _sideBySideDropdown("Team Number", teams, selectedTeam, (v) { setState(() => selectedTeam = v); if (v != null) _fetchCellGroups(v); }),
              _sideBySideDropdown("Cell Group", cellGroups, selectedCell, (v) { setState(() => selectedCell = v); }),
            ],
          ], pPurple),

          const SizedBox(height: 12),

          // CARD 2: Identity Details
          _buildCard("2. Identity Details", [
            _sideBySideDropdown("Account Category", accountTypeOptions, selectedAccountType, (v) { setState(() => selectedAccountType = v); _updateVisibleRoles(); }),
            _sideBySideDropdown("Church Role", dynamicRoles, selectedChurchRole, (v) {
              setState(() {
                selectedChurchRole = v;
                if (!_isTeamLeaderRole) _isDualTeamSecretary = false;
              });
            }),

            // Case A: Team Leader Dual Role Switch (Only for Region Teams)
            if (!_isChurchLocation && _isTeamLeaderRole)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.3)))),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text("Also assign Team Secretary (Dual Role)?", style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.purple[900]))),
                    Switch(
                      value: _isDualTeamSecretary,
                      activeThumbColor: pPurple,
                      onChanged: (val) => setState(() => _isDualTeamSecretary = val),
                    ),
                  ],
                ),
              ),

            // Case B: Korean Worker Dynamic Portfolio Selector
            if (_isChurchLocation && _isKoreanWorkerRole)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.3)))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Overseeing Portfolio (Select 3–5 Departments):", style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _officialDepts.where((d) => d['parent_id'] == null).map((dept) {
                        final isChecked = _selectedPortfolioDeptIds.contains(dept['id']);
                        return FilterChip(
                          label: Text(dept['name'], style: const TextStyle(fontSize: 11)),
                          selected: isChecked,
                          selectedColor: pPurple.withValues(alpha: 0.2),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) _selectedPortfolioDeptIds.add(dept['id']);
                              else _selectedPortfolioDeptIds.remove(dept['id']);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

            _sideBySideField("Full Names", _nameController, Icons.person_outline),
            _sideBySideField("User Name", _userController, Icons.alternate_email),
            _sideBySideField("Phone Number", _phoneController, Icons.phone_android_outlined),
            _sideBySideField("SCJ ID", _idController, Icons.badge_outlined),
            _sideBySideField("Email", _emailController, Icons.email_outlined),
            _sideBySideField("Password", _passwordController, Icons.lock_outline, isPass: true),
          ], pPurple),

          const SizedBox(height: 25),

          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 45), side: const BorderSide(color: Colors.grey, width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text("Go back", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14)))),
            const SizedBox(width: 15),
            Expanded(flex: 2, child: ElevatedButton(onPressed: _isLoading ? null : _saveAccount, style: ElevatedButton.styleFrom(backgroundColor: pPurple, minimumSize: const Size(0, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isLoading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text("Confirm Account", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 14)))),
          ]),
          const SizedBox(height: 50),
        ]),
      ),
    );
  }

  // ==========================================
  // HELPERS (Your exact formatting)
  // ==========================================

  Widget _buildCard(String title, List<Widget> children, Color pP) {
    return Container(
      width: double.infinity, 
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: pP.withValues(alpha: 0.2), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.w900, color: pP)),
        const Divider(height: 20),
        ...children
      ]),
    );
  }

  Widget _sideBySideDropdown(String label, List<String> items, String? val, Function(String?) onCh) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.3)))),
      child: Row(children: [
        Expanded(flex: 2, child: Text(label, style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 13))),
        Expanded(flex: 3, child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10), 
          decoration: BoxDecoration(color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.purple.withValues(alpha: 0.15))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isDense: true, 
              alignment: Alignment.center, 
              key: ValueKey("${label}_$val"), 
              value: items.contains(val) ? val : null, 
              isExpanded: true, 
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)))).toList(), 
              onChanged: onCh
            )
          )
        )),
      ]),
    );
  }

  Widget _sideBySideOfficialDeptDropdown(String label, List<Map<String, dynamic>> items, String? val, Function(String?) onCh) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.3)))),
      child: Row(children: [
        Expanded(flex: 2, child: Text(label, style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 13))),
        Expanded(flex: 3, child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10), 
          decoration: BoxDecoration(color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.purple.withValues(alpha: 0.15))),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isDense: true, 
              alignment: Alignment.center, 
              value: items.any((e) => e['id'] == val) ? val : null, 
              isExpanded: true, 
              items: items.map((e) => DropdownMenuItem<String>(value: e['id'], child: Text(e['name'], style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)))).toList(), 
              onChanged: onCh
            )
          )
        )),
      ]),
    );
  }

  Widget _sideBySideField(String label, TextEditingController ctrl, IconData icon, {bool isPass = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.3)))),
      child: Row(children: [
        Expanded(flex: 2, child: Text(label, style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 13))),
        Expanded(flex: 3, child: SizedBox(
          height: 32,
          child: TextField(
            controller: ctrl, 
            obscureText: isPass, 
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold), 
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 15, color: Colors.purple), 
              filled: true, fillColor: const Color(0xFFF3E5F5), 
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none), 
              contentPadding: EdgeInsets.zero
            )
          ),
        )),
      ]),
    );
  }
}