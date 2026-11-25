import 'bbox.dart';

/// 一次拆分中，单件衣物在「确认入库前」的草稿。
///
/// 它不是 Hive 模型：草稿只活在内存里，用户点确认后才转成 Clothing 落库。
class SplitCandidate {
  /// 内部主分类 key（tops/bottoms/...）
  String category;

  /// 内部子分类 key（t_shirt/jeans/...）
  String subCategory;

  BBox bbox;

  /// 中文颜色，第一个作为主色
  List<String> colors;

  /// 内部风格 key
  List<String> styleTags;

  /// 内部季节 key
  List<String> seasons;

  /// 模型自报置信度 0-1
  double confidence;

  /// 模型原始分类文本（保留用于回溯）
  String rawCategory;

  /// 模型给的自由标签
  List<String> extraTags;

  /// 用户是否改过（分类/颜色/bbox 任一）
  bool userEdited = false;

  /// 是否勾选入库
  bool selected = true;

  /// 裁剪/抠图产物
  String? imagePath;

  /// true = 透明 PNG（抠图成功）
  bool transparent = false;

  /// success / failed / pending
  String cutoutStatus = 'pending';

  /// 抠图失败时的提示
  String? cutoutNote;

  /// 重复检测命中说明（仅提示，不阻止）
  String? duplicateHint;

  SplitCandidate({
    required this.category,
    required this.subCategory,
    required this.bbox,
    this.colors = const [],
    this.styleTags = const [],
    this.seasons = const [],
    this.confidence = 0,
    this.rawCategory = '',
    this.extraTags = const [],
  });

  String get primaryColor => colors.isEmpty ? '未知' : colors.first;

  Map<String, dynamic> toJson() => {
        'category': category,
        'subCategory': subCategory,
        'bbox': bbox.toJson(),
        'colors': colors,
        'styleTags': styleTags,
        'seasons': seasons,
        'confidence': confidence,
        'rawCategory': rawCategory,
        'extraTags': extraTags,
      };

  factory SplitCandidate.fromJson(Map<String, dynamic> json) {
    return SplitCandidate(
      category: json['category'] as String? ?? 'tops',
      subCategory: json['subCategory'] as String? ?? 't_shirt',
      bbox: BBox.fromJson(json['bbox']),
      colors: (json['colors'] as List?)?.cast<String>() ?? const [],
      styleTags: (json['styleTags'] as List?)?.cast<String>() ?? const [],
      seasons: (json['seasons'] as List?)?.cast<String>() ?? const [],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      rawCategory: json['rawCategory'] as String? ?? '',
      extraTags: (json['extraTags'] as List?)?.cast<String>() ?? const [],
    );
  }
}
