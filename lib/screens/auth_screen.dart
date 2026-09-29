// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _supabase = Supabase.instance.client;
  
  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  // --- CONFIGURATION STATE ---
  bool _isLoading = true; // Start true while loading config
  bool _isSignUp = false;
  bool _otpSent = false;
  String _authMethod = 'email'; 

  // Dynamic Config Variables (with safe defaults)
  String _appName = "Master Administration";
  String _signupPrompt = "Need a new unit? Sign Up";
  Map<String, dynamic> _flags = {"google_login": true, "phone_login": true, "maintenance_mode": false};
  List<dynamic> _countries = [{"name": "Uganda", "code": "+256", "flag": "🇺🇬"}];
  Map<String, dynamic> _selectedCountry = {"name": "Uganda", "code": "+256", "flag": "🇺🇬"};

  @override
  void initState() {
    super.initState();
    _loadAppConfig();
  }

  // ==========================================
  // CATEGORY 1: CONFIGURATION LOGIC
  // ==========================================

  Future<void> _loadAppConfig() async {
    try {
      final List<dynamic> data = await _supabase.from('app_config').select();
      
      if (mounted) {
        setState(() {
          for (var item in data) {
            String key = item['config_key'];
            var value = item['config_value'];

            if (key == 'app_branding') _appName = value['name'];
            if (key == 'supported_countries') {
              _countries = value;
              _selectedCountry = _countries.first;
            }
            if (key == 'feature_flags') _flags = value;
            if (key == 'system_messages') _signupPrompt = value['signup_prompt'];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Config Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================
  // CATEGORY 2: AUTH LOGIC
  // ==========================================

  Future<void> _handleEmailAuth() async {
    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        await _supabase.auth.signUp(email: _emailController.text.trim(), password: _passwordController.text.trim());
        _showMsg('Check your email for confirmation!');
      } else {
        final AuthResponse res = await _supabase.auth.signInWithPassword(email: _emailController.text.trim(), password: _passwordController.text.trim());
        if (res.user != null) await _saveIdToDevice(res.user!.id);
      }
    } on AuthException catch (e) {
      _showMsg(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendOTP() async {
    if (_phoneController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      // Combine country code with phone number
      String fullPhone = "${_selectedCountry['code']}${_phoneController.text.trim()}";
      await _supabase.auth.signInWithOtp(phone: fullPhone);
      setState(() => _otpSent = true);
      _showMsg('OTP Sent to $fullPhone');
    } catch (e) {
      _showMsg(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOTP() async {
    setState(() => _isLoading = true);
    try {
      String fullPhone = "${_selectedCountry['code']}${_phoneController.text.trim()}";
      final AuthResponse res = await _supabase.auth.verifyOTP(type: OtpType.sms, token: _otpController.text.trim(), phone: fullPhone);
      if (res.user != null) await _saveIdToDevice(res.user!.id);
    } catch (e) { _showMsg(e.toString(), isError: true); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _saveIdToDevice(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedIds = prefs.getStringList('device_account_ids') ?? [];
    if (!savedIds.contains(uid)) {
      savedIds.add(uid);
      await prefs.setStringList('device_account_ids', savedIds);
    }
  }

  void _showMsg(String m, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: isError ? Colors.red : Colors.green));
  }

  // ==========================================
  // CATEGORY 3: UI RENDERING
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (_flags['maintenance_mode'] == true) return _buildMaintenanceUI();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: _isLoading && _countries.length <= 1 
          ? const CircularProgressIndicator(color: Color(0xFF4A148C))
          : SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(32.0),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 30)]),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.admin_panel_settings_rounded, size: 60, color: Color(0xFF4A148C)),
                  const SizedBox(height: 10),
                  Text(_appName, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF4A148C))),
                  const SizedBox(height: 30),
                  if (!_otpSent && _flags['phone_login']) _buildAuthSwitcher(),
                  const SizedBox(height: 25),
                  if (_authMethod == 'email') _buildEmailUI() else if (!_otpSent) _buildPhoneUI() else _buildOTPUI(),
                  if (_flags['google_login']) ...[
                    const SizedBox(height: 25),
                    _divider(),
                    const SizedBox(height: 25),
                    _googleBtn(),
                  ]
                ]),
              ),
            ),
      ),
    );
  }

  Widget _buildAuthSwitcher() => Container(
    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      _toggleBtn('Email', _authMethod == 'email', () => setState(() => _authMethod = 'email')),
      _toggleBtn('Phone', _authMethod == 'phone', () => setState(() => _authMethod = 'phone')),
    ]),
  );

  Widget _buildEmailUI() => Column(children: [
    TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
    const SizedBox(height: 15),
    TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
    const SizedBox(height: 20),
    _mainBtn(_isSignUp ? 'Create Account' : 'Sign In', _handleEmailAuth),
    TextButton(onPressed: () => setState(() => _isSignUp = !_isSignUp), child: Text(_isSignUp ? 'Already have an account? Sign In' : _signupPrompt))
  ]);

  Widget _buildPhoneUI() => Column(children: [
    Row(children: [
      // NEW: INTERNATIONAL COUNTRY PICKER
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(5)),
        child: DropdownButton<dynamic>(
          value: _selectedCountry,
          underline: const SizedBox(),
          items: _countries.map((c) => DropdownMenuItem(value: c, child: Text("${c['flag']} ${c['code']}"))).toList(),
          onChanged: (v) => setState(() => _selectedCountry = v!),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()))),
    ]),
    const SizedBox(height: 20),
    _mainBtn('Send Verification Code', _sendOTP, color: Colors.green),
  ]);

  Widget _buildOTPUI() => Column(children: [
    Text('Verify Your Number', style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    TextField(controller: _otpController, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '6-Digit Code', border: OutlineInputBorder())),
    const SizedBox(height: 20),
    _mainBtn('Verify & Login', _verifyOTP),
    TextButton(onPressed: () => setState(() => _otpSent = false), child: const Text("Change Number")),
  ]);

  Widget _buildMaintenanceUI() => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.sync_problem_rounded, size: 80, color: Colors.orange),
    const SizedBox(height: 20),
    Text("Under Maintenance", style: GoogleFonts.merriweather(fontSize: 24, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Text(_signupPrompt, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
  ]))));

  // --- HELPERS ---
  Widget _googleBtn() => OutlinedButton.icon(
    onPressed: () => _supabase.auth.signInWithOAuth(OAuthProvider.google),
    icon: const FaIcon(FontAwesomeIcons.google, color: Color(0xFF4A148C), size: 18),
    label: Text('Sign in with Google', style: GoogleFonts.openSans(fontWeight: FontWeight.bold, color: Colors.black87)),
    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52), side: const BorderSide(color: Colors.black12)),
  );

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) => Expanded(child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: active ? const Color(0xFF4A148C) : Colors.transparent, borderRadius: BorderRadius.circular(10)), child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: active ? Colors.white : Colors.black54, fontWeight: FontWeight.bold)))));

  Widget _mainBtn(String label, VoidCallback? action, {Color color = const Color(0xFF4A148C)}) => SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: _isLoading ? null : action, style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(label)));

  Widget _divider() => Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text("OR", style: GoogleFonts.openSans(fontSize: 12, color: Colors.grey))), const Expanded(child: Divider())]);
}