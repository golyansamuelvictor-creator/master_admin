// ignore_for_file: curly_braces_in_flow_control_structures
// ignore: unnecessary_import
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

class DocumentScreen extends StatefulWidget {
  final String title, userEmail, userRole;
  const DocumentScreen({super.key, required this.title, required this.userEmail, required this.userRole});
  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  // --- UI & EDITOR STATE ---
  bool _isDocOpen = false;
  String activeTab = "Home";
  late QuillController _controller;
  final ScrollController _verticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  bool _isReady = false;
  int wordCount = 0;
  int pageCount = 1;
  double zoomLevel = 1.0;
  final Color pPurple = const Color(0xFF4A148C);

  // SUPABASE DATA
  String? currentDocId;
  Map<String, List<String>> docMenus = {"Home": ["Loading..."]};

  @override
  void initState() {
    super.initState();
    BrowserContextMenu.disableContextMenu();
    _controller = QuillController.basic();
    _setupControllerListener();
    _initApp();
  }

  void _setupControllerListener() {
    _controller.addListener(() {
      final text = _controller.document.toPlainText().trim();
      if (mounted) {
        setState(() {
          wordCount = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
          pageCount = (wordCount / 300).ceil().clamp(1, 99); 
        });
      }
    });
  }

  Future<void> _initApp() async {
    await _fetchMenuConfig();
    if (mounted) setState(() => _isReady = true);
  }

  // --- SUPABASE ACTIONS ---

  Future<void> _fetchMenuConfig() async {
    final response = await supabase.from('document_ui_menus').select().order('sort_order');
    Map<String, List<String>> newMenus = {};
    for (var row in response) {
      newMenus[row['category']] = List<String>.from(row['items']);
    }
    if (mounted && newMenus.isNotEmpty) {
      setState(() {
        docMenus = newMenus;
        activeTab = docMenus.keys.first;
      });
    }
  }

  Future<void> _loadDocument(String id, String title, dynamic content) async {
    setState(() {
      currentDocId = id;
      if (content != null) {
        _controller = QuillController(
          document: Document.fromJson(content),
          selection: const TextSelection.collapsed(offset: 0),
        );
        _setupControllerListener();
      } else {
        _controller = QuillController.basic();
        _setupControllerListener();
      }
      _isDocOpen = true;
    });
  }

  Future<void> _saveDocument() async {
    final content = _controller.document.toDelta().toJson();
    try {
      if (currentDocId == null) {
        final res = await supabase.from('documents').insert({
          'title': widget.title.isEmpty ? "New Document" : widget.title,
          'owner_email': widget.userEmail,
          'content': content,
          'word_count': wordCount,
        }).select().single();
        currentDocId = res['id'];
      } else {
        await supabase.from('documents').update({
          'content': content,
          'word_count': wordCount,
          'last_modified': DateTime.now().toIso8601String(),
        }).eq('id', currentDocId!);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Document Cloud-Synced")));
    } catch (e) {
      debugPrint("Save error: $e");
    }
  }

  @override
  void dispose() {
    BrowserContextMenu.enableContextMenu();
    _controller.dispose();
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF1F5F9)),
      body: AnimatedSwitcher(duration: const Duration(milliseconds: 300), 
        child: _isDocOpen ? _buildEditor() : _buildHub()),
    );
  }

  // --- 1. THE 3-COLUMN HUB (RESTORED ALL CARDS) ---
  Widget _buildHub() {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 1000;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF1F5F9)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white), elevation: 0.5,
        title: Text("Official Documents Hub", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple)))),
      body: Padding(padding: const EdgeInsets.all(25), child: isDesktop ? Row(children: [
        Expanded(flex: 2, child: _hubOpt()),
        const SizedBox(width: 25),
        Expanded(flex: 5, child: _recent()),
        const SizedBox(width: 25),
        Expanded(flex: 3, child: _guide()),
      ]) : ListView(children: [_hubOpt(), const SizedBox(height: 20), _recent(), const SizedBox(height: 20), _guide()])),
    );
  }

  Widget _hubOpt() => Column(children: [
    _hCard(Icons.add, "New Document", Colors.blue, () {
      setState(() {
        currentDocId = null;
        _controller = QuillController.basic();
        _setupControllerListener();
        _isDocOpen = true;
      });
    }),
    _hCard(Icons.folder, "Open Existing", Colors.orange, () {}),
    _hCard(Icons.auto_stories, "Templates", Colors.green, () {}), // RESTORED
  ]);

  Widget _recent() => Container(
    decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]), 
    child: Column(children: [
      Padding(padding: const EdgeInsets.all(15), child: TextField(decoration: InputDecoration(hintText: "Search cloud documents...", border: InputBorder.none, filled: true, fillColor: AppPalette.bg(const Color(0xFFFBFBFE))))), 
      Expanded(
        child: StreamBuilder(
          stream: supabase.from('documents').stream(primaryKey: ['id']).eq('owner_email', widget.userEmail),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!;
            return ListView.builder(
              itemCount: docs.length, 
              itemBuilder: (c, i) => ListTile(
                leading: Icon(Icons.description, color: AppPalette.fg(Colors.blue)), 
                title: Text(docs[i]['title'], style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)), 
                subtitle: Text("Words: ${docs[i]['word_count']} • Last Sync: ${docs[i]['last_modified'].toString().substring(0,10)}"), 
                onTap: () => _loadDocument(docs[i]['id'], docs[i]['title'], docs[i]['content'])
              )
            );
          }
        )
      )
    ])
  );

  Widget _guide() => Container(padding: const EdgeInsets.all(25), decoration: BoxDecoration(gradient: LinearGradient(colors: [AppPalette.solid(pPurple), AppPalette.solid(Colors.indigo)]), borderRadius: BorderRadius.circular(25)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.cloud_done, color: AppPalette.fg(Colors.white)), const SizedBox(height: 15), Text("Briefing Guide", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 18)), Text("\n• Page and Word count updated in real-time.\n• Full Word context menu on right click.\n• Automatic Cloud Synchronization.", style: TextStyle(color: AppPalette.fg(Colors.white70), height: 1.7))]));

  Widget _hCard(IconData i, String t, Color c, VoidCallback onTap) => Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(onTap: onTap, leading: Icon(i, color: AppPalette.fg(c)), title: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold))));

  // --- 2. THE EDITOR ---
  Widget _buildEditor() {
    double width = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFE5E7EB)),
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
                  Positioned(left: 10, child: IconButton(icon: Icon(Icons.close, color: AppPalette.fg(Colors.red), size: 20), onPressed: () => setState(() => _isDocOpen = false))),
                  Center(child: Column(children: [
                        Text(widget.title, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple))),
                        Text("Cloud Sync: ${widget.userEmail}", style: TextStyle(fontSize: 9, color: AppPalette.fg(Colors.grey), fontWeight: FontWeight.bold)),
                  ])),
                  Positioned(right: 15, child: IconButton(icon: Icon(Icons.cloud_upload, color: AppPalette.fg(Colors.blue)), onPressed: _saveDocument)),
              ]),
            ),
            _buildRibbonTabs(),
            _buildRibbonActionCards(),
        ]),
      ),
      body: Column(children: [
        _ruler(),
        Expanded(child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalScroll,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: width - 25), 
                  child: SingleChildScrollView(
                    controller: _verticalScroll,
                    child: GestureDetector(
                      onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition), 
                      child: Center( 
                        child: Container(
                          width: 850 * zoomLevel, 
                          constraints: const BoxConstraints(minHeight: 1100), 
                          margin: const EdgeInsets.symmetric(vertical: 40, horizontal: 20), 
                          padding: const EdgeInsets.all(60), 
                          decoration: BoxDecoration(color: AppPalette.bg(Colors.white), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 10))]), 
                          child: QuillEditor.basic(controller: _controller, focusNode: _focusNode),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildVerticalScrollWithArrows(), 
          ],
        )),
        _buildHorizontalScrollWithArrows(width),
        _buildBottomStatusBar(),
      ]),
    );
  }

  Widget _buildRibbonTabs() => Container(height: 32, padding: const EdgeInsets.only(left: 15), child: Row(children: docMenus.keys.map((t) => GestureDetector(
    onTap: () => setState(() => activeTab = t), 
    child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: AppPalette.bg(activeTab == t ? pPurple : const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(8)), 
      child: Center(child: Text(t, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(activeTab == t ? Colors.white : pPurple)))))
  )).toList()));

  Widget _buildRibbonActionCards() => Container(height: 35, width: double.infinity, color: AppPalette.bg(const Color(0xFFFBFBFE)), child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5), children: (docMenus[activeTab] ?? []).map((item) => Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: AppPalette.bg(Colors.white), border: Border.all(color: AppPalette.line(Colors.grey.shade200)), borderRadius: BorderRadius.circular(6)), 
    child: Center(child: Text(item, style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold))))).toList()));

  Widget _buildVerticalScrollWithArrows() => Container(width: 18, color: AppPalette.bg(Colors.grey[100]), child: Column(children: [
    IconButton(icon: const Icon(Icons.arrow_drop_up, size: 14), padding: EdgeInsets.zero, onPressed: () => _verticalScroll.animateTo(_verticalScroll.offset - 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
    Expanded(child: Container(width: 12, decoration: BoxDecoration(color: AppPalette.bg(Colors.grey[300]), borderRadius: BorderRadius.circular(5)))),
    IconButton(icon: const Icon(Icons.arrow_drop_down, size: 14), padding: EdgeInsets.zero, onPressed: () => _verticalScroll.animateTo(_verticalScroll.offset + 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
  ]));

  Widget _buildHorizontalScrollWithArrows(double w) => Container(height: 18, color: AppPalette.bg(Colors.grey[100]), child: Row(children: [
    const SizedBox(width: 20), 
    IconButton(icon: const Icon(Icons.arrow_left, size: 14), padding: EdgeInsets.zero, onPressed: () => _horizontalScroll.animateTo(_horizontalScroll.offset - 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
    Expanded(child: Container(height: 12, decoration: BoxDecoration(color: AppPalette.bg(Colors.grey[300]), borderRadius: BorderRadius.circular(5)))),
    IconButton(icon: const Icon(Icons.arrow_right, size: 14), padding: EdgeInsets.zero, onPressed: () => _horizontalScroll.animateTo(_horizontalScroll.offset + 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
    const SizedBox(width: 18), 
  ]));

  // --- RESTORED STATUS BAR VIEW MODES ---
  Widget _buildBottomStatusBar() {
    return Container(
      height: 35, color: AppPalette.bg(Colors.white), padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(children: [
        Text("Page $pageCount of $pageCount", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        const VerticalDivider(width: 30),
        Text("$wordCount words", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        const Spacer(),
        Icon(Icons.description_outlined, size: 16, color: AppPalette.fg(Colors.blue)), // Print Layout RESTORED
        const SizedBox(width: 15),
        const Icon(Icons.menu_book_outlined, size: 16), // Reading RESTORED
        const SizedBox(width: 15),
        const Icon(Icons.web_asset_outlined, size: 16), // Web RESTORED
        const VerticalDivider(width: 40),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.remove, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => setState(() => zoomLevel = (zoomLevel - 0.1).clamp(0.5, 2.0))),
            const SizedBox(width: 5),
            Text("${(zoomLevel * 100).toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(width: 5),
            IconButton(icon: const Icon(Icons.add, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => setState(() => zoomLevel = (zoomLevel + 0.1).clamp(0.5, 2.0))),
          ]),
        ),
      ]),
    );
  }

  Widget _ruler() => Container(height: 18, decoration: BoxDecoration(color: AppPalette.bg(Colors.white), border: Border(bottom: BorderSide(color: AppPalette.line(Colors.black12)))), child: Row(children: [const SizedBox(width: 20), Expanded(child: CustomPaint(painter: RulerPainter()))]));

  // --- RESTORED EXTENDED CONTEXT MENU ---
  void _showContextMenu(Offset pos) {
    showMenu<dynamic>(context: context, position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy), items: <PopupMenuEntry<dynamic>>[
        _ctx(Icons.content_cut, "Cut"), _ctx(Icons.content_copy, "Copy"),
        PopupMenuItem<dynamic>(height: 35, child: Row(children: [Icon(Icons.assignment_returned, size: 18, color: AppPalette.fg(Colors.orange)), SizedBox(width: 12), Text("Paste Options:")])),
        const PopupMenuDivider(),
        _ctx(Icons.font_download_outlined, "Font..."), 
        _ctx(Icons.format_indent_increase, "Paragraph..."),
        _ctx(Icons.format_list_bulleted, "Bullets"), 
        _ctx(Icons.format_list_numbered, "Numbering"),
        _ctx(Icons.style, "Styles"),
        const PopupMenuDivider(),
        _ctx(Icons.link, "Hyperlink..."), 
        _ctx(Icons.search, "Look Up"),
        _ctx(Icons.spellcheck, "Synonyms"), 
        _ctx(Icons.translate, "Translate"),
    ]);
  }
  PopupMenuItem<dynamic> _ctx(IconData i, String t) => PopupMenuItem<dynamic>(height: 35, child: Row(children: [Icon(i, size: 18, color: AppPalette.fg(Colors.grey[700])), const SizedBox(width: 12), Text(t, style: GoogleFonts.merriweather(fontSize: 12))]));
}

class RulerPainter extends CustomPainter { @override void paint(Canvas canvas, Size size) { final p = Paint()..color = Colors.grey..strokeWidth = 1; for (double i = 0; i < size.width; i += 15) canvas.drawLine(Offset(i, 0), Offset(i, i % 45 == 0 ? 7 : 3), p); } @override bool shouldRepaint(CustomPainter old) => false; }