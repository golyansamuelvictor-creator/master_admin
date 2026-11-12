import 'dart:typed_data';

/// Phones and desktop apps: photos are sent as picked (the camera / picker
/// already limits their size).
Future<Uint8List> shrinkPhoto(Uint8List bytes, {int maxSide = 1600, double quality = 0.8}) async => bytes;
