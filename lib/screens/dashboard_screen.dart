// ignore_for_file: depend_on_referenced_packages, use_build_context_synchronously, unused_element, curly_braces_in_flow_control_structures
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart';
import 'add_account_screen.dart';
import 'package:master_admin/core/app_palette.dart';

// PRESERVED: UserAccount Model
class UserAccount {
  final String fullName, userName, phoneNumber, email, role, accountType;
  final String id; // auth user id ('' when unknown)
  UserAccount({
    this.id = '',
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

  // Local state to store live profile values
  late String _fullName;
  late String _userName;
  late String _phoneNumber;
  late String _email;
  late String _currentRole;
  late String _accountType;
  String? _avatarUrl;
  String _bio = "Master Administration Official User";

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

  // ==========================================
  // FETCH LIVE PROFILE (SAFE SELECT * QUERY)
  // ==========================================
  Future<void> _fetchLiveProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      Map<String, dynamic>? res;

      // 1. Primary lookup by user ID
      if (user != null) {
        res = await _supabase
            .from('profiles')
            .select('*')
            .eq('id', user.id)
            .maybeSingle();
      }

      // 2. Fallback to case-insensitive email if ID lookup returns null
      if (res == null && widget.email.isNotEmpty) {
        res = await _supabase
            .from('profiles')
            .select('*')
            .ilike('email', widget.email.trim())
            .maybeSingle();
      }

      if (res != null && mounted) {
        setState(() {
          // full_name
          if (res!['full_name'] != null && res['full_name'].toString().trim().isNotEmpty) {
            _fullName = res['full_name'].toString().trim();
          }

          // username (matches Supabase column strictly)
          if (res['username'] != null && res['username'].toString().trim().isNotEmpty) {
            _userName = res['username'].toString().trim();
          }

          // phone
          if (res['phone'] != null && res['phone'].toString().trim().isNotEmpty) {
            _phoneNumber = res['phone'].toString().trim();
          }

          // email
          if (res['email'] != null && res['email'].toString().trim().isNotEmpty) {
            _email = res['email'].toString().trim();
          }

          // role & account_type
          if (res['role'] != null) _currentRole = res['role'].toString();
          if (res['account_type'] != null) _accountType = res['account_type'].toString();

          // avatar_url & bio
          if (res['avatar_url'] != null && res['avatar_url'].toString().trim().isNotEmpty) {
            _avatarUrl = res['avatar_url'].toString().trim();
          }
          if (res['bio'] != null && res['bio'].toString().trim().isNotEmpty) {
            _bio = res['bio'].toString().trim();
          }
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
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        body: Column(
          children: [
            // Centered Profile Header
            _buildCenteredHeader(context, isDesktop, primaryPurple),
            
            Expanded(
              child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: primaryPurple))
              : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? width * 0.15 : 18,
                  vertical: 18
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
                          const SizedBox(height: 20),
                        ],
                      );
                    }),

                    const SizedBox(height: 14),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, color: AppPalette.fg(Colors.grey), size: 18),
                        label: Text(
                          "Close Dashboard", 
                          style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey), fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 35),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- CENTER-ALIGNED PROFILE HEADER ---
  Widget _buildCenteredHeader(BuildContext context, bool isDesktop, Color p1) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, isDesktop ? 30 : 20, 16, 22), 
      decoration: BoxDecoration(
        color: AppPalette.bg(p1),
        borderRadius: const BorderRadius.only(
          bottomRight: Radius.circular(40), 
          bottomLeft: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(
            color: p1.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Tap avatar to open Edit Profile
                    GestureDetector(
                      onTap: _showEditProfileModal,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: isDesktop ? 38 : 32,
                            backgroundColor: AppPalette.bg(Colors.white.withValues(alpha: 0.2)),
                            backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                                ? NetworkImage(_avatarUrl!)
                                : null,
                            child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                                ? Icon(Icons.person_rounded, size: isDesktop ? 38 : 30, color: AppPalette.fg(Colors.white))
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppPalette.bg(Colors.orangeAccent),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppPalette.line(p1), width: 2),
                            ),
                            child: Icon(Icons.camera_alt_rounded, size: 12, color: AppPalette.fg(Colors.black87)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Full Name
                    Text(
                      _fullName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.merriweather(
                        color: AppPalette.fg(Colors.white),
                        fontSize: isDesktop ? 22 : 17,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),

                    // Username & Phone
                    Text(
                      "@${_userName.toLowerCase()} • $_phoneNumber",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.merriweather(
                        color: AppPalette.fg(Colors.white70),
                        fontSize: isDesktop ? 12.5 : 11,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),

                    // Email
                    Text(
                      _email,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.merriweather(
                        color: AppPalette.fg(Colors.white60),
                        fontSize: isDesktop ? 12 : 10.5,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Role Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppPalette.bg(Colors.orangeAccent),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${_toTitleCase(_accountType)}: ${_toTitleCase(_currentRole.replaceAll('_', ' '))}",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.merriweather(
                          color: AppPalette.fg(Colors.black),
                          fontSize: isDesktop ? 10 : 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Top-Right 3-Dotted Menu
            Positioned(
              top: 0,
              right: 0,
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: AppPalette.fg(Colors.white70), size: 24),
                splashRadius: 20,
                onSelected: (val) => _handleMenuAction(val),
                itemBuilder: (context) => [
                  _popItem(Icons.account_circle_outlined, "View Profile", 'profile'),
                  _popItem(Icons.edit_outlined, "Edit Profile", 'edit_profile'),
                  _popItem(Icons.switch_account_outlined, "Switch Account", 'switch'),
                  _popItem(Icons.person_add_alt_1_outlined, "Add Account", 'add_account'),
                  const PopupMenuDivider(height: 8),
                  _popItem(Icons.brightness_auto_outlined, "System Theme${themeNotifier.value == ThemeMode.system ? '  ✓' : ''}", 'system'),
                  _popItem(Icons.light_mode_outlined, "Light Theme${themeNotifier.value == ThemeMode.light ? '  ✓' : ''}", 'light'),
                  _popItem(Icons.dark_mode_outlined, "Dark Theme${themeNotifier.value == ThemeMode.dark ? '  ✓' : ''}", 'dark'),
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
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(children: [
        Icon(icon, size: 17, color: AppPalette.fg(const Color(0xFF4A148C))),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        _toTitleCase(title), 
        style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.w900, color: AppPalette.fg(Colors.blueGrey[900])),
      ),
    );
  }

  Widget _buildResponsiveGrid(BuildContext context, List<dynamic> items, bool isDesktop, Color pColor) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 3 : 1,
        mainAxisSpacing: 10,
        crossAxisSpacing: 12,
        childAspectRatio: isDesktop ? 7.5 : 9.5, 
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: () { 
            Navigator.pop(context); 
            widget.onNavigate(item['navigation_key']); 
          },
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: AppPalette.bg(Colors.white), 
              borderRadius: BorderRadius.circular(15), 
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03), 
                  blurRadius: 8, 
                  offset: const Offset(0, 3),
                ),
              ], 
              border: Border.all(color: AppPalette.line(Colors.black.withValues(alpha: 0.05))),
            ),
            child: Row(children: [
              Icon(_getIcon(item['icon_name']), color: AppPalette.fg(pColor), size: 20),
              const SizedBox(width: 16), 
              Expanded(
                child: Text(
                  _toTitleCase(item['label']), 
                  style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14, color: AppPalette.fg(Colors.black87)),
                ),
              ), 
              Icon(Icons.chevron_right_rounded, size: 18, color: AppPalette.fg(Colors.black26)),
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
    } else if (action == 'edit_profile') {
      _showEditProfileModal();
    } else if (action == 'switch') {
      _showSwitchAccountDialog(context);
    } else if (action == 'add_account') {
      _showAddAccountDialog(context);
    } else if (action == 'system' || action == 'light' || action == 'dark') {
      // Applied app-wide and remembered on this device
      final mode = action == 'system' ? ThemeMode.system : (action == 'dark' ? ThemeMode.dark : ThemeMode.light);
      setAppThemeMode(mode);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(action == 'system'
            ? "Theme follows this device's setting"
            : (action == 'dark' ? "Dark theme enabled" : "Light theme enabled")),
      ));
    }
  }

  // ==========================================
  // EDIT PROFILE MODAL (WITH GALLERY UPLOAD)
  // ==========================================
  void _showEditProfileModal() {
    final nameCtrl = TextEditingController(text: _fullName);
    final userCtrl = TextEditingController(text: _userName);
    final phoneCtrl = TextEditingController(text: _phoneNumber);
    final bioCtrl = TextEditingController(text: _bio);
    final avatarCtrl = TextEditingController(text: _avatarUrl ?? '');

    bool isSaving = false;
    bool isUploadingImage = false;
    String? errorText;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          // Picks an image from phone gallery and uploads it to Supabase Storage 'avatars' bucket
          Future<void> pickAndUploadImage() async {
            try {
              final picker = ImagePicker();
              final XFile? pickedFile = await picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 800,
                maxHeight: 800,
                imageQuality: 85,
              );

              if (pickedFile == null) return;

              setModalState(() {
                isUploadingImage = true;
                errorText = null;
              });

              final user = _supabase.auth.currentUser;
              final uid = user?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
              final fileExt = pickedFile.name.split('.').last.toLowerCase();
              // profile-photos only accepts files inside the user's own folder (<uid>/...)
              final fileName = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
              final contentType = (fileExt == 'jpg' || fileExt == 'jpeg') ? 'image/jpeg' : 'image/$fileExt';

              final imageBytes = await pickedFile.readAsBytes();

              await _supabase.storage.from('profile-photos').uploadBinary(
                fileName,
                imageBytes,
                fileOptions: FileOptions(contentType: contentType, upsert: true),
              );

              final publicUrl = _supabase.storage.from('profile-photos').getPublicUrl(fileName);

              setModalState(() {
                avatarCtrl.text = publicUrl;
                isUploadingImage = false;
              });
            } catch (e) {
              setModalState(() {
                isUploadingImage = false;
                errorText = "Gallery upload error: $e";
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(color: AppPalette.bg(Colors.grey[300]), borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      "Edit Profile",
                      style: GoogleFonts.merriweather(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.fg(const Color(0xFF4A148C)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Avatar preview with Gallery Upload action
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: isUploadingImage ? null : pickAndUploadImage,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 38,
                                backgroundColor: AppPalette.bg(const Color(0xFF4A148C).withValues(alpha: 0.1)),
                                backgroundImage: avatarCtrl.text.trim().isNotEmpty
                                    ? NetworkImage(avatarCtrl.text.trim())
                                    : (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                                        ? NetworkImage(_avatarUrl!)
                                        : null,
                                child: isUploadingImage
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4A148C)),
                                      )
                                    : (avatarCtrl.text.trim().isEmpty && (_avatarUrl == null || _avatarUrl!.isEmpty))
                                        ? Icon(Icons.person_rounded, size: 38, color: AppPalette.fg(Color(0xFF4A148C)))
                                        : null,
                              ),
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(color: AppPalette.bg(Color(0xFF4A148C)), shape: BoxShape.circle),
                                child: Icon(Icons.camera_alt_rounded, size: 14, color: AppPalette.fg(Colors.white)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: isUploadingImage ? null : pickAndUploadImage,
                          icon: Icon(Icons.photo_library_outlined, size: 16, color: AppPalette.fg(Color(0xFF4A148C))),
                          label: Text(
                            isUploadingImage ? "Uploading Photo..." : "Choose from Gallery",
                            style: GoogleFonts.merriweather(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppPalette.fg(const Color(0xFF4A148C)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  _editFieldLabel("Profile Picture URL"),
                  TextField(
                    controller: avatarCtrl,
                    style: GoogleFonts.merriweather(fontSize: 13),
                    onChanged: (_) => setModalState(() {}),
                    decoration: _editInputDecoration("https://... or choose from gallery above", Icons.image_outlined),
                  ),
                  const SizedBox(height: 12),

                  _editFieldLabel("Full / Display Name"),
                  TextField(
                    controller: nameCtrl,
                    style: GoogleFonts.merriweather(fontSize: 13),
                    decoration: _editInputDecoration("e.g. John Doe", Icons.badge_outlined),
                  ),
                  const SizedBox(height: 12),

                  _editFieldLabel("Username"),
                  TextField(
                    controller: userCtrl,
                    style: GoogleFonts.merriweather(fontSize: 13),
                    decoration: _editInputDecoration("e.g. johndoe", Icons.alternate_email_rounded),
                  ),
                  const SizedBox(height: 12),

                  _editFieldLabel("Phone Number"),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.merriweather(fontSize: 13),
                    decoration: _editInputDecoration("e.g. +256 700 000000", Icons.phone_outlined),
                  ),
                  const SizedBox(height: 12),

                  _editFieldLabel("Bio / Status"),
                  TextField(
                    controller: bioCtrl,
                    maxLines: 2,
                    style: GoogleFonts.merriweather(fontSize: 13),
                    decoration: _editInputDecoration("Brief note about your role or duty", Icons.notes_rounded),
                  ),
                  const SizedBox(height: 14),

                  if (errorText != null) ...[
                    Text(
                      errorText!,
                      style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.red.shade800), fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isSaving ? null : () => Navigator.pop(modalCtx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text("Cancel", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.grey[700]))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.bg(const Color(0xFF4A148C)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final newName = nameCtrl.text.trim();
                                  final newUsername = userCtrl.text.trim();
                                  final newPhone = phoneCtrl.text.trim();
                                  final newBio = bioCtrl.text.trim();
                                  final newAvatar = avatarCtrl.text.trim();

                                  if (newName.isEmpty) {
                                    setModalState(() => errorText = "Full name cannot be empty.");
                                    return;
                                  }

                                  setModalState(() {
                                    isSaving = true;
                                    errorText = null;
                                  });

                                  try {
                                    final user = _supabase.auth.currentUser;
                                    
                                    // Strictly updates profiles table columns
                                    final updateData = {
                                      'full_name': newName,
                                      'username': newUsername,
                                      'phone': newPhone,
                                      'bio': newBio,
                                      if (newAvatar.isNotEmpty) 'avatar_url': newAvatar,
                                      'updated_at': DateTime.now().toIso8601String(),
                                    };

                                    if (user != null) {
                                      await _supabase.from('profiles').update(updateData).eq('id', user.id);
                                    } else {
                                      await _supabase.from('profiles').update(updateData).ilike('email', _email.trim());
                                    }

                                    if (mounted) {
                                      setState(() {
                                        _fullName = newName;
                                        _userName = newUsername;
                                        _phoneNumber = newPhone;
                                        _bio = newBio;
                                        if (newAvatar.isNotEmpty) _avatarUrl = newAvatar;
                                      });
                                    }

                                    Navigator.pop(modalCtx);

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Profile updated successfully!"),
                                        backgroundColor: Color(0xFF4A148C),
                                      ),
                                    );
                                  } catch (e) {
                                    setModalState(() {
                                      isSaving = false;
                                      errorText = "Failed to update profile: $e";
                                    });
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text("Save Changes", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _editFieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          label,
          style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey[800])),
        ),
      );

  InputDecoration _editInputDecoration(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey)),
        prefixIcon: Icon(icon, size: 18, color: AppPalette.fg(const Color(0xFF4A148C))),
        filled: true,
        fillColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Color(0xFF4A148C)), width: 1.5)),
      );

  // --- VIEW PROFILE DOSSIER ---
  void _showProfileDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: AppPalette.bg(Colors.grey[300]), borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 22),
            Text("Account Dossier", style: GoogleFonts.merriweather(fontSize: 19, fontWeight: FontWeight.w900, color: AppPalette.fg(const Color(0xFF4A148C)))),
            const Divider(height: 36),
            _dossierRow("Full name", _fullName),
            _dossierRow("Contact", _phoneNumber.isNotEmpty ? _phoneNumber : "Not Set"),
            _dossierRow("Username", _userName.isNotEmpty ? _userName : "Not Set"),
            _dossierRow("Email", _email),
            _dossierRow("Duty", _currentRole.replaceAll('_', ' ')),
            _dossierRow("Bio", _bio),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showEditProfileModal();
                    },
                    icon: Icon(Icons.edit_outlined, size: 16, color: AppPalette.fg(Color(0xFF4A148C))),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppPalette.line(Color(0xFF4A148C)), width: 1.2),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    label: Text("Edit Profile", style: GoogleFonts.merriweather(color: AppPalette.fg(const Color(0xFF4A148C)), fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.bg(const Color(0xFF4A148C)),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text("Done", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  Widget _dossierRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 95, child: Text(label, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.blueGrey), fontWeight: FontWeight.bold))),
        Expanded(child: Text(_toTitleCase(value), style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.fg(Colors.black87)))),
      ],
    ),
  );

  // --- SWITCH ACCOUNT DIALOG ---
  void _showSwitchAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Switch account", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17)),
            IconButton(
              icon: Icon(Icons.person_add_alt_1_rounded, size: 20, color: AppPalette.fg(Color(0xFF4A148C))),
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
                      style: GoogleFonts.merriweather(fontSize: 12.5, color: AppPalette.fg(Colors.grey))),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true, 
                  itemCount: widget.otherAccounts.length, 
                  itemBuilder: (context, index) {
                    final acc = widget.otherAccounts[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      leading: CircleAvatar(
                        backgroundColor: AppPalette.bg(const Color(0xFF4A148C)), 
                        child: Text(acc.fullName.isNotEmpty ? acc.fullName[0].toUpperCase() : "U", style: TextStyle(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold))
                      ), 
                      title: Text(acc.fullName, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14)), 
                      subtitle: Text(acc.email, style: GoogleFonts.merriweather(fontSize: 12)),
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
            icon: Icon(Icons.add_rounded, size: 16, color: AppPalette.fg(Color(0xFF4A148C))),
            label: Text("Add Account", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(const Color(0xFF4A148C)), fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx), 
            child: Text("Close", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.grey), fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ADD EXISTING ACCOUNT DIALOG
  // ==========================================
  /// "0772 123 456" -> "+256772123456"; "+256 772..." kept. Null if not a phone number.
  String? _normalizePhone(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.isEmpty) return null;
    if (p.startsWith('00')) p = '+${p.substring(2)}';
    if (p.startsWith('0')) p = '+256${p.substring(1)}'; // local Ugandan format
    if (!p.startsWith('+')) p = '+$p';
    return RegExp(r'^\+\d{9,15}$').hasMatch(p) ? p : null;
  }

  void _showAddAccountDialog(BuildContext context) {
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool obscurePassword = true;
    bool isVerifying = false;
    String? errorMessage;
    String method = 'email'; // 'email' | 'whatsapp' | 'google'
    final phoneCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    bool codeSent = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppPalette.bg(const Color(0xFF4A148C).withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.person_add_alt_1_rounded, color: AppPalette.fg(Color(0xFF4A148C)), size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                "Add Account",
                style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(const Color(0xFF4A148C))),
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
                    "Sign in to another account on this device. Your current account stays in Switch Account, so you can come back to it without signing in again.",
                    style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.blueGrey[700]), height: 1.4),
                  ),
                  const SizedBox(height: 16),

                  // How the account signs in
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final m in const [('email', 'Email', Icons.mail_outline_rounded), ('whatsapp', 'WhatsApp', Icons.chat_rounded), ('google', 'Google', Icons.g_mobiledata_rounded)])
                      ChoiceChip(
                        avatar: Icon(m.$3, size: 16, color: AppPalette.fg(method == m.$1 ? Colors.white : const Color(0xFF4A148C))),
                        label: Text(m.$2, style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(method == m.$1 ? Colors.white : const Color(0xFF4A148C)))),
                        selected: method == m.$1,
                        selectedColor: AppPalette.bg(const Color(0xFF4A148C)),
                        showCheckmark: false,
                        onSelected: isVerifying ? null : (_) => setDialogState(() {
                          method = m.$1;
                          errorMessage = null;
                        }),
                      ),
                  ]),
                  const SizedBox(height: 14),

                  if (method == 'email') ...[
                  Text("Email Address", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87))),
                  const SizedBox(height: 5),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.merriweather(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "example@domain.com",
                      hintStyle: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey)),
                      prefixIcon: Icon(Icons.mail_outline_rounded, size: 18, color: AppPalette.fg(Color(0xFF4A148C))),
                      filled: true,
                      fillColor: AppPalette.bg(Colors.white),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Color(0xFF4A148C)), width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text("Password", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87))),
                  const SizedBox(height: 5),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscurePassword,
                    style: GoogleFonts.merriweather(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Enter account password",
                      hintStyle: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey)),
                      prefixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: AppPalette.fg(Color(0xFF4A148C))),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18, color: AppPalette.fg(Colors.grey)),
                        onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                      ),
                      filled: true,
                      fillColor: AppPalette.bg(Colors.white),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Color(0xFF4A148C)), width: 1.5)),
                    ),
                  ),
                  ],

                  if (method == 'whatsapp') ...[
                    Text("WhatsApp number", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87))),
                    const SizedBox(height: 5),
                    TextField(
                      controller: phoneCtrl,
                      enabled: !codeSent,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.merriweather(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: "+256 7XX XXX XXX",
                        hintStyle: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey)),
                        prefixIcon: Icon(Icons.phone_android_rounded, size: 18, color: AppPalette.fg(Color(0xFF4A148C))),
                        filled: true,
                        fillColor: AppPalette.bg(Colors.white),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Color(0xFF4A148C)), width: 1.5)),
                      ),
                    ),
                    if (codeSent) ...[
                      const SizedBox(height: 12),
                      Text("6-digit code sent on WhatsApp", style: GoogleFonts.merriweather(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87))),
                      const SizedBox(height: 5),
                      TextField(
                        controller: codeCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: GoogleFonts.merriweather(fontSize: 13, letterSpacing: 4),
                        decoration: InputDecoration(
                          counterText: "",
                          hintText: "••••••",
                          prefixIcon: Icon(Icons.password_rounded, size: 18, color: AppPalette.fg(Color(0xFF4A148C))),
                          filled: true,
                          fillColor: AppPalette.bg(Colors.white),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Color(0xFF4A148C)), width: 1.5)),
                        ),
                      ),
                      TextButton(
                        onPressed: isVerifying ? null : () => setDialogState(() {
                          codeSent = false;
                          codeCtrl.clear();
                        }),
                        child: Text("Change number / resend code", style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(const Color(0xFF4A148C)))),
                      ),
                    ],
                  ],

                  if (method == 'google')
                    Text(
                      "You'll go to Google to choose the account, then come back here signed in to it.",
                      style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.blueGrey[700]), height: 1.4),
                    ),

                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppPalette.bg(Colors.red.shade50),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppPalette.line(Colors.red.shade200)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, size: 15, color: AppPalette.fg(Colors.red.shade700)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: GoogleFonts.merriweather(fontSize: 10.5, color: AppPalette.fg(Colors.red.shade900), fontWeight: FontWeight.w600),
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
              child: Text("Cancel", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.grey), fontSize: 12)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.bg(const Color(0xFF4A148C)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              ),
              onPressed: isVerifying ? null : () async {
                // ---- WhatsApp: send the code, then verify it ----
                if (method == 'whatsapp') {
                  final phone = _normalizePhone(phoneCtrl.text);
                  if (phone == null) {
                    setDialogState(() => errorMessage = "Enter the WhatsApp number with country code, e.g. +256 7XX XXX XXX.");
                    return;
                  }
                  setDialogState(() {
                    isVerifying = true;
                    errorMessage = null;
                  });
                  try {
                    if (!codeSent) {
                      await _supabase.auth.signInWithOtp(phone: phone, channel: OtpChannel.whatsapp);
                      setDialogState(() {
                        codeSent = true;
                        isVerifying = false;
                      });
                      return;
                    }
                    final code = codeCtrl.text.trim();
                    if (code.length < 6) {
                      setDialogState(() {
                        isVerifying = false;
                        errorMessage = "Enter the 6-digit code.";
                      });
                      return;
                    }
                    final res = await _supabase.auth.verifyOTP(type: OtpType.sms, token: code, phone: phone);
                    if (res.user == null) throw AuthException("Couldn't verify the code. Please try again.");
                    // The app reloads as the added account; the previous one stays in Switch Account.
                    if (mounted) {
                      Navigator.pop(dialogCtx);
                      Navigator.pop(context);
                    }
                  } on AuthException catch (e) {
                    setDialogState(() {
                      isVerifying = false;
                      errorMessage = e.message;
                    });
                  } catch (e) {
                    setDialogState(() {
                      isVerifying = false;
                      errorMessage = "Couldn't add the account. Check your connection and try again.";
                    });
                  }
                  return;
                }

                // ---- Google: choose the account on Google's page ----
                if (method == 'google') {
                  setDialogState(() {
                    isVerifying = true;
                    errorMessage = null;
                  });
                  try {
                    await _supabase.auth.signInWithOAuth(
                      OAuthProvider.google,
                      redirectTo: kIsWeb ? Uri.base.origin : 'masteradministration://login-callback',
                      queryParams: const {'prompt': 'select_account'},
                    );
                    if (mounted) Navigator.pop(dialogCtx);
                  } catch (e) {
                    setDialogState(() {
                      isVerifying = false;
                      errorMessage = "Google sign-in failed. Please try again.";
                    });
                  }
                  return;
                }

                // ---- Email + password ----
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
                  final profileCheck = await _supabase
                      .from('profiles')
                      .select('id, full_name, email, role, account_type, username, phone')
                      .ilike('email', email)
                      .maybeSingle();

                  if (profileCheck == null) {
                    if (mounted) {
                      Navigator.pop(dialogCtx);
                      _showAccountNotFoundDialog(context, email, password);
                    }
                    return;
                  }

                  final authRes = await _supabase.auth.signInWithPassword(
                    email: email,
                    password: password,
                  );

                  final user = authRes.user;
                  if (user != null) {
                    final loadedAccount = UserAccount(
                      fullName: profileCheck['full_name'] ?? "User",
                      userName: profileCheck['username'] ?? "user",
                      phoneNumber: profileCheck['phone'] ?? "Not set",
                      email: profileCheck['email'] ?? email,
                      role: profileCheck['role'] ?? "Member",
                      accountType: profileCheck['account_type'] ?? "Saint",
                    );

                    final prefs = await SharedPreferences.getInstance();
                    List<String> savedIds = prefs.getStringList('device_account_ids') ?? [];
                    if (!savedIds.contains(user.id)) {
                      savedIds.add(user.id);
                      await prefs.setStringList('device_account_ids', savedIds);
                    }
                    await prefs.setString('active_account_email', loadedAccount.email);

                    if (mounted) {
                      Navigator.pop(dialogCtx); 
                      Navigator.pop(context);   
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
                  : Text(
                      method == 'email'
                          ? "Confirm & Load"
                          : (method == 'google' ? "Continue with Google" : (codeSent ? "Verify & Load" : "Send WhatsApp code")),
                      style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ACCOUNT NOT FOUND PROMPT DIALOG
  // ==========================================
  void _showAccountNotFoundDialog(BuildContext context, String enteredEmail, String enteredPassword) {
    // Captured now: the pop-ups below close before the registration form opens
    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            Icon(Icons.person_off_rounded, color: AppPalette.fg(Colors.orange), size: 22),
            const SizedBox(width: 8),
            Text(
              "Account Not Found",
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16, color: AppPalette.fg(const Color(0xFF4A148C))),
            ),
          ],
        ),
        content: Text(
          "No registered account was found with the email \"$enteredEmail\".\n\nWould you like to register and create a new account now?",
          style: GoogleFonts.merriweather(fontSize: 12.5, height: 1.45, color: AppPalette.fg(Colors.black87)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Not Now", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.grey), fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.bg(const Color(0xFF4A148C)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              // Open registration with the email (and password) already typed,
              // so they don't have to be entered again
              nav.push(MaterialPageRoute(
                builder: (_) => AddAccountScreen(
                  signUpMethod: 'email',
                  initialEmail: enteredEmail,
                  initialPassword: enteredPassword.isEmpty ? null : enteredPassword,
                ),
              ));
            },
            child: Text(
              "Create Account",
              style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}