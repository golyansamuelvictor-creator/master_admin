import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_palette.dart';

/// Service Attendance › Final service picture.
///
/// The general picture taken right after a service. Only the Location
/// Secretary of that location (a role with "Upload Service Photos" in
/// app_roles) and admins can upload, see and download them; the database and
/// the private "service-photos" bucket enforce it (09_round8.sql).
class ServicePhotosScreen extends StatefulWidget {
  const ServicePhotosScreen({super.key});
  @override
  State<ServicePhotosScreen> createState() => _ServicePhotosScreenState();
}

class _ServicePhotosScreenState extends State<ServicePhotosScreen> {
  final _db = Supabase.instance.client;
  static const Color _purple = Color(0xFF4A148C);
  static const String _bucket = 'service-photos';

  String? _myLocation; // '*' for admins
  String? _location; // location being viewed
  List<String> _locations = [];
  List<Map<String, dynamic>> _photos = [];
  final Map<String, String> _urls = {};
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  static String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  Future<void> _init() async {
    try {
      final loc = (await _db.rpc('service_photo_location'))?.toString();
      if (loc == null || loc.isEmpty) {
        setState(() {
          _loading = false;
          _error = "Only the Location Secretary can add and see final service pictures.";
        });
        return;
      }
      _myLocation = loc;
      if (loc == '*') {
        final rows = await _db.from('locations').select('location').order('location');
        _locations = [for (final r in rows) (r['location'] ?? '').toString()].where((x) => x.isNotEmpty).toList();
        _location = _locations.isNotEmpty ? _locations.first : null;
      } else {
        _location = loc;
      }
      await _load();
    } catch (e) {
      debugPrint("Service photos: $e");
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't open service pictures. Ask the admin to run 09_round8.sql.";
        });
      }
    }
  }

  Future<void> _load() async {
    if (_location == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await _db.from('service_photos').select().eq('location', _location!).order('service_date', ascending: false).order('created_at', ascending: false).limit(120);
      final list = List<Map<String, dynamic>>.from(rows);
      final paths = list.map((p) => p['storage_path'].toString()).where((p) => !_urls.containsKey(p)).toList();
      if (paths.isNotEmpty) {
        // ignore: deprecated_member_use
        final signed = await _db.storage.from(_bucket).createSignedUrls(paths, 3600);
        for (final s in signed) {
          _urls[s.path] = s.signedUrl;
        }
      }
      if (!mounted) return;
      setState(() {
        _photos = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint("Service photos load: $e");
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load pictures: ${e is PostgrestException ? e.message : e}";
        });
      }
    }
  }

  void _snack(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, backgroundColor: error ? Colors.red.shade700 : null));

  Future<void> _upload() async {
    if (_location == null) return;
    DateTime date = DateTime.now();
    String day = date.weekday == DateTime.sunday ? 'Sunday' : (date.weekday == DateTime.wednesday ? 'Wednesday' : 'Other');
    final caption = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text("Final service picture"),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Location: $_location", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(DateFormat('EEE d MMM yyyy').format(date)),
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, firstDate: DateTime(2024), lastDate: DateTime.now(), initialDate: date);
                  if (d != null) {
                    setD(() {
                      date = d;
                      day = d.weekday == DateTime.sunday ? 'Sunday' : (d.weekday == DateTime.wednesday ? 'Wednesday' : day);
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: day,
                decoration: InputDecoration(labelText: tr("Service"), isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'Sunday', child: Text("Sunday service")),
                  DropdownMenuItem(value: 'Wednesday', child: Text("Wednesday service")),
                  DropdownMenuItem(value: 'Other', child: Text("Other service")),
                ],
                onChanged: (v) => setD(() => day = v ?? day),
              ),
              const SizedBox(height: 10),
              TextField(controller: caption, decoration: InputDecoration(labelText: tr("Note (optional)"), isDense: true, border: OutlineInputBorder())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.photo_library_outlined), label: const Text("Choose pictures")),
          ],
        );
      }),
    );
    if (go != true) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (picked == null || picked.files.isEmpty) return;

    setState(() => _uploading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final me = _db.auth.currentUser;
    String? myName;
    try {
      final p = await _db.from('profiles').select('full_name').eq('id', me?.id ?? '').maybeSingle();
      myName = p?['full_name']?.toString();
    } catch (_) {}
    int ok = 0;
    final failed = <String>[];
    for (final f in picked.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      if (bytes.length > 15 * 1024 * 1024) {
        failed.add("${f.name} (over 15 MB)");
        continue;
      }
      final ext = (f.extension ?? 'jpg').toLowerCase();
      final path = "${_slug(_location!)}/$dateStr/${DateTime.now().millisecondsSinceEpoch}_${_slug(f.name.replaceAll(RegExp(r'\.[^.]+$'), ''))}.$ext";
      try {
        await _db.storage.from(_bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg')));
        await _db.from('service_photos').insert({
          'location': _location,
          'service_date': dateStr,
          'service_day': day,
          'caption': caption.text.trim().isEmpty ? null : caption.text.trim(),
          'storage_path': path,
          'file_name': f.name,
          'uploader_name': myName,
        });
        ok++;
      } catch (e) {
        debugPrint("Upload ${f.name}: $e");
        failed.add(f.name);
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    _snack(failed.isEmpty ? "$ok picture${ok == 1 ? '' : 's'} uploaded" : "$ok uploaded, not uploaded: ${failed.join(', ')}", error: failed.isNotEmpty);
    _load();
  }

  Future<void> _download(Map<String, dynamic> p) async {
    try {
      final path = p['storage_path'].toString();
      final name = (p['file_name'] ?? path.split('/').last).toString();
      final url = await _db.storage.from(_bucket).createSignedUrl(path, 600);
      final sep = url.contains('?') ? '&' : '?';
      await launchUrl(Uri.parse("$url${sep}download=${Uri.encodeComponent(name)}"), mode: LaunchMode.externalApplication);
    } catch (e) {
      _snack("Couldn't download: $e", error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete this picture?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Delete", style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.storage.from(_bucket).remove([p['storage_path'].toString()]);
      await _db.from('service_photos').delete().eq('id', p['id']);
      _load();
    } catch (e) {
      _snack("Couldn't delete: $e", error: true);
    }
  }

  void _view(Map<String, dynamic> p) {
    final url = _urls[p['storage_path'].toString()];
    if (url == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(child: Center(child: Image.network(url, fit: BoxFit.contain))),
          Positioned(
            top: 6,
            right: 6,
            child: Row(children: [
              IconButton(tooltip: tr("Download"), onPressed: () => _download(p), icon: const Icon(Icons.download_rounded, color: Colors.white)),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> p) {
    final url = _urls[p['storage_path'].toString()];
    final date = DateTime.tryParse((p['service_date'] ?? '').toString());
    final up = DateTime.tryParse((p['created_at'] ?? '').toString())?.toLocal();
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => _view(p),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(fit: StackFit.expand, children: [
              url == null
                  ? Container(color: AppPalette.bg(Colors.grey.shade200), child: const Icon(Icons.image_outlined))
                  : Image.network(url, fit: BoxFit.cover, cacheWidth: 600, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
              // Date stamp
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    date == null ? '' : "${DateFormat('d MMM yyyy').format(date)} · ${p['service_day'] ?? ''}",
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((p['caption'] ?? '').toString().isNotEmpty) Text(p['caption'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  Text(
                    "Uploaded ${up == null ? '' : DateFormat('d MMM, HH:mm').format(up)}${(p['uploader_name'] ?? '').toString().isEmpty ? '' : ' by ${p['uploader_name']}'}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey.shade700)),
                  ),
                ]),
              ),
              IconButton(tooltip: tr("Download"), visualDensity: VisualDensity.compact, onPressed: () => _download(p), icon: Icon(Icons.download_rounded, color: AppPalette.fg(_purple), size: 20)),
              IconButton(tooltip: tr("Delete"), visualDensity: VisualDensity.compact, onPressed: () => _delete(p), icon: Icon(Icons.delete_outline, color: AppPalette.fg(Colors.red.shade700), size: 20)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        title: Text("Final service pictures", style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [IconButton(tooltip: tr("Refresh"), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: _myLocation == null || _location == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppPalette.bg(_purple),
              foregroundColor: Colors.white,
              onPressed: _uploading ? null : _upload,
              icon: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_a_photo_rounded),
              label: Text(_uploading ? "Uploading…" : "Upload picture"),
            ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 760 ? 3 : (c.maxWidth >= 420 ? 2 : 1));
                return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 100), children: [
                  if (_myLocation == '*' && _locations.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String>(
                        initialValue: _location,
                        decoration: InputDecoration(labelText: tr("Location"), isDense: true, border: OutlineInputBorder()),
                        items: [for (final l in _locations) DropdownMenuItem(value: l, child: Text(l))],
                        onChanged: (v) {
                          setState(() => _location = v);
                          _load();
                        },
                      ),
                    )
                  else if (_location != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text("General pictures taken right after each service in $_location.", style: TextStyle(color: AppPalette.fg(Colors.grey.shade700))),
                    ),
                  if (_loading)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  else if (_photos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(children: [
                        Icon(Icons.photo_camera_back_outlined, size: 48, color: AppPalette.fg(Colors.grey.shade400)),
                        const SizedBox(height: 10),
                        const Text("No service pictures yet. Tap “Upload picture”.", textAlign: TextAlign.center),
                      ]),
                    )
                  else
                    GridView.count(
                      crossAxisCount: cols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.98,
                      children: [for (final p in _photos) _tile(p)],
                    ),
                ]);
              }),
            ),
    );
  }
}
