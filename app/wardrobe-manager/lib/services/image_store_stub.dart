import 'dart:typed_data';

/// Web 环境的空实现：不落盘，调用方应改用 base64 或提示用户用 App。
class ImageStore {
  static final ImageStore instance = ImageStore._();

  ImageStore._();

  bool get available => false;

  Future<String?> saveBytes(Uint8List bytes,
          {String prefix = 'img', String ext = 'jpg'}) async =>
      null;

  Future<String?> importFile(String sourcePath) async => null;

  Future<void> deleteQuietly(String? path) async {}

  Future<int> usageBytes() async => 0;
}
