// ignore_for_file: curly_braces_in_flow_control_structures
// ignore: unnecessary_import
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

class SpreadsheetScreen extends StatefulWidget {
  final String title, userEmail, userRole;
  const SpreadsheetScreen({super.key, required this.title, required this.userEmail, required this.userRole});
  @override
  State<SpreadsheetScreen> createState() => _SpreadsheetScreenState();
}

class _SpreadsheetScreenState extends State<SpreadsheetScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  // --- STATE MANAGEMENT ---
  bool _isSheetOpen = false;
  String activeTab = "Home";
  PlutoGridStateManager? stateManager;
  double zoomLevel = 1.0;
  final Color pPurple = const Color(0xFF4A148C);
  
  List<String> sheets = ["Sheet 1"];
  int activeSheetIndex = 0;
  String? currentWorkbookId;

  // Data loaded from Supabase
  Map<String, List<String>> functionCategories = {};
  Map<String, List<String>> ribbonData = {"File": ["Loading..."]};

  @override
  void initState() {
    super.initState();
    BrowserContextMenu.disableContextMenu();
    _fetchMenuConfig();
  }

  // --- SUPABASE LOGIC ---

  Future<void> _fetchMenuConfig() async {
    final response = await supabase.from('spreadsheet_ui_menus').select();
    
    Map<String, List<String>> newRibbon = {};
    Map<String, List<String>> newFunctions = {};

    for (var row in response) {
      List<String> items = List<String>.from(row['items']);
      if (row['menu_type'] == 'ribbon') {
        newRibbon[row['category']] = items;
      } else {
        newFunctions[row['category']] = items;
      }
    }

    if (!mounted) return;
    setState(() {
      ribbonData = newRibbon.isNotEmpty ? newRibbon : ribbonData;
      functionCategories = newFunctions;
      if (ribbonData.keys.isNotEmpty) activeTab = ribbonData.keys.first;
    });
  }

  Future<void> _saveCurrentWork() async {
    if (stateManager == null) return;

    final List<Map<String, dynamic>> rowData = stateManager!.rows.map((row) {
      return row.cells.map((key, cell) => MapEntry(key, cell.value));
    }).toList();

    try {
      if (currentWorkbookId == null) {
        final wb = await supabase.from('workbooks').insert({
          'title': widget.title.isEmpty || widget.title == "New SpreadSheet" ? "Strategy Workbook" : widget.title,
          'owner_email': widget.userEmail
        }).select().single();
        currentWorkbookId = wb['id'];
      }

      await supabase.from('spreadsheet_contents').upsert({
        'workbook_id': currentWorkbookId,
        'sheet_name': sheets[activeSheetIndex],
        'grid_data': rowData,
      }, onConflict: 'workbook_id, sheet_name');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Workbook Cloud-Synced")));
    } catch (e) {
      debugPrint("Save error: $e");
    }
  }

  @override
  void dispose() {
    BrowserContextMenu.enableContextMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300), 
        child: _isSheetOpen ? _buildEditor() : _buildHub(),
      ),
    );
  }

  // --- 1. THE 3-COLUMN HUB (FULLY RESTORED) ---
  Widget _buildHub() {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 1000;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF1F5F9)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white), elevation: 0.5,
        title: Text("Cloud Sheets Hub", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple)))),
      body: Padding(
        padding: const EdgeInsets.all(25),
        child: isDesktop ? Row(children: [
          Expanded(flex: 2, child: _hubCol1()), 
          const SizedBox(width: 25),
          Expanded(flex: 5, child: _hubCol2()), 
          const SizedBox(width: 25),
          Expanded(flex: 3, child: _hubCol3()), 
        ]) : ListView(children: [_hubCol1(), const SizedBox(height: 20), _hubCol2(), const SizedBox(height: 20), _hubCol3()]),
      ),
    );
  }

  Widget _hubCol1() => Column(children: [
    _hubCard("New Sheet", Icons.add_box, Colors.green, () {
      setState(() {
        currentWorkbookId = null;
        _isSheetOpen = true;
      });
    }),
    _hubCard("Open Existing", Icons.folder, Colors.blue, () {}),
    _hubCard("Templates", Icons.dashboard_customize, Colors.orange, () {}), // RESTORED
  ]);

  Widget _hubCol2() => Container(
    decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15)]),
    child: Column(children: [
      Padding(padding: const EdgeInsets.all(15), child: TextField(decoration: InputDecoration(hintText: "Search files...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: AppPalette.bg(const Color(0xFFFBFBFE)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)))),
      Expanded(
        child: StreamBuilder(
          stream: supabase.from('workbooks').stream(primaryKey: ['id']).eq('owner_email', widget.userEmail),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!;
            return ListView.builder(
              itemCount: docs.length, 
              itemBuilder: (c, i) => ListTile(
                leading: Icon(Icons.table_chart, color: AppPalette.fg(Colors.green)), 
                title: Text(docs[i]['title'], style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)), 
                subtitle: Text("Sync Date: ${docs[i]['last_modified'].toString().substring(0,10)}"),
                onTap: () {
                   currentWorkbookId = docs[i]['id'];
                   setState(() => _isSheetOpen = true);
                }
              )
            );
          }
        ),
      )
    ]));

  Widget _hubCol3() => Container(padding: const EdgeInsets.all(25), decoration: BoxDecoration(gradient: LinearGradient(colors: [AppPalette.solid(pPurple), AppPalette.solid(Colors.indigo)]), borderRadius: BorderRadius.circular(20)), 
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.help_center_outlined, color: AppPalette.fg(Colors.white), size: 30), const SizedBox(height: 15), 
      Text("Briefing Guide", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 18)), 
      Text("\n• Full Excel-style context menu.\n• Scroll arrows for fine control.\n• Row height set to 16.5.", style: TextStyle(color: AppPalette.fg(Colors.white70), height: 1.8))
    ]));

  Widget _hubCard(String t, IconData i, Color c, VoidCallback onTap) => Card(margin: const EdgeInsets.only(bottom: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(onTap: onTap, leading: Icon(i, color: AppPalette.fg(c), size: 30), title: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold))));

  // --- 2. THE EDITOR VIEW ---
  Widget _buildEditor() {
    double width = MediaQuery.of(context).size.width;
    String displayTitle = (widget.title.isEmpty || widget.title == "New SpreadSheet") ? "My New Sheet" : widget.title;

    return Scaffold(
      backgroundColor: AppPalette.bg(Colors.white),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(135), 
        child: Column(children: [
            Container(
              width: double.infinity, margin: const EdgeInsets.fromLTRB(10, 10, 10, 5), padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.15)), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
              ),
              child: Stack(children: [
                  Positioned(left: 10, child: IconButton(icon: Icon(Icons.close, color: AppPalette.fg(Colors.red), size: 20), onPressed: () => setState(() => _isSheetOpen = false))),
                  Center(child: Column(children: [
                        Text(displayTitle, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple))),
                        Text(widget.userEmail, style: TextStyle(fontSize: 9, color: AppPalette.fg(Colors.grey), fontWeight: FontWeight.bold)),
                  ])),
                  Positioned(right: 10, child: TextButton.icon(onPressed: _saveCurrentWork, icon: const Icon(Icons.cloud_upload, size: 16), label: const Text("SAVE", style: TextStyle(fontSize: 10)))),
              ]),
            ),
            _buildRibbonTabs(),
            _buildRibbonActionCards(),
        ]),
      ),
      body: Column(children: [
          _buildRoundedFXBar(),
          Expanded(child: Row(children: [
                Expanded(child: GestureDetector(
                    onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition),
                    child: PlutoGrid(
                      columns: [
                        PlutoColumn(title: '#', field: 'r', type: PlutoColumnType.number(), width: 35, readOnly: true, enableSorting: false, frozen: PlutoColumnFrozen.start, textAlign: PlutoColumnTextAlign.center, titleTextAlign: PlutoColumnTextAlign.center),
                        ...List.generate(26, (i) => PlutoColumn(title: String.fromCharCode(65+i), field: 'c$i', type: PlutoColumnType.text(), width: 100, textAlign: PlutoColumnTextAlign.center, titleTextAlign: PlutoColumnTextAlign.center)),
                      ],
                      rows: List.generate(100, (i) => PlutoRow(cells: {'r': PlutoCell(value: i+1), for(int j=0; j<26; j++) 'c$j': PlutoCell(value: '')})),
                      onLoaded: (e) => stateManager = e.stateManager,
                      configuration: PlutoGridConfiguration(
                        scrollbar: const PlutoGridScrollbarConfig(scrollbarThickness: 15, isAlwaysShown: true),
                        style: PlutoGridStyleConfig(
                          columnHeight: 22, 
                          rowHeight: 16.5,  // STRICT 16.5 RESTORED
                          columnTextStyle: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold),
                          cellTextStyle: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                )),
                _buildVerticalScrollWithArrows(), 
          ])),
          _buildHorizontalScrollWithArrows(width),
          _buildSheetTabLine(), 
      ]),
    );
  }

  Widget _buildRibbonTabs() => Container(height: 32, padding: const EdgeInsets.only(left: 15), child: Row(children: [
    ...ribbonData.keys.map((t) => GestureDetector(
      onTap: () => setState(() => activeTab = t), 
      child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: AppPalette.bg(activeTab == t ? pPurple : const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(8)), 
        child: Center(child: Text(t, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(activeTab == t ? Colors.white : pPurple)))))
    )),
    GestureDetector(
      onTap: () => setState(() => activeTab = "Functions"), 
      child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: AppPalette.bg(activeTab == "Functions" ? Colors.green : const Color(0xFFE8F5E9)), borderRadius: BorderRadius.circular(8)), 
        child: Center(child: Text("Functions", style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(activeTab == "Functions" ? Colors.white : Colors.green[900])))))
    )
  ]));

  Widget _buildRibbonActionCards() => SizedBox(
    height: 35, width: double.infinity, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5), children: activeTab == "Functions" 
    ? functionCategories.keys.map((cat) => _actionCard(cat, onTap: () => _showFunctionList(cat))).toList()
    : (ribbonData[activeTab] ?? []).map((item) => _actionCard(item)).toList()));

  Widget _actionCard(String l, {VoidCallback? onTap}) => InkWell(onTap: onTap, child: Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: AppPalette.bg(Colors.white), border: Border.all(color: AppPalette.line(Colors.grey.shade200)), borderRadius: BorderRadius.circular(6)), 
    child: Center(child: Text(l, style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold)))));

  Widget _buildRoundedFXBar() => Container(
      height: 32, margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFFBFBFE)), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.2)))),
      child: Row(children: [
        Text("fx", style: TextStyle(fontStyle: FontStyle.italic, color: AppPalette.fg(Colors.grey), fontWeight: FontWeight.bold, fontSize: 16)),
        const VerticalDivider(indent: 5, endIndent: 5),
        const Expanded(child: TextField(decoration: InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero), style: TextStyle(fontSize: 13))),
      ]),
  );

  // --- SCROLL CONTROLS WITH ARROWS (RESTORED FINE CONTROL) ---
  Widget _buildVerticalScrollWithArrows() => Container(width: 22, color: AppPalette.bg(Colors.grey[100]), child: Column(children: [
    IconButton(icon: const Icon(Icons.arrow_drop_up, size: 14), padding: EdgeInsets.zero, onPressed: () => stateManager?.scroll.vertical?.animateTo(stateManager!.scroll.vertical!.offset - 50, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
    Expanded(child: Container(width: 15, decoration: BoxDecoration(color: AppPalette.bg(Colors.grey[300]), borderRadius: BorderRadius.circular(5)))),
    IconButton(icon: const Icon(Icons.arrow_drop_down, size: 14), padding: EdgeInsets.zero, onPressed: () => stateManager?.scroll.vertical?.animateTo(stateManager!.scroll.vertical!.offset + 50, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
  ]));

  Widget _buildHorizontalScrollWithArrows(double w) => Container(height: 22, color: AppPalette.bg(Colors.grey[100]), child: Row(children: [
    const SizedBox(width: 35),
    IconButton(icon: const Icon(Icons.arrow_left, size: 14), padding: EdgeInsets.zero, onPressed: () => stateManager?.scroll.horizontal?.animateTo(stateManager!.scroll.horizontal!.offset - 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
    Expanded(child: Container(height: 15, decoration: BoxDecoration(color: AppPalette.bg(Colors.grey[300]), borderRadius: BorderRadius.circular(5)))),
    IconButton(icon: const Icon(Icons.arrow_right, size: 14), padding: EdgeInsets.zero, onPressed: () => stateManager?.scroll.horizontal?.animateTo(stateManager!.scroll.horizontal!.offset + 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
    const SizedBox(width: 22), 
  ]));

  Widget _buildSheetTabLine() => Container(height: 32, color: AppPalette.bg(Colors.grey[100]), child: Row(children: [
      IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: () {}),
      IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: () {}),
      const VerticalDivider(),
      Expanded(child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: sheets.length, itemBuilder: (c, i) => GestureDetector(onTap: () => setState(() => activeSheetIndex = i), child: Container(padding: const EdgeInsets.symmetric(horizontal: 15), color: AppPalette.bg(i == activeSheetIndex ? Colors.white : Colors.transparent), child: Center(child: Text(sheets[i], style: TextStyle(fontSize: 11, fontWeight: i == activeSheetIndex ? FontWeight.bold : FontWeight.normal, color: AppPalette.fg(i == activeSheetIndex ? pPurple : Colors.black54)))))))),
      IconButton(icon: Icon(Icons.add, size: 18, color: AppPalette.fg(Colors.green)), onPressed: () => setState(() => sheets.add("Sheet ${sheets.length + 1}"))),
      const Spacer(),
      Text("${(zoomLevel * 100).toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      SizedBox(width: 80, child: Slider(value: zoomLevel, min: 0.5, max: 2.0, activeColor: pPurple, onChanged: (v) => setState(() => zoomLevel = v))),
  ]));

  void _showFunctionList(String cat) {
    showModalBottomSheet(context: context, builder: (c) => ListView(children: (functionCategories[cat] ?? []).map((f) => ListTile(title: Text(f), onTap: () => Navigator.pop(context))).toList()));
  }

  // --- EXTENDED CONTEXT MENU (RESTORED ALL OPTIONS) ---
  void _showContextMenu(Offset pos) {
    showMenu<dynamic>(context: context, position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy), items: <PopupMenuEntry<dynamic>>[
      _ctx(Icons.content_cut, "Cut"), _ctx(Icons.content_copy, "Copy"),
      PopupMenuItem<dynamic>(height: 35, child: Row(children: [Icon(Icons.assignment_turned_in, size: 18, color: AppPalette.fg(Colors.orange)), SizedBox(width: 12), Text("Paste Options:")])),
      _ctx(Icons.paste, "Paste Special..."),
      const PopupMenuDivider(),
      _ctx(Icons.add, "Insert..."), _ctx(Icons.delete_outline, "Delete..."),
      _ctx(Icons.layers_clear, "Clear Contents"),
      const PopupMenuDivider(),
      _ctx(Icons.filter_alt_outlined, "Filter"), _ctx(Icons.sort_by_alpha, "Sort"),
      _ctx(Icons.format_paint_outlined, "Format Cells..."),
      _ctx(Icons.list_alt, "Pick From Drop-down List..."),
      _ctx(Icons.label_important_outline, "Define Name..."),
      _ctx(Icons.link, "Hyperlink..."),
    ]);
  }
  PopupMenuItem<dynamic> _ctx(IconData i, String t) => PopupMenuItem<dynamic>(height: 35, child: Row(children: [Icon(i, size: 18, color: AppPalette.fg(Colors.grey[700])), const SizedBox(width: 12), Text(t, style: GoogleFonts.merriweather(fontSize: 12))]));
}