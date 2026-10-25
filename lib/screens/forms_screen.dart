// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';

class FormsScreen extends StatefulWidget {
  final String title;
  final String userEmail;
  final String userRole;

  const FormsScreen({
    super.key,
    required this.title,
    required this.userEmail,
    required this.userRole,
  });

  @override
  State<FormsScreen> createState() => _FormsScreenState();
}

class _FormsScreenState extends State<FormsScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  
  late TabController _tabController;
  Color themeColor = const Color(0xFF673AB7);
  
  // Controllers for the Form Header
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  // State Management
  String? currentFormId;
  List<Map<String, dynamic>> formFields = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _titleController.text = widget.title;
    _fetchOrCreateForm();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  // --- SUPABASE LOGIC ---

  Future<void> _fetchOrCreateForm() async {
    try {
      final existing = await supabase
          .from('user_forms')
          .select()
          .eq('owner_email', widget.userEmail)
          .eq('title', widget.title)
          .maybeSingle();

      if (existing != null) {
        currentFormId = existing['id'];
        _titleController.text = existing['title'];
        _descController.text = existing['description'] ?? "";
        // FIXED: Using toARGB32 logic for compatibility
        themeColor = Color(int.parse(existing['theme_hex'], radix: 16));
        
        final fields = await supabase
            .from('user_form_fields')
            .select()
            .eq('form_id', currentFormId!)
            .order('order_index');
        
        formFields = List<Map<String, dynamic>>.from(fields);
      } else {
        final newForm = await supabase.from('user_forms').insert({
          'title': widget.title,
          'owner_email': widget.userEmail,
          // FIXED: Changed .value to .toARGB32() to avoid deprecation
          'theme_hex': themeColor.toARGB32().toRadixString(16).toUpperCase(),
        }).select().single();
        currentFormId = newForm['id'];
      }
    } catch (e) {
      debugPrint("Init error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveForm() async {
    if (currentFormId == null) return;
    
    try {
      await supabase.from('user_forms').update({
        'title': _titleController.text,
        'description': _descController.text,
        // FIXED: Changed .value to .toARGB32()
        'theme_hex': themeColor.toARGB32().toRadixString(16).toUpperCase(),
        'last_modified': DateTime.now().toIso8601String(),
      }).eq('id', currentFormId!);

      await supabase.from('user_form_fields').delete().eq('form_id', currentFormId!);
      
      final fieldsToInsert = formFields.asMap().entries.map((e) => {
        'form_id': currentFormId,
        'label': e.value['label'],
        'field_type': e.value['field_type'] ?? e.value['type'],
        'hint': e.value['hint'],
        'is_required': e.value['is_required'] ?? e.value['required'],
        'order_index': e.key,
      }).toList();

      await supabase.from('user_form_fields').insert(fieldsToInsert);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Form Synced to Cloud")));
    } catch (e) {
      debugPrint("Save error: $e");
    }
  }

  void _addField(String type) {
    setState(() {
      formFields.add({
        "type": type,
        "label": "Untitled $type",
        "hint": "Type here...",
        "required": false
      });
    });
    if (MediaQuery.of(context).size.width < 800 && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    bool isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF0F2F5)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        titleSpacing: isMobile ? 10 : 40,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppPalette.fg(Colors.black54)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description, color: AppPalette.fg(themeColor), size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_titleController.text, style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.w500)),
                  Text(widget.userEmail, style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.grey))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.palette_outlined, size: 20), onPressed: _showThemePicker),
          if (!isMobile) ...[
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _saveForm,
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(themeColor), foregroundColor: AppPalette.fg(Colors.white)),
              child: const Text("Save Sync"),
            ),
          ],
          const SizedBox(width: 10),
          CircleAvatar(
              radius: 14,
              backgroundColor: AppPalette.bg(themeColor),
              // FIXED: child is now the last property
              child: Text(
                widget.userEmail.isNotEmpty ? widget.userEmail[0].toUpperCase() : "U", 
                style: TextStyle(fontSize: 10, color: AppPalette.fg(Colors.white))
              )),
          const SizedBox(width: 15),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelColor: themeColor,
            indicatorColor: themeColor,
            tabs: const [Tab(text: "Questions"), Tab(text: "Responses"), Tab(text: "Settings")],
          ),
        ),
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton(backgroundColor: AppPalette.bg(themeColor), onPressed: _showMobileAddMenu, child: Icon(Icons.add, color: AppPalette.fg(Colors.white)))
          : null,
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildQuestionsTab(isMobile),
              _buildResponsesTab(),
              _buildEmptyState("Settings & Logic for ${widget.userRole}"),
            ],
          ),
          if (!isMobile)
            Positioned(right: MediaQuery.of(context).size.width * 0.1, top: 50, child: _buildDesktopQuickBar()),
        ],
      ),
    );
  }

  Widget _buildQuestionsTab(bool isMobile) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 25),
      child: Column(
        children: [
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 750),
              child: Column(
                children: [
                  _buildFormHeader(),
                  const SizedBox(height: 15),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: formFields.length,
                    // FIXED: Changed onReorder to onReorderItem as per lint
                    onReorderItem: (oldIdx, newIdx) {
                      setState(() {
                        final item = formFields.removeAt(oldIdx);
                        formFields.insert(newIdx, item);
                      });
                    },
                    itemBuilder: (context, index) => _buildQuestionBlock(index),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildFormHeader() {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border(top: BorderSide(color: AppPalette.line(themeColor), width: 10)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5)],
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            style: GoogleFonts.merriweather(fontSize: 28, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(hintText: "Untitled Form", border: InputBorder.none),
          ),
          Text("Author: ${widget.userEmail}", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey), fontStyle: FontStyle.italic)),
          TextField(
            controller: _descController,
            style: GoogleFonts.merriweather(fontSize: 14),
            decoration: const InputDecoration(hintText: "Form description", border: InputBorder.none),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionBlock(int index) {
    return Container(
      key: ValueKey("field_$index"),
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppPalette.line(Colors.grey.shade300))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.drag_indicator, color: AppPalette.fg(Colors.grey), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: formFields[index]['label'],
                  onChanged: (val) => formFields[index]['label'] = val,
                  style: GoogleFonts.merriweather(fontWeight: FontWeight.w500, fontSize: 16),
                  decoration: const InputDecoration(border: UnderlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              _buildTypeBadge(formFields[index]['field_type'] ?? formFields[index]['type']),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            enabled: false,
            decoration: InputDecoration(
              hintText: formFields[index]['hint'],
              filled: true,
              fillColor: AppPalette.bg(Colors.grey.shade50),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
            ),
          ),
          const Divider(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(icon: Icon(Icons.delete_outline, size: 20, color: AppPalette.fg(Colors.black54)), onPressed: () => setState(() => formFields.removeAt(index))),
              const VerticalDivider(width: 20),
              const Text("Required", style: TextStyle(fontSize: 12)),
              Switch(
                value: formFields[index]['is_required'] ?? formFields[index]['required'],
                // FIXED: Changed activeColor to activeThumbColor
                activeThumbColor: themeColor,
                onChanged: (val) => setState(() => formFields[index]['is_required'] = val),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildResponsesTab() {
    return StreamBuilder(
      stream: supabase.from('user_form_submissions').stream(primaryKey: ['id']).eq('form_id', currentFormId!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final submissions = snapshot.data!;
        if (submissions.isEmpty) return _buildEmptyState("No responses yet.");
        
        return ListView.builder(
          itemCount: submissions.length,
          itemBuilder: (c, i) => ListTile(
            title: Text("Submission from ${submissions[i]['submitted_by']}"),
            subtitle: Text("At: ${submissions[i]['created_at']}"),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) => Center(child: Text(message, style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))));

  Widget _buildTypeBadge(String type) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppPalette.bg(Colors.grey.shade100), borderRadius: BorderRadius.circular(4)), child: Text(type.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black54))));

  Widget _buildDesktopQuickBar() => Container(width: 46, decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)], border: Border.all(color: AppPalette.line(Colors.grey.shade200))), child: Column(mainAxisSize: MainAxisSize.min, children: [_quickBarAction(Icons.add_circle_outline, "Add Question", "text"), _quickBarAction(Icons.title, "Add Title", "text"), _quickBarAction(Icons.calendar_month, "Add Date", "date")]));

  Widget _quickBarAction(IconData icon, String tooltip, String type) => Tooltip(message: tooltip, child: InkWell(onTap: () => _addField(type), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Icon(icon, color: AppPalette.fg(Colors.black54), size: 20))));

  void _showMobileAddMenu() => showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))), builder: (context) => Padding(padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20), child: GridView.count(shrinkWrap: true, crossAxisCount: 3, children: [_mobileMenuOption(Icons.text_fields, "Short Text", "text"), _mobileMenuOption(Icons.calendar_month, "Date", "date"), _mobileMenuOption(Icons.check_box, "Checkboxes", "choice")])));

  Widget _mobileMenuOption(IconData icon, String label, String type) => InkWell(onTap: () => _addField(type), child: Column(children: [CircleAvatar(backgroundColor: AppPalette.bg(themeColor.withValues(alpha: 0.1)), child: Icon(icon, color: AppPalette.fg(themeColor), size: 20)), const SizedBox(height: 8), Text(label, style: const TextStyle(fontSize: 11))]));

  void _showThemePicker() => showDialog(context: context, builder: (context) => AlertDialog(title: const Text("Theme Color"), content: Wrap(spacing: 12, runSpacing: 12, children: [Colors.indigo, Colors.red, Colors.teal, Colors.blue, Colors.black87].map((color) => InkWell(onTap: () { setState(() => themeColor = color); Navigator.pop(context); }, child: CircleAvatar(backgroundColor: AppPalette.bg(color), radius: 18))).toList())));
}