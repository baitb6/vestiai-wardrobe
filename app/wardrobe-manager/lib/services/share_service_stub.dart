import 'dart:typed_data';

/// Web 版没有临时目录，分享卡改为提示用户截图保存
class ShareService {
  const ShareService._();

  static bool get available => false;

  static Future<String?> sharePng(
    Uint8List bytes, {
    required String fileName,
    String? text,
  }) async =>
      null;
}
