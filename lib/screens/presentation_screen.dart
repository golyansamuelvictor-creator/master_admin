// ignore_for_file: curly_braces_in_flow_control_structures
// ignore: unnecessary_import
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresentationScreen extends StatefulWidget {
  final String title, userEmail, userRole;
  const PresentationScreen({super.key, required this.title, required this.userEmail, required this.userRole});
  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  // NAVIGATION & UI STATE
  bool _isEditorOpen = false;
  String activeTab = "Home";
  int currentSlideIndex = 0;
  double zoomLevel = 0.7;
  final Color pOrange = const Color(0xFFB7472A);
  
  final ScrollController _verticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();

  // DATA FROM SUPABASE
  String? currentDeckId;
  List<Map<String, dynamic>> slides = [];
  Map<String, List<String>> pptMenus = {"Home": ["Loading..."]};

  @override
  void initState() {
    super.initState();
    BrowserContextMenu.disableContextMenu();
    _fetchMenuConfig();
  }

  // --- SUPABASE LOGIC ---

  Future<void> _fetchMenuConfig() async {
    final response = await supabase.from('presentation_ui_menus').select().order('sort_order');
    Map<String, List<String>> newMenus = {};
    for (var row in response) {
      newMenus[row['tab_name']] = List<String>.from(row['items']);
    }
    if (!mounted) return;
    setState(() {
      pptMenus = newMenus.isNotEmpty ? newMenus : pptMenus;
      activeTab = pptMenus.keys.first;
    });
  }

  Future<void> _loadSlides(String deckId) async {
    final response = await supabase
        .from('presentation_slides')
        .select()
        .eq('presentation_id', deckId)
        .order('slide_order');
    
    if (!mounted) return;
    setState(() {
      slides = List<Map<String, dynamic>>.from(response);
      currentSlideIndex = 0;
      currentDeckId = deckId;
      _isEditorOpen = true;
    });
  }

  Future<void> _createNewDeck() async {
    final deck = await supabase.from('presentations').insert({
      'title': widget.title == "New Presentation" ? "Strategy Deck" : widget.title,
      'owner_email': widget.userEmail
    }).select().single();

    await supabase.from('presentation_slides').insert({
      'presentation_id': deck['id'],
      'slide_order': 0,
      'title': 'Click to add title',
      'content': 'Click to add content'
    });

    _loadSlides(deck['id']);
  }

  Future<void> _saveSlideChanges() async {
    if (slides.isEmpty) return;
    final currentSlide = slides[currentSlideIndex];
    
    try {
      await supabase.from('presentation_slides').update({
        'title': currentSlide['title'],
        'content': currentSlide['content'],
      }).eq('id', currentSlide['id']);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Slide Cloud-Synced")));
    } catch (e) {
      debugPrint("Save error: $e");
    }
  }

  @override
  void dispose() {
    BrowserContextMenu.enableContextMenu();
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300), 
        child: _isEditorOpen ? _buildEditor() : _buildHub(),
      ),
    );
  }

  // --- 1. THE 3-COLUMN HUB (RESTORED TEMPLATES) ---
  Widget _buildHub() {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 1000;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0.5,
        title: Text("Presentation Hub", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: pOrange))),
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
    _hubCard("New Presentation", Icons.add_to_photos, pOrange, _createNewDeck),
    _hubCard("Open Existing", Icons.folder_shared, Colors.blue, () {}),
    _hubCard("Templates", Icons.style, Colors.green, () {}), // RESTORED
  ]);

  Widget _hubCol2() => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15)]),
    child: Column(children: [
      Padding(padding: const EdgeInsets.all(15), child: TextField(decoration: InputDecoration(hintText: "Search decks...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFFFBFBFE), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)))),
      Expanded(
        child: StreamBuilder(
          stream: supabase.from('presentations').stream(primaryKey: ['id']).eq('owner_email', widget.userEmail),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!;
            return ListView.builder(
              itemCount: docs.length, 
              itemBuilder: (c, i) => ListTile(
                leading: const Icon(Icons.slideshow, color: Color(0xFFB7472A)), 
                title: Text(docs[i]['title'], style: GoogleFonts.merriweather(fontWeight: FontWeight.bold)), 
                subtitle: Text("Modified: ${docs[i]['last_modified'].toString().substring(0,10)}"),
                onTap: () => _loadSlides(docs[i]['id']),
              )
            );
          }
        ),
      )
    ]));

  Widget _hubCol3() => Container(padding: const EdgeInsets.all(25), decoration: BoxDecoration(gradient: LinearGradient(colors: [pOrange, Colors.orange[800]!]), borderRadius: BorderRadius.circular(20)), 
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.lightbulb_outline, color: Colors.white, size: 30), const SizedBox(height: 15), 
      Text("Briefing Guide", style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)), 
      const Text("\n• Right-click for Slide Actions.\n• Use scroll arrows for fine movement.\n• Real-time cloud synchronization.", style: TextStyle(color: Colors.white70, height: 1.8))
    ]));

  Widget _hubCard(String t, IconData i, Color c, VoidCallback onTap) => Card(margin: const EdgeInsets.only(bottom: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(onTap: onTap, leading: Icon(i, color: c, size: 30), title: Text(t, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold))));

  // --- 2. THE EDITOR (RESTORED PLAY BUTTON) ---
  Widget _buildEditor() {
    double width = MediaQuery.of(context).size.width;
    String displayTitle = widget.title.isEmpty ? "My Presentation" : widget.title;

    return Scaffold(
      backgroundColor: const Color(0xFFCBCBCB),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(135), 
        child: Column(children: [
            Container(
              width: double.infinity, margin: const EdgeInsets.fromLTRB(10, 10, 10, 5), padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(15), 
                border: Border.all(color: pOrange.withValues(alpha: 0.15), width: 1.5), 
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]
              ),
              child: Stack(children: [
                  Positioned(left: 10, child: IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 20), onPressed: () => setState(() => _isEditorOpen = false))),
                  Center(child: Column(children: [
                        Text(displayTitle, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w900, color: pOrange)),
                        Text("Cloud Deck: ${widget.userEmail}", style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                  ])),
                  Positioned(right: 60, top: 5, child: IconButton(icon: const Icon(Icons.cloud_upload, color: Colors.blue), onPressed: _saveSlideChanges)),
                  const Positioned(right: 20, top: 5, child: Icon(Icons.play_circle_fill, color: Color(0xFFB7472A), size: 30)), // RESTORED
              ]),
            ),
            _buildRibbonTabs(),
            _buildActionCards(),
        ]),
      ),
      body: Column(children: [
        Expanded(child: Row(
          children: [
            _buildSlideSidebar(),
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalScroll, scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _verticalScroll,
                  child: GestureDetector(
                    onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition),
                    child: Center(child: _buildSlideCanvas()),
                  ),
                ),
              ),
            ),
            _buildVerticalArrowControls(), 
          ],
        )),
        _buildHorizontalArrowControls(width),
        _buildStatusBar(),
      ]),
    );
  }

  Widget _buildSlideSidebar() => Container(width: 160, color: Colors.white, child: ListView.builder(itemCount: slides.length, itemBuilder: (c, i) => GestureDetector(onTap: () => setState(() => currentSlideIndex = i), child: Container(margin: const EdgeInsets.all(10), height: 85, decoration: BoxDecoration(color: currentSlideIndex == i ? pOrange.withValues(alpha: 0.1) : Colors.white, border: Border.all(color: currentSlideIndex == i ? pOrange : Colors.grey.shade300, width: 2), borderRadius: BorderRadius.circular(8)), child: Center(child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold)))))));

  Widget _buildSlideCanvas() {
    if (slides.isEmpty) return const SizedBox.shrink();
    final slide = slides[currentSlideIndex];
    
    return Container(
      width: 960 * zoomLevel, height: 540 * zoomLevel, margin: const EdgeInsets.all(50), 
      padding: const EdgeInsets.all(60), decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)]),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextField(
          controller: TextEditingController(text: slide['title'])..selection = TextSelection.collapsed(offset: slide['title'].length),
          onChanged: (v) => slides[currentSlideIndex]['title'] = v,
          textAlign: TextAlign.center,
          style: GoogleFonts.merriweather(fontSize: 35 * zoomLevel, fontWeight: FontWeight.w900, color: pOrange),
          decoration: const InputDecoration(border: InputBorder.none),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: TextEditingController(text: slide['content'])..selection = TextSelection.collapsed(offset: slide['content'].length),
          onChanged: (v) => slides[currentSlideIndex]['content'] = v,
          textAlign: TextAlign.center,
          maxLines: null,
          style: GoogleFonts.merriweather(fontSize: 18 * zoomLevel),
          decoration: const InputDecoration(border: InputBorder.none),
        ),
      ]),
    );
  }

  Widget _buildRibbonTabs() => Container(height: 32, padding: const EdgeInsets.only(left: 15), child: ListView(scrollDirection: Axis.horizontal, children: pptMenus.keys.map((t) => GestureDetector(
    onTap: () => setState(() => activeTab = t), 
    child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: activeTab == t ? pOrange : const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(8)), 
      child: Center(child: Text(t, style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: activeTab == t ? Colors.white : pOrange))))
  )).toList()));

  Widget _buildActionCards() => Container(height: 35, width: double.infinity, color: const Color(0xFFFBFBFE), child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5), children: (pptMenus[activeTab] ?? []).map((item) => Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(6)), 
    child: Center(child: Text(item, style: GoogleFonts.merriweather(fontSize: 9, fontWeight: FontWeight.bold))))).toList()));

  Widget _buildVerticalArrowControls() => Container(width: 22, color: Colors.grey[200], child: Column(children: [
    IconButton(icon: const Icon(Icons.arrow_drop_up, size: 16), onPressed: () => _verticalScroll.animateTo(_verticalScroll.offset - 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
    Expanded(child: Container(width: 15, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(5)))),
    IconButton(icon: const Icon(Icons.arrow_drop_down, size: 16), onPressed: () => _verticalScroll.animateTo(_verticalScroll.offset + 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
  ]));

  Widget _buildHorizontalArrowControls(double w) => Container(height: 22, color: Colors.grey[100], child: Row(children: [
    const SizedBox(width: 160), 
    IconButton(icon: const Icon(Icons.arrow_left, size: 16), onPressed: () => _horizontalScroll.animateTo(_horizontalScroll.offset - 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
    Expanded(child: Container(height: 15, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(5)))),
    IconButton(icon: const Icon(Icons.arrow_right, size: 16), onPressed: () => _horizontalScroll.animateTo(_horizontalScroll.offset + 100, duration: const Duration(milliseconds: 50), curve: Curves.linear)),
    const SizedBox(width: 22), 
  ]));

  // --- RESTORED STATUS BAR FEATURES ---
  Widget _buildStatusBar() {
    return Container(
      height: 35, color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(children: [
        Text("Slide ${currentSlideIndex + 1} of ${slides.length}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        const Spacer(),
        const Icon(Icons.crop_original, size: 16, color: Colors.blue), // Normal
        const SizedBox(width: 15),
        const Icon(Icons.grid_view_rounded, size: 16), // Sorter
        const SizedBox(width: 15),
        const Icon(Icons.menu_book_outlined, size: 16), // Reading
        const SizedBox(width: 15),
        const Icon(Icons.play_arrow_outlined, size: 16), // Show
        const VerticalDivider(width: 40),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: const Color(0xFFF3E5F5), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.remove, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => setState(() => zoomLevel = (zoomLevel - 0.1).clamp(0.2, 1.5))),
            const SizedBox(width: 5),
            Text("${(zoomLevel * 100).toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(width: 5),
            IconButton(icon: const Icon(Icons.add, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => setState(() => zoomLevel = (zoomLevel + 0.1).clamp(0.2, 1.5))),
          ]),
        ),
      ]),
    );
  }

  // --- RESTORED EXTENDED CONTEXT MENU ---
  void _showContextMenu(Offset pos) {
    showMenu<dynamic>(context: context, position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: <PopupMenuEntry<dynamic>>[
        _ctx(Icons.content_cut, "Cut"), _ctx(Icons.content_copy, "Copy"),
        const PopupMenuItem<dynamic>(height: 35, child: Row(children: [Icon(Icons.paste, size: 18, color: Colors.orange), SizedBox(width: 12), Text("Paste Options:")])),
        const PopupMenuDivider(),
        _ctx(Icons.layers, "Layouts"),
        _ctx(Icons.copy_all, "Duplicate Slide"),
        _ctx(Icons.delete_sweep_outlined, "Delete Slide"),
        const PopupMenuDivider(),
        _ctx(Icons.auto_fix_high, "Transitions..."),
        _ctx(Icons.wallpaper, "Format Background..."),
        _ctx(Icons.link, "Hyperlink..."),
      ],
    );
  }

  PopupMenuItem<dynamic> _ctx(IconData i, String t) => PopupMenuItem<dynamic>(height: 35, child: Row(children: [Icon(i, size: 18, color: Colors.grey[700]), const SizedBox(width: 12), Text(t, style: GoogleFonts.merriweather(fontSize: 12))]));
}