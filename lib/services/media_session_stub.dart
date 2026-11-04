/// Phone media controls (notification bar / lock screen): web only.
void updateMediaSession({
  required String title,
  String? artist,
  String? artwork,
  required bool playing,
  required void Function() onPlay,
  required void Function() onPause,
  required void Function() onNext,
  required void Function() onPrevious,
}) {}

void clearMediaSession() {}
