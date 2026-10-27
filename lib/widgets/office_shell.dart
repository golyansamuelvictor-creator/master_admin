// Shared look of Docs, Sheets and Slides (the original "hub + ribbon" design):
//  * OfficeHub: 3 columns: actions + templates | my files | briefing guide
//  * OfficeTemplateGrid / showOfficeTemplates: equal-size template cards
//  * OfficeHeaderCard: rounded title card with close / save / extra actions
//  * OfficeRibbon: pill tabs + a row of action cards under them
//  * OfficeScrollArrows: the fine-scroll arrows beside the page
//  * showOfficeMenu / OfficeRightClick: right-click menus with shortcut hints
//  * officeKeys: Ctrl (and Cmd on Mac) shortcuts
//  * OfficeRulerPainter, OfficeZoomPill, OfficeViewIcon: status bar pieces
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart' hide Text;
import 'package:master_admin/core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_palette.dart';

// ---------------------------------------------------------------------------
// Browser right-click: the app shows its own menus while an office screen is open
// ---------------------------------------------------------------------------
class OfficeBrowserMenu {
  OfficeBrowserMenu._();
  static int _users = 0;

  static void acquire() {
    if (!kIsWeb) return;
    if (_users++ == 0) BrowserContextMenu.disableContextMenu();
  }

  static void release() {
    if (!kIsWeb) return;
    if (_users > 0 && --_users == 0) BrowserContextMenu.enableContextMenu();
  }
}

// ---------------------------------------------------------------------------
// Shortcuts
// ---------------------------------------------------------------------------
/// Ctrl+[key] (and Cmd+[key] on Mac) → [action].
Map<ShortcutActivator, VoidCallback> officeKeys(Map<LogicalKeyboardKey, VoidCallback> ctrl, {Map<LogicalKeyboardKey, VoidCallback> ctrlShift = const {}}) => {
      for (final e in ctrl.entries) ...{
        SingleActivator(e.key, control: true): e.value,
        SingleActivator(e.key, meta: true): e.value,
      },
      for (final e in ctrlShift.entries) ...{
        SingleActivator(e.key, control: true, shift: true): e.value,
        SingleActivator(e.key, meta: true, shift: true): e.value,
      },
    };

// ---------------------------------------------------------------------------
// Right-click menus
// ---------------------------------------------------------------------------
class OfficeMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? shortcut;
  final Color? color;
  final bool isDivider;

  const OfficeMenuItem(this.label, {this.icon, this.onTap, this.shortcut, this.color}) : isDivider = false;
  const OfficeMenuItem.divider()
      : label = '',
        icon = null,
        onTap = null,
        shortcut = null,
        color = null,
        isDivider = true;
}

/// Shows [items] at [globalPos] (a right-click or long-press position).
Future<void> showOfficeMenu(BuildContext context, Offset globalPos, List<OfficeMenuItem> items) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final size = overlay?.size ?? MediaQuery.of(context).size;
  final picked = await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, size.width - globalPos.dx, size.height - globalPos.dy),
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
    items: [
      for (int i = 0; i < items.length; i++)
        if (items[i].isDivider)
          const PopupMenuDivider(height: 8)
        else
          PopupMenuItem<int>(
            value: i,
            height: 34,
            enabled: items[i].onTap != null,
            child: Row(children: [
              Icon(items[i].icon ?? Icons.circle_outlined, size: 17, color: AppPalette.fg(items[i].color ?? Colors.grey.shade700)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(items[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.merriweather(fontSize: 12, color: items[i].color == null ? null : AppPalette.fg(items[i].color))),
              ),
              if (items[i].shortcut != null) ...[
                const SizedBox(width: 10),
                Text(items[i].shortcut!, style: TextStyle(fontSize: 10.5, color: AppPalette.fg(Colors.grey.shade600))),
              ],
            ]),
          ),
    ],
  );
  if (picked != null) items[picked].onTap?.call();
}

/// Calls [onMenu] on a right-click (mouse) or, when [longPress] is true,
/// on a long-press (touch). Doesn't block taps or text selection.
class OfficeRightClick extends StatelessWidget {
  final Widget child;
  final void Function(Offset globalPos) onMenu;
  final bool longPress;
  const OfficeRightClick({super.key, required this.child, required this.onMenu, this.longPress = false});

  @override
  Widget build(BuildContext context) {
    Widget w = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (e.buttons == kSecondaryMouseButton) onMenu(e.position);
      },
      child: child,
    );
    if (longPress) {
      w = GestureDetector(behavior: HitTestBehavior.translucent, onLongPressStart: (d) => onMenu(d.globalPosition), child: w);
    }
    return w;
  }
}

// ---------------------------------------------------------------------------
// Templates (all cards have the same size)
// ---------------------------------------------------------------------------
class OfficeTemplate {
  final String key;
  final String name;
  final String description;
  final IconData icon;
  /// Optional picture of the template (e.g. the first slide); the icon is used otherwise.
  final Widget Function()? preview;
  const OfficeTemplate(this.key, this.name, this.description, this.icon, {this.preview});
}

class OfficeTemplateGrid extends StatelessWidget {
  final List<OfficeTemplate> templates;
  final void Function(OfficeTemplate) onTap;
  final Color accent;
  final double maxCardWidth;
  final double cardHeight;
  final bool scrollable;
  const OfficeTemplateGrid({
    super.key,
    required this.templates,
    required this.onTap,
    required this.accent,
    this.maxCardWidth = 190,
    this.cardHeight = 168,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCardWidth,
        mainAxisExtent: cardHeight, // every card the same height
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: templates.length,
      itemBuilder: (_, i) => _TemplateCard(t: templates[i], accent: accent, onTap: () => onTap(templates[i])),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final OfficeTemplate t;
  final Color accent;
  final VoidCallback onTap;
  const _TemplateCard({required this.t, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.bg(Colors.white),
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: AppPalette.bg(accent.withValues(alpha: 0.07)),
                  child: t.preview != null
                      ? FittedBox(fit: BoxFit.contain, child: t.preview!())
                      : Center(child: Icon(t.icon, size: 34, color: AppPalette.fg(accent))),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 12.5)),
            const SizedBox(height: 2),
            SizedBox(
              height: 30, // two lines, so every card lines up
              child: Text(t.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.3, color: AppPalette.fg(Colors.grey.shade600))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The full template gallery in a dialog.
Future<OfficeTemplate?> showOfficeTemplates(BuildContext context, {required String title, required List<OfficeTemplate> templates, required Color accent}) {
  return showDialog<OfficeTemplate>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.dashboard_customize_rounded, color: AppPalette.fg(accent)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 17, color: AppPalette.fg(accent)))),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 10),
            Flexible(
              child: OfficeTemplateGrid(
                templates: templates,
                accent: accent,
                scrollable: true,
                maxCardWidth: 210,
                cardHeight: 180,
                onTap: (t) => Navigator.pop(ctx, t),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Hub (start page)
// ---------------------------------------------------------------------------
class OfficeHubAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const OfficeHubAction(this.label, this.icon, this.color, this.onTap);
}

class OfficeHub extends StatelessWidget {
  final String title;
  final Color accent;
  final Color accent2;
  final List<OfficeHubAction> actions;
  final List<OfficeTemplate> templates;
  final void Function(OfficeTemplate) onTemplate;
  final VoidCallback onAllTemplates;

  final List<Map<String, dynamic>> files;
  final bool loading;
  final String searchHint;
  final String emptyText;
  final ValueChanged<String> onSearch;
  final IconData fileIcon;
  final Color fileIconColor;
  final String Function(Map<String, dynamic>) fileSubtitle;
  final void Function(Map<String, dynamic>) onOpen;
  final List<OfficeMenuItem> Function(Map<String, dynamic>) fileMenu;
  final Future<void> Function() onRefresh;
  final TextEditingController? searchController;

  final IconData guideIcon;
  final List<String> guideLines;

  const OfficeHub({
    super.key,
    required this.title,
    required this.accent,
    required this.accent2,
    required this.actions,
    required this.templates,
    required this.onTemplate,
    required this.onAllTemplates,
    required this.files,
    required this.loading,
    required this.searchHint,
    required this.emptyText,
    required this.onSearch,
    required this.fileIcon,
    required this.fileIconColor,
    required this.fileSubtitle,
    required this.onOpen,
    required this.fileMenu,
    required this.onRefresh,
    required this.guideIcon,
    required this.guideLines,
    this.searchController,
  });

  Widget _hubCard(OfficeHubAction a) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: ListTile(
          onTap: a.onTap,
          leading: Icon(a.icon, color: AppPalette.fg(a.color), size: 28),
          title: Text(a.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13.5)),
        ),
      );

  Widget _templatesBlock(BuildContext context, {int max = 4}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text("Templates", style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, fontSize: 13.5))),
          TextButton(onPressed: onAllTemplates, child: Text("See all (${templates.length})", style: TextStyle(color: AppPalette.fg(accent), fontSize: 12))),
        ]),
        const SizedBox(height: 4),
        OfficeTemplateGrid(templates: templates.take(max).toList(), accent: accent, onTap: onTemplate, maxCardWidth: 200, cardHeight: 150),
      ]);

  Widget _files(BuildContext context, {required bool expand}) {
    final list = loading
        ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        : files.isEmpty
            ? Padding(padding: const EdgeInsets.all(30), child: Center(child: Text(emptyText, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.fg(Colors.grey[600])))))
            : ListView.builder(
                shrinkWrap: !expand,
                physics: expand ? null : const NeverScrollableScrollPhysics(),
                itemCount: files.length,
                itemBuilder: (ctx, i) {
                  final f = files[i];
                  return OfficeRightClick(
                    onMenu: (p) => showOfficeMenu(ctx, p, fileMenu(f)),
                    longPress: true,
                    child: ListTile(
                      leading: Icon(fileIcon, color: AppPalette.fg(fileIconColor)),
                      title: Text((f['title'] ?? 'Untitled').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      subtitle: Text(fileSubtitle(f), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      onTap: () => onOpen(f),
                      trailing: Builder(
                        builder: (bctx) => IconButton(
                          tooltip: tr("Options"),
                          icon: const Icon(Icons.more_vert_rounded),
                          onPressed: () {
                            final box = bctx.findRenderObject() as RenderBox?;
                            final pos = box == null ? Offset.zero : box.localToGlobal(box.size.bottomLeft(Offset.zero));
                            showOfficeMenu(bctx, pos, fileMenu(f));
                          },
                        ),
                      ),
                    ),
                  );
                },
              );
    return Container(
      decoration: BoxDecoration(color: AppPalette.bg(Colors.white), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15)]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(15),
          child: TextField(
            controller: searchController,
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: searchHint,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: AppPalette.bg(const Color(0xFFFBFBFE)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
        ),
        if (expand) Expanded(child: list) else list,
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _guide() => Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [AppPalette.solid(accent), AppPalette.solid(accent2)]), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(guideIcon, color: Colors.white, size: 30),
          const SizedBox(height: 15),
          Text("Briefing Guide", style: GoogleFonts.merriweather(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          for (final l in guideLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("•  ", style: TextStyle(color: Colors.white70, height: 1.5)),
                Expanded(child: Text(l, style: const TextStyle(color: Colors.white70, height: 1.5))),
              ]),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(const Color(0xFFF1F5F9)),
      appBar: AppBar(
        backgroundColor: AppPalette.bg(Colors.white),
        elevation: 0.5,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.merriweather(fontWeight: FontWeight.w900, color: AppPalette.fg(accent))),
        actions: [IconButton(tooltip: tr("Refresh"), onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth > 1000) {
          return Padding(
            padding: const EdgeInsets.all(25),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 2,
                child: ListView(children: [for (final a in actions) _hubCard(a), const SizedBox(height: 6), _templatesBlock(context)]),
              ),
              const SizedBox(width: 25),
              Expanded(flex: 5, child: _files(context, expand: true)),
              const SizedBox(width: 25),
              Expanded(flex: 3, child: SingleChildScrollView(child: _guide())),
            ]),
          );
        }
        final pad = c.maxWidth < 600 ? 14.0 : 25.0;
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(padding: EdgeInsets.all(pad), children: [
            for (final a in actions) _hubCard(a),
            const SizedBox(height: 8),
            _templatesBlock(context, max: c.maxWidth < 600 ? 4 : 6),
            const SizedBox(height: 20),
            _files(context, expand: false),
            const SizedBox(height: 20),
            _guide(),
          ]),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Editor header card (the rounded card at the top of an open file)
// ---------------------------------------------------------------------------
class OfficeHeaderCard extends StatelessWidget {
  final Color accent;
  final TextEditingController titleController;
  final ValueChanged<String> onTitleChanged;
  final String subtitle;
  final Color subtitleColor;
  final VoidCallback onClose;
  final List<Widget> actions;
  const OfficeHeaderCard({
    super.key,
    required this.accent,
    required this.titleController,
    required this.onTitleChanged,
    required this.subtitle,
    required this.onClose,
    this.subtitleColor = Colors.grey,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 5),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.white),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppPalette.line(accent.withValues(alpha: 0.15)), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Row(children: [
        IconButton(tooltip: tr("Close (back to the hub)"), icon: Icon(Icons.close, color: AppPalette.fg(Colors.red), size: 20), onPressed: onClose),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: titleController,
              onChanged: onTitleChanged,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: GoogleFonts.merriweather(fontSize: 17, fontWeight: FontWeight.w900, color: AppPalette.fg(accent)),
              decoration: InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4), hintText: tr("Title")),
            ),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: AppPalette.fg(subtitleColor), fontWeight: FontWeight.bold)),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Ribbon
// ---------------------------------------------------------------------------
class OfficeRibbonTab {
  final String name;
  final List<Widget> Function() items;
  /// A custom row instead of the action cards (e.g. the text formatting toolbar).
  final Widget Function()? custom;
  final Color? color;
  const OfficeRibbonTab(this.name, this.items, {this.custom, this.color});
}

class OfficeRibbon extends StatelessWidget {
  final List<OfficeRibbonTab> tabs;
  final int active;
  final ValueChanged<int> onTab;
  final Color accent;
  final Color tint;
  final double rowHeight;
  const OfficeRibbon({super.key, required this.tabs, required this.active, required this.onTab, required this.accent, this.tint = const Color(0xFFF3E5F5), this.rowHeight = 40});

  @override
  Widget build(BuildContext context) {
    final tab = tabs[active.clamp(0, tabs.length - 1)];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 32,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(left: 15, right: 15), children: [
          for (int i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTab(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: AppPalette.bg(i == active ? (tabs[i].color ?? accent) : (tabs[i].color?.withValues(alpha: 0.12) ?? tint)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(tabs[i].name,
                        style: GoogleFonts.merriweather(fontSize: 11, fontWeight: FontWeight.bold, color: AppPalette.fg(i == active ? Colors.white : (tabs[i].color ?? accent)))),
                  ),
                ),
              ),
            ),
        ]),
      ),
      Container(
        height: rowHeight,
        width: double.infinity,
        color: AppPalette.bg(const Color(0xFFFBFBFE)),
        child: tab.custom != null
            ? tab.custom!()
            : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5), children: tab.items()),
      ),
    ]);
  }
}

/// One card in the ribbon row.
class OfficeAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color accent;
  final bool selected;
  const OfficeAction(this.icon, this.label, this.onTap, {super.key, this.tooltip, this.accent = const Color(0xFF4A148C), this.selected = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final card = Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppPalette.bg(selected ? accent.withValues(alpha: 0.12) : Colors.white),
        border: Border.all(color: AppPalette.line(selected ? accent.withValues(alpha: 0.5) : Colors.grey.shade200)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppPalette.fg(enabled ? accent : Colors.grey)),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold, color: AppPalette.fg(enabled ? Colors.black87 : Colors.grey))),
      ]),
    );
    final w = InkWell(borderRadius: BorderRadius.circular(6), onTap: onTap, child: card);
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// A ribbon card that opens a list of choices.
class OfficeMenuAction<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<(T, String)> choices;
  final ValueChanged<T> onSelected;
  final Color accent;
  final String? tooltip;
  const OfficeMenuAction(this.icon, this.label, this.choices, this.onSelected, {super.key, this.accent = const Color(0xFF4A148C), this.tooltip});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip ?? label,
      onSelected: onSelected,
      itemBuilder: (_) => [for (final c in choices) PopupMenuItem<T>(value: c.$1, height: 36, child: Text(c.$2, style: const TextStyle(fontSize: 13)))],
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(color: AppPalette.bg(Colors.white), border: Border.all(color: AppPalette.line(Colors.grey.shade200)), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: AppPalette.fg(accent)),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.merriweather(fontSize: 10, fontWeight: FontWeight.bold)),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
      ),
    );
  }
}

/// A small divider between groups of ribbon cards.
class OfficeRibbonGap extends StatelessWidget {
  const OfficeRibbonGap({super.key});
  @override
  Widget build(BuildContext context) => const VerticalDivider(width: 14, indent: 4, endIndent: 4);
}

// ---------------------------------------------------------------------------
// Fine-scroll arrows (beside / below the page)
// ---------------------------------------------------------------------------
class OfficeScrollArrows extends StatelessWidget {
  final Axis axis;
  final VoidCallback onBack;
  final VoidCallback onForward;
  /// When given, the track shows where you are.
  final ScrollController? controller;
  final double leadingGap;
  const OfficeScrollArrows({super.key, required this.axis, required this.onBack, required this.onForward, this.controller, this.leadingGap = 0});

  factory OfficeScrollArrows.of(ScrollController c, Axis axis, {double step = 100, double leadingGap = 0}) {
    void by(double d) {
      if (!c.hasClients) return;
      final p = c.position;
      c.animateTo((c.offset + d).clamp(p.minScrollExtent, p.maxScrollExtent), duration: const Duration(milliseconds: 90), curve: Curves.easeOut);
    }

    return OfficeScrollArrows(axis: axis, onBack: () => by(-step), onForward: () => by(step), controller: c, leadingGap: leadingGap);
  }

  @override
  Widget build(BuildContext context) {
    final v = axis == Axis.vertical;
    Widget track = LayoutBuilder(builder: (context, box) {
      final len = v ? box.maxHeight : box.maxWidth;
      final base = Container(
        width: v ? 12 : null,
        height: v ? null : 12,
        decoration: BoxDecoration(color: AppPalette.bg(Colors.grey[300]), borderRadius: BorderRadius.circular(5)),
      );
      final c = controller;
      if (c == null) return base;
      return AnimatedBuilder(
        animation: c,
        builder: (context, child) {
          if (!c.hasClients || !c.position.hasContentDimensions || c.position.maxScrollExtent <= 0) return base;
          final p = c.position;
          final frac = (p.viewportDimension / (p.maxScrollExtent + p.viewportDimension)).clamp(0.08, 1.0);
          final thumb = len * frac;
          final pos = (len - thumb) * (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
          return Stack(children: [
            Positioned.fill(child: base),
            Positioned(
              left: v ? 0 : pos,
              top: v ? pos : 0,
              width: v ? 12 : thumb,
              height: v ? thumb : 12,
              child: Container(decoration: BoxDecoration(color: AppPalette.bg(Colors.grey[500]), borderRadius: BorderRadius.circular(5))),
            ),
          ]);
        },
      );
    });
    final back = InkWell(onTap: onBack, child: Icon(v ? Icons.arrow_drop_up : Icons.arrow_left, size: 16));
    final fwd = InkWell(onTap: onForward, child: Icon(v ? Icons.arrow_drop_down : Icons.arrow_right, size: 16));
    if (v) {
      return Container(
        width: 18,
        color: AppPalette.bg(Colors.grey[100]),
        child: Column(children: [back, Expanded(child: Center(child: track)), fwd]),
      );
    }
    return Container(
      height: 18,
      color: AppPalette.bg(Colors.grey[100]),
      child: Row(children: [SizedBox(width: leadingGap), back, Expanded(child: Center(child: track)), fwd, const SizedBox(width: 18)]),
    );
  }
}

// ---------------------------------------------------------------------------
// Status bar pieces
// ---------------------------------------------------------------------------
class OfficeZoomPill extends StatelessWidget {
  final double zoom;
  final double min, max, step;
  final ValueChanged<double> onChanged;
  final String? label; // e.g. "Fit"
  final VoidCallback? onReset;
  const OfficeZoomPill({super.key, required this.zoom, required this.onChanged, this.min = 0.5, this.max = 2.0, this.step = 0.1, this.label, this.onReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppPalette.bg(const Color(0xFFF3E5F5)), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(onTap: () => onChanged((zoom - step).clamp(min, max).toDouble()), child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.remove, size: 14))),
        const SizedBox(width: 4),
        InkWell(
          onTap: onReset,
          child: Text(label ?? "${(zoom * 100).round()}%", style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 4),
        InkWell(onTap: () => onChanged((zoom + step).clamp(min, max).toDouble()), child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.add, size: 14))),
      ]),
    );
  }
}

class OfficeViewIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  const OfficeViewIcon(this.icon, this.tooltip, this.selected, this.onTap, {super.key, this.accent = Colors.blue});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(icon, size: 17, color: AppPalette.fg(selected ? accent : Colors.black54)),
          ),
        ),
      );
}

class OfficeRulerPainter extends CustomPainter {
  final Color color;
  OfficeRulerPainter({this.color = Colors.grey});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 15) {
      canvas.drawLine(Offset(i, 0), Offset(i, i % 45 == 0 ? 7 : 3), p);
    }
  }

  @override
  bool shouldRepaint(covariant OfficeRulerPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Small dialogs shared by the three apps
// ---------------------------------------------------------------------------
Future<String?> officeAsk(BuildContext context, String title, String initial, {String ok = "OK", String? hint}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(border: const OutlineInputBorder(), hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

Future<bool> officeConfirm(BuildContext context, String title, String body, {String ok = "Delete"}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok, style: TextStyle(color: AppPalette.fg(Colors.red.shade700)))),
      ],
    ),
  );
  return r == true;
}

/// "Saved / Saving… / Unsaved / Not saved" for a save state string.
(String, IconData, Color) officeSaveStatus(String state) => switch (state) {
      'saving' => ('Saving…', Icons.cloud_sync_outlined, Colors.blueGrey),
      'unsaved' => ('Unsaved changes', Icons.edit_note_rounded, Colors.orange.shade800),
      'error' => ('Not saved, retry', Icons.cloud_off_rounded, Colors.red.shade700),
      _ => ('Saved', Icons.cloud_done_outlined, Colors.green.shade700),
    };
