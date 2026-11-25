/// 图片仓库里的一个文件
class StoredImage {
  final String path;
  final String name;
  final int bytes;
  final DateTime modified;

  const StoredImage({
    required this.path,
    required this.name,
    required this.bytes,
    required this.modified,
  });

  /// 按文件名前缀归类：fullbody 原图 / piece 裁片抠图 / 其他
  String get kind {
    if (name.startsWith('fullbody_')) return 'fullbody';
    if (name.startsWith('piece_')) return 'piece';
    if (name.startsWith('photo_')) return 'photo';
    if (name.startsWith('restored_')) return 'restored';
    return 'other';
  }

  String get sizeLabel => formatBytes(bytes);

  bool get isOrphan => false;
}

/// 一次扫描的结果
class ImageUsage {
  final List<StoredImage> files;
  final List<StoredImage> orphans;

  const ImageUsage({required this.files, required this.orphans});

  int get totalBytes => files.fold<int>(0, (s, f) => s + f.bytes);
  int get fileCount => files.length;
  int get orphanBytes => orphans.fold<int>(0, (s, f) => s + f.bytes);
  int get orphanCount => orphans.length;

  Map<String, int> get bytesByKind {
    final map = <String, int>{};
    for (final f in files) {
      map[f.kind] = (map[f.kind] ?? 0) + f.bytes;
    }
    return map;
  }

  Map<String, int> get countByKind {
    final map = <String, int>{};
    for (final f in files) {
      map[f.kind] = (map[f.kind] ?? 0) + 1;
    }
    return map;
  }

  /// 占用最大的几个文件
  List<StoredImage> get largest {
    final list = files.toList()..sort((a, b) => b.bytes.compareTo(a.bytes));
    return list.take(5).toList();
  }

  bool get isEmpty => files.isEmpty;
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

const Map<String, String> kImageKindNames = {
  'fullbody': '全身照原图',
  'piece': '裁片 / 抠图',
  'photo': '手动录入照片',
  'restored': '备份恢复图片',
  'other': '其他',
};
