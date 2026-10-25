// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notice_permissions.dart';
import 'package:master_admin/core/app_palette.dart';

class QuotesScreen extends StatefulWidget {
  final double s;
  final bool isFullPage;

  const QuotesScreen({super.key, this.s = 1.0, this.isFullPage = false});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<dynamic> _dynamicQuotes = [];
  
  // Moved to class level to fix "Undefined name 'pPurple'"
  final Color pPurple = const Color(0xFF4A148C);

  // Quotes are added by roles with "Manage Quotes" (Internal Affairs Dept Sec by default)
  NoticePermissions _perm = NoticePermissions.none;

  static const List<String> _swatches = ['#4A148C', '#B71C1C', '#0D47A1', '#1B5E20', '#E65100', '#37474F'];

  @override
  void initState() {
    super.initState();
    _fetchQuotes();
    NoticePermissions.load().then((p) {
      if (mounted) setState(() => _perm = p);
    });
  }

  Future<void> _deleteQuote(dynamic q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove quote?", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
        content: Text(q['quote_text']?.toString() ?? '', style: GoogleFonts.merriweather(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Remove", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase.from('app_quotes').delete().eq('id', q['id']);
      _fetchQuotes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't remove it. You may not have permission.")));
      }
    }
  }

  Future<void> _openQuoteForm({dynamic existing}) async {
    final textC = TextEditingController(text: existing?['quote_text']?.toString() ?? '');
    final orderC = TextEditingController(text: (existing?['sort_order'] ?? (_dynamicQuotes.length + 1)).toString());
    String color = (existing?['color_hex'] ?? _swatches.first).toString();
    String? error;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(existing == null ? "Add quote" : "Edit quote",
                style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(pPurple))),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Shown to everyone in the church",
                      style: GoogleFonts.merriweather(fontSize: 11, color: AppPalette.fg(Colors.blueGrey[700]), fontStyle: FontStyle.italic)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textC,
                    minLines: 3,
                    maxLines: 7,
                    decoration: const InputDecoration(labelText: "Quote", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Text("Colour", style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _swatches.map((h) {
                      final selected = h.toUpperCase() == color.toUpperCase();
                      return InkWell(
                        onTap: () => setD(() => color = h),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppPalette.bg(_fromHex(h)),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppPalette.line(selected ? Colors.black87 : Colors.white), width: 3),
                          ),
                          child: selected ? Icon(Icons.check, size: 16, color: AppPalette.fg(Colors.white)) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: orderC,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Order", border: OutlineInputBorder()),
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
                          setD(() => error = "Write the quote first.");
                          return;
                        }
                        setD(() {
                          saving = true;
                          error = null;
                        });
                        final data = {
                          'quote_text': text,
                          'color_hex': color,
                          'sort_order': int.tryParse(orderC.text.trim()) ?? 0,
                        };
                        try {
                          if (existing == null) {
                            await _supabase.from('app_quotes').insert({...data, 'is_active': true});
                          } else {
                            await _supabase.from('app_quotes').update(data).eq('id', existing['id']);
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          _fetchQuotes();
                        } catch (e) {
                          setD(() {
                            saving = false;
                            error = "Couldn't save. Your role may not be allowed to manage quotes.";
                          });
                        }
                      },
                child: Text(saving ? "Saving..." : "Save"),
              ),
            ],
          )),
    );
  }

  // ==========================================
  // DATA LOGIC
  // ==========================================

  Future<void> _fetchQuotes() async {
    try {
      final res = await _supabase
          .from('app_quotes')
          .select()
          .eq('is_active', true)
          .order('sort_order');

      if (mounted) {
        setState(() {
          _dynamicQuotes = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Quotes Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.tryParse(buffer.toString(), radix: 16) ?? 0xFF4A148C);
  }

  // ==========================================
  // UI RENDERING
  // ==========================================

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    bool isDesktop = width > 900;
    double titleFontSize = isDesktop ? 22 : 14;

    Widget mainContent = SizedBox.expand(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 40 : 20, vertical: 15),
        child: Column(
          children: [
            _buildOutstandingHeader(titleFontSize, isDesktop),
            if (_perm.canAddQuotes)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.bg(pPurple),
                      foregroundColor: AppPalette.fg(Colors.white),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _openQuoteForm(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text("Add quote", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ),
            const SizedBox(height: 15), 
            Expanded(
              child: _isLoading 
                ? Center(child: CircularProgressIndicator(color: pPurple))
                : _dynamicQuotes.isEmpty 
                  ? Center(child: Text("No quotes found in database.", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey))))
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: widget.isFullPage ? _dynamicQuotes.length : (_dynamicQuotes.length < 2 ? _dynamicQuotes.length : 2),
                      itemBuilder: (context, index) {
                        final q = _dynamicQuotes[index];
                        return _buildQuoteCard(
                          q['quote_text'] ?? '', 
                          (index + 1).toString(), 
                          _fromHex(q['color_hex'] ?? "#4A148C"),
                          isDesktop,
                          item: _perm.canAddQuotes ? q : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );

    if (widget.isFullPage) {
      return mainContent; 
    } else {
      return Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white),
          elevation: 0.5,
          centerTitle: true,
          title: Text("Quotes of Chairman", style: GoogleFonts.merriweather(fontSize: 16, color: AppPalette.fg(pPurple), fontWeight: FontWeight.bold)),
        ),
        body: mainContent,
      );
    }
  }

  Widget _buildOutstandingHeader(double size, bool isDesktop) {
    return Container(
      width: double.infinity, 
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), 
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white.withValues(alpha: 0.9)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
        border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.1)), width: 1),
      ),
      child: Center(
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: "총회장님 말씀  ", 
                style: GoogleFonts.merriweather(
                  fontSize: size, 
                  color: AppPalette.fg(Colors.red[900]), 
                  fontWeight: FontWeight.bold
                )
              ),
              TextSpan(
                text: "|  Quotes of Chairman", 
                style: GoogleFonts.merriweather(
                  fontSize: size * 0.9, 
                  color: AppPalette.fg(pPurple), 
                  fontWeight: FontWeight.w900
                )
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteCard(String text, String id, Color quoteColor, bool isDesktop, {dynamic item}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), 
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppPalette.line(Colors.grey.withValues(alpha: 0.1)), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Container(
            height: 4, 
            decoration: BoxDecoration(color: AppPalette.bg(quoteColor), borderRadius: const BorderRadius.vertical(top: Radius.circular(15))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), 
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15, 
                  backgroundColor: AppPalette.bg(pPurple.withValues(alpha: 0.05)),
                  child: Text(id, style: TextStyle(color: AppPalette.fg(quoteColor), fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    text,
                    style: GoogleFonts.merriweather(
                      fontSize: isDesktop ? 16 : 13,
                      height: 1.5,
                      color: AppPalette.fg(Colors.black87),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (item != null)
                  PopupMenuButton<String>(
                    tooltip: "Edit or remove",
                    icon: Icon(Icons.more_vert_rounded, size: 18, color: AppPalette.fg(Colors.blueGrey[400])),
                    onSelected: (v) => v == 'edit' ? _openQuoteForm(existing: item) : _deleteQuote(item),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text("Edit")),
                      PopupMenuItem(value: 'delete', child: Text("Remove")),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}