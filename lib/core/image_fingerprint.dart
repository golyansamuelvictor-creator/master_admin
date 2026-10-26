import 'dart:typed_data';
import 'dart:ui' as ui;

/// A photo's visual fingerprint (a 64-bit "difference hash").
///
/// Two photos of the same picture give nearly the same fingerprint even when
/// one was resized, recompressed, screenshotted, brightened or lightly
/// cropped, so a reused evidence photo can be spotted without comparing the
/// images themselves. The number of differing bits ([distance]) says how
/// alike they are: 0–8 is the same picture, above ~20 is a different one.
class ImageFingerprint {
  final String hash; // 16 hex characters
  final String mirrorHash; // the same photo flipped left-right
  final Uint8List? thumbnailPng; // small copy (longest side ~480 px)
  final int width;
  final int height;

  const ImageFingerprint({
    required this.hash,
    required this.mirrorHash,
    required this.thumbnailPng,
    required this.width,
    required this.height,
  });

  /// Returns null when the bytes are not a readable image.
  static Future<ImageFingerprint?> compute(Uint8List bytes, {int thumbSide = 480}) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;

      // 1. Fingerprint: shrink to 72 x 64, average into a 9 x 8 grey grid
      final small = await _decode(descriptor, 72, 64);
      final grey = _greyGrid(small, 72, 64, 9, 8);
      final hash = _dHash(grey, mirror: false);
      final mirrorHash = _dHash(grey, mirror: true);

      // 2. Thumbnail for previews and the AI check
      Uint8List? thumb;
      try {
        final scale = thumbSide / (w > h ? w : h);
        final tw = scale < 1 ? (w * scale).round() : w;
        final th = scale < 1 ? (h * scale).round() : h;
        final codec = await descriptor.instantiateCodec(targetWidth: tw, targetHeight: th);
        final frame = await codec.getNextFrame();
        final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        codec.dispose();
        thumb = png?.buffer.asUint8List();
      } catch (_) {
        thumb = null;
      }

      return ImageFingerprint(hash: hash, mirrorHash: mirrorHash, thumbnailPng: thumb, width: w, height: h);
    } catch (_) {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static Future<Uint8List> _decode(ui.ImageDescriptor d, int w, int h) async {
    final codec = await d.instantiateCodec(targetWidth: w, targetHeight: h);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    return data!.buffer.asUint8List();
  }

  /// Average brightness of each cell of a [cols] x [rows] grid.
  static List<List<double>> _greyGrid(Uint8List rgba, int w, int h, int cols, int rows) {
    final cw = w ~/ cols;
    final ch = h ~/ rows;
    return List.generate(rows, (r) {
      return List.generate(cols, (c) {
        double sum = 0;
        int n = 0;
        for (int y = r * ch; y < (r + 1) * ch; y++) {
          for (int x = c * cw; x < (c + 1) * cw; x++) {
            final i = (y * w + x) * 4;
            sum += 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
            n++;
          }
        }
        return n == 0 ? 0 : sum / n;
      });
    });
  }

  /// 64 bits: is each cell brighter than its right-hand neighbour?
  /// Built as two 32-bit halves so it is exact on the web too.
  static String _dHash(List<List<double>> g, {required bool mirror}) {
    int hi = 0, lo = 0, bit = 0;
    for (int r = 0; r < 8; r++) {
      final row = mirror ? g[r].reversed.toList() : g[r];
      for (int c = 0; c < 8; c++) {
        final b = row[c] > row[c + 1] ? 1 : 0;
        if (bit < 32) {
          hi = hi * 2 + b;
        } else {
          lo = lo * 2 + b;
        }
        bit++;
      }
    }
    return hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');
  }

  /// Number of differing bits between two fingerprints (0–64).
  static int distance(String a, String b) {
    if (a.length != 16 || b.length != 16) return 64;
    int d = 0;
    for (int i = 0; i < 16; i++) {
      int x = (int.tryParse(a[i], radix: 16) ?? 0) ^ (int.tryParse(b[i], radix: 16) ?? 0);
      while (x != 0) {
        d += x & 1;
        x >>= 1;
      }
    }
    return d;
  }
}
