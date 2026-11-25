import 'dart:math' as math;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/bbox.dart';

/// 抠图结果
class CutoutResult {
  /// 输出图（抠图成功是透明 PNG；失败是裁剪图）
  final Uint8List bytes;

  /// true = 背景已去除
  final bool transparent;

  /// 失败原因（给用户看的一句话）
  final String? note;

  const CutoutResult({
    required this.bytes,
    required this.transparent,
    this.note,
  });
}

/// 可插拔抠图服务：MVP 用本地边缘泛洪，后续可替换 rembg / SAM / 分割 API，
/// 页面与 Hive 都不用改。
abstract class CutoutService {
  Future<CutoutResult> process(Uint8List source, BBox box);
}

/// 本地实现：先按 bbox 裁剪，再从边缘做颜色泛洪去背景。
///
/// 对「浅色纯背景 / 白墙 / 平铺拍摄」效果可以；背景复杂时主动放弃，
/// 直接返回裁剪图并标记 transparent=false（页面提示可重试）。
class LocalEdgeCutoutService implements CutoutService {
  /// 背景色容差（0-255 的加权 RGB 距离）
  final int tolerance;

  const LocalEdgeCutoutService({this.tolerance = 42});

  @override
  Future<CutoutResult> process(Uint8List source, BBox box) async {
    try {
      // 大图解码 + BFS 泛洪 + PNG 编码是纯 CPU 重活，放后台 isolate 跑，
      // 否则拆衣页会整帧卡住（AI 拆衣「应用卡死」的主因）。
      // 再加一道超时，极端图片也不会让任务永远停在「生成中」。
      // 闭包只允许捕获 tol/source/box 纯数据，绝不捕获 this：
      // Service 将来挂上流/客户端/Box 之类的字段，真机会直接抛
      // object is unsendable（这类错误无法静态发现，只能按模式防御）。
      final tol = tolerance;
      return await Isolate.run(
        () => LocalEdgeCutoutService(tolerance: tol)._process(source, box),
      ).timeout(const Duration(seconds: 25));
    } catch (e) {
      // 解码 / 裁剪 / 编码 / isolate 超时，都退回原图（README 承诺）
      print('抠图处理异常，已退回原图：$e');
      return CutoutResult(
        bytes: source,
        transparent: false,
        note: '抠图处理超时或失败，已保留原图',
      );
    }
  }

  CutoutResult _process(Uint8List source, BBox box) {
    final decoded = img.decodeImage(source);
    if (decoded == null) {
      return CutoutResult(
        bytes: source,
        transparent: false,
        note: '图片解码失败，已保留原图',
      );
    }

    // JPEG 解出来是 3 通道，没有 alpha 通道就写不进透明度
    final cropped = _crop(decoded, box).convert(numChannels: 4);
    final bounded = _resizeIfNeeded(cropped);

    final bg = _estimateBackground(bounded);
    if (bg == null) {
      return CutoutResult(
        bytes: Uint8List.fromList(img.encodeJpg(bounded, quality: 88)),
        transparent: false,
        note: '背景太杂，先按矩形裁片入库',
      );
    }

    final removed = _floodRemoveBackground(bounded, bg, tolerance);
    final ratio = removed / (bounded.width * bounded.height);

    // 去掉太少 = 没找到背景；去掉太多 = 把衣服也吃了，都判失败
    if (ratio < 0.04 || ratio > 0.92) {
      return CutoutResult(
        bytes: Uint8List.fromList(img.encodeJpg(bounded, quality: 88)),
        transparent: false,
        note: ratio < 0.04 ? '背景不纯，先按矩形裁片入库' : '主体识别不清，先按矩形裁片入库',
      );
    }

    return CutoutResult(
      bytes: Uint8List.fromList(img.encodePng(bounded, level: 6)),
      transparent: true,
    );
  }

  img.Image _crop(img.Image src, BBox box) {
    final b = box.clamped;
    // 外扩 1.5%，避免抠图时把衣物边缘切掉
    const pad = 0.015;
    final x = ((b.x - pad) * src.width).clamp(0, src.width - 2).toInt();
    final y = ((b.y - pad) * src.height).clamp(0, src.height - 2).toInt();
    final w = math.max(4, (b.w * src.width).round());
    final h = math.max(4, (b.h * src.height).round());
    return img.copyCrop(
      src,
      x: x,
      y: y,
      width: math.min(w, src.width - x),
      height: math.min(h, src.height - y),
    );
  }

  img.Image _resizeIfNeeded(img.Image im) {
    final longest = math.max(im.width, im.height);
    if (longest <= 1000) return im;
    final scale = 1000 / longest;
    return img.copyResize(
      im,
      width: (im.width * scale).round(),
      height: (im.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  /// 四边采样估计背景色；差异过大返回 null（说明不是纯色背景）
  List<int>? _estimateBackground(img.Image im) {
    final samples = <List<int>>[];
    final stepX = math.max(1, im.width ~/ 24);
    final stepY = math.max(1, im.height ~/ 24);
    for (var x = 0; x < im.width; x += stepX) {
      samples.add(_rgb(im, x, 0));
      samples.add(_rgb(im, x, im.height - 1));
    }
    for (var y = 0; y < im.height; y += stepY) {
      samples.add(_rgb(im, 0, y));
      samples.add(_rgb(im, im.width - 1, y));
    }
    if (samples.isEmpty) return null;

    final mean = <int>[0, 0, 0];
    for (final s in samples) {
      mean[0] += s[0];
      mean[1] += s[1];
      mean[2] += s[2];
    }
    for (var i = 0; i < 3; i++) {
      mean[i] = (mean[i] / samples.length).round();
    }

    var variance = 0.0;
    for (final s in samples) {
      final d = _distance(s, mean);
      variance += d * d;
    }
    variance /= samples.length;

    // 边缘颜色标准差 > 55 视为背景复杂
    if (math.sqrt(variance) > 55) return null;
    return mean;
  }

  /// 从四边泛洪，把与背景色接近的连通区域设为透明，返回移除像素数
  int _floodRemoveBackground(img.Image im, List<int> bg, int tol) {
    final w = im.width;
    final h = im.height;
    final visited = Uint8List(w * h);
    final queue = <int>[];
    void seed(int x, int y) {
      final idx = y * w + x;
      if (visited[idx] == 1) return;
      if (_distance(_rgb(im, x, y), bg) > tol) return;
      visited[idx] = 1;
      queue.add(idx);
    }

    for (var x = 0; x < w; x++) {
      seed(x, 0);
      seed(x, h - 1);
    }
    for (var y = 0; y < h; y++) {
      seed(0, y);
      seed(w - 1, y);
    }

    var removed = 0;
    var head = 0;
    while (head < queue.length) {
      final idx = queue[head++];
      final x = idx % w;
      final y = idx ~/ w;
      final px = im.getPixel(x, y);
      im.setPixelRgba(x, y, px.r, px.g, px.b, 0);
      removed++;

      if (x > 0) _tryPush(im, visited, queue, bg, tol, x - 1, y, w);
      if (x < w - 1) _tryPush(im, visited, queue, bg, tol, x + 1, y, w);
      if (y > 0) _tryPush(im, visited, queue, bg, tol, x, y - 1, w);
      if (y < h - 1) _tryPush(im, visited, queue, bg, tol, x, y + 1, w);
    }
    return removed;
  }

  void _tryPush(img.Image im, Uint8List visited, List<int> queue,
      List<int> bg, int tol, int x, int y, int w) {
    final idx = y * w + x;
    if (visited[idx] == 1) return;
    visited[idx] = 1;
    if (_distance(_rgb(im, x, y), bg) <= tol) {
      queue.add(idx);
    }
  }

  List<int> _rgb(img.Image im, int x, int y) {
    final p = im.getPixel(x, y);
    return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
  }

  double _distance(List<int> a, List<int> b) {
    final dr = (a[0] - b[0]).toDouble();
    final dg = (a[1] - b[1]).toDouble();
    final db = (a[2] - b[2]).toDouble();
    return math.sqrt(dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11);
  }
}
