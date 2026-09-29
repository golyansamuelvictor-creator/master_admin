// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchQuotes();
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
    return Color(int.parse(buffer.toString(), radix: 16));
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
            const SizedBox(height: 15), 
            Expanded(
              child: _isLoading 
                ? Center(child: CircularProgressIndicator(color: pPurple))
                : _dynamicQuotes.isEmpty 
                  ? Center(child: Text("No quotes found in database.", style: GoogleFonts.merriweather(color: Colors.grey)))
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: widget.isFullPage ? _dynamicQuotes.length : 2,
                      itemBuilder: (context, index) {
                        final q = _dynamicQuotes[index];
                        return _buildQuoteCard(
                          q['quote_text'], 
                          (index + 1).toString(), 
                          _fromHex(q['color_hex'] ?? "#4A148C"),
                          isDesktop
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
        backgroundColor: const Color(0xFFFBFBFE),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          centerTitle: true,
          title: Text("Quotes of Chairman", style: GoogleFonts.merriweather(fontSize: 16, color: pPurple, fontWeight: FontWeight.bold)),
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
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
        border: Border.all(color: pPurple.withValues(alpha: 0.1), width: 1),
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
                  color: Colors.red[900], 
                  fontWeight: FontWeight.bold
                )
              ),
              TextSpan(
                text: "|  Quotes of Chairman", 
                style: GoogleFonts.merriweather(
                  fontSize: size * 0.9, 
                  color: pPurple, 
                  fontWeight: FontWeight.w900
                )
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteCard(String text, String id, Color quoteColor, bool isDesktop) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), 
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Container(
            height: 4, 
            decoration: BoxDecoration(color: quoteColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(15))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), 
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 15, 
                  backgroundColor: pPurple.withValues(alpha: 0.05),
                  child: Text(id, style: TextStyle(color: quoteColor, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    text,
                    style: GoogleFonts.merriweather(
                      fontSize: isDesktop ? 16 : 13,
                      height: 1.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}