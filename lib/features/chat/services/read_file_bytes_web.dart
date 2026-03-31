import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<Uint8List> readFileBytes(String path) async {
  final response = await http.get(Uri.parse(path));
  return response.bodyBytes;
}

Future<void> deleteFile(String path) async {}
