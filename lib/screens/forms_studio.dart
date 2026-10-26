// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_palette.dart';
import '../core/table_export.dart';
import '../widgets/app_menus.dart';
import '../widgets/office_shell.dart' show OfficeTemplate, OfficeTemplateGrid;

/// Surveys & forms (Tally / Google Forms style): build a form with many
/// question types, sections and "show only if" logic, publish it to the
/// church app, collect answers, and read them as a summary with charts,
/// one by one, or as a table (Excel / PDF / print).
///
/// Tables: user_forms, user_form_fields, user_form_submissions (08_round7.sql).

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
const Map<String, (String, IconData)> kQuestionTypes = {
  'short_text': ('Short answer', Icons.short_text_rounded),
  'long_text': ('Paragraph', Icons.notes_rounded),
  'multiple_choice': ('Multiple choice', Icons.radio_button_checked_rounded),
  'checkboxes': ('Checkboxes', Icons.check_box_outlined),
  'dropdown': ('Dropdown', Icons.arrow_drop_down_circle_outlined),
  'yes_no': ('Yes / No', Icons.thumbs_up_down_outlined),
  'linear_scale': ('Linear scale', Icons.linear_scale_rounded),
  'rating': ('Rating', Icons.star_outline_rounded),
  'number': ('Number', Icons.pin_outlined),
  'email': ('Email', Icons.alternate_email_rounded),
  'phone': ('Phone', Icons.phone_outlined),
  'date': ('Date', Icons.calendar_today_outlined),
  'time': ('Time', Icons.schedule_outlined),
  'statement': ('Text block', Icons.text_snippet_outlined),
  'section': ('New page', Icons.view_agenda_outlined),
};

bool _isChoice(String t) => t == 'multiple_choice' || t == 'checkboxes' || t == 'dropdown';
bool _isInput(String t) => t != 'statement' && t != 'section';

String _newKey() {
  final r = math.Random();
  return List.generate(10, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[r.nextInt(32)]).join();
}

class FormQ {
  String key;
  String type;
  String label;
  String description;
  bool required;
  List<String> options;
  Map<String, dynamic> settings;

  FormQ({required this.key, required this.type, this.label = '', this.description = '', this.required = false, List<String>? options, Map<String, dynamic>? settings})
      : options = options ?? [],
        settings = settings ?? {};

  FormQ copy() => FormQ(key: _newKey(), type: type, label: label, description: description, required: required, options: List.of(options), settings: Map.of(settings)..remove('show_if'));

  static String _mapOldType(String t) => switch (t) { 'text' => 'short_text', 'choice' => 'checkboxes', 'paragraph' => 'long_text', _ => kQuestionTypes.containsKey(t) ? t : 'short_text' };

  factory FormQ.fromRow(Map m) {
    final s = m['settings'] is Map ? Map<String, dynamic>.from(m['settings'] as Map) : <String, dynamic>{};
    return FormQ(
      key: (s['key'] ?? m['id'] ?? _newKey()).toString(),
      type: _mapOldType((m['field_type'] ?? 'short_text').toString()),
      label: (m['label'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      required: m['is_required'] == true,
      options: (m['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
      settings: s,
    );
  }

  Map<String, dynamic> toRow(String formId, int i) => {
        'form_id': formId,
        'label': label,
        'field_type': type,
        'hint': settings['placeholder']?.toString(),
        'is_required': required,
        'order_index': i,
        'description': description.isEmpty ? null : description,
        'options': options,
        'settings': {...settings, 'key': key},
      };

  int get scaleMin => (settings['min'] as num?)?.toInt() ?? 1;
  int get scaleMax => (settings['max'] as num?)?.toInt() ?? (type == 'rating' ? 5 : 5);
}

Color _hexColor(String? hex, [Color fallback = const Color(0xFF673AB7)]) {
  final h = (hex ?? '').replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// Answers → readable text for tables and summaries.
String formatAnswer(FormQ q, dynamic v) {
  if (v == null) return '';
  if (v is List) return v.map((e) => e.toString()).join(', ');
  if (q.type == 'yes_no') return v == true || v == 'yes' ? 'Yes' : (v == false || v == 'no' ? 'No' : v.toString());
  return v.toString();
}

class FormsService {
  FormsService._();
  static SupabaseClient get _db => Supabase.instance.client;
  static String? get myId => _db.auth.currentUser?.id;

  static Future<List<Map<String, dynamic>>> overview() async {
    final r = await _db.rpc('forms_overview');
    return List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  static Future<Map<String, dynamic>> form(String id) async => Map<String, dynamic>.from(await _db.from('user_forms').select().eq('id', id).single());

  static Future<List<FormQ>> questions(String id) async {
    final r = await _db.from('user_form_fields').select().eq('form_id', id).order('order_index');
    return (r as List).map((m) => FormQ.fromRow(m as Map)).toList();
  }

  static Future<String> create(String title, String description, List<FormQ> qs, {String theme = 'FF673AB7'}) async {
    final email = _db.auth.currentUser?.email ?? '';
    final row = await _db
        .from('user_forms')
        .insert({'title': title, 'description': description, 'owner_email': email, 'owner_id': myId, 'theme_hex': theme, 'confirmation': 'Thank you! Your answers were sent.'})
        .select('id')
        .single();
    final id = row['id'].toString();
    if (qs.isNotEmpty) await _db.from('user_form_fields').insert([for (int i = 0; i < qs.length; i++) qs[i].toRow(id, i)]);
    return id;
  }

  static Future<void> saveForm(String id, Map<String, dynamic> values) =>
      _db.from('user_forms').update({...values, 'last_modified': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  static Future<void> saveQuestions(String id, List<FormQ> qs) async {
    await _db.from('user_form_fields').delete().eq('form_id', id);
    if (qs.isNotEmpty) await _db.from('user_form_fields').insert([for (int i = 0; i < qs.length; i++) qs[i].toRow(id, i)]);
  }

  static Future<void> delete(String id) => _db.from('user_forms').delete().eq('id', id);

  static Future<List<Map<String, dynamic>>> submissions(String id) async {
    final r = await _db.from('user_form_submissions').select().eq('form_id', id).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(r);
  }

  /// Inserted without reading back: anonymous answers carry no owner, so
  /// nobody (not even the person who answered) can read them afterwards.
  static Future<void> submit(String id, Map<String, dynamic> data) => _db.from('user_form_submissions').insert({'form_id': id, 'data': data});

  static Future<void> deleteSubmission(String id) => _db.from('user_form_submissions').delete().eq('id', id);
}

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------
FormQ _q(String type, String label, {bool req = false, List<String>? opts, Map<String, dynamic>? s, String desc = ''}) =>
    FormQ(key: _newKey(), type: type, label: label, required: req, options: opts, settings: s, description: desc);

final Map<String, (String, String, List<FormQ> Function())> _formTemplates = {
  'blank': ('Untitled form', '', () => [_q('short_text', 'Untitled question')]),
  'event': (
    'Event registration',
    'Register for the event. We will contact you with details.',
    () => [
          _q('short_text', 'Full name', req: true),
          _q('phone', 'Phone number', req: true),
          _q('email', 'Email'),
          _q('dropdown', 'Your department', opts: ['Men', 'Women', 'Youth', 'Students', 'Children']),
          _q('multiple_choice', 'Will you attend?', req: true, opts: ['Yes', 'Maybe', 'No']),
          _q('number', 'How many people are coming with you?', s: {'min': 0, 'max': 20}),
          _q('long_text', 'Anything we should know? (diet, transport …)'),
        ]
  ),
  'feedback': (
    'Feedback survey',
    'Help us improve. It takes 2 minutes.',
    () => [
          _q('rating', 'How satisfied are you overall?', req: true, s: {'max': 5}),
          _q('linear_scale', 'How likely are you to recommend it to a friend?', s: {'min': 0, 'max': 10, 'min_label': 'Not likely', 'max_label': 'Very likely'}),
          _q('checkboxes', 'What did you like?', opts: ['Message', 'Praise', 'Organisation', 'Fellowship'], s: {'other': true}),
          _q('long_text', 'What should we improve?'),
        ]
  ),
  'prayer': (
    'Prayer request',
    'Share your prayer request. It is kept private to the leaders.',
    () => [
          _q('short_text', 'Name (optional)'),
          _q('dropdown', 'Topic', req: true, opts: ['Health', 'Family', 'Work / studies', 'Faith', 'Thanksgiving', 'Other']),
          _q('long_text', 'Your request', req: true),
          _q('yes_no', 'May a leader contact you?'),
          _q('phone', 'Phone number', s: {'show_if': {'key': '', 'equals': 'yes'}}),
        ]
  ),
  'volunteer': (
    'Volunteer sign-up',
    'Choose where you would like to serve.',
    () => [
          _q('short_text', 'Full name', req: true),
          _q('phone', 'Phone number', req: true),
          _q('checkboxes', 'Teams', req: true, opts: ['Ushering', 'Media', 'Choir', 'Welfare', 'Cleaning', 'Security']),
          _q('checkboxes', 'Days available', opts: ['Wednesday', 'Saturday', 'Sunday']),
          _q('long_text', 'Skills or experience'),
        ]
  ),
  'checkin': (
    'Attendance check-in',
    'Check in for today.',
    () => [
          _q('short_text', 'Full name', req: true),
          _q('short_text', 'Cell / team'),
          _q('multiple_choice', 'How are you attending?', req: true, opts: ['In person', 'Online']),
          _q('date', 'Date', req: true),
        ]
  ),
  'contact': (
    'Contact details update',
    'Please keep your details up to date.',
    () => [
          _q('short_text', 'Full name', req: true),
          _q('phone', 'Phone number', req: true),
          _q('email', 'Email'),
          _q('short_text', 'Home area / address'),
          _q('date', 'Date of birth'),
          _q('short_text', 'Emergency contact (name and phone)'),
        ]
  ),
  'quizlike': (
    'Bible study check',
    'A short check after the lesson.',
    () => [
          _q('short_text', 'Name', req: true),
          _q('multiple_choice', 'Question 1', req: true, opts: ['Answer A', 'Answer B', 'Answer C']),
          _q('multiple_choice', 'Question 2', req: true, opts: ['Answer A', 'Answer B', 'Answer C']),
          _q('section', 'Reflection'),
          _q('long_text', 'What did you learn today?'),
          _q('linear_scale', 'How well did you understand the lesson?', s: {'min': 1, 'max': 5, 'min_label': 'Not at all', 'max_label': 'Fully'}),
        ]
  ),
};

const List<OfficeTemplate> _formTemplateCards = [
  OfficeTemplate('blank', 'Blank form', 'Start from scratch', Icons.add_rounded),
  OfficeTemplate('event', 'Event registration', 'Name, phone, attendance, guests', Icons.event_available_outlined),
  OfficeTemplate('feedback', 'Feedback survey', 'Rating, scale, likes, ideas', Icons.reviews_outlined),
  OfficeTemplate('prayer', 'Prayer request', 'Topic, request, contact if allowed', Icons.volunteer_activism_outlined),
  OfficeTemplate('volunteer', 'Volunteer sign-up', 'Teams and days available', Icons.handshake_outlined),
  OfficeTemplate('checkin', 'Attendance check-in', 'Name, unit, in person / online', Icons.how_to_reg_outlined),
  OfficeTemplate('contact', 'Contact details', 'Phone, email, address, birthday', Icons.contact_page_outlined),
  OfficeTemplate('quizlike', 'Lesson check', 'Questions, reflection, understanding', Icons.quiz_outlined),
];

// ---------------------------------------------------------------------------
// Hub: forms to answer + my forms
// ---------------------------------------------------------------------------
class FormsHub extends StatefulWidget {
  /// Shows the old admin feedback questions as one more card.
  final Widget Function(BuildContext)? legacyFeedback;
  final bool startNew;
  final bool fullPage;
  const FormsHub({super.key, this.legacyFeedback, this.startNew = false, this.fullPage = true});

  @override
  State<FormsHub> createState() => _FormsHubState();
}

class _FormsHubState extends State<FormsHub> {
  List<Map<String, dynamic>> _forms = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  static const Color _accent = Color(0xFF673AB7);

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.startNew) WidgetsBinding.instance.addPostFrameCallback((_) => _newForm());
  }

  Future<void> _load() async {
    try {
      final f = await FormsService.overview();
      if (!mounted) return;
      setState(() {
        _forms = f;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint("Forms error: $e");
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load forms. Ask the admin to run 08_round7.sql.";
        });
      }
    }
  }

  Future<void> _newForm() async {
    final t = await showDialog<OfficeTemplate>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text("Start a new form", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 10),
              Flexible(child: OfficeTemplateGrid(templates: _formTemplateCards, accent: _accent, scrollable: true, maxCardWidth: 210, cardHeight: 150, onTap: (t) => Navigator.pop(ctx, t))),
            ]),
          ),
        ),
      ),
    );
    if (t == null) return;
    final tpl = _formTemplates[t.key]!;
    try {
      final qs = tpl.$3();
      // link "show only if" in the prayer template to the yes/no question
      for (int i = 0; i < qs.length; i++) {
        final si = qs[i].settings['show_if'];
        if (si is Map && (si['key'] ?? '') == '' && i > 0) si['key'] = qs[i - 1].key;
      }
      final id = await FormsService.create(tpl.$1, tpl.$2, qs);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => FormBuilderScreen(formId: id)));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't create the form: ${e is PostgrestException ? e.message : e}")));
    }
  }

  Future<void> _open(Map<String, dynamic> f, {String tab = 'edit'}) async {
    final id = f['id'].toString();
    if (f['mine'] == true && tab != 'fill') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => FormBuilderScreen(formId: id, initialTab: tab == 'responses' ? 1 : 0)));
    } else {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => FormFillScreen(formId: id, preview: f['mine'] == true)));
    }
    _load();
  }

  Future<void> _duplicate(Map<String, dynamic> f) async {
    try {
      final form = await FormsService.form(f['id'].toString());
      final qs = await FormsService.questions(f['id'].toString());
      await FormsService.create("${form['title'] ?? 'Form'} (copy)", (form['description'] ?? '').toString(), qs,
          theme: (form['theme_hex'] ?? 'FF673AB7').toString());
      _load();
    } catch (_) {}
  }

  Future<void> _delete(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete \"${f['title']}\"?"),
        content: const Text("The form and all its responses are deleted. This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Delete", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    await FormsService.delete(f['id'].toString());
    _load();
  }

  List<OfficeMenuItem> _menu(Map<String, dynamic> f) => [
        if (f['mine'] == true) ...[
          OfficeMenuItem("Edit", icon: Icons.edit_outlined, onTap: () => _open(f)),
          OfficeMenuItem("Responses (${f['responses'] ?? 0})", icon: Icons.insights_rounded, onTap: () => _open(f, tab: 'responses')),
          OfficeMenuItem("Preview", icon: Icons.visibility_outlined, onTap: () => _open(f, tab: 'fill')),
          OfficeMenuItem(f['is_published'] == true ? "Unpublish" : "Publish", icon: Icons.public_rounded, onTap: () async {
            await FormsService.saveForm(f['id'].toString(), {'is_published': f['is_published'] != true});
            _load();
          }),
          OfficeMenuItem("Make a copy", icon: Icons.copy_rounded, onTap: () => _duplicate(f)),
          const OfficeMenuItem.divider(),
          OfficeMenuItem("Delete", icon: Icons.delete_outline, color: Colors.red.shade700, onTap: () => _delete(f)),
        ] else
          OfficeMenuItem("Answer", icon: Icons.edit_note_rounded, onTap: () => _open(f, tab: 'fill')),
      ];

  Widget _card(Map<String, dynamic> f) {
    final color = _hexColor(f['theme_hex']?.toString(), _accent);
    final mine = f['mine'] == true;
    final closed = f['accepting'] == false || (DateTime.tryParse((f['closes_at'] ?? '').toString())?.isBefore(DateTime.now()) ?? false);
    final status = mine ? (f['is_published'] == true ? (closed ? 'Closed' : 'Published') : 'Draft') : (f['answered'] == true ? 'Answered' : (closed ? 'Closed' : 'Open'));
    final statusColor = switch (status) { 'Published' || 'Open' => Colors.green.shade700, 'Answered' => Colors.blue.shade700, 'Closed' => Colors.red.shade700, _ => Colors.grey.shade700 };
    return OfficeRightClick(
      longPress: true,
      onMenu: (p) => showOfficeMenu(context, p, _menu(f)),
      child: Material(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        shadowColor: Colors.black12,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(f, tab: mine ? 'edit' : 'fill'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(height: 8, decoration: BoxDecoration(color: AppPalette.bg(color), borderRadius: const BorderRadius.vertical(top: Radius.circular(16)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(backgroundColor: AppPalette.bg(color.withValues(alpha: 0.12)), child: Icon(mine ? Icons.description_outlined : Icons.assignment_outlined, color: AppPalette.fg(color))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((f['title'] ?? 'Untitled form').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 14.5)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (!mine && (f['owner_name'] ?? '').toString().isNotEmpty) "by ${f['owner_name']}",
                        "${f['questions'] ?? 0} question${f['questions'] == 1 ? '' : 's'}",
                        if (mine) "${f['responses'] ?? 0} response${f['responses'] == 1 ? '' : 's'}",
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppPalette.bg(statusColor.withValues(alpha: 0.1)), borderRadius: BorderRadius.circular(20)),
                      child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(statusColor))),
                    ),
                  ]),
                ),
                Builder(
                  builder: (bctx) => IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () {
                      final box = bctx.findRenderObject() as RenderBox?;
                      showOfficeMenu(bctx, box == null ? Offset.zero : box.localToGlobal(box.size.bottomLeft(Offset.zero)), _menu(f));
                    },
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _grid(List<Map<String, dynamic>> forms) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1100 ? 3 : c.maxWidth >= 680 ? 2 : 1;
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final f in forms) SizedBox(width: w, child: _card(f))]);
      });

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    bool match(Map f) => q.isEmpty || (f['title'] ?? '').toString().toLowerCase().contains(q);
    final toAnswer = _forms.where((f) => f['mine'] != true && match(f)).toList();
    final mine = _forms.where((f) => f['mine'] == true && match(f)).toList();
    final body = RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final maxW = c.maxWidth > 1200 ? 1200.0 : c.maxWidth;
        final pad = (c.maxWidth - maxW) / 2 + (c.maxWidth < 600 ? 14 : 24);
        return ListView(padding: EdgeInsets.fromLTRB(pad, 16, pad, 100), children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Surveys & forms", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 20, color: AppPalette.fg(_accent))),
                Text("Answer surveys from your church, or build your own like Google Forms.", style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.grey.shade700))),
              ]),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_accent), foregroundColor: Colors.white, shape: const StadiumBorder()),
              onPressed: _newForm,
              icon: const Icon(Icons.add_rounded),
              label: const Text("New form"),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: "Search forms",
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: AppPalette.bg(Colors.white),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.red.shade800))))
          else ...[
            Text("To answer", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 10),
            if (widget.legacyFeedback != null && q.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: AppPalette.bg(Colors.white),
                  borderRadius: BorderRadius.circular(16),
                  elevation: 1,
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: CircleAvatar(backgroundColor: AppPalette.bg(const Color(0xFF4A148C).withValues(alpha: 0.12)), child: Icon(Icons.feedback_outlined, color: AppPalette.fg(const Color(0xFF4A148C)))),
                    title: Text("Administrative feedback form", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text("Your insights help us improve the church management system."),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: widget.legacyFeedback!)),
                  ),
                ),
              ),
            if (toAnswer.isEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text("No open surveys right now.", style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))))
            else
              _grid(toAnswer),
            const SizedBox(height: 26),
            Text("My forms", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 10),
            if (mine.isEmpty)
              Text("You haven't made a form yet. Tap “New form” to start from a template.", style: TextStyle(color: AppPalette.fg(Colors.grey.shade600)))
            else
              _grid(mine),
          ],
        ]);
      }),
    );
    if (!widget.fullPage) return Container(color: AppPalette.bg(const Color(0xFFF3F0FA)), child: body);
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF3F0FA)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        title: Text("Forms", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(_accent))),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Builder
// ---------------------------------------------------------------------------
class FormBuilderScreen extends StatefulWidget {
  final String formId;
  final int initialTab;
  const FormBuilderScreen({super.key, required this.formId, this.initialTab = 0});
  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends State<FormBuilderScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  Map<String, dynamic> _form = {};
  List<FormQ> _qs = [];
  bool _loading = true;
  String _save = 'saved';
  Timer? _timer;
  int _selected = -1;
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _confirm = TextEditingController();
  int _responses = 0;

  Color get _color => _hexColor(_form['theme_hex']?.toString());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_save == 'unsaved') _flush();
    _tabs.dispose();
    _title.dispose();
    _desc.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final f = await FormsService.form(widget.formId);
      final q = await FormsService.questions(widget.formId);
      final s = await FormsService.submissions(widget.formId);
      if (!mounted) return;
      setState(() {
        _form = f;
        _qs = q;
        _responses = s.length;
        _title.text = (f['title'] ?? '').toString();
        _desc.text = (f['description'] ?? '').toString();
        _confirm.text = (f['confirmation'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _dirty() {
    setState(() => _save = 'unsaved');
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1400), _flush);
  }

  Future<void> _flush() async {
    _timer?.cancel();
    if (mounted) setState(() => _save = 'saving');
    try {
      await FormsService.saveForm(widget.formId, {
        'title': _title.text.trim().isEmpty ? 'Untitled form' : _title.text.trim(),
        'description': _desc.text.trim(),
        'confirmation': _confirm.text.trim(),
        'theme_hex': _form['theme_hex'],
        'accepting': _form['accepting'] != false,
        'closes_at': _form['closes_at'],
        'one_per_user': _form['one_per_user'] == true,
        'anonymous': _form['anonymous'] == true,
        'settings': _form['settings'] ?? {},
      });
      await FormsService.saveQuestions(widget.formId, _qs);
      if (mounted) setState(() => _save = 'saved');
    } catch (e) {
      debugPrint("Form save error: $e");
      if (mounted) setState(() => _save = 'error');
    }
  }

  Future<void> _togglePublish() async {
    if (_save != 'saved') await _flush();
    final v = _form['is_published'] != true;
    if (v && _qs.where((q) => _isInput(q.type)).isEmpty) {
      _snack("Add at least one question before publishing.");
      return;
    }
    await FormsService.saveForm(widget.formId, {'is_published': v});
    setState(() => _form['is_published'] = v);
    _snack(v ? "Published: everyone in the app can answer it under Surveys." : "Unpublished: it's a draft again.");
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _addQuestion([int? at]) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: MediaQuery.of(ctx).size.width < 520 ? 3 : 5,
            childAspectRatio: 1.25,
            children: [
              for (final e in kQuestionTypes.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, e.key),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    CircleAvatar(backgroundColor: AppPalette.bg(_color.withValues(alpha: 0.1)), child: Icon(e.value.$2, color: AppPalette.fg(_color))),
                    const SizedBox(height: 6),
                    Text(e.value.$1, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11.5)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
    if (type == null) return;
    final q = FormQ(
      key: _newKey(),
      type: type,
      label: type == 'section' ? 'New page' : (type == 'statement' ? 'Text' : 'Untitled question'),
      options: _isChoice(type) ? ['Option 1'] : [],
      settings: type == 'linear_scale' ? {'min': 1, 'max': 5} : (type == 'rating' ? {'max': 5} : {}),
    );
    setState(() {
      final i = (at ?? (_selected >= 0 ? _selected + 1 : _qs.length)).clamp(0, _qs.length);
      _qs.insert(i, q);
      _selected = i;
    });
    _dirty();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final status = officeStatus(_save);
    final published = _form['is_published'] == true;
    final wide = MediaQuery.of(context).size.width >= 760;
    return CallbackShortcuts(
      bindings: officeKeys({LogicalKeyboardKey.keyS: _flush, LogicalKeyboardKey.enter: () => _addQuestion()}),
      child: Scaffold(
        backgroundColor: AppPalette.bg(Color.lerp(_color, Colors.white, 0.9)!),
        appBar: AppBar(
          backgroundColor: AppPalette.bg(Colors.white),
          elevation: 0.5,
          titleSpacing: 0,
          title: Text(_title.text.isEmpty ? 'Untitled form' : _title.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
          actions: [
            Tooltip(message: status.$1, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(status.$2, color: AppPalette.fg(status.$3), size: 20))),
            IconButton(
              tooltip: "Preview",
              icon: const Icon(Icons.visibility_outlined),
              onPressed: () async {
                await _flush();
                if (!context.mounted) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => FormFillScreen(formId: widget.formId, preview: true)));
              },
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: wide
                  ? ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(published ? Colors.green.shade700 : _color), foregroundColor: Colors.white),
                      onPressed: _togglePublish,
                      icon: Icon(published ? Icons.check_circle_rounded : Icons.public_rounded, size: 18),
                      label: Text(published ? "Published" : "Publish"),
                    )
                  : IconButton(tooltip: published ? "Unpublish" : "Publish", onPressed: _togglePublish, icon: Icon(Icons.public_rounded, color: AppPalette.fg(published ? Colors.green.shade700 : _color))),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            labelColor: _color,
            indicatorColor: _color,
            tabs: [const Tab(text: "Questions"), Tab(text: "Responses ($_responses)"), const Tab(text: "Settings")],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
                backgroundColor: AppPalette.bg(_color),
                foregroundColor: Colors.white,
                onPressed: () {
                  _tabs.animateTo(0);
                  _addQuestion();
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text("Add question"),
              ),
        body: TabBarView(controller: _tabs, children: [
          _questionsTab(),
          FormResponsesView(formId: widget.formId, questions: _qs, title: _title.text, color: _color, onCount: (n) {
            if (n != _responses && mounted) setState(() => _responses = n);
          }),
          _settingsTab(),
        ]),
      ),
    );
  }

  (String, IconData, Color) officeStatus(String s) => switch (s) {
        'saving' => ('Saving…', Icons.cloud_sync_outlined, Colors.blueGrey),
        'unsaved' => ('Unsaved changes', Icons.edit_note_rounded, Colors.orange.shade800),
        'error' => ('Not saved — check your connection', Icons.cloud_off_rounded, Colors.red.shade700),
        _ => ('All changes saved', Icons.cloud_done_outlined, Colors.green.shade700),
      };

  Widget _centered(Widget child) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: child));

  Widget _questionsTab() {
    return ListView(padding: const EdgeInsets.fromLTRB(12, 16, 12, 120), children: [
      _centered(Container(
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border(top: BorderSide(color: AppPalette.line(_color), width: 10)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _title,
            onChanged: (_) => _dirty(),
            style: GoogleFonts.merriweather(fontSize: 24, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(hintText: "Form title", border: InputBorder.none),
          ),
          TextField(
            controller: _desc,
            onChanged: (_) => _dirty(),
            maxLines: null,
            decoration: const InputDecoration(hintText: "Description (optional)", border: InputBorder.none),
          ),
        ]),
      )),
      const SizedBox(height: 6),
      _centered(ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: _qs.length,
        onReorder: (oldIdx, newIdx) {
          if (newIdx > oldIdx) newIdx -= 1;
          setState(() {
            final item = _qs.removeAt(oldIdx);
            _qs.insert(newIdx, item);
            _selected = newIdx;
          });
          _dirty();
        },
        itemBuilder: (context, i) => KeyedSubtree(key: ValueKey(_qs[i].key), child: _questionCard(i)),
      )),
      if (_qs.isEmpty)
        _centered(Padding(
          padding: const EdgeInsets.all(30),
          child: Text("No questions yet. Tap “Add question”.", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))),
        )),
    ]);
  }

  Widget _questionCard(int i) {
    final q = _qs[i];
    final sel = i == _selected;
    final t = kQuestionTypes[q.type] ?? kQuestionTypes['short_text']!;
    final isSection = q.type == 'section';
    return OfficeRightClick(
      onMenu: (p) => showOfficeMenu(context, p, [
        OfficeMenuItem("Duplicate", icon: Icons.copy_rounded, shortcut: "Ctrl+D", onTap: () => _duplicateQ(i)),
        OfficeMenuItem("Add question below", icon: Icons.add_rounded, onTap: () => _addQuestion(i + 1)),
        OfficeMenuItem("Move up", icon: Icons.arrow_upward_rounded, onTap: i > 0 ? () => _moveQ(i, -1) : null),
        OfficeMenuItem("Move down", icon: Icons.arrow_downward_rounded, onTap: i < _qs.length - 1 ? () => _moveQ(i, 1) : null),
        if (_isInput(q.type)) OfficeMenuItem(q.required ? "Make optional" : "Make required", icon: Icons.emergency_outlined, onTap: () {
          setState(() => q.required = !q.required);
          _dirty();
        }),
        const OfficeMenuItem.divider(),
        OfficeMenuItem("Delete", icon: Icons.delete_outline, color: Colors.red.shade700, onTap: () => _deleteQ(i)),
      ]),
      child: GestureDetector(
        onTap: () => setState(() => _selected = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: EdgeInsets.only(top: isSection ? 22 : 10),
          decoration: BoxDecoration(
            color: AppPalette.bg(Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: AppPalette.line(sel ? _color : Colors.transparent), width: 5)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: sel ? 0.10 : 0.04), blurRadius: sel ? 10 : 4)],
          ),
          padding: const EdgeInsets.fromLTRB(14, 6, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ReorderableDragStartListener(index: i, child: MouseRegion(cursor: SystemMouseCursors.grab, child: Icon(Icons.drag_indicator, color: AppPalette.fg(Colors.grey), size: 20))),
              const SizedBox(width: 6),
              Icon(t.$2, size: 18, color: AppPalette.fg(_color)),
              const SizedBox(width: 6),
              Expanded(child: Text(isSection ? "Page break — new section" : t.$1, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700), fontWeight: FontWeight.w600))),
              if (q.settings['show_if'] is Map && ((q.settings['show_if'] as Map)['key'] ?? '').toString().isNotEmpty)
                Tooltip(message: "Shown only when a condition is met", child: Icon(Icons.call_split_rounded, size: 18, color: AppPalette.fg(Colors.orange.shade800))),
              if (q.required) Padding(padding: const EdgeInsets.only(left: 4), child: Text("Required", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.red.shade600)))),
            ]),
            if (!sel)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(q.label.isEmpty ? 'Untitled' : q.label, style: GoogleFonts.merriweather(fontSize: isSection ? 17 : 15, fontWeight: FontWeight.w600)),
                  if (q.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(q.description, style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.grey.shade700)))),
                  const SizedBox(height: 8),
                  IgnorePointer(child: FormQuestionInput(q: q, value: null, onChanged: (_) {}, color: _color, preview: true)),
                ]),
              )
            else
              _editor(i),
          ]),
        ),
      ),
    );
  }

  void _duplicateQ(int i) {
    setState(() {
      _qs.insert(i + 1, _qs[i].copy());
      _selected = i + 1;
    });
    _dirty();
  }

  void _moveQ(int i, int d) {
    final to = i + d;
    if (to < 0 || to >= _qs.length) return;
    setState(() {
      final q = _qs.removeAt(i);
      _qs.insert(to, q);
      _selected = to;
    });
    _dirty();
  }

  void _deleteQ(int i) {
    final removed = _qs[i];
    setState(() {
      _qs.removeAt(i);
      for (final q in _qs) {
        final si = q.settings['show_if'];
        if (si is Map && si['key'] == removed.key) q.settings.remove('show_if');
      }
      _selected = -1;
    });
    _dirty();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Question deleted"),
      action: SnackBarAction(label: "Undo", onPressed: () {
        setState(() => _qs.insert(i.clamp(0, _qs.length), removed));
        _dirty();
      }),
    ));
  }

  Widget _editor(int i) {
    final q = _qs[i];
    final isSection = q.type == 'section';
    InputDecoration deco(String hint) => InputDecoration(hintText: hint, isDense: true, filled: true, fillColor: AppPalette.bg(const Color(0xFFF8FAFC)), border: const UnderlineInputBorder());
    final earlier = [for (int j = 0; j < i; j++) if (_qs[j].type == 'yes_no' || _isChoice(_qs[j].type)) _qs[j]];
    final cond = q.settings['show_if'] is Map ? Map<String, dynamic>.from(q.settings['show_if'] as Map) : null;
    final condQ = cond == null ? null : earlier.where((x) => x.key == cond['key']).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 6),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextFormField(
            key: ValueKey('label-${q.key}'),
            initialValue: q.label,
            autofocus: q.label.startsWith('Untitled'),
            maxLines: null,
            style: GoogleFonts.merriweather(fontSize: isSection ? 17 : 15, fontWeight: FontWeight.w600),
            decoration: deco(isSection ? "Page title" : "Question"),
            onChanged: (v) {
              q.label = v;
              _dirty();
            },
          ),
        ),
        const SizedBox(width: 10),
        if (!isSection)
          DropdownButton<String>(
            value: q.type,
            underline: const SizedBox.shrink(),
            items: [
              for (final e in kQuestionTypes.entries)
                if (e.key != 'section') DropdownMenuItem(value: e.key, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(e.value.$2, size: 16), const SizedBox(width: 6), Text(e.value.$1, style: const TextStyle(fontSize: 13))])),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                q.type = v;
                if (_isChoice(v) && q.options.isEmpty) q.options = ['Option 1'];
                if (v == 'linear_scale') q.settings.addAll({'min': q.settings['min'] ?? 1, 'max': q.settings['max'] ?? 5});
                if (v == 'rating') q.settings['max'] = (q.settings['max'] as num?)?.clamp(3, 10) ?? 5;
              });
              _dirty();
            },
          ),
      ]),
      const SizedBox(height: 6),
      TextFormField(
        key: ValueKey('desc-${q.key}'),
        initialValue: q.description,
        maxLines: null,
        style: const TextStyle(fontSize: 13),
        decoration: deco(isSection ? "Description of this page (optional)" : "Description or help text (optional)"),
        onChanged: (v) {
          q.description = v;
          _dirty();
        },
      ),
      const SizedBox(height: 10),
      if (_isChoice(q.type)) ...[
        for (int k = 0; k < q.options.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(q.type == 'checkboxes' ? Icons.check_box_outline_blank_rounded : (q.type == 'dropdown' ? Icons.arrow_right_rounded : Icons.radio_button_unchecked), size: 18, color: AppPalette.fg(Colors.grey)),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('opt-${q.key}-$k-${q.options.length}'),
                  initialValue: q.options[k],
                  decoration: const InputDecoration(isDense: true, border: UnderlineInputBorder()),
                  onChanged: (v) {
                    q.options[k] = v;
                    _dirty();
                  },
                  onFieldSubmitted: (_) {
                    setState(() => q.options.add('Option ${q.options.length + 1}'));
                    _dirty();
                  },
                ),
              ),
              IconButton(
                tooltip: "Remove",
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: q.options.length <= 1
                    ? null
                    : () {
                        setState(() => q.options.removeAt(k));
                        _dirty();
                      },
              ),
            ]),
          ),
        Wrap(spacing: 4, children: [
          TextButton.icon(
            onPressed: () {
              setState(() => q.options.add('Option ${q.options.length + 1}'));
              _dirty();
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text("Add option"),
          ),
          if (q.type != 'dropdown')
            TextButton(
              onPressed: () {
                setState(() => q.settings['other'] = !(q.settings['other'] == true));
                _dirty();
              },
              child: Text(q.settings['other'] == true ? "Remove “Other”" : "Add “Other”"),
            ),
          TextButton(
            onPressed: () async {
              final c = TextEditingController(text: q.options.join('\n'));
              final r = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Paste options"),
                  content: SizedBox(width: 380, child: TextField(controller: c, maxLines: 10, decoration: const InputDecoration(hintText: "One option per line", border: OutlineInputBorder()))),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text("Use"))],
                ),
              );
              if (r == null) return;
              final list = r.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              if (list.isEmpty) return;
              setState(() => q.options = list);
              _dirty();
            },
            child: const Text("Paste a list"),
          ),
        ]),
      ],
      if (q.type == 'linear_scale') ...[
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownButton<int>(
            value: q.scaleMin.clamp(0, 1),
            items: const [DropdownMenuItem(value: 0, child: Text("0")), DropdownMenuItem(value: 1, child: Text("1"))],
            onChanged: (v) {
              setState(() => q.settings['min'] = v);
              _dirty();
            },
          ),
          const Text("to"),
          DropdownButton<int>(
            value: q.scaleMax.clamp(2, 10),
            items: [for (int k = 2; k <= 10; k++) DropdownMenuItem(value: k, child: Text("$k"))],
            onChanged: (v) {
              setState(() => q.settings['max'] = v);
              _dirty();
            },
          ),
        ]),
        Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('minl-${q.key}'),
              initialValue: (q.settings['min_label'] ?? '').toString(),
              decoration: const InputDecoration(labelText: "Label for the lowest (optional)", isDense: true),
              onChanged: (v) {
                q.settings['min_label'] = v;
                _dirty();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: ValueKey('maxl-${q.key}'),
              initialValue: (q.settings['max_label'] ?? '').toString(),
              decoration: const InputDecoration(labelText: "Label for the highest (optional)", isDense: true),
              onChanged: (v) {
                q.settings['max_label'] = v;
                _dirty();
              },
            ),
          ),
        ]),
      ],
      if (q.type == 'rating')
        Row(children: [
          const Text("Stars: "),
          DropdownButton<int>(
            value: q.scaleMax.clamp(3, 10),
            items: [for (int k = 3; k <= 10; k++) DropdownMenuItem(value: k, child: Text("$k"))],
            onChanged: (v) {
              setState(() => q.settings['max'] = v);
              _dirty();
            },
          ),
        ]),
      if (q.type == 'number')
        Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('nmin-${q.key}'),
              initialValue: q.settings['min']?.toString() ?? '',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Smallest allowed", isDense: true),
              onChanged: (v) {
                final n = num.tryParse(v);
                if (n == null) {
                  q.settings.remove('min');
                } else {
                  q.settings['min'] = n;
                }
                _dirty();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: ValueKey('nmax-${q.key}'),
              initialValue: q.settings['max']?.toString() ?? '',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Largest allowed", isDense: true),
              onChanged: (v) {
                final n = num.tryParse(v);
                if (n == null) {
                  q.settings.remove('max');
                } else {
                  q.settings['max'] = n;
                }
                _dirty();
              },
            ),
          ),
        ]),
      if (q.type == 'short_text' || q.type == 'long_text')
        TextFormField(
          key: ValueKey('ph-${q.key}'),
          initialValue: (q.settings['placeholder'] ?? '').toString(),
          decoration: const InputDecoration(labelText: "Placeholder (optional)", isDense: true),
          onChanged: (v) {
            q.settings['placeholder'] = v;
            _dirty();
          },
        ),
      // "Show only if" (conditional logic, like Tally)
      if (earlier.isNotEmpty && !isSection) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
          decoration: BoxDecoration(color: AppPalette.bg(Colors.orange.withValues(alpha: 0.06)), borderRadius: BorderRadius.circular(8)),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
            Icon(Icons.call_split_rounded, size: 18, color: AppPalette.fg(Colors.orange.shade800)),
            const Text("Show only if", style: TextStyle(fontSize: 12.5)),
            DropdownButton<String>(
              value: condQ?.key ?? '',
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(value: '', child: Text("— always show —", style: TextStyle(fontSize: 12.5))),
                for (final e in earlier)
                  DropdownMenuItem(value: e.key, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text(e.label.isEmpty ? 'Untitled' : e.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)))),
              ],
              onChanged: (v) {
                setState(() {
                  if (v == null || v.isEmpty) {
                    q.settings.remove('show_if');
                  } else {
                    final src = earlier.firstWhere((x) => x.key == v);
                    q.settings['show_if'] = {'key': v, 'equals': src.type == 'yes_no' ? 'yes' : (src.options.isNotEmpty ? src.options.first : '')};
                  }
                });
                _dirty();
              },
            ),
            if (condQ != null) ...[
              const Text("is", style: TextStyle(fontSize: 12.5)),
              DropdownButton<String>(
                value: (condQ.type == 'yes_no' ? ['yes', 'no'] : condQ.options).contains(cond!['equals']) ? cond['equals'].toString() : null,
                underline: const SizedBox.shrink(),
                items: [
                  for (final o in (condQ.type == 'yes_no' ? ['yes', 'no'] : condQ.options))
                    DropdownMenuItem(value: o, child: Text(o == 'yes' && condQ.type == 'yes_no' ? 'Yes' : (o == 'no' && condQ.type == 'yes_no' ? 'No' : o), style: const TextStyle(fontSize: 12.5))),
                ],
                onChanged: (v) {
                  setState(() => q.settings['show_if'] = {'key': condQ.key, 'equals': v});
                  _dirty();
                },
              ),
            ],
          ]),
        ),
      ],
      const Divider(height: 22),
      Row(children: [
        IconButton(tooltip: "Duplicate", icon: const Icon(Icons.copy_rounded, size: 20), onPressed: () => _duplicateQ(i)),
        IconButton(tooltip: "Delete", icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _deleteQ(i)),
        IconButton(tooltip: "Move up", icon: const Icon(Icons.arrow_upward_rounded, size: 20), onPressed: i > 0 ? () => _moveQ(i, -1) : null),
        IconButton(tooltip: "Move down", icon: const Icon(Icons.arrow_downward_rounded, size: 20), onPressed: i < _qs.length - 1 ? () => _moveQ(i, 1) : null),
        const Spacer(),
        if (_isInput(q.type)) ...[
          const Text("Required", style: TextStyle(fontSize: 12.5)),
          Switch(
            value: q.required,
            activeThumbColor: _color,
            onChanged: (v) {
              setState(() => q.required = v);
              _dirty();
            },
          ),
        ],
      ]),
    ]);
  }

  Widget _settingsTab() {
    final closes = DateTime.tryParse((_form['closes_at'] ?? '').toString())?.toLocal();
    final settings = _form['settings'] is Map ? Map<String, dynamic>.from(_form['settings'] as Map) : <String, dynamic>{};
    const swatches = ['FF673AB7', 'FF4A148C', 'FF1E88E5', 'FF00897B', 'FF43A047', 'FFF4511E', 'FFE91E63', 'FF546E7A', 'FFFFB300'];
    return ListView(padding: const EdgeInsets.fromLTRB(12, 16, 12, 120), children: [
      _centered(Card(
        child: Column(children: [
          SwitchListTile(
            secondary: const Icon(Icons.inbox_outlined),
            title: const Text("Accepting responses"),
            subtitle: Text(_form['is_published'] == true ? "Published" : "Draft — publish it to collect answers"),
            value: _form['accepting'] != false,
            onChanged: (v) {
              setState(() => _form['accepting'] = v);
              _dirty();
            },
          ),
          ListTile(
            leading: const Icon(Icons.event_busy_outlined),
            title: const Text("Close automatically on"),
            subtitle: Text(closes == null ? "Never" : DateFormat('d MMM yyyy, HH:mm').format(closes)),
            trailing: closes == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() => _form['closes_at'] = null);
                      _dirty();
                    },
                  ),
            onTap: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)), initialDate: closes ?? DateTime.now().add(const Duration(days: 7)));
              if (d == null || !mounted) return;
              final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 23, minute: 59));
              final dt = DateTime(d.year, d.month, d.day, t?.hour ?? 23, t?.minute ?? 59);
              setState(() => _form['closes_at'] = dt.toUtc().toIso8601String());
              _dirty();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.looks_one_outlined),
            title: const Text("One response per person"),
            subtitle: const Text("Not available for anonymous forms"),
            value: _form['one_per_user'] == true && _form['anonymous'] != true,
            onChanged: _form['anonymous'] == true
                ? null
                : (v) {
                    setState(() => _form['one_per_user'] = v);
                    _dirty();
                  },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.person_off_outlined),
            title: const Text("Anonymous responses"),
            subtitle: const Text("Names are not recorded, even for you"),
            value: _form['anonymous'] == true,
            onChanged: (v) {
              setState(() {
                _form['anonymous'] = v;
                if (v) _form['one_per_user'] = false;
              });
              _dirty();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.linear_scale_rounded),
            title: const Text("Show a progress bar"),
            value: settings['progress'] != false,
            onChanged: (v) {
              settings['progress'] = v;
              setState(() => _form['settings'] = settings);
              _dirty();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.shuffle_rounded),
            title: const Text("Shuffle the order of choices"),
            value: settings['shuffle'] == true,
            onChanged: (v) {
              settings['shuffle'] = v;
              setState(() => _form['settings'] = settings);
              _dirty();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.replay_rounded),
            title: const Text("Allow “Submit another response”"),
            value: settings['allow_again'] != false,
            onChanged: (v) {
              settings['allow_again'] = v;
              setState(() => _form['settings'] = settings);
              _dirty();
            },
          ),
          ListTile(
            leading: const Icon(Icons.celebration_outlined),
            title: TextField(
              controller: _confirm,
              onChanged: (_) => _dirty(),
              maxLines: 2,
              decoration: const InputDecoration(labelText: "Message after submitting", hintText: "Thank you! Your answers were sent."),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text("Theme colour"),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final h in swatches)
                  InkWell(
                    onTap: () {
                      setState(() => _form['theme_hex'] = h);
                      _dirty();
                    },
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: _hexColor(h),
                      child: (_form['theme_hex'] ?? '').toString().toUpperCase() == h ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      )),
    ]);
  }
}

// ---------------------------------------------------------------------------
// One question, as the person answering sees it (also used in the builder preview)
// ---------------------------------------------------------------------------
class FormQuestionInput extends StatefulWidget {
  final FormQ q;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final Color color;
  final bool preview;
  final bool shuffle;
  const FormQuestionInput({super.key, required this.q, required this.value, required this.onChanged, required this.color, this.preview = false, this.shuffle = false});
  @override
  State<FormQuestionInput> createState() => _FormQuestionInputState();
}

class _FormQuestionInputState extends State<FormQuestionInput> {
  late final List<String> _order = () {
    final o = List.of(widget.q.options);
    if (widget.shuffle) o.shuffle();
    return o;
  }();
  final _otherC = TextEditingController();

  @override
  void dispose() {
    _otherC.dispose();
    super.dispose();
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: AppPalette.bg(const Color(0xFFF8FAFC)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(Colors.grey.shade300))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppPalette.line(widget.color), width: 1.6)),
      );

  @override
  Widget build(BuildContext context) {
    final q = widget.q;
    final v = widget.value;
    final opts = widget.preview ? q.options : _order;
    final hasOther = q.settings['other'] == true;
    switch (q.type) {
      case 'statement':
      case 'section':
        return const SizedBox.shrink();
      case 'long_text':
        return TextFormField(initialValue: v?.toString(), minLines: 3, maxLines: 8, decoration: _deco((q.settings['placeholder'] ?? 'Your answer').toString()), onChanged: widget.onChanged);
      case 'number':
        return TextFormField(
          initialValue: v?.toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: _deco("Number"),
          onChanged: (s) => widget.onChanged(s.trim().isEmpty ? null : (num.tryParse(s.trim()) ?? s.trim())),
        );
      case 'email':
        return TextFormField(initialValue: v?.toString(), keyboardType: TextInputType.emailAddress, decoration: _deco("name@example.com"), onChanged: widget.onChanged);
      case 'phone':
        return TextFormField(initialValue: v?.toString(), keyboardType: TextInputType.phone, decoration: _deco("+256 7XX XXX XXX"), onChanged: widget.onChanged);
      case 'date':
      case 'time':
        final isDate = q.type == 'date';
        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
          icon: Icon(isDate ? Icons.calendar_today_outlined : Icons.schedule_outlined, size: 18, color: AppPalette.fg(widget.color)),
          label: Text((v ?? '').toString().isEmpty ? (isDate ? "Choose a date" : "Choose a time") : v.toString()),
          onPressed: widget.preview
              ? null
              : () async {
                  if (isDate) {
                    final d = await showDatePicker(context: context, firstDate: DateTime(1920), lastDate: DateTime(2100), initialDate: DateTime.tryParse((v ?? '').toString()) ?? DateTime.now());
                    if (d != null) widget.onChanged(DateFormat('yyyy-MM-dd').format(d));
                  } else {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (t != null) widget.onChanged('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                  }
                },
        );
      case 'yes_no':
        return Wrap(spacing: 10, children: [
          for (final (k, l, i) in [('yes', 'Yes', Icons.thumb_up_alt_outlined), ('no', 'No', Icons.thumb_down_alt_outlined)])
            ChoiceChip(
              avatar: Icon(i, size: 16, color: AppPalette.fg(v == k ? Colors.white : widget.color)),
              label: Text(l, style: TextStyle(color: AppPalette.fg(v == k ? Colors.white : Colors.black87))),
              selected: v == k,
              showCheckmark: false,
              selectedColor: AppPalette.bg(widget.color),
              onSelected: (_) => widget.onChanged(v == k ? null : k),
            ),
        ]);
      case 'multiple_choice':
        final otherSel = hasOther && v != null && !opts.contains(v);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final o in opts)
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: widget.color,
              value: o,
              groupValue: otherSel ? null : v?.toString(),
              title: Text(o),
              onChanged: (x) => widget.onChanged(x),
            ),
          if (hasOther)
            Row(children: [
              Radio<String>(value: '__other', groupValue: otherSel ? '__other' : null, activeColor: widget.color, onChanged: (_) => widget.onChanged(_otherC.text.isEmpty ? 'Other' : _otherC.text)),
              const Text("Other: "),
              Expanded(child: TextField(controller: _otherC, decoration: const InputDecoration(isDense: true), onChanged: (s) => widget.onChanged(s.isEmpty ? 'Other' : s))),
            ]),
        ]);
      case 'checkboxes':
        final list = v is List ? v.map((e) => e.toString()).toList() : <String>[];
        final other = list.where((e) => !opts.contains(e)).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final o in opts)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: widget.color,
              value: list.contains(o),
              title: Text(o),
              onChanged: (c) {
                final n = List.of(list);
                c == true ? n.add(o) : n.remove(o);
                widget.onChanged(n.isEmpty ? null : n);
              },
            ),
          if (hasOther)
            Row(children: [
              Checkbox(
                value: other.isNotEmpty,
                activeColor: widget.color,
                onChanged: (c) {
                  final n = list.where((e) => opts.contains(e)).toList();
                  if (c == true) n.add(_otherC.text.isEmpty ? 'Other' : _otherC.text);
                  widget.onChanged(n.isEmpty ? null : n);
                },
              ),
              const Text("Other: "),
              Expanded(
                child: TextField(
                  controller: _otherC,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (s) {
                    final n = list.where((e) => opts.contains(e)).toList()..add(s.isEmpty ? 'Other' : s);
                    widget.onChanged(n);
                  },
                ),
              ),
            ]),
        ]);
      case 'dropdown':
        return DropdownButtonFormField<String>(
          initialValue: opts.contains(v) ? v.toString() : null,
          isExpanded: true,
          decoration: _deco("Choose"),
          items: [for (final o in opts) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
          onChanged: widget.preview ? null : widget.onChanged,
        );
      case 'linear_scale':
        final lo = q.scaleMin, hi = q.scaleMax;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (int k = lo; k <= hi; k++)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => widget.onChanged(v == k ? null : k),
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: AppPalette.bg(v == k ? widget.color : widget.color.withValues(alpha: 0.08)),
                  child: Text("$k", style: TextStyle(color: AppPalette.fg(v == k ? Colors.white : Colors.black87), fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
          if ((q.settings['min_label'] ?? '').toString().isNotEmpty || (q.settings['max_label'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(child: Text((q.settings['min_label'] ?? '').toString(), style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700)))),
                Expanded(child: Text((q.settings['max_label'] ?? '').toString(), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700)))),
              ]),
            ),
        ]);
      case 'rating':
        final max = q.scaleMax.clamp(3, 10);
        final cur = (v as num?)?.toInt() ?? 0;
        return Wrap(children: [
          for (int k = 1; k <= max; k++)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => widget.onChanged(cur == k ? null : k),
              icon: Icon(k <= cur ? Icons.star_rounded : Icons.star_outline_rounded, size: 32, color: k <= cur ? const Color(0xFFF59E0B) : Colors.grey),
            ),
        ]);
      default:
        return TextFormField(initialValue: v?.toString(), decoration: _deco((q.settings['placeholder'] ?? 'Your answer').toString()), onChanged: widget.onChanged);
    }
  }
}

// ---------------------------------------------------------------------------
// Answering a form
// ---------------------------------------------------------------------------
class FormFillScreen extends StatefulWidget {
  final String formId;
  final bool preview;
  const FormFillScreen({super.key, required this.formId, this.preview = false});
  @override
  State<FormFillScreen> createState() => _FormFillScreenState();
}

class _FormFillScreenState extends State<FormFillScreen> {
  Map<String, dynamic> _form = {};
  List<FormQ> _qs = [];
  final Map<String, dynamic> _answers = {};
  bool _loading = true;
  bool _sending = false;
  bool _done = false;
  int _page = 0;
  final Set<String> _errors = {};
  final _scroll = ScrollController();

  Color get _color => _hexColor(_form['theme_hex']?.toString());
  Map<String, dynamic> get _settings => _form['settings'] is Map ? Map<String, dynamic>.from(_form['settings'] as Map) : const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final f = await FormsService.form(widget.formId);
      final q = await FormsService.questions(widget.formId);
      if (mounted) {
        setState(() {
          _form = f;
          _qs = q;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pages are split at "New page" questions.
  List<List<FormQ>> get _pages {
    final pages = <List<FormQ>>[[]];
    for (final q in _qs) {
      if (q.type == 'section' && pages.last.isNotEmpty) pages.add([]);
      pages.last.add(q);
    }
    return pages.where((p) => p.isNotEmpty).toList();
  }

  bool _visible(FormQ q) {
    final si = q.settings['show_if'];
    if (si is! Map || (si['key'] ?? '').toString().isEmpty) return true;
    final a = _answers[si['key']];
    final want = si['equals']?.toString();
    if (a is List) return a.map((e) => e.toString()).contains(want);
    return a?.toString() == want;
  }

  String? _problem(FormQ q) {
    if (!_isInput(q.type) || !_visible(q)) return null;
    final v = _answers[q.key];
    final empty = v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);
    if (empty) return q.required ? "This question is required" : null;
    if (q.type == 'email' && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.toString().trim())) return "Enter a valid email";
    if (q.type == 'number') {
      if (v is! num) return "Enter a number";
      final min = q.settings['min'] as num?, max = q.settings['max'] as num?;
      if (min != null && v < min) return "Must be at least $min";
      if (max != null && v > max) return "Must be at most $max";
    }
    if (q.type == 'phone' && v.toString().replaceAll(RegExp(r'[^0-9]'), '').length < 7) return "Enter a valid phone number";
    return null;
  }

  bool _checkPage(List<FormQ> page) {
    _errors.clear();
    for (final q in page) {
      if (_problem(q) != null) _errors.add(q.key);
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _submit() async {
    final pages = _pages;
    if (!_checkPage(pages[_page])) return;
    if (widget.preview) {
      setState(() => _done = true);
      return;
    }
    setState(() => _sending = true);
    try {
      // keep only visible answers, labelled by question key
      final data = <String, dynamic>{
        for (final q in _qs)
          if (_isInput(q.type) && _visible(q) && _answers[q.key] != null) q.key: _answers[q.key],
      };
      await FormsService.submit(widget.formId, data);
      setState(() => _done = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is PostgrestException ? e.message : "Couldn't send your answers. Check your connection.")));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pages = _pages;
    final closed = !widget.preview &&
        (_form['is_published'] != true || _form['accepting'] == false || (DateTime.tryParse((_form['closes_at'] ?? '').toString())?.isBefore(DateTime.now()) ?? false));
    final bg = Color.lerp(_color, Colors.white, 0.9)!;
    Widget card(Widget child, {bool top = false}) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          decoration: BoxDecoration(
            color: AppPalette.bg(Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: top ? Border(top: BorderSide(color: AppPalette.line(_color), width: 10)) : null,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
          ),
          child: child,
        );
    final header = card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text((_form['title'] ?? 'Form').toString(), style: GoogleFonts.merriweather(fontSize: 24, fontWeight: FontWeight.w800)),
        if ((_form['description'] ?? '').toString().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_form['description'].toString(), style: TextStyle(color: AppPalette.fg(Colors.grey.shade800), height: 1.4))),
        const SizedBox(height: 8),
        Text(
          [
            if (_form['anonymous'] == true) "Anonymous — your name is not recorded" else "Your name is recorded with your answers",
            if (_qs.any((q) => q.required)) "* required",
          ].join(' · '),
          style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade600)),
        ),
      ]),
      top: true,
    );
    Widget content;
    if (_done) {
      content = card(Column(children: [
        Icon(Icons.check_circle_rounded, color: AppPalette.fg(_color), size: 56),
        const SizedBox(height: 10),
        Text(widget.preview ? "This is how the end looks (preview — nothing was sent)." : ((_form['confirmation'] ?? '').toString().isEmpty ? "Thank you! Your answers were sent." : _form['confirmation'].toString()),
            textAlign: TextAlign.center, style: GoogleFonts.merriweather(fontSize: 16)),
        const SizedBox(height: 14),
        Wrap(spacing: 10, alignment: WrapAlignment.center, children: [
          if (_settings['allow_again'] != false && _form['one_per_user'] != true)
            OutlinedButton(
              onPressed: () => setState(() {
                _answers.clear();
                _page = 0;
                _done = false;
              }),
              child: const Text("Submit another response"),
            ),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_color), foregroundColor: Colors.white), onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ]),
      ]));
    } else if (closed) {
      content = card(Column(children: [
        Icon(Icons.lock_clock_outlined, size: 48, color: AppPalette.fg(Colors.grey)),
        const SizedBox(height: 8),
        const Text("This form is no longer accepting responses.", textAlign: TextAlign.center),
      ]));
    } else if (pages.isEmpty) {
      content = card(const Text("This form has no questions yet."));
    } else {
      final page = pages[_page.clamp(0, pages.length - 1)];
      final visibleQs = page.where(_visible).toList();
      content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final q in visibleQs)
          if (q.type == 'section')
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.label, style: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w800, color: AppPalette.fg(_color))),
              if (q.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(q.description)),
            ]))
          else if (q.type == 'statement')
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.label, style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.w700)),
              if (q.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(q.description, style: const TextStyle(height: 1.4))),
            ]))
          else
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              decoration: BoxDecoration(
                color: AppPalette.bg(Colors.white),
                borderRadius: BorderRadius.circular(14),
                border: _errors.contains(q.key) ? Border.all(color: AppPalette.line(Colors.red.shade400), width: 1.5) : null,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: q.label, style: GoogleFonts.merriweather(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (q.required) TextSpan(text: " *", style: TextStyle(color: AppPalette.fg(Colors.red.shade600))),
                ])),
                if (q.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(q.description, style: TextStyle(fontSize: 12.5, color: AppPalette.fg(Colors.grey.shade700)))),
                const SizedBox(height: 10),
                FormQuestionInput(
                  key: ValueKey('in-${q.key}'),
                  q: q,
                  value: _answers[q.key],
                  color: _color,
                  shuffle: _settings['shuffle'] == true,
                  onChanged: (v) => setState(() {
                    if (v == null) {
                      _answers.remove(q.key);
                    } else {
                      _answers[q.key] = v;
                    }
                    if (_errors.contains(q.key) && _problem(q) == null) _errors.remove(q.key);
                  }),
                ),
                if (_errors.contains(q.key))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Icon(Icons.error_outline, size: 16, color: AppPalette.fg(Colors.red.shade600)),
                      const SizedBox(width: 4),
                      Flexible(child: Text(_problem(q) ?? '', style: TextStyle(color: AppPalette.fg(Colors.red.shade600), fontSize: 12))),
                    ]),
                  ),
              ]),
            ),
        Row(children: [
          if (_page > 0)
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _page--);
                _scroll.jumpTo(0);
              },
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text("Back"),
            ),
          const Spacer(),
          if (_page < pages.length - 1)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_color), foregroundColor: Colors.white),
              onPressed: () {
                if (!_checkPage(page)) return;
                setState(() => _page++);
                _scroll.jumpTo(0);
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text("Next"),
            )
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_color), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
              onPressed: _sending ? null : _submit,
              icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
              label: Text(widget.preview ? "Submit (preview)" : "Submit"),
            ),
        ]),
      ]);
    }
    return Scaffold(
      backgroundColor: AppPalette.bg(bg),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        title: Text(widget.preview ? "Preview" : "Answer", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 16)),
        bottom: pages.length > 1 && _settings['progress'] != false && !_done
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: (_page + 1) / pages.length, minHeight: 4, color: _color, backgroundColor: AppPalette.bg(_color.withValues(alpha: 0.15))),
              )
            : null,
      ),
      body: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(12, 16, 12, 40), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_page == 0 || _done) header,
              if (pages.length > 1 && !_done) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text("Page ${_page + 1} of ${pages.length}", style: TextStyle(color: AppPalette.fg(Colors.grey.shade700), fontSize: 12))),
              content,
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Responses: summary with charts, one by one, table + Excel / PDF / print
// ---------------------------------------------------------------------------
class FormResponsesView extends StatefulWidget {
  final String formId;
  final List<FormQ> questions;
  final String title;
  final Color color;
  final ValueChanged<int>? onCount;
  const FormResponsesView({super.key, required this.formId, required this.questions, required this.title, required this.color, this.onCount});
  @override
  State<FormResponsesView> createState() => _FormResponsesViewState();
}

class _FormResponsesViewState extends State<FormResponsesView> {
  List<Map<String, dynamic>> _subs = [];
  bool _loading = true;
  String _mode = 'summary'; // summary | individual | table
  int _index = 0;

  List<FormQ> get _inputs => widget.questions.where((q) => _isInput(q.type)).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await FormsService.submissions(widget.formId);
      if (!mounted) return;
      setState(() {
        _subs = s;
        _loading = false;
        if (_index >= s.length) _index = s.isEmpty ? 0 : s.length - 1;
      });
      widget.onCount?.call(s.length);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _data(Map s) => s['data'] is Map ? Map<String, dynamic>.from(s['data'] as Map) : const {};

  ExportTable _table() => ExportTable(
        title: "${widget.title} – responses",
        subtitle: "${_subs.length} response${_subs.length == 1 ? '' : 's'}",
        headers: ['Submitted', 'Name', for (final q in _inputs) q.label.isEmpty ? 'Untitled' : q.label],
        rows: [
          for (final s in _subs)
            [
              DateFormat('d MMM yyyy HH:mm').format(DateTime.tryParse((s['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now()),
              (s['respondent_name'] ?? s['submitted_by'] ?? 'Anonymous').toString(),
              for (final q in _inputs) formatAnswer(q, _data(s)[q.key]),
            ],
        ],
      );

  Widget _summaryFor(FormQ q) {
    final answers = [for (final s in _subs) _data(s)[q.key]].where((v) => v != null && !(v is String && v.trim().isEmpty) && !(v is List && v.isEmpty)).toList();
    Widget body;
    if (_isChoice(q.type) || q.type == 'yes_no' || q.type == 'linear_scale' || q.type == 'rating') {
      final counts = <String, int>{};
      final order = <String>[
        if (_isChoice(q.type)) ...q.options,
        if (q.type == 'yes_no') ...['Yes', 'No'],
        if (q.type == 'linear_scale') for (int k = q.scaleMin; k <= q.scaleMax; k++) '$k',
        if (q.type == 'rating') for (int k = 1; k <= q.scaleMax; k++) '$k ★',
      ];
      for (final a in answers) {
        final list = a is List ? a : [a];
        for (final x in list) {
          final key = q.type == 'yes_no' ? formatAnswer(q, x) : (q.type == 'rating' ? '$x ★' : x.toString());
          counts[key] = (counts[key] ?? 0) + 1;
        }
      }
      final keys = [...order, ...counts.keys.where((k) => !order.contains(k))];
      final maxC = counts.values.fold<int>(0, math.max);
      final avg = (q.type == 'linear_scale' || q.type == 'rating') && answers.isNotEmpty
          ? answers.map((a) => (a is num) ? a.toDouble() : double.tryParse(a.toString()) ?? 0).reduce((a, b) => a + b) / answers.length
          : null;
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (avg != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text("Average: ${avg.toStringAsFixed(1)}", style: TextStyle(fontWeight: FontWeight.bold, color: AppPalette.fg(widget.color)))),
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 130, child: Text(k, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxC == 0 ? 0 : (counts[k] ?? 0) / maxC,
                    minHeight: 16,
                    color: widget.color,
                    backgroundColor: AppPalette.bg(widget.color.withValues(alpha: 0.08)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text("${counts[k] ?? 0} (${answers.isEmpty ? 0 : ((counts[k] ?? 0) / answers.length * 100).round()}%)", textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ),
      ]);
    } else {
      final texts = answers.map((a) => formatAnswer(q, a)).toList();
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final t in texts.take(30))
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF8FAFC)), borderRadius: BorderRadius.circular(8)),
            child: SelectableText(t, style: const TextStyle(fontSize: 13)),
          ),
        if (texts.length > 30) Text("…and ${texts.length - 30} more (see Table)", style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700))),
      ]);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q.label.isEmpty ? 'Untitled' : q.label, style: GoogleFonts.merriweather(fontWeight: FontWeight.w700, fontSize: 14.5)),
          Text("${answers.length} answer${answers.length == 1 ? '' : 's'}", style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade600))),
          const SizedBox(height: 10),
          if (answers.isEmpty) Text("No answers yet.", style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))) else body,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final header = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text("${_subs.length} response${_subs.length == 1 ? '' : 's'}", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 18)),
      const SizedBox(width: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'summary', icon: Icon(Icons.bar_chart_rounded, size: 18), label: Text("Summary")),
          ButtonSegment(value: 'individual', icon: Icon(Icons.person_outline, size: 18), label: Text("One by one")),
          ButtonSegment(value: 'table', icon: Icon(Icons.table_chart_outlined, size: 18), label: Text("Table")),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
      IconButton(tooltip: "Refresh", onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      IconButton(tooltip: "Download Excel / PDF / Print", onPressed: _subs.isEmpty ? null : () => TableExport.showMenu(context, _table), icon: const Icon(Icons.download_rounded)),
    ]);
    Widget body;
    if (_subs.isEmpty) {
      body = Padding(padding: const EdgeInsets.all(30), child: Text("No responses yet. Publish the form so people can answer it under Surveys.", textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey.shade600))));
    } else if (_mode == 'summary') {
      body = Column(children: [for (final q in _inputs) _summaryFor(q)]);
    } else if (_mode == 'individual') {
      final s = _subs[_index.clamp(0, _subs.length - 1)];
      final d = _data(s);
      body = Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(onPressed: _index > 0 ? () => setState(() => _index--) : null, icon: const Icon(Icons.chevron_left)),
              Text("${_index + 1} of ${_subs.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(onPressed: _index < _subs.length - 1 ? () => setState(() => _index++) : null, icon: const Icon(Icons.chevron_right)),
              const Spacer(),
              IconButton(
                tooltip: "Delete this response",
                icon: Icon(Icons.delete_outline, color: AppPalette.fg(Colors.red.shade700)),
                onPressed: () async {
                  await FormsService.deleteSubmission(s['id'].toString());
                  _load();
                },
              ),
            ]),
            Text(
              "${(s['respondent_name'] ?? s['submitted_by'] ?? 'Anonymous')} · ${DateFormat('d MMM yyyy, HH:mm').format(DateTime.tryParse((s['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now())}",
              style: TextStyle(color: AppPalette.fg(Colors.grey.shade700)),
            ),
            const Divider(height: 24),
            for (final q in _inputs)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(q.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  SelectableText(formatAnswer(q, d[q.key]).isEmpty ? '—' : formatAnswer(q, d[q.key]), style: TextStyle(color: AppPalette.fg(Colors.grey.shade800))),
                ]),
              ),
          ]),
        ),
      );
    } else {
      final t = _table();
      body = Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppPalette.bg(widget.color.withValues(alpha: 0.08))),
            columns: [for (final h in t.headers) DataColumn(label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text(h, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))))],
            rows: [
              for (final r in t.rows) DataRow(cells: [for (final c in r) DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: Text(c, overflow: TextOverflow.ellipsis)))]),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 16, 12, 120), children: [
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: 12), body]))),
      ]),
    );
  }
}
