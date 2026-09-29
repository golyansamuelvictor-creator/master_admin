// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsScreen extends StatefulWidget {
  final String userEmail, userRole;
  const SettingsScreen({super.key, required this.userEmail, required this.userRole});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? selectedCategory;
  final Color pPurple = const Color(0xFF4A148C);
  final _supabase = Supabase.instance.client;

  final Map<String, List<String>> settingsData = {
    "My Account": ["Profile Information", "Change Password", "Manage Devices", "Account Verification", "signout/logout"],
    "Notifications & Sounds": ["Push Notifications", "Email Notifications", "In-App Sounds", "Notification Preferences"],
    "Privacy & Security": ["Password & Security", "2-Step Verification", "Data Encryption", "Location Sharing", "App Lock"],
    "Language": ["English", "Korean", "Spanish", "French", "Arabic", "Mandarin", "Swahili", "Portuguese"],
    "Feedback": ["Send Feedback", "Report a Bug", "Suggest a Feature"],
  };

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFE),
      appBar: AppBar(
        title: Text(selectedCategory ?? "System Settings",
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: isDesktop ? 26 : 22, color: pPurple)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () {
              if (selectedCategory != null) setState(() => selectedCategory = null);
              else Navigator.pop(context);
            }),
      ),
      body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: selectedCategory == null ? _buildMainGrid(isDesktop, width) : _buildSubList(isDesktop, width)),
    );
  }

  Widget _buildMainGrid(bool isDesktop, double width) {
    return ListView(
      padding: EdgeInsets.symmetric(vertical: 15, horizontal: isDesktop ? width * 0.2 : 20),
      children: [
        _buildCenteredHeader(isDesktop),
        const SizedBox(height: 15),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: settingsData.keys.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isDesktop ? 3 : 1,
            mainAxisSpacing: 6,
            crossAxisSpacing: 8,
            childAspectRatio: isDesktop ? 5.5 : 7.5,
          ),
          itemBuilder: (context, index) {
            String cat = settingsData.keys.elementAt(index);
            return _buildUniformCard(cat, isDesktop, () => setState(() => selectedCategory = cat));
          },
        ),
      ],
    );
  }

  Widget _buildSubList(bool isDesktop, double width) {
    List<String> items = settingsData[selectedCategory]!;
    return ListView(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: isDesktop ? width * 0.25 : 20),
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _buildUniformCard(item, isDesktop, () => _handleAction(item)),
      )).toList(),
    );
  }

  Widget _buildUniformCard(String title, bool isDesktop, VoidCallback onTap) {
    bool isLogout = title == "signout/logout";
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isLogout ? Colors.red.withValues(alpha: 0.3) : Colors.purple.withValues(alpha: 0.1), width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))]),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: GoogleFonts.merriweather(fontSize: isDesktop ? 15 : 14, fontWeight: FontWeight.w700, color: isLogout ? Colors.red : Colors.black87)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, size: 12, color: isLogout ? Colors.red : Colors.grey.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenteredHeader(bool isDesktop) {
    String initials = widget.userEmail.isNotEmpty ? widget.userEmail[0].toUpperCase() : "?";
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: pPurple.withValues(alpha: 0.1))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(radius: 25, backgroundColor: pPurple.withValues(alpha: 0.1), child: Text(initials, style: TextStyle(fontWeight: FontWeight.bold, color: pPurple, fontSize: 20))),
          const SizedBox(height: 12),
          Text(widget.userEmail, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: isDesktop ? 18 : 15)),
          Text("Official Role: ${_formatRoleToTitleCase(widget.userRole)}", textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueGrey, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatRoleToTitleCase(String? role) => (role ?? "").replaceAll('_', ' ').toUpperCase();

  void _handleAction(String item) async {
    if (item == "signout/logout") {
      await _supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => SubItemDetailScreen(
        title: item,
        category: selectedCategory!,
        userEmail: widget.userEmail,
        supabase: _supabase,
        pPurple: pPurple,
      ),
    ));
  }
}

// ==========================================
// COMPACT & FLOATING DETAIL SCREEN
// ==========================================

class SubItemDetailScreen extends StatefulWidget {
  final String title, category, userEmail;
  final SupabaseClient supabase;
  final Color pPurple;

  const SubItemDetailScreen({super.key, required this.title, required this.category, required this.userEmail, required this.supabase, required this.pPurple});

  @override
  State<SubItemDetailScreen> createState() => _SubItemDetailScreenState();
}

class _SubItemDetailScreenState extends State<SubItemDetailScreen> {
  final List<String> soundsList = ["Default Chime", "Crystal Wave", "Electronic Chirp", "Simple Ping"];
  final _oldPw = TextEditingController(), _newPw = TextEditingController(), _confPw = TextEditingController();

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    bool isDesktop = screenWidth > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9), // Subtly darker to emphasize floating cards
      appBar: AppBar(
        title: Text(widget.title, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.bold, color: widget.pPurple)),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        elevation: 0.5,
        centerTitle: true,
        backgroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min, // Squeeze column to content
            children: [
              const SizedBox(height: 30),
              // Main Card (Wider by 25% on desktop: 750px)
              Container(
                width: isDesktop ? 750 : screenWidth * 0.95,
                padding: const EdgeInsets.symmetric(vertical: 20), // Tighter padding
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 25, offset: const Offset(0, 10))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // Ensures card doesn't stretch to full screen height
                  children: [
                    // Sub Card covering 3/4 width
                    FractionallySizedBox(
                      widthFactor: 0.75,
                      child: Container(
                        padding: const EdgeInsets.all(10), // Tighter internal padding
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: widget.pPurple.withValues(alpha: 0.05)),
                        ),
                        child: _buildBody(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text("System Settings v1.0", style: TextStyle(color: Colors.grey.shade400, fontSize: 9)),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (widget.title) {
      case "Profile Information": return _buildProfileView();
      case "Change Password": return _buildPasswordView();
      case "Manage Devices": return _buildDevicesView();
      case "Account Verification": return _buildVerificationView();
      case "Push Notifications": return _buildNotificationSoundView('push');
      case "Email Notifications": return _buildNotificationSoundView('email');
      case "In-App Sounds": return _buildNotificationSoundView('in_app');
      case "Notification Preferences": return _buildNotificationPrefs();
      default: return Center(child: Text("Details for ${widget.title} coming soon."));
    }
  }

  Widget _buildProfileView() {
    return FutureBuilder(
      future: widget.supabase.from('profiles').select().eq('email', widget.userEmail).single(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
        final data = snapshot.data ?? {};
        return Column(
          children: [
            _profileField("Full Name", data['full_name']),
            _profileField("Username", data['username']),
            _profileField("Scj ID", data['scj_id'] ?? data['id_number']),
            _profileField("Location", data['location']),
            _profileField("Cell Unit", data['team'] ?? data['cell_unit']),
            _profileField("Email", widget.userEmail),
            _profileField("Phone", data['phone'], isLast: true),
          ],
        );
      },
    );
  }

  Widget _buildPasswordView() {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          TextField(controller: _oldPw, decoration: const InputDecoration(labelText: "Old Password", isDense: true)),
          const SizedBox(height: 8),
          TextField(controller: _newPw, decoration: const InputDecoration(labelText: "New Password", isDense: true)),
          const SizedBox(height: 8),
          TextField(controller: _confPw, decoration: const InputDecoration(labelText: "Confirm Password", isDense: true)),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: widget.pPurple, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              if (_newPw.text == _confPw.text) {
                await widget.supabase.auth.updateUser(UserAttributes(password: _newPw.text));
                if (!mounted) return;
                Navigator.pop(context);
              }
            },
            child: const Text("Update Password", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildDevicesView() {
    return Column(
      children: [
        _compactRow(Icons.phone_android, "This Phone", "Active Now"),
        _compactRow(Icons.laptop, "Desktop", "2h ago", isLast: true),
      ],
    );
  }

  Widget _buildVerificationView() {
    final user = widget.supabase.auth.currentUser;
    bool isVer = user?.emailConfirmedAt != null;
    return Column(
      children: [
        const SizedBox(height: 10),
        Icon(isVer ? Icons.verified : Icons.error_outline, size: 50, color: isVer ? Colors.green : Colors.orange),
        const SizedBox(height: 8),
        Text(isVer ? "Verified" : "Pending", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildNotificationSoundView(String type) {
    final userId = widget.supabase.auth.currentUser?.id;
    return FutureBuilder(
      future: widget.supabase.from('user_settings').select().eq('user_id', userId ?? '').maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data ?? {};
        bool enabled = data['${type}_enabled'] ?? true;
        String currentSound = data['${type}_sound'] ?? 'Default Chime';
        return Column(
          children: [
            SwitchListTile(
              dense: true,
              title: const Text("Enabled", style: TextStyle(fontWeight: FontWeight.bold)),
              value: enabled,
              activeColor: widget.pPurple,
              onChanged: (val) async {
                await widget.supabase.from('user_settings').upsert({'user_id': userId, '${type}_enabled': val});
                if (!mounted) return;
                setState(() {});
              },
            ),
            const Divider(height: 1),
            ...soundsList.map((s) => RadioListTile<String>(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(s, style: const TextStyle(fontSize: 14)),
              value: s,
              groupValue: currentSound,
              onChanged: enabled ? (val) async {
                await widget.supabase.from('user_settings').upsert({'user_id': userId, '${type}_sound': val});
                if (!mounted) return;
                setState(() {});
              } : null,
            )),
          ],
        );
      },
    );
  }

  Widget _buildNotificationPrefs() {
    final userId = widget.supabase.auth.currentUser?.id;
    return FutureBuilder(
      future: widget.supabase.from('user_settings').select().eq('user_id', userId ?? '').maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data ?? {};
        return Column(
          children: [
            _compactPref(userId, "Home Alerts", data['home_notifications'] ?? true, 'home_notifications'),
            _compactPref(userId, "Reports", data['report_notifications'] ?? true, 'report_notifications', isLast: true),
          ],
        );
      },
    );
  }

  // --- HELPERS (25% REDUCED HEIGHT) ---

  Widget _profileField(String label, String? value, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12), // Reduced height from 12 to 7
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1), width: 1)),
      ),
      child: Row(
        children: [
          Text("$label: ", style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          Expanded(
            child: Text(value ?? "N/A", 
              textAlign: TextAlign.right,
              style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _compactRow(IconData icon, String title, String subtitle, {bool isLast = false}) => Container(
    decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)))),
    child: ListTile(
      dense: true,
      leading: Icon(icon, color: widget.pPurple, size: 20),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      trailing: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ),
  );

  Widget _compactPref(String? id, String label, bool val, String key, {bool isLast = false}) => Container(
    decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)))),
    child: CheckboxListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      value: val,
      activeColor: widget.pPurple,
      onChanged: (v) async {
        await widget.supabase.from('user_settings').upsert({'user_id': id, key: v});
        if (!mounted) return;
        setState(() {});
      },
    ),
  );
}