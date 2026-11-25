import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/bbox.dart';
import 'cutout_service.dart';

/// 本地白底商品图：先尝试去背景，再合成纯白画布。
///
/// 完全不联网，照片不出手机。失败自动退回「原图居中 + 白底」，
/// 保证「添加衣物」这个主流程永远不会因为美化失败而卡住。
class LocalWhiteBackground {
  const LocalWhiteBackground();

  static const int _canvas = 1024;
  static const int _padding = 64;

  Future<Uint8List> build(Uint8List source) async {
    final cut = await LocalEdgeCutoutService().process(source, BBox.empty);
    return Isolate.run(() => _compose(cut.bytes, cut.transparent));
  }

  static Uint8List _compose(Uint8List bytes, bool transparent) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('图片无法解码');
    }
    final src = decoded.convert(numChannels: 4);
    final limit = _canvas - _padding * 2;
    final scale = (limit / src.width).clamp(0.0, limit / src.height).toDouble();
    final width = (src.width * scale).round().clamp(1, limit);
    final height = (src.height * scale).round().clamp(1, limit);
    final resized = img.copyResize(src,
        width: width, height: height, interpolation: img.Interpolation.average);

    final canvas = img.Image(width: _canvas, height: _canvas, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    final dx = (_canvas - width) ~/ 2;
    final dy = (_canvas - height) ~/ 2;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = resized.getPixel(x, y);
        final a = transparent ? (p.a / 255.0) : 1.0;
        if (a <= 0) continue;
        // 透明区域与白底按 alpha 混合，避免边缘出现黑边
        final r = (p.r * a + 255 * (1 - a)).round().clamp(0, 255);
        final g = (p.g * a + 255 * (1 - a)).round().clamp(0, 255);
        final b = (p.b * a + 255 * (1 - a)).round().clamp(0, 255);
        canvas.setPixelRgb(dx + x, dy + y, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
  }
}
