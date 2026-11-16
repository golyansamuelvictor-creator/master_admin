import 'package:flutter/foundation.dart';

import 'offline.dart';

/// The end of an error message members can act on, without technical
/// details: "Couldn't load. Check your internet connection and refresh."
/// The real error goes to the console for the developer.
String friendlyTail(Object? e) {
  if (e == null) return ". Please refresh and try again.";
  debugPrint("Error: $e");
  final s = e.toString().toLowerCase();
  if (isNetworkError(e) || s.contains('timeout') || s.contains('network') || s.contains('connection')) {
    return ". Check your internet connection and refresh.";
  }
  if (s.contains('42501') || s.contains('permission denied') || s.contains('not allowed') || s.contains('row-level security')) {
    return ". Your account doesn't have access to this.";
  }
  return ". Check your internet connection and refresh. If it keeps happening, tell your administrator.";
}
