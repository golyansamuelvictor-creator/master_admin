import 'package:flutter/foundation.dart';

/// AuthWrapper listens to this and reloads the signed-in user's profile.
/// Call [requestProfileRefresh] after anything that changes approval state
/// (approval confirmed, SCJ verification finished, etc.).
final ValueNotifier<int> profileRefreshNotifier = ValueNotifier<int>(0);

void requestProfileRefresh() => profileRefreshNotifier.value++;