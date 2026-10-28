// ignore_for_file: use_build_context_synchronously
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_palette.dart';
import '../../core/app_sizes.dart';
import '../../core/i18n.dart';
import 'approval_inbox.dart';

enum TransferMode { individual, bulk }

/// Member Bio › Request member transfer.
///
/// You only see — and can only transfer — members of your own unit. Choose
/// the destination Group, Location, Sub-location and Department and add a
/// photo of the members. The destination department's leaders assign the
/// Team and Cell; the team leader, cell leader, sub-location, location,
/// Internal Affairs and the Administration Department then approve in turn
/// (the steps are rows of `transfer_steps`); only then is the member's unit
/// changed (transfer_create / transfer_decide, 14_round13.sql).
class TransferRequestForm extends StatefulWidget {
  const TransferRequestForm({super.key});
  @override
  State<TransferRequestForm> createState() => _TransferRequestFormState();
}

class _TransferRequestFormState extends State<TransferRequestForm> {
  final _db = Supabase.instance.client;
  static const Color _purple = Color(0xFF4A148C);

  TransferMode _mode = TransferMode.individual;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _opts = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _submitting = false;
  bool _canReview = false;
  String? _error;
  String _search = '';

  String? _group, _location, _sub, _dept;
  final _reason = TextEditingController();
  final List<PlatformFile> _photos = [];
  List<String> _route = const []; // transfer_steps labels, in order

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([
        _db.rpc('transfer_my_members', params: {'p_search': ''}),
        _db.rpc('transfer_dest_options'),
        _db.rpc('can_review_transfers'),
        _db.from('transfer_steps').select('label').order('step_no', ascending: true),
      ]);
      if (mounted) {
        setState(() {
          _members = List<Map<String, dynamic>>.from(r[0] as List);
          _opts = List<Map<String, dynamic>>.from(r[1] as List);
          _canReview = r[2] == true;
          _route = [for (final s in (r[3] as List)) (s['label'] ?? '').toString()];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load your members (run 13_round12.sql): ${e is PostgrestException ? e.message : e}";
        });
      }
    }
  }

  List<String> _values(String kind, {String? p1, String? p2}) {
    final s = <String>{};
    for (final o in _opts) {
      if (o['kind'] != kind) continue;
      if (p1 != null && o['parent1'] != p1) continue;
      if (p2 != null && o['parent2'] != p2) continue;
      s.add(o['value'].toString());
    }
    return s.toList()..sort();
  }

  String _unit(Map m) => [m['location'], m['sub_location'], m['department'], m['team'], m['cell_group']]
      .where((x) => (x ?? '').toString().isNotEmpty && x.toString().toUpperCase() != 'N/A')
      .join(' › ');

  Future<void> _pickPhotos() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (r == null) return;
    setState(() => _photos.addAll(r.files.where((f) => f.bytes != null)));
  }

  void _snack(String m, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null, behavior: SnackBarBehavior.floating));

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      _snack("Choose the member${_mode == TransferMode.bulk ? 's' : ''} to transfer.", error: true);
      return;
    }
    if (_location == null || _sub == null || _dept == null) {
      _snack("Choose the destination location, sub-location and department.", error: true);
      return;
    }
    if (_photos.isEmpty) {
      _snack("Add a photo of the member${_selected.length > 1 ? 's' : ''} being transferred.", error: true);
      return;
    }
    if (_reason.text.trim().isEmpty) {
      _snack("Write the reason for the transfer.", error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final uid = _db.auth.currentUser!.id;
      final paths = <String>[];
      for (final f in _photos) {
        final ext = (f.extension ?? 'jpg').toLowerCase();
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_${paths.length}.$ext';
        await _db.storage.from('transfer-photos').uploadBinary(path, f.bytes!, fileOptions: FileOptions(contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}'));
        paths.add(path);
      }
      final n = await _db.rpc('transfer_create', params: {
        'p_members': _selected.toList(),
        'p_dest': {'group': _group, 'location': _location, 'sub_location': _sub, 'department': _dept},
        'p_reason': _reason.text.trim(),
        'p_photos': paths,
      });
      _snack("Transfer request sent for $n member${n == 1 ? '' : 's'}. The destination department will assign the team and cell.");
      setState(() {
        _selected.clear();
        _photos.clear();
        _reason.clear();
        _submitting = false;
      });
      _load();
    } catch (e) {
      setState(() => _submitting = false);
      _snack("Couldn't send: ${e is PostgrestException ? e.message : e}", error: true);
    }
  }

  Widget _card(String title, IconData icon, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.line(Colors.black12)),
          boxShadow: [BoxShadow(color: _purple.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: AppPalette.fg(_purple), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppPalette.fg(_purple)))),
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _drop(String label, String? value, List<String> items, void Function(String?) onChanged, {bool optional = false}) => SizedBox(
        width: 260,
        child: DropdownButtonFormField<String>(
          initialValue: items.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr(optional ? "$label (optional)" : label), isDense: true, border: const OutlineInputBorder()),
          items: [
            if (optional) const DropdownMenuItem<String>(value: null, child: Text("—")),
            for (final i in items) DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        ),
      );

  Widget _modeSelector() => SegmentedButton<TransferMode>(
        segments: [
          ButtonSegment(
            value: TransferMode.individual,
            icon: const Icon(Icons.person_rounded, size: 18),
            // FittedBox: the words shrink instead of running out of the button on phones
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text("Individual transfer")),
          ),
          ButtonSegment(
            value: TransferMode.bulk,
            icon: const Icon(Icons.groups_rounded, size: 18),
            label: const FittedBox(fit: BoxFit.scaleDown, child: Text("Bulk transfer")),
          ),
        ],
        selected: {_mode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() {
          _mode = s.first;
          if (_mode == TransferMode.individual && _selected.length > 1) {
            final keep = _selected.first;
            _selected
              ..clear()
              ..add(keep);
          }
        }),
      );

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final list = _members.where((m) => q.isEmpty || '${m['english_name']} ${m['scj_id']} ${m['team']} ${m['cell_group']}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF8FAFC)),
      appBar: AppBar(
        centerTitle: true,
        title: Text("Member transfer", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(_purple))),
        actions: [
          if (_canReview)
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApprovalInbox(userRole: ''))),
              icon: const Icon(Icons.inbox_rounded, size: 18),
              label: const Text("Approvals"),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : ListView(padding: AppSizes.page, children: [
                  Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _modeSelector())),
                  const SizedBox(height: 12),
                  _card(
                    _mode == TransferMode.individual ? "1. Member (from your unit)" : "1. Members (from your unit) · ${_selected.length} chosen",
                    Icons.person_search_rounded,
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr("Search name or SCJ ID"), isDense: true, border: const OutlineInputBorder()),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                      if (_mode == TransferMode.bulk)
                        Align(
                          alignment: Alignment.center,
                          child: TextButton.icon(
                            onPressed: () => setState(() {
                              final ids = list.where((m) => m['pending'] != true).map((m) => m['id'].toString());
                              if (ids.every(_selected.contains)) {
                                _selected.removeAll(ids);
                              } else {
                                _selected.addAll(ids);
                              }
                            }),
                            icon: const Icon(Icons.select_all_rounded, size: 18),
                            label: const Text("Select all shown"),
                          ),
                        ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 280,
                        child: list.isEmpty
                            ? Center(child: Text("No members in your unit match.", style: TextStyle(color: AppPalette.fg(Colors.grey))))
                            : ListView.builder(
                                itemCount: list.length,
                                itemExtent: 46,
                                itemBuilder: (_, i) {
                                  final m = list[i];
                                  final id = m['id'].toString();
                                  final busy = m['pending'] == true;
                                  final sel = _selected.contains(id);
                                  return ListTile(
                                    dense: true,
                                    enabled: !busy,
                                    leading: Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked, color: AppPalette.fg(sel ? _purple : Colors.grey)),
                                    title: Text((m['english_name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(busy ? "A transfer is already on its way" : _unit(m), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    onTap: busy
                                        ? null
                                        : () => setState(() {
                                              if (_mode == TransferMode.individual) {
                                                _selected
                                                  ..clear()
                                                  ..add(id);
                                              } else if (sel) {
                                                _selected.remove(id);
                                              } else {
                                                _selected.add(id);
                                              }
                                            }),
                                  );
                                },
                              ),
                      ),
                    ]),
                  ),
                  _card(
                    "2. Destination",
                    Icons.place_rounded,
                    Column(children: [
                      Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                        _drop("Group", _group, _values('group'), (v) => setState(() => _group = v), optional: true),
                        _drop("Location", _location, _values('location'), (v) => setState(() {
                              _location = v;
                              _sub = null;
                              _dept = null;
                            })),
                        _drop("Sub-location", _sub, _location == null ? const [] : _values('sub_location', p1: _location), (v) => setState(() {
                              _sub = v;
                              _dept = null;
                            })),
                        _drop("Department", _dept, _sub == null ? const [] : _values('department', p1: _location, p2: _sub), (v) => setState(() => _dept = v)),
                      ]),
                      const SizedBox(height: 8),
                      Text("The team and cell are assigned by the destination department's leaders.",
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppPalette.fg(Colors.grey.shade700))),
                    ]),
                  ),
                  _card(
                    "3. Photo and reason",
                    Icons.photo_camera_rounded,
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                        for (int i = 0; i < _photos.length; i++)
                          Stack(children: [
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_photos[i].bytes!, width: 90, height: 90, fit: BoxFit.cover)),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: InkWell(
                                onTap: () => setState(() => _photos.removeAt(i)),
                                child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                              ),
                            ),
                          ]),
                        OutlinedButton.icon(onPressed: _pickPhotos, icon: const Icon(Icons.add_a_photo_rounded), label: Text(_photos.isEmpty ? "Add photo of the member(s)" : "Add more")),
                      ]),
                      const SizedBox(height: 12),
                      TextField(controller: _reason, maxLines: 3, decoration: InputDecoration(labelText: tr("Reason for the transfer"), border: const OutlineInputBorder(), alignLabelWithHint: true)),
                    ]),
                  ),
                  Center(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(_purple), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
                      label: Text(_selected.length > 1 ? "Send transfer request (${_selected.length} members)" : "Send transfer request"),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _route.isEmpty
                        ? "Route: destination department (assigns team & cell) → team leader → cell leader → sub-location → location → Internal Affairs → Administration Department → member moved."
                        : "Route: ${_route.join(' → ')} → member moved.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700)),
                  ),
                ]),
    );
  }
}
