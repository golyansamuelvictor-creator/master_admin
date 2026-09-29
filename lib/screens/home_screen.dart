// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

// ALL IMPORTS PRESERVED
import 'dashboard_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'add_account_screen.dart';
import 'media_hub_screen.dart';
import 'quotes_screen.dart';
import 'intentions_screen.dart';
import 'calendar_screen.dart';
import 'survey_screen.dart';
import 'spreadsheet_screen.dart';
import 'document_screen.dart';
import 'presentation_screen.dart';
import 'communication_screen.dart';
import 'forms_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  int _selectedIndex = 0;
  late Timer _timer;
  bool isLoading = true;

  // PROFILE STATE (LIVE profiles)
  String fullName = "User", email = "", selectedRole = "Member", accountType = "Saint";
  String userLoc = "", userSub = "", userDept = "", userTeam = "", userCell = "";
  List<UserAccount> availableAccounts = [];

  // DYNAMIC CONFIG STATE (LIVE master_tabs & home_quick_picks)
  List<Map<String, dynamic>> _dynamicTabs = [
    {'label': 'Home', 'icon_name': 'home_rounded'},
    {'label': 'Intentions', 'icon_name': 'track_changes_rounded'},
    {'label': 'Calendar', 'icon_name': 'event_available_rounded'},
    {'label': 'Surveys', 'icon_name': 'fact_check_rounded'},
  ];
  List<Map<String, dynamic>> _quickPicks = [];

  // SUPABASE LIVE DATA: QUOTES (app_quotes)
  List<Map<String, dynamic>> _liveQuotes = [];
  int _currentQuoteIndex = 0;
  bool _isLoadingQuotes = false;

  // SUPABASE LIVE DATA: UPCOMING CHURCH EVENTS (church_events)
  List<Map<String, dynamic>> _upcomingEvents = [];
  bool _isLoadingEvents = false;

  // SUPABASE LIVE DATA: APP INTENTIONS (app_intentions)
  List<Map<String, dynamic>> _liveIntentions = [];
  bool _isLoadingIntentions = false;

  // PALETTE: DARK PURPLE, BLUE, GREEN, BLACK, GOLD ACCENT
  final Color pPurple = const Color(0xFF4A148C);
  final Color pBlue = const Color(0xFF1565C0);
  final Color pGreen = const Color(0xFF2E7D32);
  final Color pBlack = const Color(0xFF212121);
  final Color pGold = const Color(0xFFB78103);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() {});
    });
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    await Future.wait([
      _fetchUserProfile(),
      _fetchHomeConfig(),
      _fetchLiveQuotes(),
      _fetchLiveUpcomingEvents(),
      _fetchLiveIntentions(),
    ]);

    if (mounted) setState(() => isLoading = false);
  }

  // ==========================================
  // 1. SUPABASE FETCH: CONFIG & TABS
  // ==========================================
  Future<void> _fetchHomeConfig() async {
    try {
      final tabRes = await _supabase.from('master_tabs').select().eq('is_active', true);
      final pickRes = await _supabase.from('home_quick_picks').select().order('sort_order');

      if (mounted) {
        List<String> correctOrder = ['Home', 'Intentions', 'Calendar', 'Surveys'];
        List<Map<String, dynamic>> sortedTabs = [];

        for (var label in correctOrder) {
          final matches = tabRes.where((e) => e['label'] == label);
          if (matches.isNotEmpty) {
            sortedTabs.add(Map<String, dynamic>.from(matches.first));
          } else {
            sortedTabs.add({'label': label, 'icon_name': _getDefaultIconName(label)});
          }
        }

        setState(() {
          if (sortedTabs.isNotEmpty) _dynamicTabs = sortedTabs;
          _quickPicks = List<Map<String, dynamic>>.from(pickRes);
        });
      }
    } catch (e) {
      debugPrint("Config fetch error: $e");
    }
  }

  String _getDefaultIconName(String label) {
    switch (label) {
      case 'Home': return 'home_rounded';
      case 'Intentions': return 'track_changes_rounded';
      case 'Calendar': return 'event_available_rounded';
      case 'Surveys': return 'fact_check_rounded';
      default: return 'circle';
    }
  }

  // ==========================================
  // 2. SUPABASE FETCH: LIVE QUOTES (app_quotes)
  // ==========================================
  Future<void> _fetchLiveQuotes() async {
    try {
      final res = await _supabase
          .from('app_quotes')
          .select()
          .eq('is_active', true)
          .order('sort_order');

      if (mounted) {
        setState(() {
          _liveQuotes = List<Map<String, dynamic>>.from(res);
          _currentQuoteIndex = 0;
          _isLoadingQuotes = false;
        });
      }
    } catch (e) {
      debugPrint("Quotes fetch error: $e");
      if (mounted) setState(() => _isLoadingQuotes = false);
    }
  }

  // ==========================================
  // 3. SUPABASE FETCH: UPCOMING EVENTS (church_events)
  // ==========================================
  Future<void> _fetchLiveUpcomingEvents() async {
    try {
      final res = await _supabase.from('church_events').select();
      if (mounted) {
        DateTime now = DateTime.now();
        DateTime todayMidnight = DateTime(now.year, now.month, now.day);

        List<Map<String, dynamic>> events = [];
        for (var item in (res as List)) {
          DateTime? eventDate = DateTime.tryParse(item['event_date'] ?? '');
          if (eventDate != null) {
            events.add({
              ...Map<String, dynamic>.from(item),
              '_parsedDate': eventDate,
            });
          }
        }

        events.sort((a, b) => (a['_parsedDate'] as DateTime).compareTo(b['_parsedDate'] as DateTime));
        var filtered = events.where((e) {
          DateTime d = e['_parsedDate'] as DateTime;
          return d.isAfter(todayMidnight.subtract(const Duration(seconds: 1)));
        }).toList();

        if (filtered.isEmpty && events.isNotEmpty) {
          filtered = events.reversed.take(4).toList();
        }

        setState(() {
          _upcomingEvents = filtered.take(4).toList();
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      debugPrint("Events fetch error: $e");
      if (mounted) setState(() => _isLoadingEvents = false);
    }
  }

  // ==========================================
  // 4. SUPABASE FETCH: INTENTIONS (app_intentions)
  // ==========================================
  Future<void> _fetchLiveIntentions() async {
    try {
      final res = await _supabase
          .from('app_intentions')
          .select()
          .eq('is_active', true)
          .order('sort_order');

      if (mounted) {
        setState(() {
          _liveIntentions = List<Map<String, dynamic>>.from(res);
          _isLoadingIntentions = false;
        });
      }
    } catch (e) {
      debugPrint("Intentions fetch error: $e");
      if (mounted) setState(() => _isLoadingIntentions = false);
    }
  }

 // ==========================================
  // 5. SUPABASE FETCH: USER PROFILE (MULTI-ACCOUNT AWARE)
  // ==========================================
  Future<void> _fetchUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      List<String> savedIds = prefs.getStringList('device_account_ids') ?? [];
      if (!savedIds.contains(user.id)) {
        savedIds.add(user.id);
        await prefs.setStringList('device_account_ids', savedIds);
      }

      // Fetch all registered profiles on this device
      final List<dynamic> data = await _supabase.from('profiles').select().inFilter('id', savedIds);

      if (mounted) {
        setState(() {
          // Check which account is currently active (defaults to the logged in user)
          final activeEmail = prefs.getString('active_account_email') ?? user.email ?? "";

          final currentData = data.firstWhere(
            (item) => item['email'] == activeEmail,
            orElse: () => data.firstWhere((item) => item['id'] == user.id, orElse: () => null),
          );

          if (currentData != null) {
            fullName = currentData['full_name'] ?? "User";
            email = currentData['email'] ?? user.email ?? "";
            selectedRole = currentData['role'] ?? "Member";
            accountType = currentData['account_type'] ?? "Saint";
            userLoc = currentData['location'] ?? "";
            userSub = currentData['sub_location'] ?? "";
            userDept = currentData['department'] ?? "";
            userTeam = currentData['team'] ?? "";
            userCell = currentData['cell_group'] ?? "";
          }

          // Available accounts list contains all OTHER device accounts
          availableAccounts = data
              .map<UserAccount>((item) => UserAccount(
                    fullName: item['full_name'] ?? "No name",
                    userName: item['username'] ?? "user",
                    phoneNumber: item['phone'] ?? "No phone",
                    email: item['email'] ?? "No email",
                    role: item['role'] ?? "Member",
                    accountType: item['account_type'] ?? "Saint",
                  ))
              .where((acc) => acc.email != email)
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Profile error: $e");
    }
  }

  // SWITCH ACCOUNT HANDLER
  Future<void> _switchActiveAccount(UserAccount acc) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_account_email', acc.email);
    await _fetchInitialData();
  }

  Color _fromHex(String? hexString) {
    if (hexString == null || hexString.isEmpty) return pPurple;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return pPurple;
    }
  }

  IconData _getIcon(String name) {
    switch (name) {
      case 'home_rounded': return Icons.home_rounded;
      case 'format_quote_rounded': return Icons.format_quote_rounded;
      case 'stars_rounded': return Icons.stars_rounded;
      case 'event_available_rounded': return Icons.event_available_rounded;
      case 'fact_check_rounded': return Icons.fact_check_rounded;
      case 'notification_important_rounded': return Icons.notification_important_rounded;
      case 'track_changes_rounded': return Icons.track_changes_rounded;
      case 'event_note_rounded': return Icons.event_note_rounded;
      default: return Icons.circle;
    }
  }

  void handleNavigation(String v) {
    if (v == 'registration') Navigator.push(context, MaterialPageRoute(builder: (c) => const AddAccountScreen())).then((_) => _fetchUserProfile());
    else if (v == 'settings_main') Navigator.push(context, MaterialPageRoute(builder: (c) => SettingsScreen(userEmail: email, userRole: selectedRole)));
    else if (v == 'role_grid') Navigator.push(context, MaterialPageRoute(builder: (c) => ReportsScreen(userEmail: email, userRole: selectedRole)));
    else if (v == 'mediahub_main') Navigator.push(context, MaterialPageRoute(builder: (c) => MediaHubScreen(title: "Media", userEmail: email, userRole: selectedRole)));
    else if (v == 'forms_main') Navigator.push(context, MaterialPageRoute(builder: (c) => FormsScreen(title: "New form", userEmail: email, userRole: selectedRole)));
    else if (v == 'spreadsheet_main') Navigator.push(context, MaterialPageRoute(builder: (c) => SpreadsheetScreen(title: "Sheets", userEmail: email, userRole: selectedRole)));
    else if (v == 'document_main') Navigator.push(context, MaterialPageRoute(builder: (c) => DocumentScreen(title: "Docs", userEmail: email, userRole: selectedRole)));
    else if (v == 'ppt_main') Navigator.push(context, MaterialPageRoute(builder: (c) => PresentationScreen(title: "Presentation", userEmail: email, userRole: selectedRole)));
    else if (v == 'my_home') Navigator.push(context, MaterialPageRoute(builder: (c) => CommunicationScreen(userEmail: email, userRole: selectedRole)));
  }

  void _navigateToTab(String tabLabel) {
    int idx = _dynamicTabs.indexWhere((t) => t['label'].toString().toLowerCase() == tabLabel.toLowerCase());
    if (idx != -1) {
      setState(() => _selectedIndex = idx);
    }
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "U";
    List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 900;
    double cardPadding = isDesktop ? 28 : 16;

    if (isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: pPurple),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      drawer: SizedBox(
        width: width,
        child: DashboardScreen(
          currentRole: selectedRole,
          accountType: accountType,
          fullName: fullName,
          email: email,
          userName: "user",
          phoneNumber: "Not set",
          otherAccounts: availableAccounts,
          onSwitchAccount: (acc) => _switchActiveAccount(acc),
          onNavigate: handleNavigation,
        ),
      ),
      body: Stack(
        children: [
          // Background Watermark
          Positioned.fill(
            child: Center(
              child: Opacity(
                opacity: 0.018,
                child: Text(
                  "Master Administration",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.merriweather(
                    fontSize: isDesktop ? 96 : 46,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),

          // Main View
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      _buildHomeTab(isDesktop, width, cardPadding),
                      const SizedBox.expand(child: IntentionsScreen(isFullPage: true)),
                      const SizedBox.expand(child: CalendarScreen(isFullPage: true)),
                      const SizedBox.expand(child: SurveyScreen(isFullPage: true)),
                    ],
                  ),
                ),

                // Bottom Navigation Shelf
                Container(
                  height: 68,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 1350),
                      child: Row(
                        children: _dynamicTabs.map((tab) {
                          int idx = _dynamicTabs.indexOf(tab);
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: _navCard(idx, _getIcon(tab['icon_name']), tab['label'], isDesktop),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ASK AI BUTTON
          Positioned(
            right: cardPadding + 8,
            bottom: 82,
            child: FloatingActionButton.extended(
              heroTag: 'ai_btn',
              elevation: 6,
              onPressed: () => _openFullScreenAI(context),
              backgroundColor: pPurple,
              icon: const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 18),
              label: Text(
                "Ask AI",
                style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ====================================================================
  // REFINED MODERN CARD (NO HARSH OUTLINES)
  // ====================================================================
  Widget _modernCard({
    required Widget child,
    VoidCallback? onTap,
    EdgeInsetsGeometry? padding,
    Color? backgroundColor,
    Border? customBorder,
    Gradient? gradient,
  }) {
    bool isHovered = false;
    return StatefulBuilder(
      builder: (context, setCardState) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        onHighlightChanged: (val) => setCardState(() => isHovered = val),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white,
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            border: customBorder ?? Border.all(
              color: isHovered ? pPurple.withValues(alpha: 0.28) : pPurple.withValues(alpha: 0.08),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isHovered ? pPurple.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.03),
                blurRadius: isHovered ? 20 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  // ==========================================
  // HOME TAB (WITH FROZEN APP BAR TITLE)
  // ==========================================
  Widget _buildHomeTab(bool isDesktop, double width, double cardPadding) {
    String dateStr = DateFormat('EEEE, d MMMM y').format(DateTime.now());
    String timeStr = DateFormat('hh:mm a').format(DateTime.now());

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // FROZEN APP BAR
        SliverAppBar(
          pinned: true,
          floating: false,
          backgroundColor: const Color(0xFFF7F8FC),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: Builder(
            builder: (context) => IconButton(
              icon: Icon(Icons.menu_rounded, color: pPurple, size: 28),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          centerTitle: true,
          title: Text(
            "Master Administration",
            style: GoogleFonts.merriweather(
              fontSize: isDesktop ? 22 : 18,
              fontWeight: FontWeight.w900,
              color: pPurple,
              letterSpacing: 0.3,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: pPurple.withValues(alpha: 0.08),
              height: 1.0,
            ),
          ),
        ),

        // BODY CONTENT
        SliverToBoxAdapter(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1350),
              padding: EdgeInsets.symmetric(horizontal: cardPadding, vertical: 16),
              child: Column(
                children: [
                  // 1. UNIFIED COMMAND CENTER HERO BANNER (profiles data)
                  _buildUnifiedHeroBanner(isDesktop, dateStr, timeStr),
                  const SizedBox(height: 20),

                  // 2. BALANCED 3-COLUMN BENTO GRID ON DESKTOP (100% SUPABASE)
                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // COLUMN 1: LIVE QUICK PICKS & LIVE INTENTIONS
                        Expanded(
                          flex: 1,
                          child: Column(
                            children: [
                              _buildQuickPicks(),
                              const SizedBox(height: 18),
                              _buildIntentionsSnippetCard(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),

                        // COLUMN 2: LIVE CHAIRMAN QUOTE (app_quotes Centerpiece)
                        Expanded(
                          flex: 1,
                          child: _buildChairmanQuoteCard(),
                        ),
                        const SizedBox(width: 20),

                        // COLUMN 3: LIVE UPCOMING EVENTS (church_events Master Itinerary)
                        Expanded(
                          flex: 1,
                          child: _buildUpcomingEventsCard(),
                        ),
                      ],
                    )
                  else
                    // Mobile vertical flow
                    Column(
                      children: [
                        _buildChairmanQuoteCard(),
                        const SizedBox(height: 16),
                        _buildUpcomingEventsCard(),
                        const SizedBox(height: 16),
                        _buildIntentionsSnippetCard(),
                        const SizedBox(height: 16),
                        _buildQuickPicks(),
                      ],
                    ),

                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // UNIFIED COMMAND HERO BANNER (LIVE profiles data)
  // ==========================================
  Widget _buildUnifiedHeroBanner(bool isDesktop, String dateStr, String timeStr) {
    // Dynamic location derived from Supabase profile
    String locationText = userLoc.isNotEmpty ? "Sunny 28°C • $userLoc" : "Sunny 28°C • Kampala, Uganda";

    return _modernCard(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 18, vertical: 18),
      child: isDesktop
          ? Row(
              children: [
                // User Avatar Circle (Initials computed dynamically from profile fullName)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [pPurple, const Color(0xFF6A1B9A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: pPurple.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _getInitials(fullName),
                      style: GoogleFonts.merriweather(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Greeting & Profile Data from Supabase
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: pGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: pGreen.withValues(alpha: 0.25)),
                            ),
                            child: Text(
                              "Samyeong wansung hapshida",
                              style: GoogleFonts.merriweather(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: pGreen,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: pBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_rounded, size: 12, color: pBlue),
                                const SizedBox(width: 4),
                                Text(
                                  _toTitleCase(selectedRole.replaceAll('_', ' ')),
                                  style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pBlue),
                                ),
                                Text(
                                  " • $accountType",
                                  style: GoogleFonts.merriweather(fontSize: 11, color: pBlack, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            "Welcome back, ",
                            style: GoogleFonts.merriweather(fontSize: 13, color: Colors.blueGrey[600], fontStyle: FontStyle.italic),
                          ),
                          Flexible(
                            child: Text(
                              fullName,
                              style: GoogleFonts.merriweather(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: pPurple,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Vertical Divider
                Container(
                  height: 48,
                  width: 1,
                  color: pPurple.withValues(alpha: 0.12),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                ),

                // Live Clock & Dynamic Location
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 14, color: pPurple),
                        const SizedBox(width: 6),
                        Text(
                          timeStr,
                          style: GoogleFonts.merriweather(
                            color: pPurple,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dateStr,
                      style: GoogleFonts.merriweather(fontSize: 12, color: Colors.blueGrey[700], fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.wb_sunny_rounded, color: Colors.orange[700], size: 13),
                        const SizedBox(width: 4),
                        Text(
                          locationText,
                          style: GoogleFonts.merriweather(fontSize: 11, color: pGreen, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [pPurple, const Color(0xFF6A1B9A)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(fullName),
                          style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: pGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              "Samyeong wansung hapshida",
                              style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: pGreen),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            fullName,
                            style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.w900, color: pPurple),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _toTitleCase(selectedRole.replaceAll('_', ' ')),
                      style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: pBlue),
                    ),
                    Text(
                      "$timeStr • $locationText",
                      style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey[700]),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // ==========================================
  // CHAIRMAN'S QUOTE CARD (LIVE app_quotes)
  // ==========================================
  Widget _buildChairmanQuoteCard() {
    if (_isLoadingQuotes) {
      return _modernCard(
        child: SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator(color: pPurple)),
        ),
      );
    }

    if (_liveQuotes.isEmpty) {
      return _modernCard(
        child: SizedBox(
          height: 220,
          child: Center(
            child: Text("No quotes found in database.", style: GoogleFonts.merriweather(color: Colors.grey, fontSize: 13)),
          ),
        ),
      );
    }

    final quote = _liveQuotes[_currentQuoteIndex];
    final String fullText = quote['quote_text'] ?? "";
    final Color quoteColor = _fromHex(quote['color_hex']);

    String snapText = fullText;
    if (snapText.length > 140) {
      snapText = "${snapText.substring(0, 140)}...";
    }

    String quoteDateDisplay = "";
    if (quote['created_at'] != null) {
      try {
        DateTime parsed = DateTime.parse(quote['created_at']);
        quoteDateDisplay = DateFormat('MMMM d, yyyy').format(parsed);
      } catch (_) {}
    }

    return _modernCard(
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 28,
            child: Opacity(
              opacity: 0.05,
              child: Icon(Icons.format_quote_rounded, size: 100, color: pPurple),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.format_quote_rounded, color: pPurple, size: 24),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            "Quote of Chairman",
                            style: GoogleFonts.merriweather(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: pPurple,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: _pickQuoteDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: pPurple.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: pPurple.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_month_rounded, size: 13, color: pPurple),
                          const SizedBox(width: 4),
                          Text(
                            "Search Date",
                            style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (quoteDateDisplay.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 12, color: Colors.blueGrey),
                        const SizedBox(width: 4),
                        Text(
                          quoteDateDisplay,
                          style: GoogleFonts.merriweather(fontSize: 11, color: Colors.blueGrey[700], fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFFD54F)),
                    ),
                    child: Text(
                      "총회장님 말씀",
                      style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.w900, color: pGold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCFBFE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: pPurple.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "“$snapText”",
                      style: GoogleFonts.merriweather(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        height: 1.6,
                        color: pBlack,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "— 총회장님 말씀 (Chairman)",
                        style: GoogleFonts.merriweather(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: quoteColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () => _openFullQuoteDialog(quote, quoteColor),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: pPurple,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: pPurple.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Text(
                            "Read more",
                            style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: Colors.white),
                        ],
                      ),
                    ),
                  ),

                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
                        color: _currentQuoteIndex > 0 ? pPurple : Colors.grey.shade400,
                        splashRadius: 18,
                        onPressed: _currentQuoteIndex > 0
                            ? () => setState(() => _currentQuoteIndex--)
                            : null,
                        tooltip: "Previous Quote",
                      ),
                      Text(
                        "${_currentQuoteIndex + 1} / ${_liveQuotes.length}",
                        style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.w900, color: pPurple),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        color: _currentQuoteIndex < _liveQuotes.length - 1 ? pPurple : Colors.grey.shade400,
                        splashRadius: 18,
                        onPressed: _currentQuoteIndex < _liveQuotes.length - 1
                            ? () => setState(() => _currentQuoteIndex++)
                            : null,
                        tooltip: "Next Quote",
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // QUICK PICKS (LIVE home_quick_picks)
  // ==========================================
  Widget _buildQuickPicks() {
    return _modernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: Colors.amber[800], size: 20),
                  const SizedBox(width: 6),
                  Text(
                    "Quick picks",
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: pPurple),
                  ),
                ],
              ),
              Text(
                "Priority items",
                style: GoogleFonts.merriweather(fontSize: 11, color: pBlue, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(height: 18),
          if (_quickPicks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text("No active alerts at this moment.", style: GoogleFonts.merriweather(fontSize: 12, color: Colors.grey)),
            )
          else
            ..._quickPicks.map((pick) => _pickItem(_getIcon(pick['icon_name']), pick['title'] ?? "")),
        ],
      ),
    );
  }

  Widget _pickItem(IconData i, String t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: pBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(i, size: 15, color: pBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t,
              style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: pBlack),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: Colors.black26),
        ],
      ),
    );
  }

  // ==========================================
  // UPCOMING EVENTS (LIVE church_events)
  // ==========================================
  Widget _buildUpcomingEventsCard() {
    if (_isLoadingEvents) {
      return _modernCard(
        child: SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator(color: pPurple)),
        ),
      );
    }

    return _modernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.event_available_rounded, color: pBlue, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    "Upcoming Events",
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: pPurple),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _navigateToTab('Calendar'),
                child: Text(
                  "Calendar",
                  style: GoogleFonts.merriweather(fontSize: 11, color: pBlue, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          if (_upcomingEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text("No upcoming church events found.", style: GoogleFonts.merriweather(fontSize: 12, color: Colors.grey)),
              ),
            )
          else
            ..._upcomingEvents.map((evt) {
              DateTime? d = evt['_parsedDate'] as DateTime?;
              String dayNum = d != null ? DateFormat('d').format(d) : "--";
              String monthStr = d != null ? DateFormat('MMM').format(d).toUpperCase() : "DATE";
              String timeDisplay = evt['event_time'] ?? "All Day";
              if (evt['venue'] != null && evt['venue'].toString().isNotEmpty) {
                timeDisplay += " • ${evt['venue']}";
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFD),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: pPurple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: pPurple.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          Text(dayNum, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 12, color: pPurple)),
                          Text(monthStr, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 8, color: pPurple)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            evt['title'] ?? "Church Event",
                            style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12, color: pBlack),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeDisplay,
                            style: GoogleFonts.merriweather(fontSize: 10, color: Colors.blueGrey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => _navigateToTab('Calendar'),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Read more in Calendar",
                      style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, size: 10, color: pPurple),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // INTENTIONS SNIPPET (LIVE app_intentions)
  // ==========================================
  Widget _buildIntentionsSnippetCard() {
    if (_isLoadingIntentions) {
      return _modernCard(
        child: SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator(color: pPurple)),
        ),
      );
    }

    final snippetItems = _liveIntentions.take(3).toList();

    return _modernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.track_changes_rounded, color: pGreen, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    "Current Intentions",
                    style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15, color: pPurple),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _navigateToTab('Intentions'),
                child: Text(
                  "Focus",
                  style: GoogleFonts.merriweather(fontSize: 11, color: pGreen, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          if (snippetItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text("No active intentions found.", style: GoogleFonts.merriweather(fontSize: 12, color: Colors.grey)),
              ),
            )
          else
            ...snippetItems.asMap().entries.map((entry) {
              int idx = entry.key + 1;
              var item = entry.value;
              String cat = item['category'] ?? "General";
              String pointText = item['point_text'] ?? "";

              Color catColor = pGreen;
              if (cat == 'Headquarters') catColor = Colors.orange[900]!;
              else if (cat == 'Tribe') catColor = const Color(0xFF0D47A1);
              else if (cat == 'Church') catColor = Colors.green[800]!;
              else if (cat == 'Regions') catColor = Colors.teal[800]!;
              else if (cat == 'Department') catColor = Colors.deepPurple[600]!;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFD),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$idx.",
                      style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w900, color: catColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              cat,
                              style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: catColor),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pointText,
                            style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w500, color: pBlack, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => _navigateToTab('Intentions'),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Read more in Intentions",
                      style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, size: 10, color: pPurple),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // NAVIGATION BOTTOM SHELF CARD
  // ==========================================
  Widget _navCard(int index, IconData icon, String label, bool isDesktop) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isSelected ? pPurple : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? pPurple : Colors.grey.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: isSelected ? pPurple.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : pPurple, size: 18),
            if (isDesktop) const SizedBox(height: 2),
            if (isDesktop)
              Text(
                label,
                style: GoogleFonts.merriweather(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : pBlack,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // HELPER DIALOGS & METHODS
  // ==========================================
  Future<void> _pickQuoteDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: pPurple,
              onPrimary: Colors.white,
              onSurface: pBlack,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      String searchKey = DateFormat('yyyy-MM-dd').format(picked);
      int foundIndex = _liveQuotes.indexWhere((q) {
        String? created = q['created_at'];
        if (created != null && created.startsWith(searchKey)) return true;
        return false;
      });

      if (foundIndex != -1) {
        setState(() => _currentQuoteIndex = foundIndex);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No quote found specifically recorded for $searchKey.", style: GoogleFonts.merriweather()),
            backgroundColor: pPurple,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _openFullQuoteDialog(Map<String, dynamic> quote, Color quoteColor) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: pPurple.withValues(alpha: 0.2), width: 1.2),
        ),
        title: Row(
          children: [
            Icon(Icons.format_quote_rounded, color: quoteColor, size: 26),
            const SizedBox(width: 8),
            Text(
              "Quotes of Chairman",
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pPurple, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                quote['quote_text'] ?? "",
                style: GoogleFonts.merriweather(fontSize: 13, height: 1.6, color: pBlack),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "— 총회장님 말씀 (Chairman)",
                  style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.w900, color: quoteColor),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (ctx) => const QuotesScreen(isFullPage: true)));
            },
            child: Text("Open Full Quotes Screen", style: GoogleFonts.merriweather(color: pBlue, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: pPurple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(c),
            child: Text("Close", style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _openFullScreenAI(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => FullScreenAIAssistant(
          userRole: selectedRole,
          accountType: accountType,
          userUnit: userCell.isNotEmpty ? userCell : (userTeam.isNotEmpty ? userTeam : userDept),
        ),
      ),
    );
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) => word.isEmpty ? "" : word[0].toUpperCase() + word.substring(1).toLowerCase()).join(' ');
  }
}

// ==========================================
// DEDICATED FULL SCREEN AI VIEW (LIVE SUPABASE INTEGRATED)
// ==========================================
class FullScreenAIAssistant extends StatefulWidget {
  final String userRole;
  final String accountType;
  final String userUnit;

  const FullScreenAIAssistant({
    super.key,
    required this.userRole,
    required this.accountType,
    required this.userUnit,
  });

  @override
  State<FullScreenAIAssistant> createState() => _FullScreenAIAssistantState();
}

class _FullScreenAIAssistantState extends State<FullScreenAIAssistant> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _queryCtrl = TextEditingController();
  final List<Map<String, String>> _conversation = [];
  bool _isProcessing = false;
  final Color pPurple = const Color(0xFF4A148C);

  @override
  void initState() {
    super.initState();
    _conversation.add({
      'sender': 'ai',
      'text': "Greetings. I am your Master Administration AI Assistant.\n\n"
              "I have direct access to your live Church Knowledge Base, Chairman's Quotes, Strategic Intentions, and Master Calendar (both upcoming and past events).\n\n"
              "Ask any question regarding church standards, attendance guidelines, history, or quotes.",
    });
  }

  String _formatRole(String r) {
    return r.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? "" : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  Future<void> _ask(String prompt) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) return;

    setState(() {
      _conversation.add({'sender': 'user', 'text': cleanPrompt});
      _isProcessing = true;
    });
    _queryCtrl.clear();

    final queryLower = cleanPrompt.toLowerCase();
    List<String> responseBlocks = [];

    try {
      // 1. SEARCH AI KNOWLEDGE BASE (ai_knowledge_base)
      try {
        final kbRes = await _supabase
            .from('ai_knowledge_base')
            .select()
            .eq('is_active', true);

        List<dynamic> matchedKB = (kbRes as List).where((item) {
          final title = (item['title'] ?? '').toString().toLowerCase();
          final content = (item['content'] ?? '').toString().toLowerCase();
          final category = (item['category'] ?? '').toString().toLowerCase();
          final keywords = (item['keywords'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];

          return title.contains(queryLower) ||
                 content.contains(queryLower) ||
                 category.contains(queryLower) ||
                 keywords.any((k) => queryLower.contains(k));
        }).toList();

        if (matchedKB.isNotEmpty) {
          for (var item in matchedKB.take(2)) {
            responseBlocks.add(
              "📖 [${item['category'] ?? 'Knowledge Base'}] ${item['title']}\n${item['content']}"
            );
          }
        }
      } catch (e) {
        debugPrint("Knowledge base lookup note: $e");
      }

      // 2. SEARCH CHAIRMAN'S QUOTES OF LIFE (app_quotes)
      bool asksQuote = queryLower.contains('quote') ||
                       queryLower.contains('chairman') ||
                       queryLower.contains('life') ||
                       queryLower.contains('word') ||
                       queryLower.contains('말씀');
      if (asksQuote) {
        try {
          final quoteRes = await _supabase
              .from('app_quotes')
              .select()
              .eq('is_active', true)
              .order('sort_order');

          List<dynamic> matchedQuotes = (quoteRes as List).where((q) {
            final text = (q['quote_text'] ?? '').toString().toLowerCase();
            return text.contains(queryLower) || asksQuote;
          }).toList();

          if (matchedQuotes.isNotEmpty) {
            var q = matchedQuotes.first;
            responseBlocks.add(
              "📜 Chairman's Quote of Life (총회장님 말씀):\n“${q['quote_text']}”\n— Chairman"
            );
          }
        } catch (e) {
          debugPrint("Quotes lookup error: $e");
        }
      }

      // 3. SEARCH CHURCH EVENTS (church_events)
      bool asksEvents = queryLower.contains('event') ||
                        queryLower.contains('calendar') ||
                        queryLower.contains('upcoming') ||
                        queryLower.contains('past') ||
                        queryLower.contains('schedule') ||
                        queryLower.contains('meeting') ||
                        queryLower.contains('service');
      if (asksEvents) {
        try {
          final eventRes = await _supabase.from('church_events').select();
          DateTime now = DateTime.now();
          DateTime todayMidnight = DateTime(now.year, now.month, now.day);

          List<Map<String, dynamic>> parsedEvents = [];
          for (var item in (eventRes as List)) {
            DateTime? d = DateTime.tryParse(item['event_date'] ?? '');
            if (d != null) {
              parsedEvents.add({...Map<String, dynamic>.from(item), '_date': d});
            }
          }

          if (queryLower.contains('past')) {
            var past = parsedEvents.where((e) => (e['_date'] as DateTime).isBefore(todayMidnight)).toList();
            past.sort((a, b) => (b['_date'] as DateTime).compareTo(a['_date'] as DateTime));

            if (past.isNotEmpty) {
              String pastList = past.take(3).map((e) {
                String dateStr = DateFormat('MMM d, yyyy').format(e['_date'] as DateTime);
                return "• ${e['title']} ($dateStr • ${e['event_time'] ?? 'All Day'})";
              }).join('\n');
              responseBlocks.add("📅 Past Church Events Recorded:\n$pastList");
            } else {
              responseBlocks.add("📅 Past Events: No past events recorded in the calendar archive.");
            }
          } else {
            var upcoming = parsedEvents.where((e) => !(e['_date'] as DateTime).isBefore(todayMidnight)).toList();
            upcoming.sort((a, b) => (a['_date'] as DateTime).compareTo(b['_date'] as DateTime));

            if (upcoming.isNotEmpty) {
              String upcomingList = upcoming.take(3).map((e) {
                String dateStr = DateFormat('EEE, MMM d').format(e['_date'] as DateTime);
                return "• ${e['title']} ($dateStr • ${e['event_time'] ?? 'All Day'}${e['venue'] != null ? ' @ ${e['venue']}' : ''})";
              }).join('\n');
              responseBlocks.add("🗓️ Upcoming Church Events:\n$upcomingList");
            }
          }
        } catch (e) {
          debugPrint("Events lookup error: $e");
        }
      }

      // 4. SEARCH STRATEGIC INTENTIONS (app_intentions)
      bool asksIntentions = queryLower.contains('intention') ||
                            queryLower.contains('strategy') ||
                            queryLower.contains('mission') ||
                            queryLower.contains('focus') ||
                            queryLower.contains('target') ||
                            queryLower.contains('headquarters') ||
                            queryLower.contains('tribe');
      if (asksIntentions) {
        try {
          final intRes = await _supabase
              .from('app_intentions')
              .select()
              .eq('is_active', true)
              .order('sort_order');

          List<dynamic> matchedInt = (intRes as List).where((item) {
            final pt = (item['point_text'] ?? '').toString().toLowerCase();
            final cat = (item['category'] ?? '').toString().toLowerCase();
            return pt.contains(queryLower) || cat.contains(queryLower) || asksIntentions;
          }).toList();

          if (matchedInt.isNotEmpty) {
            String intList = matchedInt.take(3).map((i) => "• [${i['category']}] ${i['point_text']}").join('\n');
            responseBlocks.add("🎯 Current Strategic Intentions:\n$intList");
          }
        } catch (e) {
          debugPrint("Intentions lookup error: $e");
        }
      }

      // 5. ASSEMBLE FINAL RESPONSE
      String finalReply = "";
      if (responseBlocks.isNotEmpty) {
        finalReply = responseBlocks.join("\n\n-----------------------------------\n\n");
      } else {
        finalReply = "Research review for \"$cleanPrompt\":\n\n"
            "I checked your live Church Knowledge Base, Calendar, and Intentions. No specific entries directly matched your phrase.\n\n"
            "You can:\n"
            "• Ask about 'Attendance guidelines' or 'Church standards'\n"
            "• Ask for 'Chairman quote of life'\n"
            "• Ask for 'Upcoming events' or 'Past events'\n"
            "• Ask about 'Strategic intentions' or 'Bookshop resources'";
      }

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _conversation.add({'sender': 'ai', 'text': finalReply});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _conversation.add({
            'sender': 'ai',
            'text': "An error occurred while researching the database: $e",
          });
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF4A148C)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Text(
              "Ask AI Assistant",
              style: GoogleFonts.merriweather(color: pPurple, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFEDE7F6),
            child: Text(
              "Jurisdiction: ${_formatRole(widget.userRole)} • ${widget.userUnit.isEmpty ? 'Church administration' : widget.userUnit}",
              style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold, color: pPurple),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _conversation.length,
              itemBuilder: (context, i) {
                bool isUser = _conversation[i]['sender'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser ? pPurple : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: isUser ? null : Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SelectableText(
                      _conversation[i]['text'] ?? "",
                      style: GoogleFonts.merriweather(
                        color: isUser ? Colors.white : Colors.black87,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isProcessing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: pPurple, strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "Searching church knowledge base...",
                    style: GoogleFonts.merriweather(fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip("Attendance guidelines", () => _ask("Attendance guidelines")),
                  const SizedBox(width: 8),
                  _chip("Church standards", () => _ask("Church standards")),
                  const SizedBox(width: 8),
                  _chip("Chairman quote", () => _ask("Chairman quote of life")),
                  const SizedBox(width: 8),
                  _chip("Upcoming events", () => _ask("Upcoming events")),
                  const SizedBox(width: 8),
                  _chip("Past events", () => _ask("Events that happened in the past")),
                  const SizedBox(width: 8),
                  _chip("Strategic intentions", () => _ask("Current strategic intentions")),
                  const SizedBox(width: 8),
                  _chip("Bookshop resources", () => _ask("Bookshop resources and manuals")),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryCtrl,
                      decoration: InputDecoration(
                        hintText: "Ask about standards, quotes, events, or resources...",
                        hintStyle: GoogleFonts.merriweather(fontSize: 13, color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFD),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                        ),
                      ),
                      onSubmitted: _ask,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.send_rounded, color: pPurple),
                    onPressed: () => _ask(_queryCtrl.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, VoidCallback onTap) {
    return ActionChip(
      label: Text(text, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: pPurple)),
      backgroundColor: const Color(0xFFF3E5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
      onPressed: onTap,
    );
  }
}