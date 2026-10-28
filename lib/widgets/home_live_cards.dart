import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/i18n.dart';
import '../screens/admin/monthly_executive_report.dart';
import '../screens/communication_screen.dart';
import '../screens/notification_center_screen.dart';
import '../services/chat_service.dart';

/// Touches on the Home screen: the moving cards stop while someone is using
/// the screen and start moving again after a few quiet seconds.
class HomeActivity {
  HomeActivity._();
  static final ValueNotifier<DateTime> last = ValueNotifier(DateTime.now());
  static void touch() => last.value = DateTime.now();
  static bool get idle => DateTime.now().difference(last.value) > const Duration(seconds: 5);
}

enum TickerStyle { rollUp, fade, slideLeft, flip }

/// Shows [visible] of [count] items and moves on by one every few seconds,
/// while the screen is idle. [styles] are used in turn (one per move).
class AutoTicker extends StatefulWidget {
  final int count;
  final int visible;
  final double itemHeight;
  final IndexedWidgetBuilder itemBuilder;
  final List<TickerStyle> styles;
  final Duration every;

  const AutoTicker({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.visible = 5,
    this.itemHeight = 52,
    this.styles = const [TickerStyle.rollUp],
    this.every = const Duration(seconds: 4),
  });

  @override
  State<AutoTicker> createState() => _AutoTickerState();
}

class _AutoTickerState extends State<AutoTicker> {
  Timer? _timer;
  int _start = 0;
  int _moves = 0;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.every, (_) => _step());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _step() {
    if (!mounted || _hover || !HomeActivity.idle || widget.count <= widget.visible) return;
    // nothing moves while the app is in the background or under another screen
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    setState(() {
      _start = (_start + 1) % widget.count;
      _moves++;
    });
  }

  TickerStyle get _style => widget.styles[_moves % widget.styles.length];

  Widget _transition(Widget child, Animation<double> a) {
    switch (_style) {
      case TickerStyle.rollUp:
        return ClipRect(
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: FadeTransition(opacity: a, child: child),
          ),
        );
      case TickerStyle.fade:
        return FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), child: child),
        );
      case TickerStyle.slideLeft:
        return ClipRect(
          child: SlideTransition(
            position: Tween(begin: const Offset(0.3, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: FadeTransition(opacity: a, child: child),
          ),
        );
      case TickerStyle.flip:
        return AnimatedBuilder(
          animation: a,
          child: child,
          builder: (_, c) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX((1 - a.value) * 1.2),
            child: Opacity(opacity: a.value.clamp(0.0, 1.0), child: c),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    final shown = n < widget.visible ? n : widget.visible;
    return MouseRegion(
      onEnter: (_) => _hover = true,
      onExit: (_) => _hover = false,
      child: Listener(
        onPointerDown: (_) => HomeActivity.touch(),
        child: SizedBox(
          height: shown * widget.itemHeight,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 650),
            transitionBuilder: _transition,
            layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev.map((p) => Opacity(opacity: 0, child: p)), if (cur != null) cur]),
            child: Column(
              key: ValueKey(_start),
              children: [
                for (int i = 0; i < shown; i++)
                  SizedBox(height: widget.itemHeight, child: widget.itemBuilder(context, (_start + i) % n)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _cardFrame(BuildContext context, {required IconData icon, required Color color, required String title, required Widget child, VoidCallback? onMore, String more = 'Open'}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
    decoration: BoxDecoration(
      color: AppPalette.bg(cs.surface),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppPalette.line(Colors.black.withValues(alpha: 0.06))),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 14, offset: const Offset(0, 6))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(icon, size: 20, color: AppPalette.fg(color)),
        const SizedBox(width: 6),
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: AppPalette.fg(const Color(0xFF4A148C))))),
        if (onMore != null)
          TextButton(
            onPressed: onMore,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(more, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(color))),
          ),
      ]),
      const Divider(height: 14),
      child,
    ]),
  );
}

Widget _row({required Widget leading, required String title, required String flash, String? time, VoidCallback? onOpen, bool unread = false}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.merriweather(fontSize: 12, fontWeight: unread ? FontWeight.w900 : FontWeight.bold, color: AppPalette.fg(Colors.black87))),
                ),
                if (time != null) Text(time, style: TextStyle(fontSize: 9.5, color: AppPalette.fg(Colors.grey.shade600))),
              ]),
              Text(flash, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade700))),
            ]),
          ),
          if (onOpen != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.chevron_right_rounded, size: 18, color: AppPalette.fg(Colors.grey.shade500)),
            ),
        ]),
      ),
    ),
  );
}

String _ago(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return DateFormat('d MMM').format(t);
}

/// Home › Pop-up notifications: new chat messages and notifications (reports,
/// transfers, accounts …), newest first, rolling up 5 at a time.
class HomeNotificationsCard extends StatefulWidget {
  final String userEmail;
  final String userRole;
  const HomeNotificationsCard({super.key, required this.userEmail, required this.userRole});
  @override
  State<HomeNotificationsCard> createState() => _HomeNotificationsCardState();
}

class _HomeNotificationsCardState extends State<HomeNotificationsCard> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  RealtimeChannel? _ch;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    NotificationCount.unread.addListener(_soon);
    final me = _db.auth.currentUser?.id;
    if (me != null) {
      _ch = _db
          .channel('home-feed-$me')
          .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'chat_messages', callback: (_) => _soon())
          .subscribe();
    }
  }

  @override
  void dispose() {
    NotificationCount.unread.removeListener(_soon);
    _debounce?.cancel();
    final ch = _ch;
    if (ch != null) _db.removeChannel(ch);
    super.dispose();
  }

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _load);
  }

  Future<void> _load() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    final items = <Map<String, dynamic>>[];
    try {
      final n = await _db.from('app_notifications').select('id, kind, title, body, created_at, read_at').eq('user_id', uid).order('created_at', ascending: false).limit(15);
      for (final r in n) {
        items.add({
          'type': 'notice',
          'kind': r['kind'],
          'title': r['title'],
          'flash': (r['body'] ?? '').toString(),
          'at': DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal(),
          'unread': r['read_at'] == null,
        });
      }
    } catch (_) {}
    try {
      final rooms = await ChatService.rooms();
      for (final r in rooms.where((r) => r.unread > 0).take(10)) {
        items.add({
          'type': 'chat',
          'room': r.id,
          'title': r.unread > 1 ? "${r.name} · ${r.unread} new" : r.name,
          'flash': r.lastMessage ?? 'New message',
          'at': r.lastMessageAt?.toLocal(),
          'unread': true,
          'group': r.isGroup,
        });
      }
    } catch (_) {}
    items.sort((a, b) => ((b['at'] as DateTime?) ?? DateTime(2000)).compareTo((a['at'] as DateTime?) ?? DateTime(2000)));
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  void _open(Map<String, dynamic> it) {
    final Widget page = it['type'] == 'chat'
        ? CommunicationScreen(userEmail: widget.userEmail, userRole: widget.userRole, openRoomId: it['room']?.toString())
        : NotificationCenterScreen(userRole: widget.userRole);
    Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) {
      NotificationCount.refresh();
      _load();
    });
  }

  (IconData, Color) _look(Map<String, dynamic> it) {
    if (it['type'] == 'chat') return (it['group'] == true ? Icons.forum_rounded : Icons.chat_bubble_rounded, const Color(0xFF24A1DE));
    return switch ((it['kind'] ?? '').toString()) {
      'report' => (Icons.assignment_turned_in_rounded, const Color(0xFF2E7D32)),
      'transfer' => (Icons.swap_horiz_rounded, const Color(0xFFEF6C00)),
      'account' => (Icons.verified_user_rounded, const Color(0xFF4A148C)),
      _ => (Icons.notifications_rounded, const Color(0xFF1565C0)),
    };
  }

  @override
  Widget build(BuildContext context) {
    return _cardFrame(
      context,
      icon: Icons.notifications_active_rounded,
      color: const Color(0xFF1565C0),
      title: "Pop-up notifications",
      more: "All",
      onMore: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationCenterScreen(userRole: widget.userRole))).then((_) => _load()),
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : _items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text("You're all caught up.", textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey))),
                )
              : AutoTicker(
                  count: _items.length,
                  styles: const [TickerStyle.rollUp],
                  every: const Duration(milliseconds: 3500),
                  itemBuilder: (_, i) {
                    final it = _items[i];
                    final (icon, color) = _look(it);
                    return _row(
                      leading: CircleAvatar(radius: 16, backgroundColor: AppPalette.bg(color.withValues(alpha: 0.12)), child: Icon(icon, size: 16, color: AppPalette.fg(color))),
                      title: (it['title'] ?? '').toString(),
                      flash: (it['flash'] ?? '').toString(),
                      time: _ago(it['at'] as DateTime?),
                      unread: it['unread'] == true,
                      onOpen: () => _open(it),
                    );
                  },
                ),
    );
  }
}

/// Home › Growth status: every duty of the role this month against last
/// month, for the user's own unit (exec_report, 11_round10.sql).
class HomeGrowthCard extends StatefulWidget {
  final String userRole;
  const HomeGrowthCard({super.key, required this.userRole});
  @override
  State<HomeGrowthCard> createState() => _HomeGrowthCardState();
}

class _HomeGrowthCardState extends State<HomeGrowthCard> {
  List<Map<String, dynamic>> _duties = [];
  bool _loading = true;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final prevFrom = DateTime(now.year, now.month - 1, 1);
    final prevTo = from.subtract(const Duration(days: 1));
    final f = DateFormat('yyyy-MM-dd');
    try {
      final res = await Supabase.instance.client.rpc('exec_report', params: {
        'p_from': f.format(from),
        'p_to': f.format(now),
        'p_prev_from': f.format(prevFrom),
        'p_prev_to': f.format(prevTo),
        'p_include_pending': true,
      });
      final d = Map<String, dynamic>.from(res as Map);
      final list = List<Map<String, dynamic>>.from((d['duties'] ?? const []) as List);
      if (mounted) {
        setState(() {
          _duties = list.where((x) => ((x['reports'] ?? 0) as num) > 0 || ((x['prev_reports'] ?? 0) as num) > 0).toList();
          _loading = false;
          _note = _duties.isEmpty ? "No reports this month or last month yet." : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _note = "Growth status isn't available yet.";
        });
      }
    }
  }

  Color _hex(dynamic h) {
    final v = int.tryParse((h ?? '').toString().replaceAll('#', ''), radix: 16);
    return v == null ? const Color(0xFF4A148C) : Color(0xFF000000 | v);
  }

  void _open() => Navigator.push(context, MaterialPageRoute(builder: (_) => MonthlyExecutiveReport(userRole: widget.userRole)));

  @override
  Widget build(BuildContext context) {
    return _cardFrame(
      context,
      icon: Icons.trending_up_rounded,
      color: const Color(0xFF2E7D32),
      title: "Growth status",
      more: "Details",
      onMore: _open,
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : _note != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(_note!, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.grey))),
                )
              : AutoTicker(
                  count: _duties.length,
                  styles: const [TickerStyle.slideLeft, TickerStyle.fade],
                  every: const Duration(milliseconds: 4200),
                  itemBuilder: (_, i) {
                    final d = _duties[i];
                    final rate = ((d['rate'] ?? 0) as num).toDouble();
                    final prev = ((d['prev_rate'] ?? 0) as num).toDouble();
                    final diff = rate - prev;
                    final up = diff >= 0;
                    final color = _hex(d['color']);
                    return _row(
                      leading: SizedBox(
                        width: 34,
                        height: 34,
                        child: Stack(alignment: Alignment.center, children: [
                          CircularProgressIndicator(value: (rate / 100).clamp(0.0, 1.0), strokeWidth: 3.5, color: color, backgroundColor: color.withValues(alpha: 0.12)),
                          Text("${rate.round()}", style: GoogleFonts.merriweather(fontSize: 9.5, fontWeight: FontWeight.w900, color: AppPalette.fg(color))),
                        ]),
                      ),
                      title: (d['label'] ?? d['duty'] ?? '').toString(),
                      flash: "${rate.toStringAsFixed(1)}% this month · ${up ? '▲' : '▼'} ${diff.abs().toStringAsFixed(1)} vs last month",
                      onOpen: _open,
                    );
                  },
                ),
    );
  }
}
