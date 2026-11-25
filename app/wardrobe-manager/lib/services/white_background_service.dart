import 'dart:typed_data';

import 'gateway_profile.dart';
import 'try_on_service.dart';
import 'vision_gateway_service.dart';

/// 大模型白底商品图结果。
class WhiteBackgroundResult {
  final Uint8List bytes;
  final String endpoint;

  const WhiteBackgroundResult({required this.bytes, required this.endpoint});

  /// 按文件头判断真实格式，避免把 JPEG 存成 .png（分享/备份时 MIME 才正确）。
  bool get isPng =>
      bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;

  String get extension => isPng ? 'png' : 'jpg';
}

/// 使用图像编辑网关，把衣物照片整理成白底商品图。
/// 失败由调用方回退到原图或本地裁片，不影响衣物入库。
class WhiteBackgroundService {
  final TryOnService _imageEditor;

  WhiteBackgroundService({TryOnService? imageEditor})
      : _imageEditor = imageEditor ?? TryOnService();

  Future<WhiteBackgroundResult> generate({
    required Uint8List source,
    required GatewayProfile profile,
    String? apiKey,
    String? category,
    String? color,
  }) async {
    if (!profile.configured || !profile.supportsImageEdit) {
      throw GatewayException(
        GatewayErrorKind.unsupported,
        '请先配置支持图像编辑的模型，再生成白底图',
      );
    }

    final prompt = buildPrompt(category: category, color: color);
    final result = await _imageEditor.generateEditedImage(
      sourceImage: source,
      prompt: prompt,
      profile: profile,
      apiKey: apiKey,
    );
    return WhiteBackgroundResult(bytes: result.bytes, endpoint: result.endpoint);
  }

  /// 提示词单独暴露，便于测试约束（白底、只留单品、不改款式）。
  static String buildPrompt({String? category, String? color}) {
    final detail = [
      if (category != null && category.trim().isNotEmpty) '类别：${category.trim()}',
      if (color != null && color.trim().isNotEmpty) '颜色：${color.trim()}',
    ].join('；');
    return '''Generate a clean e-commerce product image of the garment in the uploaded photo.
$detail
Keep the garment design, color, material texture and details accurate.
Remove the person, body, hands, hanger, room, props, shadows and all text or watermark.
Place one complete garment centered on a pure white background (#FFFFFF), front-facing, evenly lit, with natural proportions and a small margin around it.
Do not invent extra garments or change the garment style.''';
  }

}
