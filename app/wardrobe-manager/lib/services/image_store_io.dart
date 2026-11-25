import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// 图片文件仓库：所有 AI 拆分产生的原图 / 裁片 / 抠图都存在这里，
/// Hive 只记路径，避免把几十 MB base64 塞进数据库。
class ImageStore {
  static final ImageStore instance = ImageStore._();

  ImageStore._();

  Directory? _root;

  /// 最近一次目录初始化是否失败（失败不永久锁死，下次调用会重试）
  bool _failed = false;

  bool get available => !_failed;

  Future<Directory?> _dir() async {
    if (_root != null) return _root;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'wardrobe_images'));
      if (!await dir.exists()) await dir.create(recursive: true);
      _failed = false;
      return _root = dir;
    } catch (e) {
      // 不做永久锁死：一次瞬时失败（启动竞态等）不应让整个仓库本次运行全废
      debugPrint('图片仓库目录初始化失败，稍后会重试：$e');
      _failed = true;
      return null;
    }
  }

  String _name(String prefix, String ext) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final rand = (ts % 9973).toString().padLeft(4, '0');
    return '${prefix}_${ts}_$rand.$ext';
  }

  /// 写入字节，返回绝对路径；失败返回 null（调用方按「图片缺失」处理）
  Future<String?> saveBytes(Uint8List bytes,
      {String prefix = 'img', String ext = 'jpg'}) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final file = File(p.join(dir.path, _name(prefix, ext)));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('图片写入失败（$prefix）：$e');
      return null;
    }
  }

  /// 把外部照片（相册/相机）复制进仓库，返回新路径
  Future<String?> importFile(String sourcePath) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;
      final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
      final target = p.join(
          dir.path, _name('photo', ext.isEmpty ? 'jpg' : ext));
      await src.copy(target);
      return target;
    } catch (e) {
      debugPrint('图片导入失败：$sourcePath ($e)');
      return null;
    }
  }

  Future<void> deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('图片删除失败（忽略）：$path ($e)');
    }
  }

  /// 目录占用（备份页展示）
  Future<int> usageBytes() async {
    final dir = await _dir();
    if (dir == null) return 0;
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true)) {
        if (e is File) {
          total += await e.length();
        }
      }
    } catch (e) {
      // 统计失败不致命，返回已累计的部分
      debugPrint('图片占用统计中断（返回部分结果）：$e');
    }
    return total;
  }

  /// 仓库目录（备份/清理用）
  Future<String?> rootPath() async => (await _dir())?.path;
}
