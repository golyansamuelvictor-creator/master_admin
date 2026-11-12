import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool _installed = false;

/// Web: no right-click menu, no Ctrl+P / Ctrl+S / Ctrl+Shift+S, the
/// browser's own print gives a blank page, and the page blurs while the app
/// is not in front (switching window, most snipping tools, PrtSc on Windows).
void installWebGuards() {
  if (_installed) return;
  _installed = true;
  try {
    final doc = globalContext.getProperty<JSObject>('document'.toJS);
    final win = globalContext;

    // styles: blank print + blur class
    final style = doc.callMethod<JSObject>('createElement'.toJS, 'style'.toJS);
    style.setProperty(
        'textContent'.toJS,
        ('@media print { html, body { display: none !important; } } '
                'body.ma-shield flt-glass-pane, body.ma-shield flutter-view { filter: blur(18px) !important; } '
                'body { -webkit-user-select: none; user-select: none; } '
                'input, textarea, [contenteditable="true"] { -webkit-user-select: text; user-select: text; }')
            .toJS);
    doc.getProperty<JSObject>('head'.toJS).callMethod('appendChild'.toJS, style);

    void on(JSObject target, String type, void Function(JSObject e) f) {
      target.callMethod('addEventListener'.toJS, type.toJS, ((JSObject e) => f(e)).toJS, true.toJS);
    }

    on(doc, 'contextmenu', (e) => e.callMethod('preventDefault'.toJS));
    on(doc, 'keydown', (e) {
      final key = (e.getProperty<JSString?>('key'.toJS)?.toDart ?? '').toLowerCase();
      final ctrl = (e.getProperty<JSBoolean?>('ctrlKey'.toJS)?.toDart ?? false) || (e.getProperty<JSBoolean?>('metaKey'.toJS)?.toDart ?? false);
      if ((ctrl && (key == 'p' || key == 's')) || key == 'printscreen') {
        // stops the browser's print / save page; the app still gets the
        // keys (Ctrl+S saves a document, Ctrl+P opens the app's own print)
        e.callMethod('preventDefault'.toJS);
      }
      if (key == 'printscreen') {
        _shield(doc, true);
        // PrtSc copies the screen: overwrite the clipboard
        try {
          final nav = win.getProperty<JSObject>('navigator'.toJS);
          nav.getProperty<JSObject>('clipboard'.toJS).callMethod('writeText'.toJS, ''.toJS);
        } catch (_) {}
      }
    });
    on(doc, 'keyup', (e) {
      final key = (e.getProperty<JSString?>('key'.toJS)?.toDart ?? '').toLowerCase();
      if (key == 'printscreen') {
        try {
          final nav = win.getProperty<JSObject>('navigator'.toJS);
          nav.getProperty<JSObject>('clipboard'.toJS).callMethod('writeText'.toJS, ''.toJS);
        } catch (_) {}
      }
    });
    on(win, 'blur', (_) => _shield(doc, true));
    on(win, 'focus', (_) => _shield(doc, false));
    on(doc, 'visibilitychange', (_) {
      final hidden = doc.getProperty<JSBoolean?>('hidden'.toJS)?.toDart ?? false;
      _shield(doc, hidden);
    });
    on(win, 'beforeprint', (_) => _shield(doc, true));
    on(win, 'afterprint', (_) => _shield(doc, false));
  } catch (_) {}
}

void _shield(JSObject doc, bool on) {
  try {
    final body = doc.getProperty<JSObject>('body'.toJS);
    body.getProperty<JSObject>('classList'.toJS).callMethod((on ? 'add' : 'remove').toJS, 'ma-shield'.toJS);
  } catch (_) {}
}
