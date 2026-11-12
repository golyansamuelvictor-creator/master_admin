import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Phones and desktop apps: "Save as" with the file's name.
Future<void> saveBytesAs(Uint8List bytes, String fileName, String mime) async {
  await FilePicker.platform.saveFile(dialogTitle: 'Save file', fileName: fileName, bytes: bytes);
}
