import 'dart:async';

import 'package:material_ui/material_ui.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import 'admin/approval_inbox.dart';
import '../widgets/role_change_inbox.dart';
import '../services/app_sounds.dart';
import '../services/media_playback.dart' show appNavigatorKey;
import '../services/member_view_access.dart';

/// Unread notifications for the signed-in user, live (for the bell badge).
class NotificationCount {
  NotificationCount._();
  static final ValueNotifier<int> unread = ValueNotifier(0);
  static RealtimeChannel? _channel;
  static String? _for;

  static Future<void> refresh() async {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) {
      unread.value = 0;
      return;
    }
    try {
      final rows = await db.from('app_notifications').select('id').eq('user_id', uid).isFilter('read_at', null).limit(100);
      unread.value = (rows as List).length;
    } catch (_) {}
    if (_for != uid) {
      _for = uid;
      _channel?.unsubscribe();
      _channel = db
          .channel('notif-$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'app_notifications',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
            callback: (p) {
              if (p.eventType == PostgresChangeEvent.insert) _announce(p.newRecord);
              refresh();
            },
          )
          .subscribe();
      AppSounds.load(force: true);
    }
  }

  /// A new notification: its sound and a short banner (both can be turned
  /// off in Settings › Notifications & Sounds).
  static void _announce(Map<String, dynamic> n) {
    final kind = (n['kind'] ?? 'info').toString();
    AppSounds.notification(kind);
    if (!AppSounds.bannersOn || !AppSounds.wants(kind)) return;
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((n['title'] ?? 'Notification').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
        if ((n['body'] ?? '').toString().isNotEmpty) Text(n['body'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
      action: SnackBarAction(
        label: "Open",
        onPressed: () => appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
      ),
    ));
  }
}

/// Notification Center: what happened to my reports and transfer
/// requests (Pending, Approved, Rejected), plus account messages.
/// Notifications are written by the database when a reviewer decides
/// (09_round8.sql), so they arrive whoever approved and from any device.
class NotificationCenterScreen extends StatefulWidget {
  /// Role used for the transfer approvals inbox (reviewers).
  final String? userRole;
  /// Show "Transfer approvals" (roles with the Notification Center action).
  final bool canReviewTransfers;
  const NotificationCenterScreen({super.key, this.userRole, this.canReviewTransfers = false});
  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> with TickerProviderStateMixin {
  bool _canReviewTransfers = false; // a step in transfer_steps is mine (13_round12.sql)

  final _db = Supabase.instance.client;
  static const Color _purple = Color(0xFF4A148C);
  /// Tabs this user needs (my_notification_tabs, 14_round13.sql): Transfers
  /// only for roles that request or approve transfers, My reports only for
  /// roles with duties. Everyone has Notifications.
  bool _showReports = true, _showTransfers = true;
  TabController? _tabs;

  void _setTabs(bool reports, bool transfers) {
    final n = 1 + (reports ? 1 : 0) + (transfers ? 1 : 0);
    _showReports = reports;
    _showTransfers = transfers;
    if (_tabs?.length != n) {
      _tabs?.dispose();
      _tabs = TabController(length: n, vsync: this);
    }
  }

  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _transfers = [];
  bool _loading = true;
  String? _error;
  String _reportFilter = 'All';
  String _cat = 'all'; // Notifications tab: the topic shown
  int _roleChanges = 0; // role changes waiting for me (role_change_inbox)
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _setTabs(true, true);
    Supabase.instance.client.rpc('can_review_transfers').then((v) {
      if (mounted && v == true) setState(() => _canReviewTransfers = true);
    }, onError: (_) {});
    _loadTabs();
    _load();
    _loadRoleChanges();
    NotificationCount.unread.addListener(_onLive);
  }

  @override
  void dispose() {
    NotificationCount.unread.removeListener(_onLive);
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _loadTabs() async {
    try {
      final v = await _db.rpc('my_notification_tabs');
      if (!mounted || v is! Map) return;
      final transfers = v['transfers'] == true || widget.canReviewTransfers;
      setState(() => _setTabs(v['reports'] != false || _reports.isNotEmpty, transfers));
    } catch (_) {
      // before 14_round13.sql: keep all tabs
    }
  }

  void _onLive() {
    _loadNotes();
    _loadRoleChanges();
  }

  Future<void> _loadRoleChanges() async {
    try {
      final r = await _db.rpc('role_change_inbox');
      if (mounted) setState(() => _roleChanges = (r as List).length);
    } catch (_) {}
  }

  // ------------------------------------------------------------ topics

  /// Topics of the Notifications tab: key, name, icon.
  static const List<(String, String, IconData)> _cats = [
    ('reports', 'Reports', Icons.assignment_rounded),
    ('transfers', 'Transfers', Icons.move_up_rounded),
    ('accounts', 'Accounts & roles', Icons.manage_accounts_rounded),
    ('members', 'Member profiles', Icons.badge_rounded),
    ('evangelism', 'Evangelism', Icons.campaign_rounded),
    ('activities', 'Tasks & activities', Icons.event_note_rounded),
    ('education', 'Education', Icons.menu_book_rounded),
    ('other', 'Feedback & other', Icons.notifications_rounded),
  ];

  /// The topic of a notification, from its kind (and where it links to).
  static String catOf(Map n) {
    final k = (n['kind'] ?? '').toString().toLowerCase();
    final l = (n['link_type'] ?? '').toString().toLowerCase();
    if (k == 'report' || l.startsWith('logs_')) return 'reports';
    if (k == 'transfer' || l.contains('transfer')) return 'transfers';
    if (k == 'account' || k == 'security' || k == 'role' || l == 'profiles') return 'accounts';
    if (k == 'member' || l.contains('member')) return 'members';
    if (k == 'evangelism' || k.startsWith('bb') || l.startsWith('bb_')) return 'evangelism';
    if (k == 'task' || k == 'activity' || k == 'asmis' || k == 'calendar' || l.contains('activity') || l.contains('task')) return 'activities';
    if (k == 'education' || l.startsWith('edu')) return 'education';
    return 'other';
  }

  (String, String, IconData) _catInfo(String key) => _cats.firstWhere((c) => c.$1 == key, orElse: () => _cats.last);

  Future<void> _markCatRead(String cat) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final ids = [for (final n in _notes) if (n['read_at'] == null && catOf(n) == cat) n['id']];
    if (ids.isEmpty) return;
    setState(() {
      for (final n in _notes) {
        if (n['read_at'] == null && catOf(n) == cat) n['read_at'] = now;
      }
    });
    try {
      await _db.from('app_notifications').update({'read_at': now}).inFilter('id', ids);
    } catch (_) {}
    NotificationCount.refresh();
  }

  Future<void> _loadNotes() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final n = await _db.from('app_notifications').select().eq('user_id', uid).order('created_at', ascending: false).limit(200);
      if (mounted) setState(() => _notes = List<Map<String, dynamic>>.from(n));
    } catch (_) {}
  }

  Future<void> _load() async {
    _loadRoleChanges();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _db.auth.currentUser?.id;
      final results = await Future.wait<dynamic>([
        _db.from('app_notifications').select().eq('user_id', uid ?? '').order('created_at', ascending: false).limit(200),
        _db.rpc('my_reports', params: {'p_days': _days}),
        _db.rpc('my_transfer_requests'),
      ]);
      if (!mounted) return;
      List<Map<String, dynamic>> maps(dynamic x) => List<Map<String, dynamic>>.from((x as List).map((e) => Map<String, dynamic>.from(e as Map)));
      final reports = maps(results[1])
        ..sort((a, b) {
          final c = (b['report_date'] ?? '').toString().compareTo((a['report_date'] ?? '').toString());
          return c != 0 ? c : (a['duty'] ?? '').toString().compareTo((b['duty'] ?? '').toString());
        });
      setState(() {
        _notes = maps(results[0]);
        _reports = reports;
        _transfers = maps(results[2]);
        _loading = false;
      });
      NotificationCount.refresh();
    } catch (e) {
      debugPrint("Notification center: $e");
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load your notifications. Check your internet connection and refresh.";
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.from('app_notifications').update({'read_at': now}).eq('user_id', uid).isFilter('read_at', null);
    setState(() {
      for (final n in _notes) {
        n['read_at'] ??= now;
      }
    });
    NotificationCount.refresh();
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    if (n['read_at'] != null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    setState(() => n['read_at'] = now);
    await _db.from('app_notifications').update({'read_at': now}).eq('id', n['id']);
    NotificationCount.refresh();
  }

  Future<void> _delete(Map<String, dynamic> n) async {
    setState(() => _notes.remove(n));
    await _db.from('app_notifications').delete().eq('id', n['id']);
    NotificationCount.refresh();
  }

  static (Color, IconData) _statusLook(String s) => switch (s) {
        'Approved' => (Colors.green.shade700, Icons.verified_rounded),
        'Rejected' => (Colors.red.shade700, Icons.assignment_return_rounded),
        _ => (Colors.orange.shade800, Icons.hourglass_top_rounded),
      };

  Widget _statusChip(String s) {
    final (c, i) = _statusLook(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: AppPalette.bg(c.withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppPalette.line(c.withValues(alpha: 0.35)))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 14, color: AppPalette.fg(c)),
        const SizedBox(width: 4),
        Text(s, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppPalette.fg(c))),
      ]),
    );
  }

  String _ago(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return "just now";
    if (d.inMinutes < 60) return "${d.inMinutes} min ago";
    if (d.inHours < 24) return "${d.inHours} h ago";
    if (d.inDays < 7) return "${d.inDays} d ago";
    return DateFormat('d MMM yyyy').format(t);
  }

  Widget _wrap(List<Widget> children) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 40), children: [
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: double.infinity), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
        ]),
      );

  Widget _empty(IconData i, String t) => Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Icon(i, size: 44, color: AppPalette.fg(Colors.grey.shade400)),
          const SizedBox(height: 10),
          Text(t, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))),
        ]),
      );

  Widget _notesTab() {
    final unread = _notes.where((n) => n['read_at'] == null).length;
    final byCat = <String, List<Map<String, dynamic>>>{};
    for (final n in _notes) {
      byCat.putIfAbsent(catOf(n), () => []).add(n);
    }
    int unreadOf(String c) => (byCat[c] ?? const []).where((n) => n['read_at'] == null).length + (c == 'accounts' ? _roleChanges : 0);
    final present = [for (final c in _cats) if ((byCat[c.$1]?.isNotEmpty ?? false) || (c.$1 == 'accounts' && _roleChanges > 0)) c];
    if (_cat != 'all' && !present.any((c) => c.$1 == _cat)) _cat = 'all';

    Widget chip(String key, String label, IconData icon, int count) {
      final on = _cat == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          avatar: Icon(icon, size: 16, color: on ? Colors.white : AppPalette.fg(_purple)),
          label: Text.rich(TextSpan(text: count > 0 ? "${tr(label)} ($count)" : tr(label)),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: on ? Colors.white : AppPalette.fg(_purple))),
          selected: on,
          showCheckmark: false,
          selectedColor: _purple,
          onSelected: (_) => setState(() => _cat = key),
        ),
      );
    }

    Widget header(String key, {bool showAll = false}) {
      final (_, name, icon) = _catInfo(key);
      final u = unreadOf(key);
      final total = (byCat[key]?.length ?? 0);
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Row(children: [
          CircleAvatar(radius: 14, backgroundColor: AppPalette.bg(_purple.withValues(alpha: 0.1)), child: Icon(icon, size: 16, color: AppPalette.fg(_purple))),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(text: u > 0 ? "${tr(name)} · $u ${tr('unread')}" : tr(name)),
                style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppPalette.fg(_purple))),
          ),
          if (showAll && total > 3) TextButton(onPressed: () => setState(() => _cat = key), child: Text.rich(TextSpan(text: "${tr('See all')} ($total)"))),
          if (!showAll && u > 0) TextButton.icon(onPressed: () => _markCatRead(key), icon: const Icon(Icons.done_all_rounded, size: 16), label: const Text("Mark read")),
        ]),
      );
    }

    Widget tile(Map<String, dynamic> n) => Dismissible(
          key: ValueKey(n['id']),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: AppPalette.bg(Colors.red.shade50), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.delete_outline, color: AppPalette.fg(Colors.red.shade700)),
          ),
          onDismissed: (_) => _delete(n),
          child: _noteTile(n),
        );

    final body = <Widget>[];
    if (_cat == 'all') {
      for (final c in present) {
        body.add(header(c.$1, showAll: true));
        if (c.$1 == 'accounts') body.add(const RoleChangeInboxTile());
        // unread first, then the newest; 3 per topic here
        final list = [...(byCat[c.$1] ?? const <Map<String, dynamic>>[])]..sort((a, b) => (a['read_at'] == null ? 0 : 1).compareTo(b['read_at'] == null ? 0 : 1));
        for (final n in list.take(3)) {
          body.add(tile(n));
        }
      }
    } else {
      body.add(header(_cat));
      if (_cat == 'accounts') body.add(const RoleChangeInboxTile());
      for (final n in byCat[_cat] ?? const <Map<String, dynamic>>[]) {
        body.add(tile(n));
      }
    }

    return _wrap([
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip('all', 'All', Icons.inbox_rounded, unread + _roleChanges),
          for (final c in present) chip(c.$1, c.$2, c.$3, unreadOf(c.$1)),
        ]),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: Text(unread == 0 ? "All caught up" : "$unread unread", style: const TextStyle(fontWeight: FontWeight.bold))),
        if (unread > 0 && _cat == 'all') TextButton.icon(onPressed: _markAllRead, icon: const Icon(Icons.done_all_rounded, size: 18), label: const Text("Mark all read")),
      ]),
      if (_notes.isEmpty && _roleChanges == 0)
        _empty(Icons.notifications_none_rounded, "No notifications yet. You'll be told here when your reports or transfers are approved or returned.")
      else
        ...body,
    ]);
  }

  Widget _noteTile(Map<String, dynamic> n) {
    final unread = n['read_at'] == null;
    final title = (n['title'] ?? '').toString();
    final status = title.contains('returned') || title.contains('rejected') || title.contains('not approved')
        ? 'Rejected'
        : (title.contains('approved') || title.contains('complete') ? 'Approved' : 'Pending');
    final (c, _) = _statusLook(status);
    final icon = _catInfo(catOf(n)).$3;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: unread ? 2 : 0.5,
      color: AppPalette.bg(unread ? Color.lerp(_purple, Colors.white, 0.95) : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _markRead(n);
          // a leader asked to view member details: answer it here
          if ((n['link_type'] ?? '').toString() == 'member_view_request') MemberViewAccess.showRequests(context);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 19, backgroundColor: AppPalette.bg(c.withValues(alpha: 0.12)), child: Icon(icon, size: 19, color: AppPalette.fg(c))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(title, style: TextStyle(fontWeight: unread ? FontWeight.w900 : FontWeight.w600, fontSize: 14))),
                  if (unread) Container(width: 9, height: 9, decoration: const BoxDecoration(color: _purple, shape: BoxShape.circle)),
                ]),
                if ((n['body'] ?? '').toString().isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 3), child: Text(n['body'].toString(), style: TextStyle(fontSize: 12.5, height: 1.35, color: AppPalette.fg(Colors.grey.shade800)))),
                const SizedBox(height: 4),
                Text(_ago(n['created_at']?.toString()), style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade600))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _reportsTab() {
    final counts = {for (final s in ['Pending', 'Approved', 'Rejected']) s: _reports.where((r) => r['status'] == s).length};
    final list = _reportFilter == 'All' ? _reports : _reports.where((r) => r['status'] == _reportFilter).toList();
    return _wrap([
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final f in ['All', 'Pending', 'Approved', 'Rejected'])
          ChoiceChip(
            label: Text(f == 'All' ? "All (${_reports.length})" : "$f (${counts[f]})"),
            selected: _reportFilter == f,
            onSelected: (_) => setState(() => _reportFilter = f),
          ),
        const SizedBox(width: 6),
        DropdownButton<int>(
          value: _days,
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(value: 7, child: Text("Last 7 days")),
            DropdownMenuItem(value: 30, child: Text("Last 30 days")),
            DropdownMenuItem(value: 90, child: Text("Last 3 months")),
            DropdownMenuItem(value: 365, child: Text("Last year")),
          ],
          onChanged: (v) {
            setState(() => _days = v ?? 30);
            _load();
          },
        ),
      ]),
      const SizedBox(height: 10),
      if (list.isEmpty)
        _empty(Icons.assignment_outlined, _reports.isEmpty ? "You haven't saved any reports in this period." : "No $_reportFilter reports.")
      else
        for (final r in list)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text((r['duty'] ?? '').toString(), style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, fontSize: 14))),
                  _statusChip((r['status'] ?? 'Pending').toString()),
                ]),
                const SizedBox(height: 4),
                Text(
                  [
                    DateFormat('EEE d MMM yyyy').format(DateTime.tryParse((r['report_date'] ?? '').toString()) ?? DateTime.now()),
                    if ((r['unit_name'] ?? '').toString().isNotEmpty) "Unit ${r['unit_name']}",
                    "${r['rows_count'] ?? 0} member${r['rows_count'] == 1 ? '' : 's'}",
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.grey.shade700)),
                ),
                if (r['status'] == 'Pending')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      (r['approval_level'] ?? 0) == 0 ? "Waiting for the first review" : "Approved up to level ${r['approval_level']}, waiting for the next reviewer",
                      style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.orange.shade900)),
                    ),
                  ),
                if (r['status'] == 'Rejected' && (r['correction_note'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: AppPalette.bg(Colors.red.shade50), borderRadius: BorderRadius.circular(8)),
                      child: Text("To correct: ${r['correction_note']}", style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.red.shade900))),
                    ),
                  ),
              ]),
            ),
          ),
    ]);
  }

  String _unitText(dynamic u) {
    if (u is! Map) return (u ?? '').toString();
    return ['location', 'sub_location', 'department', 'team', 'cell_group', 'cell']
        .map((k) => (u[k] ?? '').toString())
        .where((x) => x.isNotEmpty && x.toLowerCase() != 'n/a')
        .join(' › ');
  }

  Widget _transfersTab() {
    return _wrap([
      if (widget.canReviewTransfers || _canReviewTransfers)
        Card(
          margin: const EdgeInsets.only(bottom: 14),
          color: AppPalette.bg(Color.lerp(_purple, Colors.white, 0.92)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: Icon(Icons.inbox_rounded, color: AppPalette.fg(_purple)),
            title: const Text("Transfer approvals", style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text("Requests waiting for your decision (Governance Inbox)"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ApprovalInbox(userRole: widget.userRole ?? ''))).then((_) => _load()),
          ),
        ),
      Text("Transfers I requested", style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, fontSize: 14.5)),
      const SizedBox(height: 8),
      if (_transfers.isEmpty)
        _empty(Icons.move_up_rounded, "You haven't requested any member transfers.")
      else
        for (final t in _transfers)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text((t['member_name'] ?? 'Member').toString(), style: GoogleFonts.merriweather(fontWeight: FontWeight.w800, fontSize: 14))),
                  _statusChip((t['status'] ?? 'Pending').toString()),
                ]),
                const SizedBox(height: 6),
                if (_unitText(t['from_unit']).isNotEmpty) Text("From: ${_unitText(t['from_unit'])}", style: const TextStyle(fontSize: 12.5)),
                if (_unitText(t['to_unit']).isNotEmpty) Text("To: ${_unitText(t['to_unit'])}", style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(
                  [
                    "Requested ${_ago(t['created_at']?.toString())}",
                    if (t['status'] == 'Pending' && (t['current_level'] ?? '').toString().isNotEmpty) "now at ${t['current_level']}",
                  ].join(' · '),
                  style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700)),
                ),
              ]),
            ),
          ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notes.where((n) => n['read_at'] == null).length;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF7F5FB)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        title: Text("Notification Center", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [IconButton(tooltip: tr("Refresh"), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
        bottom: TabBar(
          controller: _tabs!,
          labelColor: _purple,
          indicatorColor: _purple,
          isScrollable: MediaQuery.of(context).size.width < 420,
          tabs: [
            Tab(text: unread > 0 ? "Notifications ($unread)" : "Notifications"),
            if (_showReports) Tab(text: tr("My reports")),
            if (_showTransfers) Tab(text: tr("Transfers")),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : TabBarView(controller: _tabs!, children: [_notesTab(), if (_showReports) _reportsTab(), if (_showTransfers) _transfersTab()]),
    );
  }
}
