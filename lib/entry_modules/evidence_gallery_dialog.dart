// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';

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

      if (mounted) {
        setState(() {
          _photos = List<Map<String, dynamic>>.from(res);
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
    int duplicateCount = 0;

    for (var file in result.files) {
      if (file.bytes == null) continue;

      // 1. Calculate SHA-256 hash to detect exact duplicates
      final fileHash = sha256.convert(file.bytes!).toString();

      // 2. Check if this exact file hash already exists in DB
      final existing = await supabase
          .from('report_evidence')
          .select('id')
          .eq('sheet_name', widget.sheetName)
          .eq('unit_name', widget.unitName)
          .eq('report_date', dateStr)
          .eq('file_hash', fileHash)
          .maybeSingle();

      if (existing != null) {
        duplicateCount++;
        continue; // Skip duplicate!
      }

      final ext = file.extension ?? 'jpg';
      final fileName = "${DateTime.now().millisecondsSinceEpoch}_$uploadedCount.$ext";
      // The report-evidence bucket only accepts files inside the uploader's own folder (<uid>/...)
      final storagePath = "${user?.id ?? 'anonymous'}/${widget.sheetName}/${widget.unitName}/$dateStr/$fileName";
      final contentType = (ext.toLowerCase() == 'jpg' || ext.toLowerCase() == 'jpeg') ? 'image/jpeg' : 'image/${ext.toLowerCase()}';

      try {
        await supabase.storage.from('report-evidence').uploadBinary(
              storagePath,
              file.bytes!,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );

        final publicUrl = supabase.storage.from('report-evidence').getPublicUrl(storagePath);

        await supabase.from('report_evidence').insert({
          'duty_name': widget.sheetName, // required column (the insert failed without it)
          'uploaded_by': user?.id,
          'sheet_name': widget.sheetName,
          'unit_name': widget.unitName,
          'report_date': dateStr,
          'image_url': publicUrl,
          'storage_path': storagePath,
          'file_hash': fileHash, // Saved to guard against duplicates
          'uploader_id': user?.id,
        });

        uploadedCount++;
      } catch (e) {
        debugPrint("Upload error: $e");
      }
    }

    widget.onEvidenceChanged();
    await _fetchPhotos();
    if (mounted) {
      setState(() => _isUploading = false);

      if (duplicateCount > 0 && uploadedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange[800],
            content: Text("Uploaded $uploadedCount photos. $duplicateCount duplicate photo(s) rejected."),
          ),
        );
      } else if (duplicateCount > 0 && uploadedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red[800],
            content: const Text("Rejected: Selected photo(s) have already been uploaded!"),
          ),
        );
      } else if (uploadedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green[800],
            content: Text("Uploaded $uploadedCount photo(s) successfully!"),
          ),
        );
      }
    }
  }

  Future<void> _deletePhoto(String id, String storagePath) async {
    if (!_isEditable) return;
    try {
      await supabase.storage.from('report-evidence').remove([storagePath]);
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
        backgroundColor: Colors.transparent,
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
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 20),
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
                  backgroundColor: widget.pPurple.withValues(alpha: 0.1),
                  child: Icon(Icons.photo_library_rounded, color: widget.pPurple),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Evidence Album", style: GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.w900, color: widget.pPurple)),
                    Text("$dateDisplay  •  ${widget.unitName}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                const Spacer(),
                if (_isEditable)
                  ElevatedButton.icon(
                    icon: _isUploading
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add_a_photo_outlined, size: 14),
                    label: Text(isDesktop ? "Upload Photos" : "Add"),
                    style: ElevatedButton.styleFrom(backgroundColor: widget.pPurple, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
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
                              Icon(Icons.camera_alt_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              const Text("No evidence uploaded for this date.", style: TextStyle(color: Colors.grey)),
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
                            final url = photo['image_url'] as String;
                            final id = photo['id'].toString();
                            final storagePath = photo['storage_path'] as String;

                            return ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  GestureDetector(
                                    onTap: () => _openFullScreenViewer(url),
                                    child: Image.network(url, fit: BoxFit.cover),
                                  ),
                                  if (_isEditable)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () => _deletePhoto(id, storagePath),
                                        child: const CircleAvatar(
                                          radius: 13,
                                          backgroundColor: Colors.black,
                                          child: Icon(Icons.delete_outline, size: 15, color: Colors.redAccent),
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