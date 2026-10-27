// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../services/evidence_service.dart';
import 'package:master_admin/core/app_palette.dart';

class EvidenceGalleryDialog extends StatefulWidget {
  final String sheetName;
  final String unitName;
  final DateTime reportDate;
  final Color pPurple;
  final VoidCallback onEvidenceChanged;

  const EvidenceGalleryDialog({
    super.key,
    required this.sheetName,
    required this.unitName,
    required this.reportDate,
    required this.pPurple,
    required this.onEvidenceChanged,
  });

  @override
  State<EvidenceGalleryDialog> createState() => _EvidenceGalleryDialogState();
}

class _EvidenceGalleryDialogState extends State<EvidenceGalleryDialog> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _photos = [];
  Map<String, ({String? thumb, String? full})> _links = {}; // private photo links
  bool _isLoading = true;
  bool _isUploading = false;

  bool get _isEditable {
    final diff = DateTime.now().difference(widget.reportDate).inDays;
    return diff >= 0 && diff <= 6;
  }

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
  }

  Future<void> _fetchPhotos() async {
    setState(() => _isLoading = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.reportDate);
    try {
      final res = await supabase
          .from('report_evidence')
          .select()
          .eq('sheet_name', widget.sheetName)
          .eq('unit_name', widget.unitName)
          .eq('report_date', dateStr)
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(res);
      final links = await EvidenceService.signedUrls(rows);
      if (mounted) {
        setState(() {
          _photos = rows;
          _links = links;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching photos: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    if (!_isEditable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Reports older than 6 days are locked.")),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() => _isUploading = true);
    final user = supabase.auth.currentUser;
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.reportDate);

    int uploadedCount = 0;
    int flaggedCount = 0;
    final List<String> rejected = []; // "photo name: reason"
    final List<String> batchHashes = [];

    for (var file in result.files) {
      if (file.bytes == null) continue;

      // 1. Has this picture been used before (any unit, any date)?
      final check = await EvidenceService.check(
        bytes: file.bytes!,
        dutyName: widget.sheetName,
        unitName: widget.unitName,
        reportDate: widget.reportDate,
        batchHashes: batchHashes,
      );
      if (check.blocked) {
        rejected.add("${file.name}: ${check.reason}");
        continue;
      }
      if (check.fingerprint != null) batchHashes.add(check.fingerprint!.hash);

      final ext = (file.extension ?? 'jpg').toLowerCase();
      final fileName = "${DateTime.now().millisecondsSinceEpoch}_$uploadedCount.$ext";
      // The report-evidence bucket only accepts files inside the uploader's own folder (<uid>/...)
      final storagePath = "${user?.id ?? 'anonymous'}/${widget.sheetName}/${widget.unitName}/$dateStr/$fileName";
      final thumbPath = "$storagePath.thumb.png";
      final contentType = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';

      try {
        await supabase.storage.from(EvidenceService.bucket).uploadBinary(
              storagePath,
              file.bytes!,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
        final thumb = check.fingerprint?.thumbnailPng;
        bool thumbSaved = false;
        if (thumb != null) {
          try {
            await supabase.storage.from(EvidenceService.bucket).uploadBinary(
                  thumbPath,
                  thumb,
                  fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
                );
            thumbSaved = true;
          } catch (_) {}
        }

        await supabase.from('report_evidence').insert({
          'duty_name': widget.sheetName, // required column (the insert failed without it)
          'uploaded_by': user?.id,
          'sheet_name': widget.sheetName,
          'unit_name': widget.unitName,
          'report_date': dateStr,
          // The bucket is private: photos open through short-lived links made from storage_path
          'image_url': storagePath,
          'storage_path': storagePath,
          'thumb_path': thumbSaved ? thumbPath : null,
          'file_hash': check.sha,
          'phash': check.fingerprint?.hash,
          'uploader_id': user?.id,
        });

        uploadedCount++;
        if (check.flaggedForReview) flaggedCount++;
      } catch (e) {
        debugPrint("Upload error: $e");
        rejected.add("${file.name}: couldn't be uploaded. Check your connection and try again.");
      }
    }

    widget.onEvidenceChanged();
    await _fetchPhotos();
    if (!mounted) return;
    setState(() => _isUploading = false);

    if (rejected.isNotEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.report_gmailerrorred_rounded, color: AppPalette.fg(Colors.red.shade700)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                rejected.length == 1 ? "1 photo was not uploaded" : "${rejected.length} photos were not uploaded",
                style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
          ]),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                ...rejected.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text("• $r", style: GoogleFonts.merriweather(fontSize: 12.5, height: 1.4)),
                    )),
                const SizedBox(height: 6),
                Text(
                  "Please upload the correct photos taken for this report. Reused photos are not accepted as evidence, "
                  "and your reviewers can see that these were blocked.",
                  style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.blueGrey[700]), fontStyle: FontStyle.italic),
                ),
                if (uploadedCount > 0) ...[
                  const SizedBox(height: 8),
                  Text("$uploadedCount other photo(s) were uploaded.",
                      style: GoogleFonts.merriweather(fontSize: 12, color: AppPalette.fg(Colors.green[800]), fontWeight: FontWeight.bold)),
                ],
              ]),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(widget.pPurple), foregroundColor: AppPalette.fg(Colors.white)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    } else if (uploadedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green[800],
          content: Text(flaggedCount > 0
              ? "Uploaded $uploadedCount photo(s). $flaggedCount look similar to older photos and were marked for your reviewer."
              : "Uploaded $uploadedCount photo(s) successfully!"),
        ),
      );
    }
  }

  Future<void> _deletePhoto(String id, String storagePath, String? thumbPath) async {
    if (!_isEditable) return;
    try {
      await supabase.storage.from(EvidenceService.bucket).remove([storagePath, if (thumbPath != null && thumbPath.isNotEmpty) thumbPath]);
      await supabase.from('report_evidence').delete().eq('id', id);
      widget.onEvidenceChanged();
      _fetchPhotos();
    } catch (e) {
      debugPrint("Delete error: $e");
    }
  }

  void _openFullScreenViewer(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.bg(Colors.transparent),
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
            IconButton(
              icon: CircleAvatar(
                backgroundColor: AppPalette.bg(Colors.black54),
                child: Icon(Icons.close, color: AppPalette.fg(Colors.white), size: 20),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateDisplay = DateFormat('MMM d, yyyy (E)').format(widget.reportDate);
    final isDesktop = MediaQuery.of(context).size.width > 700;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(horizontal: isDesktop ? 60 : 16, vertical: 24),
      child: Container(
        width: isDesktop ? 750 : double.infinity,
        height: isDesktop ? 600 : 520,
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppPalette.bg(widget.pPurple.withValues(alpha: 0.1)),
                  child: Icon(Icons.photo_library_rounded, color: AppPalette.fg(widget.pPurple)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Evidence Album", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.w900, color: AppPalette.fg(widget.pPurple))),
                    Text("$dateDisplay  •  ${widget.unitName}", style: TextStyle(fontSize: 11, color: AppPalette.fg(Colors.grey))),
                  ],
                )),
                const Spacer(),
                if (_isEditable)
                  ElevatedButton.icon(
                    icon: _isUploading
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add_a_photo_outlined, size: 14),
                    label: Text(isDesktop ? "Upload Photos" : "Add"),
                    style: ElevatedButton.styleFrom(backgroundColor: AppPalette.bg(widget.pPurple), foregroundColor: AppPalette.fg(Colors.white), visualDensity: VisualDensity.compact),
                    onPressed: _isUploading ? null : _pickAndUpload,
                  ),
                const SizedBox(width: 6),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 20),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _photos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt_outlined, size: 48, color: AppPalette.fg(Colors.grey.shade400)),
                              const SizedBox(height: 8),
                              Text("No evidence uploaded for this date.", style: TextStyle(color: AppPalette.fg(Colors.grey))),
                              if (_isEditable) ...[
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.upload, size: 16),
                                  label: const Text("Upload First Photo"),
                                  onPressed: _pickAndUpload,
                                ),
                              ],
                            ],
                          ),
                        )
                      : GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isDesktop ? 4 : 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: _photos.length,
                          itemBuilder: (ctx, i) {
                            final photo = _photos[i];
                            final id = photo['id'].toString();
                            final storagePath = (photo['storage_path'] ?? '').toString();
                            final thumbPath = photo['thumb_path']?.toString();
                            final link = _links[id];
                            final mine = photo['uploaded_by'] == supabase.auth.currentUser?.id;

                            return ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  GestureDetector(
                                    onTap: link?.full == null ? null : () => _openFullScreenViewer(link!.full!),
                                    child: link?.thumb == null
                                        ? Container(
                                            color: AppPalette.bg(Colors.grey.shade200),
                                            child: Icon(Icons.image_not_supported_outlined, color: AppPalette.fg(Colors.grey.shade500)),
                                          )
                                        : Image.network(
                                            link!.thumb!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              color: AppPalette.bg(Colors.grey.shade200),
                                              child: Icon(Icons.broken_image_outlined, color: AppPalette.fg(Colors.grey.shade500)),
                                            ),
                                          ),
                                  ),
                                  if (_isEditable && mine)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => _deletePhoto(id, storagePath, thumbPath),
                                        child: CircleAvatar(
                                          radius: 13,
                                          backgroundColor: AppPalette.bg(Colors.black),
                                          child: Icon(Icons.delete_outline, size: 15, color: AppPalette.fg(Colors.redAccent)),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}