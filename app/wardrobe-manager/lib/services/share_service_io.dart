import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';

/// 分享卡导出：PNG 落到临时目录，再交给系统分享面板
class ShareService {
  const ShareService._();

  static bool get available => true;

  /// 返回保存路径；调用方可用于提示「已保存到…」
  static Future<String?> sharePng(
    Uint8List bytes, {
    required String fileName,
    String? text,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final outDir = Directory(p.join(dir.path, 'wardrobe_share'));
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final file = File(p.join(outDir.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: text);
      return file.path;
    } catch (e) {
      // 返回 null：调用方按「分享失败」提示，不让导出页崩
      debugPrint('分享卡导出失败：$e');
      return null;
    }
  }
}
