// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

enum TransferMode { individual, bulk }

class TransferRequestForm extends StatefulWidget {
  const TransferRequestForm({super.key});

  @override
  State<TransferRequestForm> createState() => _TransferRequestFormState();
}

class _TransferRequestFormState extends State<TransferRequestForm> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Color _primaryPurple = const Color(0xFF4A148C);
  final Color _backgroundColor = const Color(0xFFF8FAFC);

  TransferMode _currentMode = TransferMode.individual;

  // Logged-in user profile & access control
  Map<String, dynamic>? _userAccessProfile;
  bool _isGlobalAdmin = false;

  // ==========================================
  // INDIVIDUAL MODE STATE
  // ==========================================
  dynamic _selectedMember;
  bool _isLoadingSearch = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _indReasonCtrl = TextEditingController();
  List<dynamic> _searchResults = [];

  List<String> _indLocations = [];
  List<String> _indSubLocations = [];
  List<String> _indDepartments = [];
  List<String> _indTeams = [];
  List<String> _indCells = [];

  String? _newLoc, _newSub, _newDept, _newTeam, _newCell;

  // ==========================================
  // BULK MODE STATE
  // ==========================================
  List<String> _bulkSourceLocations = [];
  List<String> _bulkSourceSubLocations = [];
  List<String> _bulkSourceDepartments = [];
  List<String> _bulkSourceTeams = [];

  String? _sourceLoc, _sourceSub, _sourceDept, _sourceTeam;

  List<String> _bulkDestLocations = [];
  List<String> _bulkDestSubLocations = [];
  List<String> _bulkDestDepartments = [];
  List<String> _bulkDestTeams = [];
  List<String> _bulkDestCells = [];

  String? _destLoc, _destSub, _destDept, _destTeam, _destCell;

  bool _isLoadingBulkMembers = false;
  List<Map<String, dynamic>> _bulkMembers = [];
  final Set<String> _selectedMemberIds = {};
  final TextEditingController _bulkReasonCtrl = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _checkUserAccessLevel();
    await _fetchInitialLocations();
  }

  // ==========================================
  // ACCESS CONTROL: RESTRICT TO AUTHORIZED UNIT
  // ==========================================

  Future<void> _checkUserAccessLevel() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final res = await _supabase
          .from('members')
          .select('id, location, sub_location, department, team, duty')
          .or('id.eq.${user.id},email_address.eq.${user.email}')
          .maybeSingle();

      if (res != null && mounted) {
        final duty = (res['duty']?.toString() ?? '').toLowerCase();
        final isAdmin = duty.contains('admin') ||
            duty.contains('ia') ||
            duty.contains('internal affairs') ||
            duty.contains('pastor') ||
            duty.contains('leader_lead');

        setState(() {
          _userAccessProfile = res;
          _isGlobalAdmin = isAdmin;

          // If restricted, automatically preset the unit levels
          if (!isAdmin) {
            final loc = res['location']?.toString();
            final sub = res['sub_location']?.toString();
            final dept = res['department']?.toString();
            final team = res['team']?.toString();

            if (loc != null && loc.isNotEmpty) {
              _sourceLoc = loc;
              _bulkFetchSourceSubLocations(loc);
            }
            if (sub != null && sub.isNotEmpty) {
              _sourceSub = sub;
              _bulkFetchSourceDepartments(sub);
            }
            if (dept != null && dept.isNotEmpty) {
              _sourceDept = dept;
              _bulkFetchSourceTeams(dept);
            }
            if (duty.contains('team') && team != null && team.isNotEmpty) {
              _sourceTeam = team;
              _fetchBulkMembers();
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Access Level Check Note: $e");
    }
  }

  // ==========================================
  // DYNAMIC LOCATION FETCHING (NEVER HARDCODED)
  // ==========================================

  Future<void> _fetchInitialLocations() async {
    final Set<String> dynamicLocations = {};

    // 1. Try querying the locations table dynamically across candidate column names
    try {
      final res = await _supabase.from('locations').select().limit(500);
      for (final row in res) {
        final loc = row['locations'] ?? row['location'] ?? row['name'] ?? row['location_name'];
        if (loc != null && loc.toString().trim().isNotEmpty) {
          dynamicLocations.add(loc.toString().trim());
        }
      }
    } catch (_) {}

    // 2. Also retrieve all distinct locations directly from the members table
    try {
      final res = await _supabase.from('members').select('location').limit(2000);
      for (final row in res) {
        final loc = row['location']?.toString().trim();
        if (loc != null && loc.isNotEmpty) {
          dynamicLocations.add(loc);
        }
      }
    } catch (_) {}

    final sortedLocs = dynamicLocations.toList()..sort();

    if (mounted) {
      setState(() {
        _indLocations = sortedLocs;
        _bulkSourceLocations = sortedLocs;
        _bulkDestLocations = sortedLocs;
      });
    }
  }

  // --- Individual Cascading Helpers ---
  Future<void> _indFetchSubLocations(String loc) async {
    final res = await _supabase.from('members').select('sub_location').eq('location', loc);
    if (mounted) {
      setState(() {
        _indSubLocations = res.map((e) => e['sub_location']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _newSub = null; _newDept = null; _newTeam = null; _newCell = null;
      });
    }
  }

  Future<void> _indFetchDepartments(String sub) async {
    final res = await _supabase.from('members').select('department').eq('sub_location', sub);
    if (mounted) {
      setState(() {
        _indDepartments = res.map((e) => e['department']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _newDept = null; _newTeam = null; _newCell = null;
      });
    }
  }

  Future<void> _indFetchTeams(String dept) async {
    final res = await _supabase.from('members').select('team').eq('department', dept);
    if (mounted) {
      setState(() {
        _indTeams = res.map((e) => e['team']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _newTeam = null; _newCell = null;
      });
    }
  }

  Future<void> _indFetchCells(String team) async {
    final res = await _supabase.from('members').select('cell_group').eq('team', team);
    if (mounted) {
      setState(() {
        _indCells = res.map((e) => e['cell_group']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _newCell = null;
      });
    }
  }

  // --- Bulk Source Hierarchy Helpers ---
  Future<void> _bulkFetchSourceSubLocations(String loc) async {
    final res = await _supabase.from('members').select('sub_location').eq('location', loc);
    if (mounted) {
      setState(() {
        _bulkSourceSubLocations = res.map((e) => e['sub_location']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _sourceSub = null; _sourceDept = null; _sourceTeam = null;
        _bulkMembers = [];
        _selectedMemberIds.clear();
      });
    }
  }

  Future<void> _bulkFetchSourceDepartments(String sub) async {
    final res = await _supabase.from('members').select('department').eq('sub_location', sub);
    if (mounted) {
      setState(() {
        _bulkSourceDepartments = res.map((e) => e['department']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _sourceDept = null; _sourceTeam = null;
        _bulkMembers = [];
        _selectedMemberIds.clear();
      });
    }
  }

  Future<void> _bulkFetchSourceTeams(String dept) async {
    final res = await _supabase.from('members').select('team').eq('department', dept);
    if (mounted) {
      setState(() {
        _bulkSourceTeams = res.map((e) => e['team']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _sourceTeam = null;
        _fetchBulkMembers();
      });
    }
  }

  Future<void> _fetchBulkMembers() async {
    if (_sourceLoc == null || _sourceSub == null || _sourceDept == null) return;

    setState(() => _isLoadingBulkMembers = true);
    try {
      var query = _supabase
          .from('members')
          .select()
          .eq('location', _sourceLoc!)
          .eq('sub_location', _sourceSub!)
          .eq('department', _sourceDept!);

      if (_sourceTeam != null && _sourceTeam!.isNotEmpty) {
        query = query.eq('team', _sourceTeam!);
      }

      final res = await query.order('english_name', ascending: true);
      if (mounted) {
        setState(() {
          _bulkMembers = List<Map<String, dynamic>>.from(res);
          _selectedMemberIds.clear();
          for (var m in _bulkMembers) {
            final id = m['id']?.toString();
            if (id != null) _selectedMemberIds.add(id);
          }
        });
      }
    } catch (e) {
      debugPrint("Fetch Bulk Members Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingBulkMembers = false);
    }
  }

  // --- Bulk Destination Hierarchy Helpers ---
  Future<void> _bulkFetchDestSubLocations(String loc) async {
    final res = await _supabase.from('members').select('sub_location').eq('location', loc);
    if (mounted) {
      setState(() {
        _bulkDestSubLocations = res.map((e) => e['sub_location']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _destSub = null; _destDept = null; _destTeam = null; _destCell = null;
      });
    }
  }

  Future<void> _bulkFetchDestDepartments(String sub) async {
    final res = await _supabase.from('members').select('department').eq('sub_location', sub);
    if (mounted) {
      setState(() {
        _bulkDestDepartments = res.map((e) => e['department']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _destDept = null; _destTeam = null; _destCell = null;
      });
    }
  }

  Future<void> _bulkFetchDestTeams(String dept) async {
    final res = await _supabase.from('members').select('team').eq('department', dept);
    if (mounted) {
      setState(() {
        _bulkDestTeams = res.map((e) => e['team']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _destTeam = null; _destCell = null;
      });
    }
  }

  Future<void> _bulkFetchDestCells(String team) async {
    final res = await _supabase.from('members').select('cell_group').eq('team', team);
    if (mounted) {
      setState(() {
        _bulkDestCells = res.map((e) => e['cell_group']?.toString()).where((e) => e != null && e.isNotEmpty).cast<String>().toSet().toList()..sort();
        _destCell = null;
      });
    }
  }

  // ==========================================
  // SEARCH & SUBMISSIONS
  // ==========================================

  Future<void> _searchIndividual(String q) async {
    if (q.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isLoadingSearch = true);

    try {
      var query = _supabase.from('members').select();

      // Access control: If not a global admin, restrict search to the user's location
      if (!_isGlobalAdmin && _userAccessProfile != null) {
        final loc = _userAccessProfile!['location']?.toString();
        if (loc != null && loc.isNotEmpty) {
          query = query.eq('location', loc);
        }
      }

      final res = await query
          .or('english_name.ilike.%$q%,scj_id.ilike.%$q%')
          .limit(6);

      if (mounted) {
        setState(() {
          _searchResults = res;
          _isLoadingSearch = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSearch = false);
    }
  }

  Future<void> _submitIndividualTransfer() async {
    if (_selectedMember == null || _newLoc == null || _indReasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete all destination unit details and provide a reason.")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final currentUserId = _supabase.auth.currentUser?.id ?? 'system';
      await _supabase.from('transfer_requests').insert({
        'member_id': _selectedMember['id'],
        'old_unit_details': {
          'location': _selectedMember['location'],
          'sub_location': _selectedMember['sub_location'],
          'department': _selectedMember['department'],
          'team': _selectedMember['team'],
          'cell_group': _selectedMember['cell_group'],
        },
        'new_unit_details': {
          'location': _newLoc,
          'sub_location': _newSub,
          'department': _newDept,
          'team': _newTeam,
          'cell_group': _newCell,
        },
        'reason': _indReasonCtrl.text.trim(),
        'requester_id': currentUserId,
        'current_level': 'TEAM_LEAD',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text("Individual transfer request submitted successfully."),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Individual Transfer Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red.shade800, content: Text("Error submitting request: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitBulkTransfer() async {
    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one member to transfer.")),
      );
      return;
    }

    if (_destLoc == null || _bulkReasonCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please specify the proposed destination unit and provide a reason.")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final currentUserId = _supabase.auth.currentUser?.id ?? 'system';
      final selectedMembers = _bulkMembers.where((m) => _selectedMemberIds.contains(m['id'].toString())).toList();

      final List<Map<String, dynamic>> requestsToInsert = selectedMembers.map((m) {
        return {
          'member_id': m['id'],
          'old_unit_details': {
            'location': m['location'],
            'sub_location': m['sub_location'],
            'department': m['department'],
            'team': m['team'],
            'cell_group': m['cell_group'],
          },
          'new_unit_details': {
            'location': _destLoc,
            'sub_location': _destSub,
            'department': _destDept,
            'team': _destTeam,
            'cell_group': _destCell,
          },
          'reason': _bulkReasonCtrl.text.trim(),
          'requester_id': currentUserId,
          'current_level': 'TEAM_LEAD',
        };
      }).toList();

      for (int i = 0; i < requestsToInsert.length; i += 50) {
        final chunk = requestsToInsert.sublist(
          i,
          (i + 50 > requestsToInsert.length) ? requestsToInsert.length : i + 50,
        );
        await _supabase.from('transfer_requests').insert(chunk);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text("Successfully submitted ${requestsToInsert.length} transfer requests."),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Bulk Transfer Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red.shade800, content: Text("Error submitting bulk transfer: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ==========================================
  // CARD DECORATION HELPER (LIGHT 2PX BORDER + SHADOW)
  // ==========================================

  BoxDecoration _cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: AppPalette.bg(Colors.white),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppPalette.line(borderColor ?? const Color(0xFFE2E8F0)),
        width: 2.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 6),
          spreadRadius: 1,
        ),
      ],
    );
  }

  // ==========================================
  // UI LAYOUT
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(_backgroundColor),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        title: Text(
          "Member Transfer Request",
          style: GoogleFonts.merriweather(
            fontWeight: FontWeight.w900,
            color: AppPalette.fg(_primaryPurple),
            fontSize: 23,
          ),
        ),
        centerTitle: true,
      ),
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModeSelector(),
              const SizedBox(height: 24),
              if (_currentMode == TransferMode.individual) ...[
                _buildIndividualView(),
              ] else ...[
                _buildBulkView(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Expanded(
            child: _buildModeTab(
              mode: TransferMode.individual,
              label: "Individual Transfer",
              icon: Icons.person_search_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildModeTab(
              mode: TransferMode.bulk,
              label: "Bulk Transfer",
              icon: Icons.groups_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({required TransferMode mode, required String label, required IconData icon}) {
    final isSelected = _currentMode == mode;
    return InkWell(
      onTap: () => setState(() => _currentMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppPalette.bg(isSelected ? _primaryPurple : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: AppPalette.fg(isSelected ? Colors.white : Colors.grey.shade700),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.merriweather(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: AppPalette.fg(isSelected ? Colors.white : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // INDIVIDUAL VIEW WIDGETS
  // ==========================================

  Widget _buildIndividualView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchCard(),
        if (_selectedMember != null) ...[
          const SizedBox(height: 24),
          // Balanced equal-height unit cards using IntrinsicHeight
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildUnitColumn("Current Unit Details", isEditable: false)),
                const SizedBox(width: 22),
                Expanded(child: _buildUnitColumn("Proposed Destination Unit", isEditable: true)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildReasonBox(controller: _indReasonCtrl),
          const SizedBox(height: 28),
          _buildSubmitButton(
            title: "Submit Individual Transfer",
            onPressed: _isSubmitting ? null : _submitIndividualTransfer,
          ),
        ],
      ],
    );
  }

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Search Member",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            onChanged: _searchIndividual,
            style: GoogleFonts.merriweather(fontSize: 16),
            decoration: InputDecoration(
              hintText: tr("Type member name or SCJ ID to search..."),
              hintStyle: GoogleFonts.merriweather(fontSize: 15, color: AppPalette.fg(Colors.grey.shade500)),
              prefixIcon: const Icon(Icons.search, size: 24),
              suffixIcon: _isLoadingSearch
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppPalette.bg(Colors.grey.shade50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppPalette.line(Colors.grey.shade200)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final m = _searchResults[i];
                  return ListTile(
                    title: Text(
                      m['english_name'] ?? "Unknown",
                      style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 15.5),
                    ),
                    subtitle: Text(
                      "SCJ ID: ${m['scj_id']} • Dept: ${m['department'] ?? '-'} • Team: ${m['team'] ?? '-'}",
                      style: GoogleFonts.merriweather(fontSize: 13.5, color: AppPalette.fg(Colors.grey.shade600)),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() {
                      _selectedMember = m;
                      _searchResults = [];
                      _searchCtrl.text = m['english_name'] ?? "";
                    }),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnitColumn(String title, {required bool isEditable}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(
        borderColor: isEditable ? _primaryPurple.withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w900,
              fontSize: 17.5,
              color: AppPalette.fg(isEditable ? _primaryPurple : const Color(0xFF1E293B)),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _unitRow("Location", isEditable ? _newLoc : _selectedMember['location'], (v) {
            setState(() => _newLoc = v);
            _indFetchSubLocations(v!);
          }, _indLocations, isEditable),
          _unitRow("Sub-Location", isEditable ? _newSub : _selectedMember['sub_location'], (v) {
            setState(() => _newSub = v);
            _indFetchDepartments(v!);
          }, _indSubLocations, isEditable),
          _unitRow("Department", isEditable ? _newDept : _selectedMember['department'], (v) {
            setState(() => _newDept = v);
            _indFetchTeams(v!);
          }, _indDepartments, isEditable),
          _unitRow("Team", isEditable ? _newTeam : _selectedMember['team'], (v) {
            setState(() => _newTeam = v);
            _indFetchCells(v!);
          }, _indTeams, isEditable),
          _unitRow("Cell Group", isEditable ? _newCell : _selectedMember['cell_group'], (v) {
            setState(() => _newCell = v);
          }, _indCells, isEditable),
        ],
      ),
    );
  }

  Widget _unitRow(String label, String? value, Function(String?)? onChanged, List<String> items, bool isEditable) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              "$label:",
              style: GoogleFonts.merriweather(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppPalette.fg(Colors.grey.shade700),
              ),
            ),
          ),
          Expanded(
            child: isEditable
                ? Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppPalette.bg(Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: items.contains(value) ? value : null,
                        hint: Text("Select $label", style: GoogleFonts.merriweather(fontSize: 13)),
                        isExpanded: true,
                        items: items.map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e, style: GoogleFonts.merriweather(fontSize: 14)),
                        )).toList(),
                        onChanged: onChanged,
                      ),
                    ),
                  )
                : Text(
                    value ?? "—",
                    style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.w700, color: AppPalette.fg(const Color(0xFF1E293B))),
                  ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // BULK VIEW WIDGETS
  // ==========================================

  Widget _buildBulkView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSourceUnitCard(),
        const SizedBox(height: 22),
        _buildDestinationUnitCard(),
        const SizedBox(height: 22),
        _buildBulkMembersList(),
        const SizedBox(height: 22),
        _buildReasonBox(controller: _bulkReasonCtrl),
        const SizedBox(height: 28),
        _buildSubmitButton(
          title: "Submit Bulk Transfer (${_selectedMemberIds.length} Members)",
          onPressed: _isSubmitting ? null : _submitBulkTransfer,
        ),
      ],
    );
  }

  Widget _buildSourceUnitCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppPalette.bg(Colors.blue.shade50), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.filter_alt_outlined, color: AppPalette.fg(Colors.blue.shade700), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Source Unit Hierarchy",
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17.5),
                  ),
                  Text(
                    "Select authorized unit levels in cascading order to retrieve members",
                    style: GoogleFonts.merriweather(fontSize: 13.5, color: AppPalette.fg(Colors.grey.shade600)),
                  ),
                ],
              )),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 18),
          Wrap(
            spacing: 20,
            runSpacing: 16,
            children: [
              _buildDropdownField(
                label: "1. Location",
                value: _sourceLoc,
                items: _bulkSourceLocations,
                onChanged: (v) {
                  setState(() => _sourceLoc = v);
                  _bulkFetchSourceSubLocations(v!);
                },
              ),
              _buildDropdownField(
                label: "2. Sub-Location",
                value: _sourceSub,
                items: _bulkSourceSubLocations,
                onChanged: (v) {
                  setState(() => _sourceSub = v);
                  _bulkFetchSourceDepartments(v!);
                },
              ),
              _buildDropdownField(
                label: "3. Department",
                value: _sourceDept,
                items: _bulkSourceDepartments,
                onChanged: (v) {
                  setState(() => _sourceDept = v);
                  _bulkFetchSourceTeams(v!);
                },
              ),
              _buildDropdownField(
                label: "4. Team (Optional)",
                value: _sourceTeam,
                items: _bulkSourceTeams,
                onChanged: (v) {
                  setState(() => _sourceTeam = v);
                  _fetchBulkMembers();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationUnitCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(
        borderColor: _primaryPurple.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppPalette.bg(Colors.purple.shade50), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.input_rounded, color: AppPalette.fg(_primaryPurple), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Proposed Destination Unit",
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17.5, color: AppPalette.fg(_primaryPurple)),
                  ),
                  Text(
                    "Define the new target unit for the selected members",
                    style: GoogleFonts.merriweather(fontSize: 13.5, color: AppPalette.fg(Colors.grey.shade600)),
                  ),
                ],
              )),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 18),
          Wrap(
            spacing: 20,
            runSpacing: 16,
            children: [
              _buildDropdownField(
                label: "Location",
                value: _destLoc,
                items: _bulkDestLocations,
                onChanged: (v) {
                  setState(() => _destLoc = v);
                  _bulkFetchDestSubLocations(v!);
                },
              ),
              _buildDropdownField(
                label: "Sub-Location",
                value: _destSub,
                items: _bulkDestSubLocations,
                onChanged: (v) {
                  setState(() => _destSub = v);
                  _bulkFetchDestDepartments(v!);
                },
              ),
              _buildDropdownField(
                label: "Department",
                value: _destDept,
                items: _bulkDestDepartments,
                onChanged: (v) {
                  setState(() => _destDept = v);
                  _bulkFetchDestTeams(v!);
                },
              ),
              _buildDropdownField(
                label: "Team",
                value: _destTeam,
                items: _bulkDestTeams,
                onChanged: (v) {
                  setState(() => _destTeam = v);
                  _bulkFetchDestCells(v!);
                },
              ),
              _buildDropdownField(
                label: "Cell Group",
                value: _destCell,
                items: _bulkDestCells,
                onChanged: (v) => setState(() => _destCell = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?)? onChanged,
  }) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w700, color: AppPalette.fg(Colors.grey.shade800)),
          ),
          const SizedBox(height: 6),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppPalette.bg(Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppPalette.line(Colors.grey.shade300)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value) ? value : null,
                hint: Text("Select...", style: GoogleFonts.merriweather(fontSize: 13.5)),
                isExpanded: true,
                items: items.map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, style: GoogleFonts.merriweather(fontSize: 14)),
                )).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact Member List: Row size reduced to ~35% height with clean multi-column alignment
  Widget _buildBulkMembersList() {
    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Members in Unit (${_bulkMembers.length})",
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  Text(
                    "${_selectedMemberIds.length} members selected for transfer",
                    style: GoogleFonts.merriweather(fontSize: 13.5, color: AppPalette.fg(Colors.grey.shade600)),
                  ),
                ],
              )),
              if (_bulkMembers.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      if (_selectedMemberIds.length == _bulkMembers.length) {
                        _selectedMemberIds.clear();
                      } else {
                        _selectedMemberIds.clear();
                        for (var m in _bulkMembers) {
                          _selectedMemberIds.add(m['id'].toString());
                        }
                      }
                    });
                  },
                  icon: Icon(
                    _selectedMemberIds.length == _bulkMembers.length ? Icons.deselect : Icons.select_all,
                    size: 20,
                    color: AppPalette.fg(_primaryPurple),
                  ),
                  label: Text(
                    _selectedMemberIds.length == _bulkMembers.length ? "Deselect All" : "Select All",
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: AppPalette.fg(_primaryPurple)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          if (_isLoadingBulkMembers) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            ),
          ] else if (_bulkMembers.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  _sourceDept == null
                      ? "Select Location, Sub-Location, and Department above to load members."
                      : "No active members found in this unit.",
                  style: GoogleFonts.merriweather(fontSize: 14, color: AppPalette.fg(Colors.grey.shade600)),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _bulkMembers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = _bulkMembers[i];
                final id = m['id'].toString();
                final isChecked = _selectedMemberIds.contains(id);

                final currentTeam = m['team'] ?? '-';
                final currentCell = m['cell_group'] ?? '-';

                // Compact single-line row: ~38px height (reduced to ~35% of original tile height)
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isChecked) {
                        _selectedMemberIds.remove(id);
                      } else {
                        _selectedMemberIds.add(id);
                      }
                    });
                  },
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: isChecked,
                            activeColor: _primaryPurple,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedMemberIds.add(id);
                                } else {
                                  _selectedMemberIds.remove(id);
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 3,
                          child: Text(
                            m['english_name'] ?? "Unknown",
                            style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 14.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            "SCJ ID: ${m['scj_id']}",
                            style: GoogleFonts.merriweather(fontSize: 13, color: AppPalette.fg(Colors.grey.shade700)),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            "Team: $currentTeam • Cell Group: $currentCell",
                            style: GoogleFonts.merriweather(fontSize: 13, color: AppPalette.fg(Colors.grey.shade600)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppPalette.bg(isChecked ? Colors.purple.shade50 : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppPalette.line(isChecked ? Colors.purple.shade200 : Colors.grey.shade300),
                            ),
                          ),
                          child: Text(
                            isChecked ? "Transfer to ${_destTeam ?? 'Target Team'}" : "Keep Unit",
                            style: GoogleFonts.merriweather(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.fg(isChecked ? _primaryPurple : Colors.grey.shade600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReasonBox({required TextEditingController controller}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Reason for Transfer Request",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 3,
            style: GoogleFonts.merriweather(fontSize: 15),
            decoration: InputDecoration(
              hintText: tr("Provide context for the internal affairs department..."),
              hintStyle: GoogleFonts.merriweather(fontSize: 14, color: AppPalette.fg(Colors.grey.shade500)),
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton({required String title, required VoidCallback? onPressed}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppPalette.bg(_primaryPurple),
        foregroundColor: AppPalette.fg(Colors.white),
        disabledBackgroundColor: Colors.grey.shade300,
        minimumSize: const Size(double.infinity, 62),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
      ),
      onPressed: onPressed,
      child: _isSubmitting
          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
          : Text(
              title,
              style: GoogleFonts.merriweather(
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
    );
  }
}