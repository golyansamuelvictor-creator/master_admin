// ignore_for_file: deprecated_member_use, use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notice_permissions.dart';
import 'package:master_admin/core/app_palette.dart';

class CalendarScreen extends StatefulWidget {
  final double s;
  final bool isFullPage;

  const CalendarScreen({super.key, this.s = 1.0, this.isFullPage = false});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _supabase = Supabase.instance.client;
  String _selectedType = "Month";
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Color pPurple = const Color(0xFF4A148C);
  
  Map<DateTime, List<dynamic>> _events = {};
  bool _isLoading = false;

  // Who may add events comes from the role's admin actions (app_roles):
  // church events by "Manage Church Events", location events by "Manage Location Events"
  NoticePermissions _perm = NoticePermissions.none;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchEvents();
    NoticePermissions.load().then((p) {
      if (mounted) setState(() => _perm = p);
    });
  }

  bool _canManageEvent(dynamic e) {
    if (e['type'] != 'event') return false;
    if (_perm.isAdmin) return true;
    final level = (e['scope_level'] ?? 'church').toString();
    if (level == 'church') return _perm.can(NoticePermissions.churchEvents);
    if (level == 'location') return _perm.can(NoticePermissions.locationEvents) && e['scope_location'] == _perm.location;
    return false;
  }

  static String _timeLabel(dynamic t) {
    final raw = (t ?? '').toString();
    if (raw.isEmpty) return "All Day";
    final parts = raw.split(':');
    final h = int.tryParse(parts[0]);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    if (h == null || m == null) return raw;
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
  }

  Future<void> _showEventDetails(dynamic e) async {
    final canManage = _canManageEvent(e);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text((e['title'] ?? '').toString(), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(pPurple))),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                [
                  if (e['type'] == 'event') (e['category'] ?? 'Event').toString() else 'Task deadline',
                  if (e['type'] == 'event') _timeLabel(e['event_time']),
                  if (e['scope_level'] == 'location' && e['scope_location'] != null) e['scope_location'].toString(),
                ].join('  •  '),
                style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.blueGrey[700]), fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text((e['description'] ?? e['task_description'] ?? '').toString(), style: GoogleFonts.merriweather(fontSize: 13, height: 1.5)),
            ]),
          ),
        ),
        actions: [
          if (canManage) TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text("Remove", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
    if (action != 'delete') return;
    try {
      await _supabase.from('church_events').delete().eq('id', e['id']);
      _fetchEvents();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't remove it. You may not have permission.")));
      }
    }
  }

  Future<void> _fetchEvents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final eventRes = await _supabase.from('church_events').select();
      final taskRes = await _supabase.from('leader_tasks').select();
      Map<DateTime, List<dynamic>> newEvents = {};
      
      for (var e in (eventRes as List)) {
        final DateTime? parsed = DateTime.tryParse((e['event_date'] ?? '').toString());
        if (parsed == null) continue;
        DateTime d = parsed;
        DateTime key = DateTime(d.year, d.month, d.day);
        if (newEvents[key] == null) newEvents[key] = [];
        newEvents[key]!.add({...e, 'type': 'event'});
      }
      for (var t in (taskRes as List)) {
        final DateTime? parsed = DateTime.tryParse((t['due_date'] ?? '').toString());
        if (parsed == null) continue;
        DateTime d = parsed;
        DateTime key = DateTime(d.year, d.month, d.day);
        if (newEvents[key] == null) newEvents[key] = [];
        newEvents[key]!.add({...t, 'type': 'task'});
      }
      if (mounted) setState(() { _events = newEvents; _isLoading = false; });
    } catch (e) { 
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  List<dynamic> _getEventsForDay(DateTime day) => _events[DateTime(day.year, day.month, day.day)] ?? [];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      bool isDesktop = constraints.maxWidth > 1100;
      
      Widget bodyContent = SizedBox.expand(
        child: _isLoading 
        ? Center(child: CircularProgressIndicator(color: pPurple))
        : SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(8), // Tightened spacing
            child: Column(children: [
              _buildHeader(isDesktop),
              const SizedBox(height: 8),
              if (isDesktop)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 2, child: _buildLeftColumn()), 
                  const SizedBox(width: 8),
                  Expanded(flex: 5, child: _buildMiddleColumn()), 
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _buildRightColumn()), 
                ])
              else
                Column(children: [
                  _buildMiddleColumn(),
                  const SizedBox(height: 8),
                  _buildLeftColumn(),
                  const SizedBox(height: 8),
                  _buildRightColumn(),
                ]),
              const SizedBox(height: 50),
            ]),
          ),
      );

      return widget.isFullPage ? bodyContent : Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white), 
          elevation: 0.5, 
          centerTitle: true,
          title: Text("Master Calendar", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 18))
        ),
        body: bodyContent,
      );
    });
  }

  // --- HEADER: CENTER ALIGNED WITH SUB-CARD ---
  Widget _buildHeader(bool isDesktop) {
    return _card(
      padding: 6, // Halved height
      child: Row(
        children: [
          const SizedBox(width: 10),
          Expanded(
            child: Center(
              child: Container( // Title Sub-card
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.bg(pPurple.withValues(alpha: 0.04)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.1)))
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text("Calendar View", style: GoogleFonts.merriweather(fontSize: isDesktop ? 24 : 18, fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple))),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: AppPalette.bg(pPurple.withValues(alpha: 0.05)), borderRadius: BorderRadius.circular(10)),
            child: DropdownButton<String>(
              value: _selectedType, 
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppPalette.fg(pPurple)),
              underline: const SizedBox(),
              style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.fg(pPurple)),
              items: ["Day", "Week", "Month", "Quarter", "Half Year", "Year"]
                  .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() { _selectedType = v!; _focusedDay = DateTime.now(); }),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  // --- LEFT COLUMN ---
  Widget _buildLeftColumn() {
    return Column(children: [
      _card(
        padding: 8,
        color: pPurple.withValues(alpha: 0.02),
        child: _card(
          padding: 5, 
          child: TableCalendar(
            firstDay: DateTime.utc(2020), lastDay: DateTime.utc(2030),
            focusedDay: _focusedDay, calendarFormat: CalendarFormat.month,
            headerVisible: false, 
            rowHeight: 32, 
            daysOfWeekHeight: 48,
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.w900), // Slightly increased
              weekendStyle: GoogleFonts.merriweather(fontSize: 13, color: AppPalette.fg(Colors.red), fontWeight: FontWeight.w900),
            ),
            calendarBuilders: _miniCalendarBuilders(),
          )
        ),
      ),
      const SizedBox(height: 8),
      _card(
        padding: 12,
        child: Column(children: [
          _card(
            padding: 6,
            color: pPurple.withValues(alpha: 0.08),
            child: Center(child: Text("CATEGORIES", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12, color: AppPalette.fg(pPurple), letterSpacing: 1.2))),
          ),
          const SizedBox(height: 8),
          _categorySmallCard("Public holiday", Colors.red),
          _categorySmallCard("Church events", Colors.blue),
          _categorySmallCard("Location events", pPurple),
          _categorySmallCard("Task deadline", Colors.orange),
        ]),
      ),
    ]);
  }

  Widget _buildMiddleColumn() {
    bool isMultiMonth = ["Quarter", "Half Year", "Year"].contains(_selectedType);
    Widget content = Column(children: _buildDynamicCalendarContent());

    if (isMultiMonth) {
      return _card(
        padding: 10,
        child: Column(
          children: [
            _card( // Outstanding Extended View Card
              padding: 8,
              color: Colors.white,
              child: Center(child: Text("Extended View: $_selectedType", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 13))),
            ),
            const SizedBox(height: 8),
            content,
          ],
        ),
      );
    }
    return content;
  }

  Widget _buildRightColumn() {
    final todayEvents = _getEventsForDay(_selectedDay ?? _focusedDay);
    return Column(children: [
      if (_perm.canAddEvents) _card(padding: 8, child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _showAddEventFullScreen(context), 
          icon: const Icon(Icons.add_rounded, size: 20), label: Text("NEW EVENT", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(pPurple), foregroundColor: AppPalette.fg(Colors.white), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
      )),
      const SizedBox(height: 8),
      _card(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        _card(
          padding: 6,
          color: Colors.blueGrey.withValues(alpha: 0.05),
          child: Center(child: Text("DAILY SCHEDULE", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12, color: AppPalette.fg(Colors.blueGrey), letterSpacing: 1.2)))
        ),
        const SizedBox(height: 10),
        if (todayEvents.isEmpty) Center(child: Text("No events found.", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey), fontSize: 14))),
        ...todayEvents.map((e) => InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _showEventDetails(e),
              child: _eventItem(
                (e['title'] ?? e['task_title'] ?? 'Untitled').toString(),
                e['type'] == 'task' ? "Task deadline" : _timeLabel(e['event_time']),
                e['type'] == 'task' ? Colors.orange : _getCategoryColor(e['category']),
              ),
            )),
      ])),
    ]);
  }

  List<Widget> _buildDynamicCalendarContent() {
    int monthCount = 1;
    if (_selectedType == "Quarter") monthCount = 3;
    else if (_selectedType == "Half Year") monthCount = 6;
    else if (_selectedType == "Year") monthCount = 12;

    if (_selectedType == "Day") return [_card(child: _buildHourlyGrid(1))];
    if (_selectedType == "Week") return [_card(child: _buildHourlyGrid(7))];

    return List.generate(monthCount, (index) {
      DateTime monthDate = DateTime(_focusedDay.year, _focusedDay.month + index);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8), 
        child: _card(
          padding: 10,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1)), icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppPalette.fg(pPurple), size: 18)),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(DateFormat('MMMM yyyy').format(monthDate), textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple))))),
                  IconButton(onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1)), icon: Icon(Icons.arrow_forward_ios_rounded, color: AppPalette.fg(pPurple), size: 18)),
                ],
              ),
              const SizedBox(height: 8),
              TableCalendar(
                firstDay: DateTime.utc(2020), lastDay: DateTime.utc(2030),
                focusedDay: monthDate,
                rowHeight: 48, 
                daysOfWeekHeight: 52,
                calendarFormat: CalendarFormat.month,
                eventLoader: _getEventsForDay,
                headerVisible: false,
                calendarBuilders: _mainCalendarBuilders(),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14), // Increased size
                  weekendStyle: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: AppPalette.fg(Colors.red)),
                ),
                onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              ),
            ],
          ),
        ),
      );
    });
  }

  // --- GOOGLE CALENDAR STYLE: SCROLLABLE 24H GRID ---
  Widget _buildHourlyGrid(int dayCount) {
    DateTime startOfWeek = _focusedDay.subtract(Duration(days: _focusedDay.weekday % 7));
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 50),
            ...List.generate(dayCount, (i) {
              DateTime day = dayCount == 1 ? _focusedDay : startOfWeek.add(Duration(days: i));
              return Expanded(
                child: Center(
                  child: Column(
                    children: [
                      Text(DateFormat('E').format(day), style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.grey))),
                      Text(DateFormat('d').format(day), style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.w900, color: AppPalette.fg(isSameDay(day, DateTime.now()) ? pPurple : Colors.black87))),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        const Divider(),
        SizedBox(
          height: 500,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: List.generate(24, (i) => Container(
                    height: 30, // Reduced by half
                    width: 50,
                    alignment: Alignment.topCenter,
                    child: Text("${i == 0 ? 12 : i > 12 ? i - 12 : i} ${i >= 12 ? 'PM' : 'AM'}", 
                      style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.blueGrey))),
                  )),
                ),
                Expanded(
                  child: Column(
                    children: List.generate(24, (hourIndex) => Container(
                      height: 30, // Reduced by half
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppPalette.line(Colors.grey.withValues(alpha: 0.1))))),
                      child: Row(
                        children: List.generate(dayCount, (dayIndex) => Expanded(
                          child: Container(decoration: BoxDecoration(border: Border(right: BorderSide(color: AppPalette.line(Colors.grey.withValues(alpha: 0.05)))))),
                        )),
                      ),
                    )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- CALENDAR BUILDERS ---
  CalendarBuilders _miniCalendarBuilders() {
    Widget gridBox(DateTime day, Color textColor, {Color? bg}) => Container(
        decoration: BoxDecoration(color: AppPalette.bg(bg), border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.08)), width: 0.5)),
        child: Center(child: Text("${day.day}", style: GoogleFonts.merriweather(fontSize: 10, color: AppPalette.fg(textColor), fontWeight: FontWeight.bold))),
    );
    return CalendarBuilders(
      defaultBuilder: (context, day, focusedDay) => gridBox(day, (day.weekday > 5) ? Colors.red : Colors.black87),
      outsideBuilder: (context, day, focusedDay) => gridBox(day, Colors.grey),
      todayBuilder: (context, day, focusedDay) => gridBox(day, pPurple, bg: pPurple.withValues(alpha: 0.1)),
    );
  }

  CalendarBuilders _mainCalendarBuilders() {
    Widget dateTile(DateTime day, {Color? textColor, bool isSelected = false, bool isToday = false}) => Container(
        margin: const EdgeInsets.all(2), 
        decoration: BoxDecoration(
          color: AppPalette.bg(isSelected ? pPurple : (isToday ? Colors.orangeAccent.withValues(alpha: 0.1) : Colors.white)),
          borderRadius: BorderRadius.circular(8), 
          border: Border.all(color: AppPalette.line(isSelected ? pPurple : (isToday ? Colors.orangeAccent : Colors.grey.withValues(alpha: 0.1))), width: 1),
        ),
        child: Center(child: Text("${day.day}", style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.fg(isSelected ? Colors.white : (textColor ?? Colors.black87))))),
    );
    return CalendarBuilders(
      defaultBuilder: (context, day, focusedDay) => dateTile(day, textColor: (day.weekday > 5) ? Colors.red : null),
      todayBuilder: (context, day, focusedDay) => dateTile(day, isToday: true),
      selectedBuilder: (context, day, focusedDay) => dateTile(day, isSelected: true),
      outsideBuilder: (context, day, focusedDay) => Opacity(opacity: 0.3, child: dateTile(day, textColor: Colors.grey)),
    );
  }

  // --- FULL SCREEN ADD EVENT ---
  Future<void> _showAddEventFullScreen(BuildContext context) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => AddEventForm(perm: _perm, initialDate: _selectedDay ?? DateTime.now())),
    );
    if (saved == true) _fetchEvents();
  }

  // --- UI HELPERS ---
  Widget _categorySmallCard(String title, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppPalette.line(color.withValues(alpha: 0.1)))),
    child: Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: AppPalette.bg(color), borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87)))),
    ]),
  );

  Widget _card({required Widget child, double padding = 15, String? title, Color? color}) => Container(
    padding: EdgeInsets.all(padding), margin: const EdgeInsets.only(bottom: 8),
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppPalette.bg(color ?? Colors.white), 
      borderRadius: BorderRadius.circular(15), 
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.05)))
    ),
    child: Column(children: [
      if (title != null) ...[
        _card(padding: 8, color: pPurple.withValues(alpha: 0.02), child: Center(child: Text(title.toUpperCase(), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 11, color: AppPalette.fg(pPurple), letterSpacing: 1.2)))),
        const SizedBox(height: 8),
      ],
      child,
    ]),
  );

  Widget _eventItem(String title, String time, Color c) => Container(
      margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFFBFBFE)), borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: AppPalette.line(c), width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(title, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: AppPalette.fg(Colors.black87)), maxLines: 2, overflow: TextOverflow.ellipsis),
        Text(time, style: GoogleFonts.merriweather(fontSize: 10, color: AppPalette.fg(Colors.blueGrey), fontWeight: FontWeight.bold)),
      ]),
  );

  Color _getCategoryColor(String? cat) {
    if (cat == "Public Holiday") return Colors.red;
    if (cat == "Church Events") return Colors.blue;
    if (cat == "Location Events") return pPurple;
    return Colors.orange;
  }
}

// ==========================================
// FULL SCREEN ADD EVENT FORM
// ==========================================

class AddEventForm extends StatefulWidget {
  final NoticePermissions perm;
  final DateTime? initialDate;
  const AddEventForm({super.key, this.perm = NoticePermissions.none, this.initialDate});
  @override
  State<AddEventForm> createState() => _AddEventFormState();
}

class _AddEventFormState extends State<AddEventForm> {
  static const Color _purple = Color(0xFF4A148C);
  final TextEditingController nameC = TextEditingController(), venueC = TextEditingController(), subjectsC = TextEditingController(), notesC = TextEditingController();
  late DateTime date;
  bool allDay = false;
  TimeOfDay start = const TimeOfDay(hour: 9, minute: 0), end = const TimeOfDay(hour: 10, minute: 0);
  String? category;
  bool saving = false;
  String? error;

  // Category -> who sees it. Church-wide categories need "Manage Church Events",
  // location events need "Manage Location Events" (set per role in app_roles).
  List<String> get _categories => [
        if (widget.perm.can(NoticePermissions.churchEvents)) ...['Church Events', 'Public Holiday'],
        if (widget.perm.can(NoticePermissions.locationEvents)) 'Location Events',
      ];

  static String _levelOf(String c) => c == 'Location Events' ? 'location' : 'church';

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate ?? DateTime.now();
    date = DateTime(d.year, d.month, d.day);
    category = _categories.isNotEmpty ? _categories.first : null;
  }

  @override
  void dispose() {
    nameC.dispose();
    venueC.dispose();
    subjectsC.dispose();
    notesC.dispose();
    super.dispose();
  }

  String _hhmm(TimeOfDay t) => "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00";

  Future<void> _save() async {
    if (category == null) {
      setState(() => error = "Your role can't add calendar events.");
      return;
    }
    if (nameC.text.trim().isEmpty) {
      setState(() => error = "Give the event a name.");
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final level = _levelOf(category!);
    final desc = [
      if (venueC.text.trim().isNotEmpty) "Venue: ${venueC.text.trim()}",
      if (subjectsC.text.trim().isNotEmpty) "Subjects: ${subjectsC.text.trim()}",
      if (!allDay) "Time: ${start.format(context)} – ${end.format(context)}",
      if (notesC.text.trim().isNotEmpty) notesC.text.trim(),
    ].join('\n');
    try {
      await Supabase.instance.client.from('church_events').insert({
        'title': nameC.text.trim(),
        'description': desc.isEmpty ? null : desc,
        'event_date': DateFormat('yyyy-MM-dd').format(date),
        'event_time': allDay ? null : _hhmm(start),
        'category': category,
        'unit_scope': level == 'location' ? widget.perm.location : 'Church',
        ...widget.perm.scopeFor(level),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint("Add event error: $e");
      if (mounted) {
        setState(() {
          saving = false;
          error = "Couldn't save the event. Your role may not be allowed to add this category.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = _categories;
    return Scaffold(
      appBar: AppBar(
        title: Text("Create New Event", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: saving || cats.isEmpty ? null : _save,
            child: Text(saving ? "SAVING..." : "SAVE", style: GoogleFonts.merriweather(color: AppPalette.fg(_purple), fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (cats.isEmpty)
                Text("Your role can't add calendar events. Ask an admin to give your role "
                    "\"Manage Church Events\" or \"Manage Location Events\".",
                    style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.red.shade800), fontSize: 13)),
              if (cats.isNotEmpty) ...[
                _sectionTitle("1. Event type"),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr("Category"), border: OutlineInputBorder()),
                  items: cats.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setState(() => category = v),
                ),
                const SizedBox(height: 6),
                Text(widget.perm.audienceFor(_levelOf(category ?? 'Church Events')),
                    style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.blueGrey[700]), fontStyle: FontStyle.italic)),
                const Divider(height: 40),
                _sectionTitle("2. Event details"),
                _input("Name of the event", nameC, Icons.event),
                _input("Venue", venueC, Icons.place),
                _input("Subjects", subjectsC, Icons.topic),
                _input("Notes (optional)", notesC, Icons.notes, lines: 3),
                const Divider(height: 40),
                _sectionTitle("3. Date & time"),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(DateFormat('EEEE, MMM d, yyyy').format(date), style: GoogleFonts.merriweather()),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2035));
                    if (d != null) setState(() => date = d);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("All day", style: GoogleFonts.merriweather(fontSize: 14)),
                  value: allDay,
                  activeColor: _purple,
                  onChanged: (v) => setState(() => allDay = v),
                ),
                if (!allDay)
                  Row(children: [
                    Expanded(child: ListTile(contentPadding: EdgeInsets.zero, title: const Text("Start"), subtitle: Text(start.format(context)), onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: start);
                      if (t != null) setState(() => start = t);
                    })),
                    Expanded(child: ListTile(contentPadding: EdgeInsets.zero, title: const Text("End"), subtitle: Text(end.format(context)), onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: end);
                      if (t != null) setState(() => end = t);
                    })),
                  ]),
              ],
              if (error != null) ...[
                const SizedBox(height: 14),
                Text(error!, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.red.shade800), fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(padding: const EdgeInsets.only(bottom: 15), child: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_purple))));

  Widget _input(String label, TextEditingController ctrl, IconData icon, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: ctrl, minLines: lines, maxLines: lines, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder())),
  );
}
