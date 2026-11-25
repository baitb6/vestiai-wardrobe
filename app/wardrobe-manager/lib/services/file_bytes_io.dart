import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

Future<Uint8List?> readFileBytes(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  } catch (e) {
    // 返回 null：调用方统一按「文件读不到」走降级（base64 / 报中文错误）
    debugPrint('读取文件失败：$path ($e)');
    return null;
  }
}

Future<bool> fileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (e) {
    debugPrint('检查文件失败：$path ($e)');
    return false;
  }
}
