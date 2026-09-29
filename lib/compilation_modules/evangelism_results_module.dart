// lib/compilation_modules/evangelism_results_module.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EvangelismResultsModule extends StatelessWidget {
  final List<dynamic> bbData; 

  const EvangelismResultsModule({super.key, required this.bbData});

  @override
  Widget build(BuildContext context) {
    const pPurple = Color(0xFF4A148C);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 5, bottom: 15),
          child: Text(
            "Evangelism results summary",
            style: GoogleFonts.merriweather(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.blueGrey[800],
            ),
          ),
        ),
        _resultCard("Chakki", "Chakki", pPurple, Colors.orange),
        _resultCard("Possible", "Possible", pPurple, Colors.blue),
        _resultCard("New Bb", "New Bb", pPurple, Colors.teal),
        _resultCard("Proceeding", "Proceeding", pPurple, Colors.indigo),
        _resultCard("Confirmed", "Confirmed", pPurple, Colors.green),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _resultCard(String title, String statusKey, Color pPurple, Color accent) {
    // Filter logic to get counts
    final group = bbData.where((d) => d['level_status'] == statusKey).toList();
    final overall = group.length;
    final offline = group.where((d) => d['method'] == 'Inperson').length;
    final online = group.where((d) => d['method'] == 'Online').length;

    // Formatting as 00 / 00 / 00 / 00 format requested
    String format(int val) => val.toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(15), 
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02), 
            blurRadius: 10, 
            offset: const Offset(0, 4)
          )
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Side Accent Bar
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  bottomLeft: Radius.circular(15),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.merriweather(
                            fontWeight: FontWeight.w900, 
                            fontSize: 15, 
                            color: pPurple
                          ),
                        ),
                        Icon(Icons.analytics_outlined, size: 16, color: accent.withValues(alpha: 0.5)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _row("Overall total", "${format(overall)} / 00 / 00 / 00"),
                    const SizedBox(height: 4),
                    _row("Total offline", "${format(offline)} / 00 / 00 / 00"),
                    const SizedBox(height: 4),
                    _row("Total online", "${format(online)} / 00 / 00 / 00"),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label, 
        style: GoogleFonts.merriweather(
          fontSize: 12, 
          color: Colors.blueGrey[600],
          fontWeight: FontWeight.w500
        )
      ),
      Text(
        value, 
        style: GoogleFonts.merriweather(
          fontSize: 13, 
          fontWeight: FontWeight.w800, 
          color: Colors.black87,
          letterSpacing: 1.2
        )
      ),
    ],
  );
}