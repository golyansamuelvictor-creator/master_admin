// ignore_for_file: deprecated_member_use, use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final eventRes = await _supabase.from('church_events').select();
      final taskRes = await _supabase.from('leader_tasks').select();
      Map<DateTime, List<dynamic>> newEvents = {};
      
      for (var e in (eventRes as List)) {
        DateTime d = DateTime.parse(e['event_date']);
        DateTime key = DateTime(d.year, d.month, d.day);
        if (newEvents[key] == null) newEvents[key] = [];
        newEvents[key]!.add({...e, 'type': 'event'});
      }
      for (var t in (taskRes as List)) {
        DateTime d = DateTime.parse(t['due_date']);
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
        backgroundColor: const Color(0xFFFBFBFE),
        appBar: AppBar(
          backgroundColor: Colors.white, 
          elevation: 0.5, 
          centerTitle: true,
          title: Text("Master Calendar", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple, fontSize: 18))
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
                  color: pPurple.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: pPurple.withValues(alpha: 0.1))
                ),
                child: Text("Calendar View", style: GoogleFonts.merriweather(fontSize: 24, fontWeight: FontWeight.w900, color: pPurple)),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: pPurple.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
            child: DropdownButton<String>(
              value: _selectedType, 
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: pPurple),
              underline: const SizedBox(),
              style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: pPurple),
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
              weekendStyle: GoogleFonts.merriweather(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w900),
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
            child: Center(child: Text("CATEGORIES", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12, color: pPurple, letterSpacing: 1.2))),
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
              child: Center(child: Text("Extended View: $_selectedType", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple, fontSize: 13))),
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
      _card(padding: 8, child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _showAddEventFullScreen(context), 
          icon: const Icon(Icons.add_rounded, size: 20), label: Text("NEW EVENT", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: pPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
      )),
      const SizedBox(height: 8),
      _card(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        _card(
          padding: 6,
          color: Colors.blueGrey.withValues(alpha: 0.05),
          child: Center(child: Text("DAILY SCHEDULE", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.blueGrey, letterSpacing: 1.2)))
        ),
        const SizedBox(height: 10),
        if (todayEvents.isEmpty) Center(child: Text("No events found.", style: GoogleFonts.merriweather(color: Colors.grey, fontSize: 14))),
        ...todayEvents.map((e) => _eventItem(e['title'], e['event_time'] ?? "All Day", _getCategoryColor(e['category']))),
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
                  IconButton(onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1)), icon: Icon(Icons.arrow_back_ios_new_rounded, color: pPurple, size: 18)),
                  Text(DateFormat('MMMM yyyy').format(monthDate), textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: pPurple)),
                  IconButton(onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1)), icon: Icon(Icons.arrow_forward_ios_rounded, color: pPurple, size: 18)),
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
                  weekendStyle: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.red),
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
                      Text(DateFormat('E').format(day), style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text(DateFormat('d').format(day), style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.w900, color: isSameDay(day, DateTime.now()) ? pPurple : Colors.black87)),
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
                      style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                  )),
                ),
                Expanded(
                  child: Column(
                    children: List.generate(24, (hourIndex) => Container(
                      height: 30, // Reduced by half
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.1)))),
                      child: Row(
                        children: List.generate(dayCount, (dayIndex) => Expanded(
                          child: Container(decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.withValues(alpha: 0.05))))),
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
        decoration: BoxDecoration(color: bg, border: Border.all(color: Colors.grey.withValues(alpha: 0.08), width: 0.5)),
        child: Center(child: Text("${day.day}", style: GoogleFonts.merriweather(fontSize: 10, color: textColor, fontWeight: FontWeight.bold))),
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
          color: isSelected ? pPurple : (isToday ? Colors.orangeAccent.withValues(alpha: 0.1) : Colors.white),
          borderRadius: BorderRadius.circular(8), 
          border: Border.all(color: isSelected ? pPurple : (isToday ? Colors.orangeAccent : Colors.grey.withValues(alpha: 0.1)), width: 1),
        ),
        child: Center(child: Text("${day.day}", style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : (textColor ?? Colors.black87)))),
    );
    return CalendarBuilders(
      defaultBuilder: (context, day, focusedDay) => dateTile(day, textColor: (day.weekday > 5) ? Colors.red : null),
      todayBuilder: (context, day, focusedDay) => dateTile(day, isToday: true),
      selectedBuilder: (context, day, focusedDay) => dateTile(day, isSelected: true),
      outsideBuilder: (context, day, focusedDay) => Opacity(opacity: 0.3, child: dateTile(day, textColor: Colors.grey)),
    );
  }

  // --- FULL SCREEN ADD EVENT ---
  void _showAddEventFullScreen(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (context) => const AddEventForm()));
  }

  // --- UI HELPERS ---
  Widget _categorySmallCard(String title, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.1))),
    child: Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87))),
    ]),
  );

  Widget _card({required Widget child, double padding = 15, String? title, Color? color}) => Container(
    padding: EdgeInsets.all(padding), margin: const EdgeInsets.only(bottom: 8),
    width: double.infinity,
    decoration: BoxDecoration(
      color: color ?? Colors.white, 
      borderRadius: BorderRadius.circular(15), 
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
      border: Border.all(color: pPurple.withValues(alpha: 0.05))
    ),
    child: Column(children: [
      if (title != null) ...[
        _card(padding: 8, color: pPurple.withValues(alpha: 0.02), child: Center(child: Text(title.toUpperCase(), style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 11, color: pPurple, letterSpacing: 1.2)))),
        const SizedBox(height: 8),
      ],
      child,
    ]),
  );

  Widget _eventItem(String title, String time, Color c) => Container(
      margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFFBFBFE), borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: c, width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(title, textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.black87), maxLines: 1),
        Text(time, style: GoogleFonts.merriweather(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
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
  const AddEventForm({super.key});
  @override
  State<AddEventForm> createState() => _AddEventFormState();
}

class _AddEventFormState extends State<AddEventForm> {
  String? host, tribe, church, location, subLoc, dept;
  final TextEditingController nameC = TextEditingController(), venueC = TextEditingController(), subjectsC = TextEditingController();
  DateTime date = DateTime.now();
  TimeOfDay start = const TimeOfDay(hour: 9, minute: 0), end = const TimeOfDay(hour: 10, minute: 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Create New Event", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("SAVE", style: GoogleFonts.merriweather(color: const Color(0xFF4A148C), fontWeight: FontWeight.w900)))]
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle("1. Event Host"),
          _dropdown("Host Level", ["HQ", "Tribe", "Church", "Location", "Sub Location", "Dept"], host, (v) => setState(() => host = v)),
          if (host != "HQ") _dropdown("Select Branch/Unit", ["Example Unit A", "Example Unit B"], subLoc, (v) => setState(() => subLoc = v)),
          
          const Divider(height: 40),
          _sectionTitle("2. Event Details"),
          _input("Name of the Event", nameC, Icons.event),
          _input("Venue", venueC, Icons.place),
          _input("Subjects", subjectsC, Icons.topic),
          
          const Divider(height: 40),
          _sectionTitle("3. Date & Time"),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text(DateFormat('EEEE, MMM d, yyyy').format(date), style: GoogleFonts.merriweather()),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime.now(), lastDate: DateTime(2030));
              if (d != null) setState(() => date = d);
            },
          ),
          Row(children: [
            Expanded(child: ListTile(title: const Text("Start"), subtitle: Text(start.format(context)), onTap: () async {
              final t = await showTimePicker(context: context, initialTime: start);
              if (t != null) setState(() => start = t);
            })),
            Expanded(child: ListTile(title: const Text("End"), subtitle: Text(end.format(context)), onTap: () async {
              final t = await showTimePicker(context: context, initialTime: end);
              if (t != null) setState(() => end = t);
            })),
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(padding: const EdgeInsets.only(bottom: 15), child: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: const Color(0xFF4A148C))));
  
  Widget _dropdown(String label, List<String> items, String? val, Function(String?) onCh) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      value: val, items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: onCh,
    ),
  );

  Widget _input(String label, TextEditingController ctrl, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: ctrl, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder())),
  );
}