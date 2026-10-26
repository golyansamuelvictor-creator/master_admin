// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';
import 'package:master_admin/screens/forms_studio.dart';

/// Surveys tab: forms to answer, my forms, and the admin feedback form.
class SurveyScreen extends StatelessWidget {
  final double s;
  final bool isFullPage;
  const SurveyScreen({super.key, this.s = 1.0, this.isFullPage = false});

  @override
  Widget build(BuildContext context) => FormsHub(fullPage: false, legacyFeedback: (_) => const AdminFeedbackForm(isFullPage: true));
}

class AdminFeedbackForm extends StatefulWidget {
  final double s;
  final bool isFullPage; // Added to match other screens

  const AdminFeedbackForm({super.key, this.s = 1.0, this.isFullPage = false});

  @override
  State<AdminFeedbackForm> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<AdminFeedbackForm> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isSubmitting = false;

  List<dynamic> _questions = [];
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  @override
  void dispose() {
    _controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  Future<void> _fetchQuestions() async {
    try {
      final res = await _supabase
          .from('app_survey_questions')
          .select()
          .eq('is_active', true)
          .order('sort_order');

      if (mounted) {
        setState(() {
          _questions = res;
          for (var q in _questions) {
            _controllers[q['id'].toString()] = TextEditingController();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitSurvey() async {
    setState(() => _isSubmitting = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      
      List<Map<String, dynamic>> responses = [];

      _controllers.forEach((qId, controller) {
        if (controller.text.isNotEmpty) {
          responses.add({
            'question_id': qId,
            'leader_id': user.id,
            'response_text': controller.text.trim(),
          });
        }
      });

      if (responses.isEmpty) {
        _showMsg("Please answer at least one question.", isError: true);
        setState(() => _isSubmitting = false);
        return;
      }

      await _supabase.from('app_survey_responses').insert(responses);

      if (mounted) {
        _showMsg("Survey submitted successfully. Thank you!");
        _controllers.forEach((key, value) => value.clear());
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      _showMsg("Submission error. Please try again.", isError: true);
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMsg(String m, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: isError ? Colors.red : Colors.green)
    );
  }

  @override
  Widget build(BuildContext context) {
    const pPurple = Color(0xFF4A148C);

    // THE FIX: Extracted core content to reuse or wrap in Scaffold
    Widget content = _isLoading 
        ? const Center(child: CircularProgressIndicator(color: pPurple))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderCard(pPurple),
                const SizedBox(height: 30),
                ..._questions.map((q) => _buildQuestionField(q, pPurple)),
                const SizedBox(height: 30),
                _buildSubmitButton(pPurple),
                const SizedBox(height: 50),
              ],
            ),
          );

    // If it's a standalone full page (like from a Navigator push)
    if (widget.isFullPage) {
      return Scaffold(
        backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white),
          elevation: 0.5,
          centerTitle: true,
          title: Text("Take a survey", 
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple), fontSize: 16)),
        ),
        body: content,
      );
    }

    // If it's inside the HomeScreen Hub, return it as a transparent container
    return Container(
      color: AppPalette.bg(Colors.transparent), // Important to keep the pink home background
      child: content,
    );
  }

  Widget _buildHeaderCard(Color pPurple) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.bg(pPurple.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Administrative feedback form", 
            style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18, color: AppPalette.fg(pPurple))),
          const SizedBox(height: 5),
          Text("Your insights help us improve the church management system.",
            style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.blueGrey), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildQuestionField(dynamic q, Color pPurple) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q['question_text'], 
            style: GoogleFonts.merriweather(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.fg(Colors.black87))),
          const SizedBox(height: 10),
          TextField(
            controller: _controllers[q['id'].toString()],
            maxLines: 3,
            decoration: InputDecoration(
              hintText: "Type your response here...",
              hintStyle: const TextStyle(fontSize: 13),
              filled: true,
              fillColor: AppPalette.bg(Colors.white),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppPalette.line(Colors.grey.withValues(alpha: 0.2)))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppPalette.line(pPurple), width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(Color pPurple) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.bg(pPurple),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 4,
        ),
        onPressed: _isSubmitting ? null : _submitSurvey,
        child: _isSubmitting 
          ? const CircularProgressIndicator(color: Colors.white)
          : Text("Submit survey", 
              style: TextStyle(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}