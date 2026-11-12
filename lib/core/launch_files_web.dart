import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Desktop app (installed from Chrome / Edge): Word, PowerPoint and Excel
/// files opened with "Open with › Master Admin" (index.html keeps them in
/// window.__maOpenFiles). Each file is handed over once.
Future<List<(String, Uint8List)>> takeLaunchFiles() async {
  final out = <(String, Uint8List)>[];
  try {
    final list = globalContext.getProperty<JSArray<JSObject>?>('__maOpenFiles'.toJS);
    if (list == null) return out;
    for (final f in list.toDart) {
      final name = f.getProperty<JSString>('name'.toJS).toDart;
      final data = f.getProperty<JSUint8Array>('data'.toJS).toDart;
      out.add((name, data));
    }
    globalContext.setProperty('__maOpenFiles'.toJS, <JSObject>[].toJS);
  } catch (_) {}
  return out;
}
