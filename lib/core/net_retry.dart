import 'dart:async';

/// Runs [task] again when the connection drops (slow or busy networks):
/// up to [tries] times, waiting a little longer each time. Each try may take
/// at most [timeout].
Future<T> withRetry<T>(Future<T> Function() task, {int tries = 3, Duration timeout = const Duration(seconds: 90)}) async {
  Object? last;
  for (int i = 0; i < tries; i++) {
    try {
      return await task().timeout(timeout);
    } catch (e) {
      last = e;
      final text = e.toString().toLowerCase();
      // a refusal (permission, duplicate, bad file) won't change by trying again
      final refused = text.contains('403') || text.contains('401') || text.contains('409') ||
          text.contains('not allowed') || text.contains('duplicate') || text.contains('too large') || text.contains('413');
      if (refused || i == tries - 1) break;
      await Future<void>.delayed(Duration(seconds: 2 * (i + 1)));
    }
  }
  throw last ?? Exception('Failed');
}
