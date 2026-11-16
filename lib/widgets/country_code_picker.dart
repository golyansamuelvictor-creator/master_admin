import 'package:flutter/material.dart' hide Text;
import 'package:google_fonts/google_fonts.dart';

import '../core/app_palette.dart';
import '../core/country_codes.dart';
import '../core/i18n.dart';

/// Every country with its calling code, with a search box ("uga" → Uganda
/// +256, "971" → United Arab Emirates). [first]: ISO codes shown at the top
/// (the church's main countries). Returns (iso, name, code) or null.
Future<(String, String, String)?> pickCountryCode(BuildContext context, {List<String> first = const ['UG', 'AE', 'KE', 'TZ', 'RW', 'KR']}) {
  return showModalBottomSheet<(String, String, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.bg(Colors.white),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CountrySheet(first: first),
  );
}

class _CountrySheet extends StatefulWidget {
  final List<String> first;
  const _CountrySheet({required this.first});
  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase().replaceAll('+', '');
    final top = [for (final iso in widget.first) ...kCountryCodes.where((c) => c.$1 == iso)];
    final rest = kCountryCodes.where((c) => !widget.first.contains(c.$1)).toList();
    bool match((String, String, String) c) =>
        q.isEmpty || c.$2.toLowerCase().contains(q) || c.$3.replaceAll('+', '').startsWith(q) || c.$1.toLowerCase() == q;
    final list = [...top.where(match), ...rest.where(match)];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: tr("Search a country or code"),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text("No country found", style: TextStyle(color: AppPalette.fg(Colors.grey))))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final divider = q.isEmpty && i == top.length && top.isNotEmpty;
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        if (divider) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          leading: Text(countryFlag(c.$1), style: const TextStyle(fontSize: 22)),
                          title: Text.rich(TextSpan(text: c.$2), style: GoogleFonts.merriweather(fontSize: 13)),
                          trailing: Text.rich(TextSpan(text: c.$3), style: GoogleFonts.merriweather(fontSize: 13, fontWeight: FontWeight.bold)),
                          onTap: () => Navigator.pop(context, c),
                        ),
                      ]);
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// A small button showing the chosen country's flag and code; tap to change.
class CountryCodeButton extends StatelessWidget {
  final String iso;
  final String code;
  final ValueChanged<(String, String, String)> onPicked;
  const CountryCodeButton({super.key, required this.iso, required this.code, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final c = await pickCountryCode(context);
        if (c != null) onPicked(c);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppPalette.bg(Colors.white),
          border: Border.all(color: AppPalette.line(Colors.grey.shade400)),
          borderRadius: BorderRadius.circular(10), boxShadow: AppPalette.cardShadow
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(countryFlag(iso), style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          Text.rich(TextSpan(text: code), style: GoogleFonts.merriweather(fontSize: 12, fontWeight: FontWeight.bold)),
          const Icon(Icons.arrow_drop_down_rounded, size: 18),
        ]),
      ),
    );
  }
}
