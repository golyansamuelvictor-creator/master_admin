// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:master_admin/core/app_palette.dart';
import 'package:file_picker/file_picker.dart'; 
import 'package:csv/csv.dart' as csv_lib; // FIXED: Using a prefix to avoid name conflicts

class AdminToolsScreen extends StatefulWidget {
  const AdminToolsScreen({super.key});

  @override
  State<AdminToolsScreen> createState() => _AdminToolsScreenState();
}

class _AdminToolsScreenState extends State<AdminToolsScreen> {
  bool _isUploading = false;

  Future<void> _importMembersFromCSV() async {
    try {
      // 1. Pick the CSV file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null) return; // User canceled

      setState(() => _isUploading = true);

      final file = File(result.files.single.path!);
      final input = file.openRead();
      
      // 2. FIXED: Using the prefixed library class
      final fields = await input
          .transform(utf8.decoder)
          .transform(const csv_lib.CsvToListConverter()) 
          .toList();

      if (fields.isEmpty) throw "The CSV file is empty";

      // 3. Map data to Supabase columns
      List<Map<String, dynamic>> newMembers = [];
      
      for (var i = 1; i < fields.length; i++) {
        final row = fields[i];
        if (row.length < 4) continue; 

        newMembers.add({
          'english_name': row[0].toString(),
          'gender': row[1].toString(),
          'scj_id': row[2].toString(),
          'location': row[3].toString(),
          'account_type': 'Saint',
          'role': 'member',
        });
      }

      if (newMembers.isEmpty) throw "No valid member data found in CSV";

      // 4. Bulk Insert to Supabase
      await Supabase.instance.client
          .from('members')
          .insert(newMembers);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text("Successfully enrolled members!")),
        );
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text("Upload failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pPurple = Color(0xFF4A148C);

    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFFBFBFE)),
      appBar: AppBar(
        title: Text("ADMIN TOOLS", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(pPurple))),
        centerTitle: true,
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
      ),
      body: Center(
        child: _isUploading 
          ? const CircularProgressIndicator(color: pPurple)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: AppPalette.bg(Colors.white),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20)],
                    border: Border.all(color: AppPalette.line(pPurple.withValues(alpha: 0.1)), width: 2),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.group_add_rounded, size: 80, color: AppPalette.fg(pPurple)),
                      const SizedBox(height: 25),
                      Text("Bulk Member Enrollment", 
                        textAlign: TextAlign.center,
                        style: GoogleFonts.merriweather(fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 40),
                      ElevatedButton.icon(
                        onPressed: _importMembersFromCSV,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text("SELECT CSV FILE"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.bg(pPurple),
                          foregroundColor: AppPalette.fg(Colors.white),
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("GO BACK", style: GoogleFonts.merriweather(color: AppPalette.fg(Colors.grey), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
      ),
    );
  }
}

// REMOVED: The manual class definition that was causing the error.