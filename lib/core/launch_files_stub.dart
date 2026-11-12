import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('ma/launch_files');

/// Android app: Word, PowerPoint, Excel and CSV files opened with
/// "Open with › Master Admin" (MainActivity.kt keeps them until asked).
/// Other platforms: none.
Future<List<(String, Uint8List)>> takeLaunchFiles() async {
  if (defaultTargetPlatform != TargetPlatform.android) return const [];
  try {
    final list = await _channel.invokeListMethod<Map>('takeFiles') ?? const [];
    return [
      for (final m in list)
        if (m['bytes'] is Uint8List) ((m['name'] ?? 'file').toString(), m['bytes'] as Uint8List),
    ];
  } catch (_) {
    return const []; // older app build without the channel
  }
}
