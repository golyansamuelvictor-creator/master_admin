// ignore_for_file: curly_braces_in_flow_control_structures, use_build_context_synchronously
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/profile_refresh.dart';
import 'add_account_screen.dart';

/// Result of checking a signed-in user's profile.
enum _Approval { approved, pending, needsVerification, rejected, error }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSub;

  // Controllers
  final _fullNameController = TextEditingController();
  final _scjIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  final FocusNode _scjIdFocusNode = FocusNode();

  // --- STATE ---
  bool _isLoading = false;
  bool _isSearchingMember = false;
  Map<String, dynamic>? _matchedMemberRecord;
  String? _memberLookupStatus;
  String? _lookedUpId;
  int _lookupToken = 0;

  bool _isSignUp = false;
  bool _otpSent = false;
  bool _isPendingApproval = false;
  String _pendingUserEmail = "";

  bool _obscurePassword = true;

  bool _isGooglePendingVerification = false;
  User? _googleUser;

  String _authMethod = 'email';
  String _requestAccessMethod = 'email';

  String _appName = "Master Administration";
  // Updated text prompt per your request:
  String _signupPrompt = "Create a New Account";
  Map<String, dynamic> _flags = {"google_login": true, "phone_login": true, "maintenance_mode": false};

  List<Map<String, dynamic>> _countries = [
    {"name": "Uganda", "code": "+256", "flag": "🇺🇬"},
    {"name": "Kenya", "code": "+254", "flag": "🇰🇪"},
    {"name": "Tanzania", "code": "+255", "flag": "🇹🇿"},
    {"name": "South Africa", "code": "+27", "flag": "🇿🇦"},
    {"name": "South Korea", "code": "+82", "flag": "🇰🇷"},
  ];
  late Map<String, dynamic> _selectedCountry;

  final Color pPurple = const Color(0xFF4A148C);
  final Color whatsAppGreen = const Color(0xFF25D366);

  @override
  void initState() {
    super.initState();
    _selectedCountry = _countries.first;
    _loadAppConfig();
    _listenToAuthChanges();

    _scjIdController.addListener(_onScjIdChanged);
    _scjIdFocusNode.addListener(() {
      if (!_scjIdFocusNode.hasFocus) _autoFetchMemberDetails();
    });

    final existingUser = _supabase.auth.currentUser;
    if (existingUser != null) {
      _isLoading = true;
      _verifyUserApproval(existingUser);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _scjIdController.removeListener(_onScjIdChanged);
    _fullNameController.dispose();
    _scjIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _scjIdFocusNode.dispose();
    super.dispose();
  }

  // ==========================================
  // HELPERS
  // ==========================================
  String get _nationalPhone =>
      _phoneController.text.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');

  String get _fullPhone => "${_selectedCountry['code']}$_nationalPhone";

  String _escapeLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  Map<String, dynamic>? _asMember(dynamic res) {
    if (res is List) {
      return res.isEmpty ? null : Map<String, dynamic>.from(res.first as Map);
    }
    if (res is Map) {
      return res.isEmpty ? null : Map<String, dynamic>.from(res);
    }
    return null;
  }

  String _lookupErrorText(Object e) {
    if (e is PostgrestException) {
      return kDebugMode
          ? "Server error ${e.code}: ${e.message}"
          : "The lookup service returned an error. Please contact support.";
    }
    return "Check your connection and try again.";
  }

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _namesMatch(String entered, Map<String, dynamic> member) {
    final e = _norm(entered);
    if (e.isEmpty) return false;
    final eWords = e.split(' ').where((w) => w.length > 1).toSet();

    for (final raw in [member['english_name'], member['korean_name']]) {
      final db = _norm((raw ?? '').toString());
      if (db.isEmpty) continue;
      if (db == e || db.replaceAll(' ', '') == e.replaceAll(' ', '')) return true;

      final dbWords = db.split(' ').where((w) => w.length > 1).toSet();
      if (dbWords.isEmpty || eWords.isEmpty) continue;
      final needed = dbWords.length >= 2 ? 2 : 1;
      if (eWords.intersection(dbWords).length >= needed) return true;
    }
    return false;
  }

  // ==========================================
  // AUTO-FETCH VIA RPC
  // ==========================================
  void _onScjIdChanged() {
    if (_scjIdController.text.trim() == _lookedUpId) return;
    if (_matchedMemberRecord == null && _memberLookupStatus == null) return;
    setState(() {
      _matchedMemberRecord = null;
      _memberLookupStatus = null;
      _lookedUpId = null;
    });
  }

  Future<void> _autoFetchMemberDetails() async {
    final scjId = _scjIdController.text.trim();
    if (scjId.length < 3) return;
    if (scjId == _lookedUpId && _matchedMemberRecord != null) return;

    final token = ++_lookupToken;
    setState(() {
      _isSearchingMember = true;
      _memberLookupStatus = null;
    });

    try {
      final res = await _supabase.rpc('verify_scj_member_id', params: {'lookup_scj_id': scjId});
      if (!mounted || token != _lookupToken) return;

      final member = _asMember(res);
      if (member != null) {
        final name = (member['english_name'] ?? member['korean_name'] ?? '').toString();
        final loc = member['location'] ?? '';
        final subLoc = member['sub_location'] ?? '';
        final dept = member['department'] ?? '';
        final duty = member['duty'] ?? 'Saint';
        setState(() {
          _matchedMemberRecord = member;
          _lookedUpId = scjId;
          if (name.isNotEmpty) _fullNameController.text = name;
          _memberLookupStatus = "✓ Verified: $name ($loc > $subLoc > $dept • $duty)";
        });
      } else {
        setState(() {
          _matchedMemberRecord = null;
          _lookedUpId = scjId;
          _memberLookupStatus = "✗ SCJ ID '$scjId' not found in church records";
        });
      }
    } catch (e) {
      debugPrint("Member lookup RPC error: $e");
      if (mounted && token == _lookupToken) {
        setState(() => _memberLookupStatus = "✗ Couldn't look up the SCJ ID. ${_lookupErrorText(e)}");
      }
    } finally {
      if (mounted && token == _lookupToken) setState(() => _isSearchingMember = false);
    }
  }

  // ==========================================
  // OAUTH & SESSION LISTENER
  // ==========================================
  void _listenToAuthChanges() {
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      final session = data.session;
      debugPrint("AuthScreen auth event: ${data.event}, hasSession: ${session != null}");

      if (session == null) {
        setState(() {
          _isGooglePendingVerification = false;
          _isPendingApproval = false;
          _isLoading = false;
        });
        return;
      }

      if (data.event == AuthChangeEvent.tokenRefreshed) return;

      _verifyUserApproval(session.user);
    });
  }

  // ==========================================
  // CHECK APPROVAL STATUS IN PROFILES
  // ==========================================
  Future<_Approval>? _verifyInFlight;

  Future<_Approval> _verifyUserApproval(User user) {
    return _verifyInFlight ??= _runApprovalCheck(user).whenComplete(() => _verifyInFlight = null);
  }

  Future<_Approval> _runApprovalCheck(User user) async {
    debugPrint("AuthScreen: checking profile for ${user.id}");
    try {
      final res = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      // SCJ ID is strictly verified as the master key
      final rawScjId = res == null ? null : res['scj_id'];
      final String? scjId = rawScjId?.toString().trim();
      final bool hasValidScjId = scjId != null &&
          scjId.isNotEmpty &&
          scjId.toLowerCase() != 'null' &&
          scjId.toLowerCase() != 'none';

      // 1. If SCJ ID is null, empty, or missing -> MUST present the Member Verification Card!
      if (res == null || !hasValidScjId) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isPendingApproval = false;
            _isGooglePendingVerification = true;
            _googleUser = user;
            if (_fullNameController.text.trim().isEmpty) {
              _fullNameController.text =
                  (user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? '').toString();
            }
          });
        }
        return _Approval.needsVerification;
      }

      final String status =
          (res['approval_status'] ?? (res['is_approved'] == true ? 'approved' : 'pending')).toString().toLowerCase();
      final bool isApproved = res['is_approved'] == true || status == 'approved';

      if (status == 'rejected') {
        final reason = res['rejection_reason'] ?? 'Please contact your immediate leaders.';
        await _supabase.auth.signOut();
        if (mounted) {
          setState(() {
            _isPendingApproval = false;
            _isGooglePendingVerification = false;
            _isLoading = false;
          });
          _showMsg("Account Request Rejected: $reason", isError: true);
        }
        return _Approval.rejected;
      }

      // 2. Has verified SCJ ID, but pending administrator review
      if (!isApproved) {
        if (mounted) {
          setState(() {
            _isPendingApproval = true;
            _isGooglePendingVerification = false;
            _pendingUserEmail = (res['email'] ?? res['phone'] ?? user.email ?? "Your account").toString();
            _isLoading = false;
          });
        }
        return _Approval.pending;
      }

      // 3. Approved
      await _saveIdToDevice(user.id);
      if (mounted) {
        setState(() {
          _isPendingApproval = false;
          _isGooglePendingVerification = false;
          _isLoading = true;
        });
        _onApproved();
      }
      return _Approval.approved;
    } catch (e) {
      debugPrint("Approval check error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showMsg(
          "Couldn't check your account status. ${kDebugMode ? '($e)' : 'Check your connection and try again.'}",
          isError: true,
        );
      }
      return _Approval.error;
    }
  }

  void _onApproved() {
    requestProfileRefresh();

    final nav = Navigator.of(context);
    if (nav.canPop()) nav.popUntil((r) => r.isFirst);

    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  // ==========================================
  // MEMBER VERIFICATION
  // ==========================================
  Future<Map<String, dynamic>?> _verifyMember(String scjId, String name) async {
    final member = _matchedMemberRecord ??
        _asMember(await _supabase.rpc('verify_scj_member_id', params: {'lookup_scj_id': scjId}));

    if (member == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showRejectionDialog("SCJ ID '$scjId' was not found in church records.");
      }
      return null;
    }

    if (!_namesMatch(name, member)) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showRejectionDialog("The Full Name entered does not match church records for SCJ ID '$scjId'.");
      }
      return null;
    }
    return member;
  }

  // ==========================================
  // GOOGLE MEMBER VERIFICATION SUBMIT
  // ==========================================
  Future<void> _handleGoogleVerificationSubmit() async {
    final scjId = _scjIdController.text.trim();
    final name = _fullNameController.text.trim();

    if (scjId.isEmpty || name.isEmpty) {
      _showMsg("Please enter both SCJ ID and Full Names.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final memberRecord = await _verifyMember(scjId, name);
      if (memberRecord == null) return;

      final existing = await _supabase
          .from('profiles')
          .select('id')
          .ilike('scj_id', _escapeLike(scjId))
          .limit(1);

      if (existing.isNotEmpty && existing.first['id'] != _googleUser?.id) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showMsg("An account with this SCJ ID already exists in the system.", isError: true);
        }
        return;
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Successfully verified with church records -> Proceed to AddAccountScreen with prefilled data
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (c) => AddAccountScreen(
            initialFullName: memberRecord['english_name'] ?? memberRecord['korean_name'] ?? name,
            initialScjId: memberRecord['scj_id'] ?? scjId,
            signUpMethod: 'google',
            initialEmail: _googleUser?.email ?? memberRecord['email_address'],
            initialPhone: memberRecord['phone_numbers']?.toString(),
            memberData: memberRecord,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Google verification error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showMsg("Verification failed. ${_lookupErrorText(e)}", isError: true);
      }
    }
  }

  Future<void> _checkPendingStatusAgain() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    final result = await _verifyUserApproval(user);
    if (!mounted) return;

    if (result == _Approval.pending) {
      _showMsg("Account is still under review by Church Administration.", isError: true);
    } else if (result == _Approval.approved) {
      _showMsg("Account approved! Welcome.", isError: false);
    }
  }

  Future<void> _loadAppConfig() async {
    try {
      final List<dynamic> data = await _supabase.from('app_config').select();
      if (!mounted) return;

      setState(() {
        for (final item in data) {
          final key = item['config_key'];
          final value = item['config_value'];

          if (key == 'app_branding' && value is Map) {
            _appName = (value['name'] ?? _appName).toString();
          }
          if (key == 'supported_countries' && value is List && value.isNotEmpty) {
            _countries = value.map((c) => Map<String, dynamic>.from(c as Map)).toList();
            _selectedCountry = _countries.first;
          }
          if (key == 'feature_flags' && value is Map) {
            _flags = {..._flags, ...Map<String, dynamic>.from(value)};
          }
          if (key == 'system_messages' && value is Map) {
            _signupPrompt = (value['signup_prompt'] ?? _signupPrompt).toString();
          }
        }
      });
    } catch (e) {
      debugPrint("Config Error: $e");
    }
  }

  // ==========================================
  // REQUEST ACCESS VIA VERIFICATION
  // ==========================================
  Future<Map<String, dynamic>?> _findExistingProfile({required String scjId, String? email, String? phone}) async {
    final byScj = await _supabase
        .from('profiles')
        .select('id, is_approved, approval_status')
        .ilike('scj_id', _escapeLike(scjId))
        .limit(1);
    if (byScj.isNotEmpty) return byScj.first;

    if (email != null && email.isNotEmpty) {
      final byEmail = await _supabase
          .from('profiles')
          .select('id, is_approved, approval_status')
          .ilike('email', _escapeLike(email))
          .limit(1);
      if (byEmail.isNotEmpty) return byEmail.first;
    }

    if (phone != null && phone.isNotEmpty) {
      final byPhone = await _supabase
          .from('profiles')
          .select('id, is_approved, approval_status')
          .ilike('phone', '%${_escapeLike(phone)}')
          .limit(1);
      if (byPhone.isNotEmpty) return byPhone.first;
    }
    return null;
  }

  Future<void> _handleRequestAccessVerification() async {
    final fullName = _fullNameController.text.trim();
    final scjId = _scjIdController.text.trim();
    final password = _passwordController.text.trim();
    final email = _emailController.text.trim();

    if (scjId.isEmpty || password.isEmpty) {
      _showMsg("Please enter SCJ ID and Password.", isError: true);
      return;
    }
    if (fullName.isEmpty) {
      _showMsg("Please enter your Full Names.", isError: true);
      return;
    }
    if (_requestAccessMethod == 'email' && email.isEmpty) {
      _showMsg("Please enter your Email Address.", isError: true);
      return;
    }
    if (_requestAccessMethod == 'whatsapp' && _nationalPhone.isEmpty) {
      _showMsg("Please enter your WhatsApp Phone Number.", isError: true);
      return;
    }
    if (password.length < 6) {
      _showMsg("Password must be at least 6 characters.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final memberRecord = await _verifyMember(scjId, fullName);
      if (memberRecord == null) return;

      final existingProfile = await _findExistingProfile(
        scjId: scjId,
        email: _requestAccessMethod == 'email' ? email : null,
        phone: _requestAccessMethod == 'whatsapp' ? _nationalPhone : null,
      );

      if (existingProfile != null) {
        final status = (existingProfile['approval_status'] ??
                (existingProfile['is_approved'] == true ? 'approved' : 'pending'))
            .toString()
            .toLowerCase();
        if (status == 'approved') {
          _showMsg("An account with this SCJ ID or contact already exists. Please sign in.", isError: true);
          if (mounted) {
            setState(() {
              _isSignUp = false;
              _isLoading = false;
            });
          }
          return;
        } else if (status == 'pending') {
          _showMsg("An account with this SCJ ID is already awaiting admin approval.", isError: true);
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (ctx) => AddAccountScreen(
            initialFullName: memberRecord['english_name'] ?? memberRecord['korean_name'] ?? fullName,
            initialScjId: memberRecord['scj_id'] ?? scjId,
            initialPassword: password,
            signUpMethod: _requestAccessMethod,
            initialEmail: _requestAccessMethod == 'email' ? email : memberRecord['email_address'],
            initialPhone: _requestAccessMethod == 'whatsapp' ? _fullPhone : memberRecord['phone_numbers']?.toString(),
            memberData: memberRecord,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Verification exception: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showMsg("Verification failed. ${_lookupErrorText(e)}", isError: true);
      }
    }
  }

  void _showRejectionDialog([String? detail]) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            Text(
              "Access Denied",
              style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red.shade900),
            ),
          ],
        ),
        content: Text(
          "${detail ?? 'Your Full Names and SCJ ID were not found inside church records.'}\n\nPlease contact your immediate leaders to confirm your details before requesting access.",
          style: GoogleFonts.merriweather(fontSize: 13, height: 1.5, color: Colors.blueGrey.shade800),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(backgroundColor: pPurple),
            child: Text("OK", style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SIGN IN METHODS
  // ==========================================
  Future<void> _handleEmailSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMsg("Please enter both email and password.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    _Approval? result;
    try {
      final AuthResponse res = await _supabase.auth.signInWithPassword(email: email, password: password);
      if (res.user != null) result = await _verifyUserApproval(res.user!);
    } on AuthException catch (e) {
      _showMsg(e.message, isError: true);
    } catch (e) {
      debugPrint("Email sign-in error: $e");
      _showMsg("Sign-in failed. Check your connection and try again.", isError: true);
    } finally {
      if (mounted && result != _Approval.approved) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendWhatsAppOTP() async {
    if (_nationalPhone.isEmpty) {
      _showMsg("Please enter your phone number.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final fullPhone = _fullPhone;
      await _supabase.auth.signInWithOtp(phone: fullPhone, channel: OtpChannel.whatsapp);

      if (mounted) setState(() => _otpSent = true);
      _showMsg('WhatsApp verification code sent to $fullPhone');
    } on AuthException catch (e) {
      _showMsg(e.message, isError: true);
    } catch (e) {
      debugPrint("Send OTP error: $e");
      _showMsg("Couldn't send the code. Check your connection and try again.", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyWhatsAppOTP() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      _showMsg("Please enter the 6-digit code.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    _Approval? result;
    try {
      final AuthResponse res = await _supabase.auth.verifyOTP(
        type: OtpType.sms,
        token: otp,
        phone: _fullPhone,
      );
      if (res.user != null) result = await _verifyUserApproval(res.user!);
    } on AuthException catch (e) {
      _showMsg(e.message, isError: true);
    } catch (e) {
      debugPrint("Verify OTP error: $e");
      _showMsg("Couldn't verify the code. Check your connection and try again.", isError: true);
    } finally {
      if (mounted && result != _Approval.approved) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    try {
      final String redirectUrl = kIsWeb ? Uri.base.origin : 'masteradministration://login-callback';

      await _supabase.auth.signInWithOAuth(OAuthProvider.google, redirectTo: redirectUrl);
    } catch (e) {
      debugPrint("Google sign-in error: $e");
      _showMsg("Google sign-in failed. Please try again.", isError: true);
    }
  }

  Future<void> _handleSignOut() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    setState(() {
      _isPendingApproval = false;
      _isGooglePendingVerification = false;
      _otpSent = false;
      _pendingUserEmail = "";
      _googleUser = null;
      _matchedMemberRecord = null;
      _memberLookupStatus = null;
      _lookedUpId = null;
      _scjIdController.clear();
      _fullNameController.clear();
      _passwordController.clear();
      _otpController.clear();
      _obscurePassword = true;
    });
  }

  Future<void> _saveIdToDevice(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList('device_account_ids') ?? [];
    if (!savedIds.contains(uid)) {
      savedIds.add(uid);
      await prefs.setStringList('device_account_ids', savedIds);
    }
  }

  void _showMsg(String m, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m, style: GoogleFonts.merriweather(fontSize: 12, color: Colors.white)),
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================
  // SHARED FIELD BUILDERS
  // ==========================================
  InputDecoration _dec(String label, IconData icon, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.merriweather(fontSize: 12),
        prefixIcon: Icon(icon, size: 18, color: pPurple),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _scjIdField({required String hint, required String tooltip}) => TextField(
        controller: _scjIdController,
        focusNode: _scjIdFocusNode,
        style: GoogleFonts.merriweather(fontSize: 13),
        decoration: _dec(
          'SCJ ID',
          Icons.badge_outlined,
          hint: hint,
          suffix: _isSearchingMember
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(icon: const Icon(Icons.search, size: 18), onPressed: _autoFetchMemberDetails, tooltip: tooltip),
        ),
        onSubmitted: (_) => _autoFetchMemberDetails(),
      );

  Widget _lookupStatus() {
    if (_memberLookupStatus == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _memberLookupStatus!,
          style: GoogleFonts.merriweather(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _matchedMemberRecord != null ? Colors.green.shade800 : Colors.red.shade800,
          ),
        ),
      ),
    );
  }

  Widget _nameField() => TextField(
        controller: _fullNameController,
        style: GoogleFonts.merriweather(fontSize: 13),
        decoration: _dec('Full Names', Icons.person_outline_rounded),
      );

  Widget _emailField() => TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        style: GoogleFonts.merriweather(fontSize: 13),
        decoration: _dec('Email Address', Icons.mail_outline_rounded),
      );

  Widget _passwordField() => TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: GoogleFonts.merriweather(fontSize: 13),
        decoration: _dec(
          'Password',
          Icons.lock_outline_rounded,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              size: 18,
              color: Colors.grey,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
          ),
        ),
      );

  // ==========================================
  // UI RENDERING
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (_flags['maintenance_mode'] == true) return _buildMaintenanceUI();

    final bool phoneLogin = _flags['phone_login'] == true;
    final bool googleLogin = _flags['google_login'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: _isLoading
              ? const SizedBox(
                  height: 48,
                  width: 48,
                  child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF4A148C)),
                )
              : _isPendingApproval
                  ? _buildPendingApprovalUI()
                  : _isGooglePendingVerification
                      ? _buildGoogleVerificationCardUI()
                      : Container(
                          constraints: const BoxConstraints(maxWidth: 440),
                          margin: const EdgeInsets.all(20),
                          padding: const EdgeInsets.all(28.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: pPurple.withValues(alpha: 0.08), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: pPurple.withValues(alpha: 0.08), shape: BoxShape.circle),
                                child: Icon(Icons.admin_panel_settings_rounded, size: 46, color: pPurple),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _appName,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.w900, color: pPurple),
                              ),
                              const SizedBox(height: 20),
                              if (!_isSignUp && !_otpSent && phoneLogin) ...[
                                _buildAuthSwitcher(),
                                const SizedBox(height: 20),
                              ],
                              if (_isSignUp)
                                _buildRequestAccessUI()
                              else if (_authMethod == 'email' || !phoneLogin)
                                _buildEmailSignInUI()
                              else if (!_otpSent)
                                _buildWhatsAppPhoneUI()
                              else
                                _buildWhatsAppOTPUI(),
                              if (!_isSignUp && googleLogin) ...[
                                const SizedBox(height: 20),
                                _divider(),
                                const SizedBox(height: 20),
                                _googleBtn(),
                              ]
                            ],
                          ),
                        ),
        ),
      ),
    );
  }

  // ==========================================
  // INLINE GOOGLE MEMBER VERIFICATION CARD
  // ==========================================
  Widget _buildGoogleVerificationCardUI() {
    final email = _googleUser?.email ?? "Your Google Account";

    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(28.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pPurple.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(color: pPurple.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: pPurple.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(Icons.verified_user_outlined, size: 42, color: pPurple),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Member Verification",
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: pPurple),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                const FaIcon(FontAwesomeIcons.google, size: 14, color: Color(0xFF4A148C)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Connected: $email",
                    style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "Please verify your church membership details to complete account registration.",
            style: GoogleFonts.merriweather(fontSize: 11, color: Colors.blueGrey[700]),
          ),
          const SizedBox(height: 16),
          _scjIdField(hint: 'Enter SCJ ID', tooltip: 'Lookup Member'),
          _lookupStatus(),
          const SizedBox(height: 12),
          _nameField(),
          const SizedBox(height: 20),
          _mainBtn('Verify & Continue', _handleGoogleVerificationSubmit),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _handleSignOut,
            child: Text(
              "Sign in with a different account",
              style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // REQUEST ACCESS UI
  // ==========================================
  Widget _buildRequestAccessUI() => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(Icons.how_to_reg_outlined, color: pPurple, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Request Access: Verification with Church Records",
                    style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF1F3F9), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                _toggleBtn('Use Email', _requestAccessMethod == 'email', () {
                  setState(() => _requestAccessMethod = 'email');
                }),
                _toggleBtn('Use WhatsApp', _requestAccessMethod == 'whatsapp', () {
                  setState(() => _requestAccessMethod = 'whatsapp');
                }, activeColor: whatsAppGreen),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _scjIdField(hint: 'Enter SCJ ID to auto-fill details', tooltip: 'Look up church records'),
          _lookupStatus(),
          const SizedBox(height: 12),
          _nameField(),
          const SizedBox(height: 12),
          if (_requestAccessMethod == 'email') _emailField() else _buildCountryPhoneInput(),
          const SizedBox(height: 12),
          _passwordField(),
          const SizedBox(height: 20),
          _mainBtn(
            'Verify & Request Access',
            _handleRequestAccessVerification,
            color: _requestAccessMethod == 'whatsapp' ? whatsAppGreen : pPurple,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _isSignUp = false),
            child: Text(
              'Already registered? Sign In',
              style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
            ),
          ),
        ],
      );

  // ==========================================
  // EMAIL SIGN IN UI
  // ==========================================
  Widget _buildEmailSignInUI() => Column(
        children: [
          _emailField(),
          const SizedBox(height: 14),
          _passwordField(),
          const SizedBox(height: 20),
          _mainBtn('Sign In', _handleEmailSignIn),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _isSignUp = true),
            child: Text(
              _signupPrompt,
              style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
            ),
          ),
        ],
      );

  Widget _buildWhatsAppPhoneUI() => Column(
        children: [
          _buildCountryPhoneInput(),
          const SizedBox(height: 20),
          _mainBtn(
            'Send WhatsApp OTP',
            _sendWhatsAppOTP,
            color: whatsAppGreen,
            icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 16, color: Colors.white),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _isSignUp = true),
            child: Text(
              _signupPrompt,
              style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
            ),
          ),
        ],
      );

  Widget _buildWhatsAppOTPUI() => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(FontAwesomeIcons.whatsapp, color: whatsAppGreen, size: 22),
              const SizedBox(width: 8),
              Text(
                'Verify WhatsApp Code',
                style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: pPurple),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Enter the 6-digit code sent to your WhatsApp",
            style: GoogleFonts.merriweather(fontSize: 11, color: Colors.blueGrey),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _otpController,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 6),
            decoration: InputDecoration(
              hintText: '• • • • • •',
              hintStyle: GoogleFonts.merriweather(fontSize: 16, letterSpacing: 4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onSubmitted: (_) => _verifyWhatsAppOTP(),
          ),
          const SizedBox(height: 20),
          _mainBtn('Verify & Continue', _verifyWhatsAppOTP, color: whatsAppGreen),
          TextButton(
            onPressed: () => setState(() {
              _otpSent = false;
              _otpController.clear();
            }),
            child: Text("Change Phone Number",
                style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple)),
          ),
        ],
      );

  Widget _buildCountryPhoneInput() => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<Map<String, dynamic>>(
              value: _selectedCountry,
              underline: const SizedBox(),
              items: _countries
                  .map((c) => DropdownMenuItem<Map<String, dynamic>>(
                        value: c,
                        child: Text("${c['flag']} ${c['code']}",
                            style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedCountry = v);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: GoogleFonts.merriweather(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'WhatsApp Phone Number',
                labelStyle: GoogleFonts.merriweather(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
        ],
      );

  Widget _buildPendingApprovalUI() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 450),
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(32.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.orange.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.hourglass_top_rounded, size: 52, color: Colors.orange),
          ),
          const SizedBox(height: 18),
          Text(
            "Account Under Review",
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.w900, color: pPurple),
          ),
          const SizedBox(height: 12),
          Text(
            "Your registration for \"$_pendingUserEmail\" has been received.",
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
          ),
          const SizedBox(height: 10),
          Text(
            "For security purposes, church administration must verify your jurisdiction and approve your account before access is granted. You will be notified once approved.",
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(fontSize: 12, color: Colors.blueGrey[600], height: 1.5),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _checkPendingStatusAgain,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text("Check Approval Status",
                  style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: pPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _handleSignOut,
            child: Text(
              "Sign in with a different account",
              style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthSwitcher() => Container(
        decoration: BoxDecoration(color: const Color(0xFFF1F3F9), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          _toggleBtn('Email', _authMethod == 'email', () => setState(() => _authMethod = 'email')),
          _toggleBtn('WhatsApp OTP', _authMethod == 'whatsapp', () => setState(() => _authMethod = 'whatsapp'),
              activeColor: whatsAppGreen),
        ]),
      );

  Widget _buildMaintenanceUI() => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sync_problem_rounded, size: 80, color: Colors.orange),
                const SizedBox(height: 20),
                Text("Under Maintenance", style: GoogleFonts.merriweather(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(_signupPrompt,
                    textAlign: TextAlign.center, style: GoogleFonts.merriweather(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
      );

  Widget _googleBtn() => OutlinedButton.icon(
        onPressed: _handleGoogleSignIn,
        icon: const FaIcon(FontAwesomeIcons.google, color: Color(0xFF4A148C), size: 16),
        label: Text(
          'Sign in with Google',
          style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 12),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          side: BorderSide(color: pPurple.withValues(alpha: 0.15)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Widget _toggleBtn(String label, bool active, VoidCallback onTap, {Color? activeColor}) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? (activeColor ?? pPurple) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.merriweather(
                color: active ? Colors.white : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      );

  Widget _mainBtn(String label, VoidCallback? action, {Color? color, Widget? icon}) => SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton(
          onPressed: _isLoading ? null : action,
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? pPurple,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _isLoading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[icon, const SizedBox(width: 8)],
                    Text(label, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
        ),
      );

  Widget _divider() => Row(children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text("OR", style: GoogleFonts.merriweather(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        ),
        const Expanded(child: Divider()),
      ]);
}