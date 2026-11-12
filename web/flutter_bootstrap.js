{{flutter_js}}
{{flutter_build_config}}

// Flutter's own service worker is not used: web/ma_sw.js (registered in
// index.html) keeps pictures, fonts and sounds on the device and lets the app
// open without a connection, while app updates still arrive at once.
_flutter.loader.load();
