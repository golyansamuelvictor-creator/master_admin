import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Reading text aloud with the browser's (phone's) voice: Web Speech API.
bool get speechAvailable => globalContext.has('speechSynthesis') && globalContext.has('SpeechSynthesisUtterance');

JSObject? get _synth => speechAvailable ? globalContext.getProperty<JSObject>('speechSynthesis'.toJS) : null;

/// Speaks [parts] one after the other (e.g. the verses of a chapter);
/// [onPart] tells which one is being read, [onDone] when all are read.
void speak(List<String> parts, {double rate = 1.0, void Function(int index)? onPart, void Function()? onDone}) {
  final s = _synth;
  if (s == null) return;
  try {
    s.callMethod('cancel'.toJS);
    final ctor = globalContext.getProperty<JSFunction>('SpeechSynthesisUtterance'.toJS);
    for (int i = 0; i < parts.length; i++) {
      final u = ctor.callAsConstructor<JSObject>(parts[i].toJS);
      u.setProperty('rate'.toJS, rate.toJS);
      u.setProperty('lang'.toJS, 'en-US'.toJS);
      final idx = i;
      u.setProperty('onstart'.toJS, ((JSAny? _) {
        onPart?.call(idx);
      }).toJS);
      if (i == parts.length - 1) {
        u.setProperty('onend'.toJS, ((JSAny? _) {
          onDone?.call();
        }).toJS);
      }
      s.callMethod('speak'.toJS, u);
    }
  } catch (_) {}
}

void stopSpeaking() {
  try {
    _synth?.callMethod('cancel'.toJS);
  } catch (_) {}
}

void pauseSpeaking() {
  try {
    _synth?.callMethod('pause'.toJS);
  } catch (_) {}
}

void resumeSpeaking() {
  try {
    _synth?.callMethod('resume'.toJS);
  } catch (_) {}
}
