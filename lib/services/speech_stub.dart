/// Reading text aloud (the browser's speech; not available here).
bool get speechAvailable => false;
void speak(List<String> parts, {double rate = 1.0, void Function(int index)? onPart, void Function()? onDone}) {}
void stopSpeaking() {}
void pauseSpeaking() {}
void resumeSpeaking() {}
