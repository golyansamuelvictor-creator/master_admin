import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The phone's media controls for the song playing in the background: the
/// title, artist and picture with play / pause / next / previous in the
/// notification bar and on the lock screen (the browser's Media Session).
void updateMediaSession({
  required String title,
  String? artist,
  String? artwork,
  required bool playing,
  required void Function() onPlay,
  required void Function() onPause,
  required void Function() onNext,
  required void Function() onPrevious,
}) {
  try {
    final nav = globalContext.getProperty<JSObject>('navigator'.toJS);
    if (!nav.has('mediaSession')) return;
    final ms = nav.getProperty<JSObject>('mediaSession'.toJS);
    if (globalContext.has('MediaMetadata')) {
      final init = JSObject();
      init.setProperty('title'.toJS, title.toJS);
      init.setProperty('artist'.toJS, (artist == null || artist.isEmpty ? 'Master Admin' : artist).toJS);
      init.setProperty('album'.toJS, 'Media Hub'.toJS);
      if (artwork != null && artwork.isNotEmpty) {
        final a = JSObject();
        a.setProperty('src'.toJS, artwork.toJS);
        a.setProperty('sizes'.toJS, '512x512'.toJS);
        init.setProperty('artwork'.toJS, <JSObject>[a].toJS);
      }
      final ctor = globalContext.getProperty<JSFunction>('MediaMetadata'.toJS);
      ms.setProperty('metadata'.toJS, ctor.callAsConstructor<JSObject>(init));
    }
    ms.setProperty('playbackState'.toJS, (playing ? 'playing' : 'paused').toJS);
    void handle(String action, void Function() f) {
      try {
        ms.callMethod('setActionHandler'.toJS, action.toJS, (() => f()).toJS);
      } catch (_) {}
    }
    handle('play', onPlay);
    handle('pause', onPause);
    handle('nexttrack', onNext);
    handle('previoustrack', onPrevious);
  } catch (_) {}
}

void clearMediaSession() {
  try {
    final nav = globalContext.getProperty<JSObject>('navigator'.toJS);
    if (!nav.has('mediaSession')) return;
    final ms = nav.getProperty<JSObject>('mediaSession'.toJS);
    ms.setProperty('metadata'.toJS, null);
    ms.setProperty('playbackState'.toJS, 'none'.toJS);
  } catch (_) {}
}
