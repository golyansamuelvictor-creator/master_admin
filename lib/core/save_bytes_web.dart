import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Web: the browser downloads the file.
Future<void> saveBytesAs(Uint8List bytes, String fileName, String mime) async {
  final blobCtor = globalContext.getProperty<JSFunction>('Blob'.toJS);
  final opts = JSObject()..setProperty('type'.toJS, mime.toJS);
  final blob = blobCtor.callAsConstructor<JSObject>([bytes.toJS].toJS, opts);
  final urlApi = globalContext.getProperty<JSObject>('URL'.toJS);
  final url = urlApi.callMethod<JSString>('createObjectURL'.toJS, blob);
  final doc = globalContext.getProperty<JSObject>('document'.toJS);
  final a = doc.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
  a.setProperty('href'.toJS, url);
  a.setProperty('download'.toJS, fileName.toJS);
  doc.getProperty<JSObject>('body'.toJS).callMethod('appendChild'.toJS, a);
  a.callMethod('click'.toJS);
  a.callMethod('remove'.toJS);
  Future<void>.delayed(const Duration(seconds: 30), () => urlApi.callMethod('revokeObjectURL'.toJS, url));
}
