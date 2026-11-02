// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/notice_permissions.dart';
import 'package:master_admin/core/app_palette.dart';

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

  // Who may add intentions comes from the role's admin actions (app_roles)
  NoticePermissions _perm = NoticePermissions.none;

  @override
  void initState() {
    super.initState();
    _fetchIntentions();
    NoticePermissions.load().then((p) {
      if (mounted) setState(() => _perm = p);
    });
  }

  // Which card a category belongs to, and who sees it:
  //   Headquarters / Tribe / Church -> everyone (Internal Affairs Dept Sec)
  //   Region (shown as "Location")  -> the author's location (location leaders)
  //   Department                    -> the author's location + sub-location + department (Dept Sec)
  static String _catLabel(String c) => (c == 'Region' || c == 'Regions') ? 'Location' : c;

  static String _levelOf(String category) =>
      (category == 'Region' || category == 'Regions') ? 'location' : (category == 'Department' ? 'department' : 'church');

  List<String> get _allowedCategories => [
        if (_perm.can(NoticePermissions.churchIntentions)) ...['Headquarters', 'Tribe', 'Church'],
        if (_perm.can(NoticePermissions.locationIntentions)) 'Region',
        if (_perm.can(NoticePermissions.departmentIntentions)) 'Department',
      ];

  /// The database decides for real; this only hides buttons that would fail.
  bool _canManage(dynamic p) {
    if (_perm.isAdmin) return true;
    final level = (p['scope_level'] ?? 'church').toString();
    if (level == 'church') return _perm.can(NoticePermissions.churchIntentions);
    if (level == 'location') {
      return _perm.can(NoticePermissions.locationIntentions) && p['scope_location'] == _perm.location;
    }
    return _perm.can(NoticePermissions.departmentIntentions) &&
        p['scope_location'] == _perm.location &&
        p['scope_sub_location'] == _perm.subLocation &&
        p['scope_department'] == _perm.department;
  }

  Future<void> _deleteIntention(dynamic p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove intention?", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
        content: Text(p['point_text']?.toString() ?? '', style: GoogleFonts.merriweather(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Remove", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase.from('app_intentions').delete().eq('id', p['id']);
      _fetchIntentions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't remove it. You may not have permission.")));
      }
    }
  }

  Future<void> _openIntentionForm({dynamic existing}) async {
    final cats = _allowedCategories;
    if (cats.isEmpty && existing == null) return;
    String category = (existing?['category'] ?? (cats.isNotEmpty ? cats.first : 'Church')).toString();
    if (!cats.contains(category) && existing == null) category = cats.first;
    final textC = TextEditingController(text: existing?['point_text']?.toString() ?? '');
    final subjectC = TextEditingController(text: existing?['subject']?.toString() ?? '');
    final orderC = TextEditingController(text: (existing?['sort_order'] ?? 0).toString());
    DateTime? deadline = DateTime.tryParse(existing?['deadline']?.toString() ?? '');
    String? error;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final level = _levelOf(category);
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(existing == null ? "Add intention" : "Edit intention",
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(pPurple))),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (existing == null)
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr("Category"), border: OutlineInputBorder()),
                    items: cats.map((c) => DropdownMenuItem(value: c, child: Text(_catLabel(c)))).toList(),
                    onChanged: (v) => setD(() => category = v ?? category),
                  ),
                const SizedBox(height: 6),
                Text(existing == null ? _perm.audienceFor(level) : "Category: ${_catLabel(category)}",
                    style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.blueGrey[700]), fontStyle: FontStyle.italic)),
                const SizedBox(height: 12),
                TextField(
                  controller: textC,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(labelText: tr("Intention / directive"), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(controller: subjectC, decoration: InputDecoration(labelText: tr("Subject (optional)"), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text(deadline == null ? "Deadline (optional)" : "Deadline: ${DateFormat('d MMM yyyy').format(deadline!)}",
                          overflow: TextOverflow.ellipsis),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: deadline ?? DateTime.now(),
                          firstDate: DateTime(2023),
                          lastDate: DateTime(2035),
                        );
                        if (d != null) setD(() => deadline = d);
                      },
                    ),
                  ),
                  if (deadline != null) IconButton(onPressed: () => setD(() => deadline = null), icon: const Icon(Icons.clear_rounded)),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: orderC,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr("Order"), border: OutlineInputBorder()),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: GoogleFonts.merriweather(fontSize: 11.5, color: AppPalette.fg(Colors.red.shade800))),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(pPurple), foregroundColor: AppPalette.fg(Colors.white)),
              onPressed: saving
                  ? null
                  : () async {
                      final text = textC.text.trim();
                      if (text.isEmpty) {
                        setD(() => error = "Write the intention first.");
                        return;
                      }
                      setD(() {
                        saving = true;
                        error = null;
                      });
                      final data = <String, dynamic>{
                        'point_text': text,
                        'subject': subjectC.text.trim().isEmpty ? null : subjectC.text.trim(),
                        'deadline': deadline == null ? null : DateFormat('yyyy-MM-dd').format(deadline!),
                        'sort_order': int.tryParse(orderC.text.trim()) ?? 0,
                        'updated_at': DateTime.now().toIso8601String(),
                      };
                      try {
                        if (existing == null) {
                          await _supabase.from('app_intentions').insert({
                            ...data,
                            'category': category,
                            'is_active': true,
                            ..._perm.scopeFor(_levelOf(category)),
                          });
                        } else {
                          await _supabase.from('app_intentions').update(data).eq('id', existing['id']);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _fetchIntentions();
                      } catch (e) {
                        setD(() {
                          saving = false;
                          error = "Couldn't save. Your role may not be allowed to add this category.";
                        });
                      }
                    },
              child: Text(saving ? "Saving..." : "Save"),
            ),
          ],
        );
      }),
    );
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
          // Saved as 'Region' (older app versions wrote 'Regions')
          _regionPoints = res.where((i) => i['category'] == 'Region' || i['category'] == 'Regions').toList();
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
      // two light tones only (the five deep colours were too many)
      _buildIntentCard("Headquarters", Icons.account_balance_rounded, const Color(0xFF7E57C2), _hqPoints),
      _buildIntentCard("Tribe", Icons.hub_rounded, const Color(0xFF5C8DB8), _tribePoints),
      _buildIntentCard("Church", Icons.church_rounded, const Color(0xFF7E57C2), _churchPoints),
      _buildIntentCard("Location", Icons.map_rounded, const Color(0xFF5C8DB8), _regionPoints),
      _buildIntentCard("Department", Icons.business_center_rounded, const Color(0xFF7E57C2), _deptPoints),
    ];

    Widget bodyContent = SizedBox.expand(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 14 : (isTablet ? 12 : 10),
          vertical: 20,
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: double.infinity),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. REFINED EXECUTIVE HEADER CARD
                _buildHeaderCard(isDesktop, totalDirectives),
                const SizedBox(height: 14),

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
                            const SizedBox(height: 14),
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
                            const SizedBox(height: 14),
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
                            const SizedBox(height: 14),
                            cards[2],
                            const SizedBox(height: 14),
                            cards[4],
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          children: [
                            cards[1],
                            const SizedBox(height: 14),
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
        backgroundColor: AppPalette.bg(const Color(0xFFF7F8FC)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white),
          elevation: 0.5,
          centerTitle: true,
          title: Text(
            "Strategic Intentions",
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.w900,
              color: AppPalette.fg(pPurple),
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
    // a slim title bar (half the old height, no line under the title)
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 20 : 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.08)), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Icon(Icons.track_changes_rounded, color: AppPalette.fg(pPurple), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Strategic Intentions & Directives",
              style: GoogleFonts.merriweather(fontSize: isDesktop ? 16 : 13.5, color: AppPalette.fg(pPurple), fontWeight: FontWeight.w900, letterSpacing: 0.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (_perm.canAddIntentions) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.bg(pPurple),
                foregroundColor: AppPalette.fg(Colors.white),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 12 : 8, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _openIntentionForm(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(isDesktop ? "Add intention" : "Add", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 11.5)),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // 2. ELEVATED INTENT CARD
  // ==========================================
  Widget _buildIntentCard(
    String title,
    IconData icon,
    Color accentColor,
    List<dynamic> points,
  ) {
    return _HoverLift(
      shadow: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LIGHT HEADER: the title only
          Container(
            padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
            decoration: BoxDecoration(
              color: AppPalette.bg(Color.lerp(accentColor, Colors.white, 0.86)!),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: AppPalette.line(accentColor.withValues(alpha: 0.25)))),
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15.5, color: AppPalette.fg(Color.lerp(accentColor, Colors.black, 0.35)), letterSpacing: 0.2),
            ),
          ),

          // CARD BODY
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 8, 6),
            child: points.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Column(children: [
                      Icon(Icons.auto_awesome_outlined, color: AppPalette.fg(accentColor.withValues(alpha: 0.5)), size: 30),
                      const SizedBox(height: 8),
                      Text(
                        "No active intentions found.",
                        style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.blueGrey[400]), fontSize: 13, fontStyle: FontStyle.italic),
                      ),
                    ]),
                  )
                : Column(
                    children: points.asMap().entries.map((entry) {
                      final int idx = entry.key + 1;
                      final p = entry.value;
                      final subject = (p['subject'] ?? '').toString().trim();
                      final deadline = DateTime.tryParse((p['deadline'] ?? '').toString());
                      return Container(
                        decoration: BoxDecoration(
                          border: idx == points.length ? null : Border(bottom: BorderSide(color: AppPalette.line(Colors.black.withValues(alpha: 0.07)))),
                        ),
                        padding: const EdgeInsets.fromLTRB(4, 5, 0, 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // NUMBER
                            Container(
                              width: 20,
                              height: 20,
                              margin: const EdgeInsets.only(top: 1),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppPalette.bg(Color.lerp(accentColor, Colors.white, 0.82)!),
                                shape: BoxShape.circle,
                              ),
                              child: Text("$idx", style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.w900, color: AppPalette.fg(Color.lerp(accentColor, Colors.black, 0.3)))),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // wraps onto more lines when long; never overlaps
                                  Text(
                                    p['point_text'] ?? "",
                                    softWrap: true,
                                    style: GoogleFonts.merriweather(
                                      fontSize: 12.5,
                                      color: AppPalette.fg(const Color(0xFF1F1B2E)),
                                      fontWeight: FontWeight.w600,
                                      height: 1.25,
                                    ),
                                  ),
                                  if (subject.isNotEmpty || deadline != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Wrap(spacing: 6, runSpacing: 3, children: [
                                        if (subject.isNotEmpty) _intentChip(Icons.label_outline_rounded, subject, accentColor),
                                        if (deadline != null)
                                          _intentChip(Icons.event_outlined, "By ${DateFormat('d MMM yyyy').format(deadline)}",
                                              deadline.isBefore(DateTime.now()) ? Colors.red.shade400 : accentColor),
                                      ]),
                                    ),
                                ],
                              ),
                            ),
                            if (_canManage(p))
                              SizedBox(
                                width: 30,
                                height: 22,
                                child: PopupMenuButton<String>(
                                  padding: EdgeInsets.zero,
                                  tooltip: tr("Edit or remove"),
                                  icon: Icon(Icons.more_vert_rounded, size: 17, color: AppPalette.fg(Colors.blueGrey[300])),
                                  onSelected: (v) => v == 'edit' ? _openIntentionForm(existing: p) : _deleteIntention(p),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'edit', child: Text("Edit")),
                                    PopupMenuItem(value: 'delete', child: Text("Remove")),
                                  ],
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

  Widget _intentChip(IconData icon, String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppPalette.bg(c.withValues(alpha: 0.10)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppPalette.line(c.withValues(alpha: 0.25))),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: AppPalette.fg(c)),
          const SizedBox(width: 4),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppPalette.fg(c)))),
        ]),
      );
}

/// White card that rises a little (bigger, tinted shadow) under the mouse.
class _HoverLift extends StatefulWidget {
  final Widget child;
  final Color shadow;
  const _HoverLift({required this.child, required this.shadow});
  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: widget.shadow.withValues(alpha: _hover ? 0.18 : 0.08), blurRadius: _hover ? 20 : 12, offset: Offset(0, _hover ? 10 : 5)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}
