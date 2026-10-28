// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';
import 'package:master_admin/core/app_sizes.dart';
import 'package:master_admin/widgets/compact_card.dart';
import 'package:master_admin/widgets/app_lock_settings.dart';
import 'package:master_admin/widgets/two_step.dart';
import 'package:master_admin/widgets/feedback_screens.dart';
import 'package:master_admin/widgets/language_screens.dart';
import 'package:master_admin/services/app_sounds.dart';
import 'package:master_admin/services/chat_service.dart';
import 'package:master_admin/services/profile_refresh.dart';
import 'package:master_admin/services/device_sessions.dart';
import 'package:master_admin/services/app_lock_manager.dart';
import 'package:master_admin/services/notice_permissions.dart';

const Color _kPurple = Color(0xFF4A148C);

class _Item {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function()? page; // opens a page
  final Future<void> Function(BuildContext)? action; // runs directly
  final Color? color;
  const _Item(this.title, this.subtitle, this.icon, {this.page, this.action, this.color});
}

class _Cat {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_Item> items;
  const _Cat(this.title, this.subtitle, this.icon, this.color, this.items);
}

/// System Settings. Every item works; nothing is "coming soon".
class SettingsScreen extends StatefulWidget {
  final String userEmail, userRole;
  const SettingsScreen({super.key, required this.userEmail, required this.userRole});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _db = Supabase.instance.client;
  String? _selected;
  Map<String, dynamic> _profile = {};
  NoticePermissions _perm = NoticePermissions.none;

  @override
  void initState() {
    super.initState();
    _loadHeader();
    AppSounds.load();
    NoticePermissions.load().then((p) {
      if (mounted) setState(() => _perm = p);
    });
  }

  Future<void> _loadHeader() async {
    final p = await ChatService.myProfile();
    if (mounted) setState(() => _profile = p);
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sign out?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Sign out", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final key = await DeviceSessions.deviceKey();
      await _db.from('user_devices').delete().eq('user_id', _db.auth.currentUser?.id ?? '').eq('device_key', key);
    } catch (_) {}
    await _db.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  List<_Cat> get _cats => [
        _Cat("My Account", "Profile, password, devices", Icons.person_rounded, _kPurple, [
          _Item("Profile information", "Photo, name, user name, phone, bio", Icons.badge_outlined, page: () => _ProfilePanel(onSaved: _loadHeader)),
          _Item("Change password", "Choose a new password", Icons.password_rounded, page: () => _PasswordPanel(email: widget.userEmail)),
          _Item("Devices", "Where you're signed in", Icons.devices_rounded, page: () => const _DevicesPanel()),
          _Item("Account verification", "Email, approval and security status", Icons.verified_outlined, page: () => const _VerificationPanel()),
          _Item("Sign out", "Leave your account on this device", Icons.logout_rounded, action: _signOut, color: Colors.red.shade700),
        ]),
        _Cat("Notifications & Sounds", "Sounds, banners, what to be told", Icons.notifications_active_rounded, const Color(0xFFE65100), [
          _Item("Sounds", "Notification and message sounds, volume", Icons.music_note_rounded, page: () => const _SoundsPanel()),
          _Item("Notifications", "Banners and which events to be told about", Icons.notifications_rounded, page: () => const _NotificationTypesPanel()),
        ]),
        _Cat("Privacy & Security", "Lock, two-step, who can see and reach you", Icons.shield_rounded, const Color(0xFF00695C), [
          _Item("App lock", "PIN and auto-lock time", Icons.lock_clock_rounded, page: () => const AppLockSettingsPanel()),
          _Item("Two-step verification", "A code from an authenticator app when signing in", Icons.phonelink_lock_rounded, page: () => const TwoStepSettingsPanel()),
          _Item("Last seen & online", "Who sees when you were last online", Icons.access_time_rounded, page: () => const _PrivacyRulesPanel(focus: 'last_seen')),
          _Item("Profile photo", "Who sees your photo", Icons.account_circle_outlined, page: () => const _PrivacyRulesPanel(focus: 'photo')),
          _Item("Messages & groups", "Who can message you or add you to groups", Icons.forum_outlined, page: () => const _PrivacyRulesPanel(focus: 'messages')),
          _Item("Read receipts & typing", "Blue ticks and \"typing…\"", Icons.done_all_rounded, page: () => const _PrivacyRulesPanel(focus: 'read_receipts')),
          _Item("Location sharing", "Allow sending your location in chats", Icons.location_on_outlined, page: () => const _LocationSharingPanel()),
          _Item("Blocked users", "People who can't message you", Icons.block_rounded, page: () => const _BlockedPanel()),
          _Item("Devices", "Sign out other devices", Icons.devices_rounded, page: () => const _DevicesPanel()),
          _Item("Data protection", "How your data is kept safe", Icons.enhanced_encryption_outlined, page: () => const _DataProtectionPanel()),
        ]),
        _Cat("Language", "System language, download more languages", Icons.translate_rounded, const Color(0xFF1565C0), [
          _Item("System language", I18n.nativeName, Icons.language_rounded,
              page: () => LanguagePanel(canManage: _perm.isAdmin || _perm.can('Manage Languages'))),
        ]),
        _Cat("Feedback", "Ideas, problems and suggestions", Icons.feedback_rounded, const Color(0xFF6A1B9A), [
          for (final e in kFeedbackKinds.entries) _Item(e.value.$1, e.value.$3, e.value.$2, page: () => FeedbackForm(kind: e.key)),
          _Item("My feedback", "What you sent and the answers", Icons.history_rounded, page: () => const FeedbackListScreen()),
          if (_perm.isAdmin || _perm.can('Manage Feedback'))
            _Item("Feedback inbox", "Everything users sent (administration)", Icons.inbox_rounded, page: () => const FeedbackListScreen(inbox: true)),
        ]),
        _Cat("About", "Version and help", Icons.info_outline_rounded, Colors.blueGrey, [
          _Item("About Master Admin", "Version ${DeviceSessions.appVersion}", Icons.info_outline_rounded, page: () => const _AboutPanel()),
        ]),
      ];

  void _open(BuildContext context, _Item it) {
    if (it.action != null) {
      it.action!(context);
      return;
    }
    final page = it.page!();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => (page is FeedbackForm || page is FeedbackListScreen) ? page : _SettingsPage(title: it.title, child: page),
      ),
    ).then((_) => _loadHeader());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 900;
    final cat = _cats.where((c) => c.title == _selected).firstOrNull;
    return PopScope(
      canPop: _selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selected = null);
      },
      child: Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
        appBar: AppBar(
          title: Text(cat?.title ?? "Settings", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: isDesktop ? 22 : 19, color: AppPalette.fg(_kPurple))),
          centerTitle: true,
          backgroundColor: AppPalette.bg(Colors.white),
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => _selected != null ? setState(() => _selected = null) : Navigator.pop(context),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            child: ListView(padding: AppSizes.page, children: [
              if (cat == null) ...[
                _header(),
                const SizedBox(height: 12),
                CardGrid(
                  shrinkWrap: true,
                  extent: AppSizes.listCard,
                  itemCount: _cats.length,
                  itemBuilder: (_, i) {
                    final c = _cats[i];
                    return _tile(c.icon, c.color, c.title, c.subtitle, () => setState(() => _selected = c.title), big: true);
                  },
                ),
              ] else
                CardGrid(
                  shrinkWrap: true,
                  extent: AppSizes.listCard,
                  itemCount: cat.items.length,
                  itemBuilder: (_, i) {
                    final it = cat.items[i];
                    return _tile(it.icon, it.color ?? cat.color, it.title, it.subtitle, () => _open(context, it), danger: it.color != null);
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final name = (_profile['full_name'] ?? widget.userEmail).toString();
    final user = (_profile['username'] ?? '').toString();
    final own = (_profile['avatar_url'] ?? '').toString();
    final avatar = myAvatarUrl.value.isNotEmpty ? myAvatarUrl.value : own;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF7B3FC4)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _kPurple.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.white24,
          backgroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
          child: avatar.isEmpty ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)) : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15.5, color: Colors.white)),
            Text(user.isNotEmpty ? "@$user · ${widget.userEmail}" : widget.userEmail,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(widget.userRole.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 11, fontWeight: FontWeight.bold)),
          ]),
        ),
      ]),
    );
  }

  Widget _tile(IconData icon, Color color, String title, String subtitle, VoidCallback onTap, {bool big = false, bool danger = false}) {
    return CompactCard(
      leading: CircleAvatar(radius: 17, backgroundColor: AppPalette.bg(color.withValues(alpha: 0.12)), child: Icon(icon, size: 19, color: AppPalette.fg(color))),
      title: title,
      subtitle: subtitle,
      titleColor: danger ? color : null,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

/// A settings page with the item's title.
class _SettingsPage extends StatelessWidget {
  final String title;
  final Widget child;
  const _SettingsPage({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF6F4FA)),
      appBar: AppBar(
        title: Text(title, style: GoogleFonts.merriweather(fontSize: 17, fontWeight: FontWeight.bold, color: AppPalette.fg(_kPurple))),
        centerTitle: true,
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: double.infinity),
          child: ListView(padding: AppSizes.page, children: [
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: child),
            ),
          ]),
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String m, {bool error = false}) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, backgroundColor: error ? Colors.red.shade700 : null));

// ---------------------------------------------------------------------------
// My Account
// ---------------------------------------------------------------------------
class _ProfilePanel extends StatefulWidget {
  final VoidCallback onSaved;
  const _ProfilePanel({required this.onSaved});
  @override
  State<_ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<_ProfilePanel> {
  Map<String, dynamic> _p = {};
  bool _loading = true;
  bool _saving = false;
  final _name = TextEditingController(), _user = TextEditingController(), _phone = TextEditingController(), _bio = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ChatService.myProfile();
    if (!mounted) return;
    setState(() {
      _p = p;
      _name.text = (p['full_name'] ?? '').toString();
      _user.text = (p['username'] ?? '').toString();
      _phone.text = (p['phone'] ?? '').toString();
      _bio.text = (p['bio'] ?? '').toString();
      _loading = false;
    });
  }

  Future<void> _photo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.firstOrNull;
    if (f == null || f.bytes == null) return;
    try {
      final url = await ChatService.uploadAvatar(f.bytes!, f.name);
      setState(() => _p['avatar_url'] = url);
      widget.onSaved();
      if (mounted) _snack(context, "Photo updated");
    } catch (e) {
      if (mounted) _snack(context, "Couldn't upload the photo: $e", error: true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final u = _user.text.trim().toLowerCase();
      if (u.isNotEmpty && u != (_p['username'] ?? '').toString()) await ChatService.setUsername(u);
      await updateMyProfile({
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'bio': _bio.text.trim(),
      });
      widget.onSaved();
      if (mounted) _snack(context, "Profile saved");
    } catch (e) {
      if (mounted) _snack(context, e is PostgrestException ? e.message : "Couldn't save: $e", error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    final avatar = myAvatarUrl.value.isNotEmpty ? myAvatarUrl.value : (_p['avatar_url'] ?? '').toString();
    InputDecoration deco(String l, {String? h, bool at = false}) =>
        InputDecoration(labelText: l, hintText: h, prefixText: at ? '@' : null, isDense: true, border: const OutlineInputBorder());
    Widget info(String l, dynamic v) => ListTile(
          dense: true,
          title: Text(l, style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
          subtitle: Text(((v ?? '').toString().isEmpty || v.toString() == 'N/A') ? '—' : v.toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        );
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        Stack(children: [
          CircleAvatar(
            radius: 46,
            backgroundColor: AppPalette.bg(_kPurple.withValues(alpha: 0.1)),
            backgroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
            child: avatar.isEmpty ? Icon(Icons.person, size: 46, color: AppPalette.fg(_kPurple)) : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: CircleAvatar(
              radius: 17,
              backgroundColor: _kPurple,
              child: IconButton(padding: EdgeInsets.zero, iconSize: 17, onPressed: _photo, icon: const Icon(Icons.camera_alt_rounded, color: Colors.white)),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: deco("Full name")),
        const SizedBox(height: 10),
        TextField(controller: _user, decoration: deco("User name", h: "3–32 letters, numbers or _", at: true)),
        const SizedBox(height: 10),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: deco("WhatsApp number", h: "+256…")),
        const SizedBox(height: 10),
        TextField(controller: _bio, maxLines: 3, maxLength: 160, decoration: deco("Bio")),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kPurple), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(_saving ? "Saving…" : "Save"),
          ),
        ),
        const Divider(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: Text("  Set by your registration (ask the administration to change)", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
        ),
        info("SCJ ID", _p['scj_id'] ?? _p['id_number']),
        info("Email", _p['email']),
        info("Role", (_p['role'] ?? '').toString().replaceAll('_', ' ')),
        info("Unit", [_p['location'], _p['sub_location'], _p['department'], _p['team'], _p['cell_group']].where((x) => (x ?? '').toString().isNotEmpty && x.toString() != 'N/A').join(' › ')),
      ]),
    );
  }
}

class _PasswordPanel extends StatefulWidget {
  final String email;
  const _PasswordPanel({required this.email});
  @override
  State<_PasswordPanel> createState() => _PasswordPanelState();
}

class _PasswordPanelState extends State<_PasswordPanel> {
  final _old = TextEditingController(), _new = TextEditingController(), _conf = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  int get _strength {
    final p = _new.text;
    int s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'\d').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s;
  }

  void _fail(String m) => setState(() => _error = m);

  Future<void> _save() async {
    final db = Supabase.instance.client;
    setState(() => _error = null);
    if (_new.text.length < 8) return _fail("Use at least 8 characters.");
    if (_new.text != _conf.text) return _fail("The new passwords don't match.");
    if (_new.text == _old.text) return _fail("Choose a different password from the current one.");
    setState(() => _busy = true);
    try {
      final email = db.auth.currentUser?.email ?? widget.email;
      if (email.isNotEmpty && _old.text.isNotEmpty) {
        try {
          await db.auth.signInWithPassword(email: email, password: _old.text);
        } catch (_) {
          _fail("The current password is wrong.");
          return;
        }
      }
      await db.auth.updateUser(UserAttributes(password: _new.text));
      if (!mounted) return;
      _snack(context, "Password changed");
      Navigator.pop(context);
    } catch (e) {
      _fail(e is AuthException ? e.message : "Couldn't change the password.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _strength;
    const labels = ["Too weak", "Weak", "Fair", "Good", "Strong"];
    const colors = [Colors.red, Colors.red, Colors.orange, Colors.lightGreen, Colors.green];
    InputDecoration deco(String l) => InputDecoration(
          labelText: l,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: () => setState(() => _show = !_show)),
        );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        TextField(controller: _old, obscureText: !_show, decoration: deco("Current password")),
        const SizedBox(height: 10),
        TextField(controller: _new, obscureText: !_show, onChanged: (_) => setState(() {}), decoration: deco("New password")),
        const SizedBox(height: 6),
        if (_new.text.isNotEmpty)
          Row(children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: (s + 1) / 5, color: colors[s], minHeight: 6))),
            const SizedBox(width: 8),
            Text(labels[s], style: TextStyle(fontSize: 12, color: AppPalette.fg(colors[s]))),
          ]),
        const SizedBox(height: 10),
        TextField(controller: _conf, obscureText: !_show, decoration: deco("Repeat new password")),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_kPurple), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? "Saving…" : "Change password"),
          ),
        ),
        const SizedBox(height: 8),
        Text("Signed in with Google or WhatsApp only? Leave “Current password” empty to set a password for email sign-in.",
            style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
      ]),
    );
  }
}

class _DevicesPanel extends StatefulWidget {
  const _DevicesPanel();
  @override
  State<_DevicesPanel> createState() => _DevicesPanelState();
}

class _DevicesPanelState extends State<_DevicesPanel> {
  List<Map<String, dynamic>> _rows = [];
  String? _myKey;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await DeviceSessions.check(register: true);
      final key = await DeviceSessions.deviceKey();
      final rows = await DeviceSessions.list();
      if (mounted) {
        setState(() {
          _myKey = key;
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(Map r) => switch ((r['platform'] ?? '').toString()) {
        'web' => Icons.language_rounded,
        'android' => Icons.phone_android_rounded,
        'iphone / ipad' => Icons.phone_iphone_rounded,
        'windows' || 'linux' => Icons.desktop_windows_rounded,
        'mac' => Icons.laptop_mac_rounded,
        _ => Icons.devices_other_rounded,
      };

  String _when(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 3) return "online";
    if (d.inMinutes < 60) return "${d.inMinutes} min ago";
    if (d.inHours < 24) return "${d.inHours} h ago";
    return DateFormat('d MMM, HH:mm').format(t);
  }

  Widget _device(Map<String, dynamic> r, {required bool mine}) {
    final place = [r['city'], r['country']].where((x) => (x ?? '').toString().isNotEmpty).join(', ');
    final first = DateTime.tryParse((r['first_seen'] ?? '').toString())?.toLocal();
    return ListTile(
      leading: CircleAvatar(backgroundColor: AppPalette.bg(_kPurple.withValues(alpha: 0.1)), child: Icon(_icon(r), color: AppPalette.fg(_kPurple))),
      title: Text((r['device_name'] ?? 'Device').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        [
          "Master Admin ${r['app_version'] ?? ''}".trim(),
          if (place.isNotEmpty) place,
          if ((r['ip'] ?? '').toString().isNotEmpty) "IP ${r['ip']}",
          mine ? "this device" : _when(r['last_active']?.toString()),
          if (first != null) "since ${DateFormat('d MMM yyyy').format(first)}",
        ].join(' · '),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: mine
          ? Icon(Icons.check_circle_rounded, color: AppPalette.fg(Colors.green.shade700))
          : TextButton(
              onPressed: () async {
                await DeviceSessions.terminate(r['id'].toString());
                await _load();
                if (mounted) _snack(context, "That device will be signed out.");
              },
              child: Text("Terminate", style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
            ),
    );
  }

  Future<void> _terminateAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Terminate all other sessions?"),
        content: const Text("Every other device will be signed out."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Terminate", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    await DeviceSessions.terminateOthers();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    final mine = _rows.where((r) => r['device_key'] == _myKey).toList();
    final others = _rows.where((r) => r['device_key'] != _myKey).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 0), child: Text("This device", style: TextStyle(fontWeight: FontWeight.bold))),
      for (final r in mine) _device(r, mine: true),
      if (others.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: TextButton.icon(
            onPressed: _terminateAll,
            icon: Icon(Icons.phonelink_erase_rounded, color: AppPalette.fg(Colors.red.shade700)),
            label: Text("Terminate all other sessions", style: TextStyle(color: AppPalette.fg(Colors.red.shade700))),
          ),
        ),
        const Divider(height: 1),
        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text("Other devices", style: TextStyle(fontWeight: FontWeight.bold))),
        for (final r in others) _device(r, mine: false),
      ] else
        const Padding(padding: EdgeInsets.all(16), child: Text("You aren't signed in anywhere else.")),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text("The place is approximate, from the internet connection.", style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
      ),
    ]);
  }
}

class _VerificationPanel extends StatefulWidget {
  const _VerificationPanel();
  @override
  State<_VerificationPanel> createState() => _VerificationPanelState();
}

class _VerificationPanelState extends State<_VerificationPanel> {
  Map<String, dynamic> _p = {};
  bool _twoStep = false;

  @override
  void initState() {
    super.initState();
    ChatService.myProfile().then((p) {
      if (mounted) setState(() => _p = p);
    });
    _checkTwoStep();
  }

  Future<void> _checkTwoStep() async {
    try {
      final f = await TwoStep.verifiedFactors();
      if (mounted) setState(() => _twoStep = f.isNotEmpty);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final approved = _p['is_approved'] == true || _p['approval_status'] == 'approved';
    Widget row(bool ok, String title, String sub) => ListTile(
          leading: Icon(ok ? Icons.verified_rounded : Icons.error_outline_rounded, color: AppPalette.fg(ok ? Colors.green.shade700 : Colors.orange.shade800)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(sub),
        );
    return Column(children: [
      row(user?.emailConfirmedAt != null, "Email", user?.emailConfirmedAt != null ? "${user?.email} is confirmed" : "${user?.email ?? ''} is not confirmed yet"),
      row(approved, "Account approval", approved ? "Approved by your administration" : "Waiting for approval"),
      row((_p['scj_id'] ?? '').toString().isNotEmpty, "SCJ ID", (_p['scj_id'] ?? 'Missing').toString()),
      row(AppLockManager.instance.hasPin, "App lock PIN", AppLockManager.instance.hasPin ? "Set" : "Not set (Privacy & Security › App lock)"),
      row(_twoStep, "Two-step verification", _twoStep ? "On" : "Off (Privacy & Security › Two-step verification)"),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Notifications & Sounds
// ---------------------------------------------------------------------------
class _SoundsPanel extends StatefulWidget {
  const _SoundsPanel();
  @override
  State<_SoundsPanel> createState() => _SoundsPanelState();
}

class _SoundsPanelState extends State<_SoundsPanel> {
  @override
  void initState() {
    super.initState();
    AppSounds.load(force: true).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _set(Map<String, dynamic> v) async {
    setState(() {});
    try {
      await AppSounds.save(v);
    } catch (e) {
      if (mounted) _snack(context, "Couldn't save (ask the admin to run 09_round8.sql)", error: true);
    }
    if (mounted) setState(() {});
  }

  Widget _picker(String title, String current, String key) {
    return ExpansionTile(
      leading: const Icon(Icons.library_music_outlined),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(AppSounds.catalog[current] ?? 'Chime'),
      children: [
        RadioGroup<String>(
          groupValue: current,
          onChanged: (v) {
            if (v == null) return;
            _set({key: v});
            AppSounds.play(v);
          },
          child: Column(children: [
            for (final e in AppSounds.catalog.entries)
              RadioListTile<String>(
                dense: true,
                value: e.key,
                title: Text(e.value),
                secondary: e.key == 'none' ? null : IconButton(tooltip: tr("Play"), icon: const Icon(Icons.play_circle_outline_rounded), onPressed: () => AppSounds.play(e.key)),
              ),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SwitchListTile(
        secondary: const Icon(Icons.volume_up_rounded),
        title: const Text("Play sounds", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text("For new notifications and new chat messages"),
        value: AppSounds.soundsOn,
        activeThumbColor: _kPurple,
        onChanged: (v) => _set({'sounds_enabled': v}),
      ),
      ListTile(
        leading: const Icon(Icons.tune_rounded),
        title: const Text("Volume", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Slider(
          value: AppSounds.volume.clamp(0.0, 1.0),
          divisions: 10,
          label: "${(AppSounds.volume * 100).round()}%",
          onChanged: AppSounds.soundsOn ? (v) => setState(() => AppSounds.prefs.value = {...AppSounds.prefs.value, 'sound_volume': v}) : null,
          onChangeEnd: (v) {
            _set({'sound_volume': v});
            AppSounds.play(AppSounds.notifSound, vol: v);
          },
        ),
      ),
      const Divider(height: 1),
      _picker("Notification sound", AppSounds.notifSound, 'notif_sound'),
      _picker("Message sound", AppSounds.messageSound, 'message_sound'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Text("The phone's own volume and silent mode also apply.", style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
      ),
    ]);
  }
}

class _NotificationTypesPanel extends StatefulWidget {
  const _NotificationTypesPanel();
  @override
  State<_NotificationTypesPanel> createState() => _NotificationTypesPanelState();
}

class _NotificationTypesPanelState extends State<_NotificationTypesPanel> {
  @override
  void initState() {
    super.initState();
    AppSounds.load(force: true).then((_) {
      if (mounted) setState(() {});
    });
  }

  bool _v(String k) => AppSounds.prefs.value[k] is bool ? AppSounds.prefs.value[k] as bool : true;

  Future<void> _set(String k, bool v) async {
    try {
      await AppSounds.save({k: v});
    } catch (_) {
      if (mounted) _snack(context, "Couldn't save (ask the admin to run 09_round8.sql)", error: true);
    }
    if (mounted) setState(() {});
  }

  Widget _sw(String k, IconData i, String t, String s) => SwitchListTile(
        secondary: Icon(i),
        title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(s),
        value: _v(k),
        activeThumbColor: _kPurple,
        onChanged: (v) => _set(k, v),
      );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _sw('banners_enabled', Icons.web_asset_rounded, "Pop-up banners", "Show a short banner when something new arrives"),
      const Divider(height: 1),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Align(alignment: Alignment.centerLeft, child: Text("Tell me about", style: TextStyle(fontWeight: FontWeight.bold))),
      ),
      _sw('notify_reports', Icons.assignment_rounded, "My reports", "Approved, moved up a level, or returned for correction"),
      _sw('notify_transfers', Icons.move_up_rounded, "Transfers", "Transfers I requested are approved or rejected"),
      _sw('notify_accounts', Icons.person_rounded, "Account", "My account and answers to my feedback"),
      _sw('notify_messages', Icons.chat_rounded, "Chat messages", "Sound for new messages in My Home"),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text("Everything is still kept in the Notification Center (the bell on the Home page); these choices only decide the sound and banner.",
            style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Privacy & Security
// ---------------------------------------------------------------------------
class _PrivacyRulesPanel extends StatefulWidget {
  final String focus;
  const _PrivacyRulesPanel({required this.focus});
  @override
  State<_PrivacyRulesPanel> createState() => _PrivacyRulesPanelState();
}

class _PrivacyRulesPanelState extends State<_PrivacyRulesPanel> {
  Map<String, dynamic> _p = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ChatService.privacy();
    if (!mounted) return;
    setState(() {
      _p = {'last_seen': 'everyone', 'photo': 'everyone', 'messages': 'everyone', 'groups': 'everyone', 'read_receipts': true, 'typing': true, ...p};
      _loading = false;
    });
  }

  Future<void> _save(String k, dynamic v) async {
    setState(() => _p[k] = v);
    try {
      final values = Map<String, dynamic>.from(_p)
        ..remove('user_id')
        ..remove('updated_at');
      await ChatService.savePrivacy(values);
    } catch (_) {
      if (mounted) _snack(context, "Couldn't save (ask the admin to run 08_round7.sql)", error: true);
    }
  }

  Widget _choice(String k, String title, List<(String, String)> opts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(left: 8, bottom: 4), child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
        RadioGroup<String>(
          groupValue: (_p[k] ?? 'everyone').toString(),
          onChanged: (v) => _save(k, v),
          child: Column(children: [for (final o in opts) RadioListTile<String>(dense: true, value: o.$1, title: Text(o.$2))]),
        ),
      ]),
    );
  }

  Widget _hint(String t) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(t, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    const who3 = [('everyone', 'Everyone'), ('contacts', 'My contacts'), ('nobody', 'Nobody')];
    const who2 = [('everyone', 'Everyone'), ('contacts', 'My contacts')];
    final sections = <String, List<Widget>>{
      'last_seen': [
        _choice('last_seen', "Who can see my last seen & online", who3),
        _hint("If you hide it, you won't see other people's last seen either."),
      ],
      'photo': [_choice('photo', "Who can see my profile photo", who3)],
      'messages': [_choice('messages', "Who can message me", who2), _choice('groups', "Who can add me to groups", who2)],
      'read_receipts': [
        SwitchListTile(
          title: const Text("Read receipts", style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text("Show blue ticks when you read a private chat"),
          value: _p['read_receipts'] != false,
          activeThumbColor: _kPurple,
          onChanged: (v) => _save('read_receipts', v),
        ),
        SwitchListTile(
          title: const Text("Typing indicator", style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text("Show \"typing…\" while you write"),
          value: _p['typing'] != false,
          activeThumbColor: _kPurple,
          onChanged: (v) => _save('typing', v),
        ),
      ],
    };
    // The chosen section first, then the others
    final order = [widget.focus, ...sections.keys.where((k) => k != widget.focus)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final k in order) ...[...?sections[k], if (k != order.last) const Divider(height: 18)],
    ]);
  }
}

class _LocationSharingPanel extends StatefulWidget {
  const _LocationSharingPanel();
  @override
  State<_LocationSharingPanel> createState() => _LocationSharingPanelState();
}

class _LocationSharingPanelState extends State<_LocationSharingPanel> {
  @override
  void initState() {
    super.initState();
    AppSounds.load(force: true).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final on = AppSounds.prefs.value['location_sharing'] != false;
    return Column(children: [
      SwitchListTile(
        secondary: const Icon(Icons.location_on_rounded),
        title: const Text("Allow location sharing", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text("Attach › Location in My Home sends where you are. The app only reads your location when you choose to send it."),
        value: on,
        activeThumbColor: _kPurple,
        onChanged: (v) async {
          await AppSounds.save({'location_sharing': v});
          if (mounted) setState(() {});
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text("Your phone or browser also asks for permission the first time.", style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
      ),
    ]);
  }
}

class _BlockedPanel extends StatefulWidget {
  const _BlockedPanel();
  @override
  State<_BlockedPanel> createState() => _BlockedPanelState();
}

class _BlockedPanelState extends State<_BlockedPanel> {
  List<ChatPerson> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await ChatService.blocked();
      if (mounted) {
        setState(() {
          _list = b;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    if (_list.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text("You haven't blocked anyone. You can block someone from their chat menu in My Home."));
    return Column(children: [
      for (final p in _list)
        ListTile(
          leading: CircleAvatar(child: Text(p.name.isEmpty ? '?' : p.name[0])),
          title: Text(p.name),
          subtitle: (p.username ?? '').isEmpty ? null : Text("@${p.username}"),
          trailing: TextButton(
            onPressed: () async {
              await ChatService.unblock(p.id);
              _load();
            },
            child: const Text("Unblock"),
          ),
        ),
    ]);
  }
}

class _DataProtectionPanel extends StatelessWidget {
  const _DataProtectionPanel();
  @override
  Widget build(BuildContext context) {
    Widget row(IconData i, String t, String s) =>
        ListTile(leading: Icon(i, color: AppPalette.fg(const Color(0xFF00695C))), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(s));
    return Column(children: [
      row(Icons.https_rounded, "Encrypted connection", "Everything between the app and the server travels encrypted (HTTPS)."),
      row(Icons.storage_rounded, "Encrypted storage", "The database and files are stored encrypted by the hosting provider (Supabase)."),
      row(Icons.lock_person_rounded, "Only the right people",
          "Member records, reports, photos and chats can only be read by approved accounts with the right role and unit. The database checks this, not just the app."),
      row(Icons.password_rounded, "Passwords and PINs", "Passwords are never stored in readable form; your app PIN is stored scrambled."),
      row(Icons.photo_library_outlined, "Private files", "Evidence photos, chat files, service pictures and media open only through links that expire."),
    ]);
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Master Administration", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18, color: AppPalette.fg(_kPurple))),
        const SizedBox(height: 4),
        Text("Version ${DeviceSessions.appVersion}"),
        const SizedBox(height: 12),
        const Text("Members, weekly reports, approvals, compilation, communication and office tools for the church."),
        const SizedBox(height: 12),
        const Text("Found a problem or have an idea? Settings › Feedback."),
      ]),
    );
  }
}
