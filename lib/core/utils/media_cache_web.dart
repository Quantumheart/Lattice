import 'dart:typed_data';

class File {
  File(this.path);
  final String path;
  bool existsSync() => false;
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  Future<File> writeAsBytes(List<int> bytes) async => this;
  Future<void> delete() async {}
  void deleteSync() {}
}
