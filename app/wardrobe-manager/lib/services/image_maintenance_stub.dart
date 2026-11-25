import 'image_usage.dart';

/// Web 版没有本地文件系统，图片仓库不可用
class ImageMaintenance {
  const ImageMaintenance._();

  static Future<ImageUsage?> scan(
    Set<String> referenced, {
    Duration minAge = const Duration(hours: 24),
  }) async =>
      null;

  static Future<int> deleteOrphans(List<StoredImage> orphans) async => 0;

  static Future<int> compress(
    Set<String> referenced, {
    int maxSide = 1400,
    int jpegQuality = 82,
    int threshold = 400 * 1024,
  }) async =>
      0;
}
