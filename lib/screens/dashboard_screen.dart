// ignore_for_file: use_build_context_synchronously, unused_element, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart'; 

// PRESERVED: UserAccount Model
class UserAccount {
  final String fullName, userName, phoneNumber, email, role, accountType;
  UserAccount({
    required this.fullName,
    required this.userName,
    required this.phoneNumber,
    required this.email,
    required this.role,
    required this.accountType,
  });
}

class DashboardScreen extends StatefulWidget {
  final String currentRole, accountType, fullName, userName, phoneNumber, email;
  final Function(String view) onNavigate;
  final List<UserAccount> otherAccounts;
  final Function(UserAccount) onSwitchAccount;

  const DashboardScreen({
    super.key,
    required this.onNavigate,
    required this.currentRole,
    required this.accountType,
    required this.fullName,
    required this.userName,
    required this.phoneNumber,
    required this.email,
    required this.otherAccounts,
    required this.onSwitchAccount,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _menuStructure = [];
  bool _isLoading = true;

  // Local state to store fetched profile values if passed as empty/N/A
  late String _fullName;
  late String _userName;
  late String _phoneNumber;
  late String _email;
  late String _currentRole;
  late String _accountType;

  @override
  void initState() {
    super.initState();
    _fullName = widget.fullName;
    _userName = widget.userName;
    _phoneNumber = widget.phoneNumber;
    _email = widget.email;
    _currentRole = widget.currentRole;
    _accountType = widget.accountType;

    _fetchMenu();
    _fetchLiveProfile();
  }

  Future<void> _fetchLiveProfile() async {
    try {
      final res = await _supabase
          .from('profiles')
          .select('full_name, username, phone, email, role, account_type')
          .eq('email', widget.email)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          if (res['full_name'] != null && res['full_name'].toString().isNotEmpty) {
            _fullName = res['full_name'];
          }
          if (res['username'] != null && res['username'].toString().isNotEmpty) {
            _userName = res['username'];
          }
          if (res['phone'] != null && res['phone'].toString().isNotEmpty) {
            _phoneNumber = res['phone'];
          }
          if (res['role'] != null) _currentRole = res['role'];
          if (res['account_type'] != null) _accountType = res['account_type'];
        });
      }
    } catch (e) {
      debugPrint("Live Profile Fetch Error: $e");
    }
  }

  Future<void> _fetchMenu() async {
    try {
      final res = await _supabase
          .from('drawer_sections')
          .select('*, drawer_items(*)')
          .order('sort_order');
      
      if (mounted) {
        setState(() {
          _menuStructure = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Menu Loading Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _getIcon(String name) {
    switch (name) {
      case 'person_add_alt_1_rounded': return Icons.person_add_alt_1_rounded;
      case 'analytics_rounded': return Icons.analytics_rounded;
      case 'settings_suggest_rounded': return Icons.settings_suggest_rounded;
      case 'forum_rounded': return Icons.forum_rounded;
      case 'play_circle_fill_rounded': return Icons.play_circle_fill_rounded;
      case 'assignment_rounded': return Icons.assignment_rounded;
      case 'table_view_rounded': return Icons.table_view_rounded;
      case 'description_rounded': return Icons.description_rounded;
      case 'present_to_all_rounded': return Icons.present_to_all_rounded;
      default: return Icons.apps_rounded;
    }
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 900;
    const primaryPurple = Color(0xFF4A148C); 

    return Drawer(
      width: width,
      child: Scaffold(
        backgroundColor: const Color(0xFFFBFBFE),
        body: Column(
          children: [
            // 1. FULLY CENTERED PREMIUM HEADER
            _buildCenteredHeader(context, isDesktop, primaryPurple),
            
            Expanded(
              child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: primaryPurple))
              : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? width * 0.15 : 20,
                  vertical: 20
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._menuStructure.map((section) {
                      List<dynamic> items = List.from(section['drawer_items']);

                      if (_accountType != 'Worker') {
                        items = items.where((i) => i['worker_only'] == false).toList();
                      }
                      items.sort((a, b) => (a['sort_order'] ?? 0).compareTo(b['sort_order'] ?? 0));

                      if (items.isEmpty) return const SizedBox();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader(section['title']),
                          const SizedBox(height: 8),
                          _buildResponsiveGrid(context, items, isDesktop, primaryPurple),
                          const SizedBox(height: 25),
                        ],
                      );
                    }),

                    const SizedBox(height: 30),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
                        label: Text("Close Dashboard", 
                          style: GoogleFonts.merriweather(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- HEADER: SIDE-BY-SIDE LAYOUT WITH UPDATED POPUP MENU ---
  Widget _buildCenteredHeader(BuildContext context, bool isDesktop, Color p1) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(25, isDesktop ? 40 : 35, 25, 25), 
      decoration: BoxDecoration(
        color: p1,
        borderRadius: const BorderRadius.only(
            bottomRight: Radius.circular(50), bottomLeft: Radius.circular(50)),
        boxShadow: [
          BoxShadow(
              color: p1.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 10))
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: isDesktop ? 45 : 38,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    child: const Icon(Icons.person_rounded, size: 40, color: Colors.white),
                  ),
                  const SizedBox(width: 25),
                  
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fullName,
                          style: GoogleFonts.merriweather(
                              color: Colors.white,
                              fontSize: isDesktop ? 26 : 22,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text("@${_userName.toLowerCase()} • $_phoneNumber",
                          style: GoogleFonts.merriweather(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w400)),
                      Text(_email,
                          style: GoogleFonts.merriweather(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w400)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.orangeAccent,
                            borderRadius: BorderRadius.circular(15)),
                        child: Text(
                            "${_toTitleCase(_accountType)}: ${_toTitleCase(_currentRole.replaceAll('_', ' '))}",
                            style: GoogleFonts.merriweather(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // TOP RIGHT OPTIONS MENU (WITH ADD ACCOUNT)
            Positioned(
              right: 0,
              top: 0,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                onSelected: (val) => _handleMenuAction(val),
                itemBuilder: (context) => [
                  _popItem(Icons.account_circle_outlined, "View Profile", 'profile'),
                  _popItem(Icons.switch_account_outlined, "Switch Account", 'switch'),
                  _popItem(Icons.person_add_alt_1_outlined, "Add Account", 'add_account'),
                  const PopupMenuDivider(height: 8),
                  _popItem(Icons.light_mode_outlined, "Light Theme", 'light'),
                  _popItem(Icons.dark_mode_outlined, "Dark Theme", 'dark'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _popItem(IconData icon, String label, String val) {
    return PopupMenuItem(
      value: val,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(children: [
        Icon(icon, size: 17, color: const Color(0xFF4A148C)),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w600))
      ]),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        _toTitleCase(title), 
        style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blueGrey[900]),
      ),
    );
  }

  Widget _buildResponsiveGrid(BuildContext context, List<dynamic> items, bool isDesktop, Color pColor) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(), // FIXED: NeverScrollableScrollPhysics
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 3 : 1,
        mainAxisSpacing: 10,
        crossAxisSpacing: 12,
        childAspectRatio: isDesktop ? 7.5 : 10.0, 
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: () { Navigator.pop(context); widget.onNavigate(item['navigation_key']); },
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(15), 
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))], 
              border: Border.all(color: Colors.black.withValues(alpha: 0.05))
            ),
            child: Row(children: [
              Icon(_getIcon(item['icon_name']), color: pColor, size: 22),
              const SizedBox(width: 18), 
              Expanded(
                child: Text(_toTitleCase(item['label']), 
                  style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87))
              ), 
              const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.black12)
            ]),
          ),
        );
      },
    );
  }

  // ==========================================
  // LOGIC: MENU ACTIONS
  // ==========================================

  void _handleMenuAction(String action) {
    if (action == 'profile') {
      _showProfileDetails();
    } else if (action == 'switch') {
      _showSwitchAccountDialog(context);
    } else if (action == 'add_account') {
      _showAddAccountDialog(context);
    } else if (action == 'light') {
      themeNotifier.value = ThemeMode.light;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Light theme enabled"))
      );
    } else if (action == 'dark') {
      themeNotifier.value = ThemeMode.dark;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Dark theme enabled"))
      );
    }
  }

  void _showProfileDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 25),
            Text("Account Dossier", style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.w900, color: const Color(0xFF4A148C))),
            const Divider(height: 40),
            _dossierRow("Full name", _fullName),
            _dossierRow("Contact", _phoneNumber.isNotEmpty ? _phoneNumber : "Not Set"),
            _dossierRow("Username", _userName.isNotEmpty ? _userName : "Not Set"),
            _dossierRow("Email", _email),
            _dossierRow("Duty", _currentRole.replaceAll('_', ' ')),
            _dossierRow("Bio", "Master Administration Official User"),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: Text("Done", style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _dossierRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: Text(label, style: GoogleFonts.merriweather(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.bold))),
        Expanded(child: Text(_toTitleCase(value), style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87))),
      ],
    ),
  );

  // --- SWITCH ACCOUNT DIALOG ---
  void _showSwitchAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFFFBFBFE),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Switch account", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18)),
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20, color: Color(0xFF4A148C)),
              tooltip: "Add Account",
              onPressed: () {
                Navigator.pop(dialogCtx);
                _showAddAccountDialog(context);
              },
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: widget.otherAccounts.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text("No other accounts registered on this device.", 
                      style: GoogleFonts.merriweather(fontSize: 13, color: Colors.grey)),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true, 
                  itemCount: widget.otherAccounts.length, 
                  itemBuilder: (context, index) {
                    final acc = widget.otherAccounts[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF4A148C), 
                        child: Text(acc.fullName.isNotEmpty ? acc.fullName[0].toUpperCase() : "U", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                      ), 
                      title: Text(acc.fullName, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 16)), 
                      subtitle: Text(acc.email, style: GoogleFonts.merriweather(fontSize: 13)),
                      onTap: () async { 
                        Navigator.pop(dialogCtx);
                        if (!mounted) return;
                        Navigator.pop(context);
                        await widget.onSwitchAccount(acc);
                      }
                    );
                  }
                ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _showAddAccountDialog(context);
            },
            icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF4A148C)),
            label: Text("Add Account", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: const Color(0xFF4A148C))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx), 
            child: Text("Close", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ADD EXISTING ACCOUNT DIALOG
  // ==========================================
  void _showAddAccountDialog(BuildContext context) {
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool obscurePassword = true;
    bool isVerifying = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFFBFBFE),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A148C).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF4A148C), size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                "Add Account",
                style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18, color: const Color(0xFF4A148C)),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Sign in to an existing account to access it on this device without logging out your current session.",
                    style: GoogleFonts.merriweather(fontSize: 12, color: Colors.blueGrey[700], height: 1.4),
                  ),
                  const SizedBox(height: 18),

                  // Email Input
                  Text("Email Address", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.merriweather(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "example@domain.com",
                      hintStyle: GoogleFonts.merriweather(fontSize: 12, color: Colors.grey),
                      prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18, color: Color(0xFF4A148C)),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A148C), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Password Input
                  Text("Password", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscurePassword,
                    style: GoogleFonts.merriweather(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Enter account password",
                      hintStyle: GoogleFonts.merriweather(fontSize: 12, color: Colors.grey),
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF4A148C)),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: Colors.grey),
                        onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A148C), width: 1.5)),
                    ),
                  ),

                  // Error notification if any
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, size: 16, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: GoogleFonts.merriweather(fontSize: 11, color: Colors.red.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isVerifying ? null : () => Navigator.pop(dialogCtx),
              child: Text("Cancel", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A148C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: isVerifying ? null : () async {
                final email = emailCtrl.text.trim();
                final password = passwordCtrl.text.trim();

                if (email.isEmpty || password.isEmpty) {
                  setDialogState(() => errorMessage = "Please enter both email and password.");
                  return;
                }

                setDialogState(() {
                  isVerifying = true;
                  errorMessage = null;
                });

                try {
                  // 1. Check if the account exists in Supabase profiles
                  final profileCheck = await _supabase
                      .from('profiles')
                      .select('id, full_name, email, role, account_type, username, phone')
                      .eq('email', email)
                      .maybeSingle();

                  if (profileCheck == null) {
                    // User does NOT exist in Supabase
                    if (mounted) {
                      Navigator.pop(dialogCtx);
                      _showAccountNotFoundDialog(context, email);
                    }
                    return;
                  }

                 // 2. Authenticate the account with Supabase Auth
                  final authRes = await _supabase.auth.signInWithPassword(
                    email: email,
                    password: password,
                  );

                  final user = authRes.user;
                  if (user != null) {
                    // 3. Construct UserAccount object FIRST
                    final loadedAccount = UserAccount(
                      fullName: profileCheck['full_name'] ?? "User",
                      userName: profileCheck['username'] ?? "user",
                      phoneNumber: profileCheck['phone'] ?? "Not set",
                      email: profileCheck['email'] ?? email,
                      role: profileCheck['role'] ?? "Member",
                      accountType: profileCheck['account_type'] ?? "Saint",
                    );

                    // 4. Save to SharedPreferences (ONCE) and set active
                    final prefs = await SharedPreferences.getInstance();
                    List<String> savedIds = prefs.getStringList('device_account_ids') ?? [];
                    if (!savedIds.contains(user.id)) {
                      savedIds.add(user.id);
                      await prefs.setStringList('device_account_ids', savedIds);
                    }
                    await prefs.setString('active_account_email', loadedAccount.email);

                    if (mounted) {
                      Navigator.pop(dialogCtx); // Close dialog
                      Navigator.pop(context);   // Close drawer
                      await widget.onSwitchAccount(loadedAccount);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Account for ${loadedAccount.fullName} loaded successfully!",
                            style: GoogleFonts.merriweather(),
                          ),
                          backgroundColor: const Color(0xFF4A148C),
                        ),
                      );
                    }
                  }
                } on AuthException catch (e) {
                  setDialogState(() {
                    isVerifying = false;
                    errorMessage = e.message.contains("Invalid login credentials")
                        ? "Incorrect password for this account. Please try again."
                        : e.message;
                  });
                } catch (e) {
                  setDialogState(() {
                    isVerifying = false;
                    errorMessage = "Failed to load account: $e";
                  });
                }
              },
              child: isVerifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text("Confirm & Load", style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ACCOUNT NOT FOUND PROMPT DIALOG
  // ==========================================
  void _showAccountNotFoundDialog(BuildContext context, String enteredEmail) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFBFBFE),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.person_off_rounded, color: Colors.orange, size: 24),
            const SizedBox(width: 10),
            Text(
              "Account Not Found",
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: const Color(0xFF4A148C)),
            ),
          ],
        ),
        content: Text(
          "No registered account was found with the email \"$enteredEmail\".\n\nWould you like to register and create a new account now?",
          style: GoogleFonts.merriweather(fontSize: 13, height: 1.5, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Not Now", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A148C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);      // Close alert dialog
              Navigator.pop(context);  // Close drawer
              widget.onNavigate('registration'); // Navigate to AddAccountScreen
            },
            child: Text(
              "Create Account",
              style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}