import '../models/models.dart';

class BackupEntry {
  final String path;
  final String name;
  final int bytes;
  final DateTime createdAt;

  BackupEntry({
    required this.path,
    required this.name,
    required this.bytes,
    required this.createdAt,
  });

  String get sizeLabel =>
      bytes > 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
                          : '${(bytes / 1024).round()} KB';
}

class BackupResult {
  final bool ok;
  final String message;
  final String? path;
  final int itemCount;
  final int imageCount;

  BackupResult({
    required this.ok,
    required this.message,
    this.path,
    this.itemCount = 0,
    this.imageCount = 0,
  });
}

class RestoreResult {
  final bool ok;
  final String message;
  final int clothes;
  final int outfits;
  final int records;

  /// 备份里引用了但没找到的图片数量
  final int missingImages;

  RestoreResult({
    required this.ok,
    required this.message,
    this.clothes = 0,
    this.outfits = 0,
    this.records = 0,
    this.missingImages = 0,
  });
}

/// Web 上无文件系统
class BackupService {
  static final BackupService instance = BackupService._();

  BackupService._();

  bool get available => false;

  /// 与 io 版保持同一签名（Web 上无意义）
  void bind(Object storage) {}

  Future<List<BackupEntry>> listBackups() async => [];

  Future<BackupResult> export() async => BackupResult(
        ok: false,
        message: '网页版没有文件系统，请用 App 导出备份',
      );

  Future<RestoreResult> restore(String zipPath) async => RestoreResult(
        ok: false,
        message: '网页版不支持恢复备份',
      );
}

/// 供 UI 组装备份内容时复用（stub 也需要这个签名）
typedef ClothingListProvider = List<Clothing> Function();
