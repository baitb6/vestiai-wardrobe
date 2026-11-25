import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import 'image_usage.dart';

/// 图片仓库维护：统计占用、找孤儿、批量压缩。
///
/// 孤儿 = 目录里存在、但没有任何衣物 / 拆分任务引用的文件。
/// 只做「用户点一下才执行」的清理，绝不自动删，避免误删正在确认中的草稿。
class ImageMaintenance {
  const ImageMaintenance._();

  static Future<Directory?> _dir() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'wardrobe_images'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (e) {
      debugPrint('图片仓库目录不可用：$e');
      return null;
    }
  }

  /// 扫描仓库。[referenced] 是所有 Hive 里出现过的绝对路径。
  ///
  /// [minAge] 内的新文件不算孤儿：刚生成的裁片可能还在确认页里，
  /// 此时 Hive 里没有引用，但删掉用户就没法入库了。
  static Future<ImageUsage?> scan(
    Set<String> referenced, {
    Duration minAge = const Duration(hours: 24),
  }) async {
    final dir = await _dir();
    if (dir == null) return null;

    final cutoff = DateTime.now().subtract(minAge);
    final files = <StoredImage>[];
    final orphans = <StoredImage>[];
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final FileStat stat;
        try {
          stat = await e.stat();
        } catch (err) {
          // 单个文件 stat 失败（刚被删/权限问题）：跳过，不让整个扫描报废
          debugPrint('扫描时读取文件信息失败，跳过：${e.path} ($err)');
          continue;
        }
        final item = StoredImage(
          path: e.path,
          name: p.basename(e.path),
          bytes: stat.size,
          modified: stat.modified,
        );
        files.add(item);
        if (!referenced.contains(e.path) && stat.modified.isBefore(cutoff)) {
          orphans.add(item);
        }
      }
    } catch (e) {
      debugPrint('图片仓库扫描失败：$e');
      return null;
    }
    files.sort((a, b) => b.modified.compareTo(a.modified));
    orphans.sort((a, b) => b.bytes.compareTo(a.bytes));
    return ImageUsage(files: files, orphans: orphans);
  }

  /// 删除孤儿文件，返回释放的字节数
  static Future<int> deleteOrphans(List<StoredImage> orphans) async {
    var freed = 0;
    for (final o in orphans) {
      try {
        final f = File(o.path);
        if (await f.exists()) {
          await f.delete();
          freed += o.bytes;
        }
      } catch (e) {
        // 单个删不掉不影响其他
        debugPrint('孤儿图删除失败：${o.path} ($e)');
      }
    }
    return freed;
  }

  /// 压缩仓库里的大图，返回释放的字节数。
  /// 只处理被引用的文件；先写临时文件再替换，避免压缩失败把原图弄坏。
  static Future<int> compress(
    Set<String> referenced, {
    int maxSide = 1400,
    int jpegQuality = 82,
    int threshold = 400 * 1024,
  }) async {
    final dir = await _dir();
    if (dir == null) return 0;

    var freed = 0;
    for (final path in referenced) {
      try {
        final f = File(path);
        if (!await f.exists()) continue;
        if (!p.equals(p.dirname(path), dir.path)) continue;
        final size = await f.length();
        if (size <= threshold) continue;

        final ext = p.extension(path).toLowerCase();
        final bytes = await f.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;

        final longest =
            decoded.width > decoded.height ? decoded.width : decoded.height;
        var out = decoded;
        if (longest > maxSide) {
          out = img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxSide : null,
            height: decoded.height > decoded.width ? maxSide : null,
            interpolation: img.Interpolation.average,
          );
        }

        // 透明图保持 PNG，否则一律转 JPEG
        final keepAlpha = (ext == '.png') && decoded.hasAlpha;
        final encoded = keepAlpha
            ? Uint8List.fromList(img.encodePng(out, level: 6))
            : Uint8List.fromList(img.encodeJpg(out, quality: jpegQuality));

        if (encoded.length >= size) continue;

        final tmp = File('${path}.tmp');
        await tmp.writeAsBytes(encoded, flush: true);
        await tmp.rename(path);
        freed += size - encoded.length;
      } catch (e) {
        // 单个文件失败不影响其他文件；把可能残留的 .tmp 清掉，
        // 否则它会作为孤儿躺 24 小时才被清
        try {
          final tmp = File('${path}.tmp');
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        debugPrint('压缩单张图片失败，已跳过：$path ($e)');
      }
    }
    return freed;
  }
}
