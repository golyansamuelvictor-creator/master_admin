import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Makes a photo smaller before it is uploaded: the longest side at most
/// [maxSide] pixels, saved as JPEG. A 6 MB phone photo becomes about 300 KB,
/// so it uploads on a slow connection and doesn't freeze the page (the
/// browser does the work, not the app). Returns the original if it can't be
/// read or is already small.
Future<Uint8List> shrinkPhoto(Uint8List bytes, {int maxSide = 1600, double quality = 0.8}) async {
  if (bytes.length < 350 * 1024) return bytes;
  try {
    final blobCtor = globalContext.getProperty<JSFunction>('Blob'.toJS);
    final blob = blobCtor.callAsConstructor<JSObject>([bytes.toJS].toJS);
    final bmp = await globalContext.callMethod<JSPromise<JSObject>>('createImageBitmap'.toJS, blob).toDart;
    final w = bmp.getProperty<JSNumber>('width'.toJS).toDartInt;
    final h = bmp.getProperty<JSNumber>('height'.toJS).toDartInt;
    if (w <= 0 || h <= 0) return bytes;
    final scale = (w > h ? w : h) > maxSide ? maxSide / (w > h ? w : h) : 1.0;
    final tw = (w * scale).round(), th = (h * scale).round();

    final doc = globalContext.getProperty<JSObject>('document'.toJS);
    final canvas = doc.callMethod<JSObject>('createElement'.toJS, 'canvas'.toJS);
    canvas.setProperty('width'.toJS, tw.toJS);
    canvas.setProperty('height'.toJS, th.toJS);
    final ctx = canvas.callMethod<JSObject>('getContext'.toJS, '2d'.toJS);
    ctx.callMethodVarArgs('drawImage'.toJS, [bmp, 0.toJS, 0.toJS, tw.toJS, th.toJS]);
    try {
      bmp.callMethod('close'.toJS);
    } catch (_) {}

    final done = Completer<JSObject?>();
    canvas.callMethod('toBlob'.toJS, ((JSObject? b) => done.complete(b)).toJS, 'image/jpeg'.toJS, quality.toJS);
    final out = await done.future.timeout(const Duration(seconds: 20));
    if (out == null) return bytes;
    final buf = await out.callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS).toDart;
    final res = buf.toDart.asUint8List();
    return res.isNotEmpty && res.length < bytes.length ? res : bytes;
  } catch (_) {
    return bytes;
  }
}
