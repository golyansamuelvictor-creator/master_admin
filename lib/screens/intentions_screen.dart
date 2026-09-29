// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IntentionsScreen extends StatefulWidget {
  final double s;
  final bool isFullPage;

  const IntentionsScreen({super.key, this.s = 1.0, this.isFullPage = false});

  @override
  State<IntentionsScreen> createState() => _IntentionsScreenState();
}

class _IntentionsScreenState extends State<IntentionsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  List<dynamic> _hqPoints = [];
  List<dynamic> _tribePoints = [];
  List<dynamic> _churchPoints = [];
  List<dynamic> _regionPoints = [];
  List<dynamic> _deptPoints = [];

  final Color pPurple = const Color(0xFF4A148C);

  @override
  void initState() {
    super.initState();
    _fetchIntentions();
  }

  Future<void> _fetchIntentions() async {
    try {
      final res = await _supabase
          .from('app_intentions')
          .select()
          .eq('is_active', true)
          .order('sort_order');

      if (mounted) {
        setState(() {
          _hqPoints = res.where((i) => i['category'] == 'Headquarters').toList();
          _tribePoints = res.where((i) => i['category'] == 'Tribe').toList();
          _churchPoints = res.where((i) => i['category'] == 'Church').toList();
          _regionPoints = res.where((i) => i['category'] == 'Regions').toList();
          _deptPoints = res.where((i) => i['category'] == 'Department').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Intentions Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 1050;
    bool isTablet = width > 680 && width <= 1050;

    int totalDirectives = _hqPoints.length +
        _tribePoints.length +
        _churchPoints.length +
        _regionPoints.length +
        _deptPoints.length;

    // 5 Category Cards
    List<Widget> cards = [
      _buildIntentCard("Headquarters", Icons.account_balance_rounded, Colors.orange[900]!, _hqPoints),
      _buildIntentCard("Tribe", Icons.hub_rounded, const Color(0xFF0D47A1), _tribePoints),
      _buildIntentCard("Church", Icons.church_rounded, Colors.green[800]!, _churchPoints),
      _buildIntentCard("Regions", Icons.map_rounded, Colors.teal[800]!, _regionPoints),
      _buildIntentCard("Department", Icons.business_center_rounded, Colors.deepPurple[600]!, _deptPoints),
    ];

    Widget bodyContent = SizedBox.expand(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 36 : (isTablet ? 24 : 16),
          vertical: 20,
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. REFINED EXECUTIVE HEADER CARD
                _buildHeaderCard(isDesktop, totalDirectives),
                const SizedBox(height: 24),

                // 2. CARDS GRID / MULTI-COLUMN LAYOUT
                if (_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 80),
                    child: Center(
                      child: CircularProgressIndicator(color: pPurple, strokeWidth: 2.5),
                    ),
                  )
                else if (isDesktop)
                  // 3 BALANCED COLUMNS ON DESKTOP
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // COLUMN 1: Headquarters & Regions
                      Expanded(
                        child: Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 22),
                            cards[3],
                          ],
                        ),
                      ),
                      const SizedBox(width: 22),

                      // COLUMN 2: Tribe & Department
                      Expanded(
                        child: Column(
                          children: [
                            cards[1],
                            const SizedBox(height: 22),
                            cards[4],
                          ],
                        ),
                      ),
                      const SizedBox(width: 22),

                      // COLUMN 3: Church (Focus Unit)
                      Expanded(
                        child: Column(
                          children: [
                            cards[2],
                          ],
                        ),
                      ),
                    ],
                  )
                else if (isTablet)
                  // 2 COLUMNS ON TABLET
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 20),
                            cards[2],
                            const SizedBox(height: 20),
                            cards[4],
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          children: [
                            cards[1],
                            const SizedBox(height: 20),
                            cards[3],
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  // 1 COLUMN ON MOBILE
                  Column(
                    children: cards
                        .map((card) => Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: card,
                            ))
                        .toList(),
                  ),

                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.isFullPage) {
      return bodyContent;
    } else {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          centerTitle: true,
          title: Text(
            "Strategic Intentions",
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w900,
              color: pPurple,
              fontSize: 18,
            ),
          ),
        ),
        body: bodyContent,
      );
    }
  }

  // ==========================================
  // 1. REFINED HEADER CARD (NO HARSH OUTLINES)
  // ==========================================
  Widget _buildHeaderCard(bool isDesktop, int totalDirectives) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 26 : 18,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pPurple.withValues(alpha: 0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: pPurple.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: pPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.track_changes_rounded, color: pPurple, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Strategic Intentions & Directives",
                        style: GoogleFonts.merriweather(
                          fontSize: isDesktop ? 20 : 16,
                          color: pPurple,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Executive Alignment • Headquarters • Tribes • Churches",
                        style: GoogleFonts.merriweather(
                          fontSize: isDesktop ? 12 : 10,
                          color: Colors.blueGrey[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Total Directives Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: pPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.checklist_rounded, size: 15, color: pPurple),
                const SizedBox(width: 6),
                Text(
                  "$totalDirectives Active",
                  style: GoogleFonts.merriweather(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: pPurple,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 2. REFINED INTENT CARD (NO BULK PURPLE OUTLINES)
  // ==========================================
  Widget _buildIntentCard(
    String title,
    IconData icon,
    Color accentColor,
    List<dynamic> points,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: pPurple.withValues(alpha: 0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // SPANNING SUB-TITLE HEADER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(
                  color: accentColor.withValues(alpha: 0.12),
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: accentColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: GoogleFonts.merriweather(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: pPurple,
                      ),
                    ),
                  ],
                ),
                // Count Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    "${points.length} Directives",
                    style: GoogleFonts.merriweather(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // CARD BODY
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: points.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        "No active intentions found.",
                        style: GoogleFonts.merriweather(
                          color: Colors.blueGrey[400],
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: points.asMap().entries.map((entry) {
                      int idx = entry.key + 1;
                      var p = entry.value;
                      bool isLast = entry.key == points.length - 1;

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: isLast
                              ? null
                              : Border(
                                  bottom: BorderSide(
                                    color: Colors.grey.withValues(alpha: 0.10),
                                    width: 1.0,
                                  ),
                                ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // NUMBER BADGE
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accentColor.withValues(alpha: 0.25),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                "$idx",
                                style: GoogleFonts.merriweather(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // DIRECTIVE TEXT
                            Expanded(
                              child: Text(
                                p['point_text'] ?? "",
                                style: GoogleFonts.merriweather(
                                  fontSize: 14,
                                  color: const Color(0xFF212121),
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}