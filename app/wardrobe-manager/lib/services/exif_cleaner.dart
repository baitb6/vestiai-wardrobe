import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 清理后的图片
class CleanImage {
  final Uint8List bytes;
  final int width;
  final int height;

  /// 是否真的做过处理（原图已足够小且无 EXIF 时可能原样返回）
  final bool changed;
  final int originalBytes;

  const CleanImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.changed,
    required this.originalBytes,
  });

  int get bytesSaved => originalBytes - bytes.length;

  String get sizeLabel => '${(bytes.length / 1024).round()} KB';
}

/// 上传前的隐私清理：
/// 1. 按 EXIF 方向旋正（避免模型看到躺倒的人）
/// 2. 长边限制在 maxSide 内（省流量、省 token）
/// 3. 重新编码 JPEG —— image 包编码时不写 EXIF，相机型号、GPS 坐标、
///    拍摄时间等元数据随之消失
///
/// 纯 Dart 实现，Web / 桌面 / 移动端都能跑；解码失败时返回 null，
/// 调用方应退回原始字节，绝不因为清理失败而阻断上传。
class ExifCleaner {
  const ExifCleaner._();

  static CleanImage? prepare(
    Uint8List input, {
    int maxSide = 1280,
    int quality = 86,
  }) {
    if (input.isEmpty) return null;

    img.Image? decoded;
    try {
      decoded = img.decodeImage(input);
    } catch (e) {
      // 解码抛异常（损坏的图片数据）：返回 null，调用方退回原始字节
      print('EXIF 清理时图片解码异常，退回原图：$e');
      return null;
    }
    if (decoded == null) return null;

    try {
      var out = img.bakeOrientation(decoded);
      final longest = out.width > out.height ? out.width : out.height;
      if (longest > maxSide) {
        out = img.copyResize(
          out,
          width: out.width >= out.height ? maxSide : null,
          height: out.height > out.width ? maxSide : null,
          interpolation: img.Interpolation.average,
        );
      }
      // 彻底清空元数据：GPS、机型、拍摄时间、缩略图都不带到上传包里
      out.exif.clear();

      final raw = Uint8List.fromList(img.encodeJpg(out, quality: quality));
      // 编码器即使元数据为空也会写一个空的 APP1 段，这里直接裁掉，
      // 保证上传出去的 JPEG 连 Exif 标记都没有。
      final bytes = _stripExifSegment(raw);
      return CleanImage(
        bytes: bytes,
        width: out.width,
        height: out.height,
        changed: true,
        originalBytes: input.length,
      );
    } catch (e) {
      // 旋正/缩放/编码任一步失败：返回 null，调用方退回原始字节（README 承诺）
      print('EXIF 清理处理失败，退回原图：$e');
      return null;
    }
  }

  /// 去掉 JPEG 里的 APP1/Exif 段（其它段原样保留）
  static Uint8List _stripExifSegment(Uint8List jpeg) {
    if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return jpeg;
    final out = BytesBuilder(copy: false)..add([0xFF, 0xD8]);
    var i = 2;
    while (i + 1 < jpeg.length) {
      if (jpeg[i] != 0xFF) return jpeg; // 结构不认识，原样返回更安全
      final marker = jpeg[i + 1];
      // 无长度的标记
      if (marker == 0xD9 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        out.add(jpeg.sublist(i, i + 2));
        i += 2;
        continue;
      }
      if (i + 4 > jpeg.length) return jpeg;
      final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
      final end = i + 2 + len;
      if (len < 2 || end > jpeg.length) return jpeg;

      final isExif = marker == 0xE1 &&
          len >= 8 &&
          jpeg[i + 4] == 0x45 && // E
          jpeg[i + 5] == 0x78 && // x
          jpeg[i + 6] == 0x69 && // i
          jpeg[i + 7] == 0x66; // f
      if (!isExif) out.add(jpeg.sublist(i, end));
      i = end;
    }
    if (i < jpeg.length) out.add(jpeg.sublist(i));
    return out.toBytes();
  }

  /// 只判断有没有 EXIF（用于「这张照片带定位」这类提示），不做解码以外的处理
  static bool hasMetadata(Uint8List input) {
    try {
      final decoded = img.decodeImage(input);
      if (decoded == null) return false;
      final exif = decoded.exif;
      return exif.keys.isNotEmpty;
    } catch (e) {
      // 判断不出来就当没有：这个提示不影响主流程
      print('EXIF 检测失败，按无元数据处理：$e');
      return false;
    }
  }
}
