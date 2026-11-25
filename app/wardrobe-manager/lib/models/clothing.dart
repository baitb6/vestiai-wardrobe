import 'package:hive/hive.dart';

import '../data/clothing_naming.dart';
import 'bbox.dart';

part 'clothing.g.dart';

@HiveType(typeId: 0)
class Clothing extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String imageUrl;

  @HiveField(2)
  String category; // tops, bottoms, dress, outerwear, shoes, accessories

  @HiveField(3)
  String subCategory; // t-shirt, jeans, skirt, coat...

  @HiveField(4)
  String color;

  @HiveField(5)
  String? pattern; // solid, striped, plaid, printed...

  @HiveField(6)
  List<String> styles; // casual, formal, sporty, dating...

  @HiveField(7)
  List<String> seasons; // spring, summer, autumn, winter

  @HiveField(8)
  String? brand;

  @HiveField(9)
  String? size;

  @HiveField(10)
  double? price;

  @HiveField(11)
  DateTime? purchaseDate;

  @HiveField(12)
  String locationStatus; // in_wardrobe, washing, wearing, storage

  @HiveField(13)
  String? locationRoom;

  @HiveField(14)
  String? locationFurniture;

  @HiveField(15)
  int wearCount;

  @HiveField(16)
  DateTime? lastWearDate;

  @HiveField(17)
  DateTime createdAt;

  @HiveField(18)
  DateTime? updatedAt;

  @HiveField(19)
  List<String> tags;

  @HiveField(20)
  bool isFavorite;

  @HiveField(21)
  String? notes;

  /// 材质（MaterialType 常量：cotton/wool/quick_dry/linen...）
  @HiveField(22)
  String? material;

  /// 厚度 0-4（0 极薄 ~ 4 特厚）
  @HiveField(23)
  int thickness;

  /// 适合温度下限（°C）
  @HiveField(24)
  int? tempMin;

  /// 适合温度上限（°C）
  @HiveField(25)
  int? tempMax;

  /// 适合场合（Occasion 常量列表）
  @HiveField(26)
  List<String> occasions;

  // ========== 以下为 AI 自动拆分新增字段 ==========
  // 全部可空 / 有默认值，旧数据读出来就是 null，不需要迁移。

  /// 原图路径（文件系统中的照片，autoSplit 时是整身照或裁片）
  @HiveField(27)
  String? originalImagePath;

  /// 抠图后的透明 PNG 路径
  @HiveField(28)
  String? cutoutImagePath;

  /// 预留：分割掩码路径（MVP 为 null）
  @HiveField(29)
  String? maskPath;

  /// 来源：manual / autoSplit / import
  @HiveField(30)
  String? sourceType;

  /// 来源整身照 ID（同一次拆分出来的单品共享）
  @HiveField(31)
  String? sourcePhotoId;

  /// 归一化包围盒 0-1
  @HiveField(32)
  double? bboxX;

  @HiveField(33)
  double? bboxY;

  @HiveField(34)
  double? bboxW;

  @HiveField(35)
  double? bboxH;

  /// AI 原始分类（用户改过分类后仍保留，便于回溯模型质量）
  @HiveField(36)
  String? aiCategory;

  /// AI 给的风格标签
  @HiveField(37)
  List<String>? aiTags;

  /// AI 给的颜色
  @HiveField(38)
  List<String>? aiColors;

  /// AI 置信度 0-1
  @HiveField(39)
  double? aiConfidence;

  /// 用户是否修改过识别结果
  @HiveField(40)
  bool? userEdited;

  /// 产生这条数据的网关配置 ID
  @HiveField(41)
  String? gatewayProfileId;

  /// 抠图状态：success / failed / pending
  @HiveField(42)
  String? cutoutStatus;

  /// 所属衣橱空间 id；null 表示默认衣橱（兼容旧数据）
  @HiveField(43)
  String? wardrobeId;

  /// 用户自定义名称（如「周末那件白T」）；为空时按颜色 + 类型生成中文全名
  @HiveField(44)
  String? customName;

  /// 自定义属性（版型、厚度、购买渠道……），纯文本键值对
  @HiveField(45)
  Map<String, String>? extraAttributes;

  Clothing({
    required this.id,
    required this.imageUrl,
    required this.category,
    required this.subCategory,
    required this.color,
    this.pattern,
    this.styles = const [],
    this.seasons = const [],
    this.brand,
    this.size,
    this.price,
    this.purchaseDate,
    this.locationStatus = 'in_wardrobe',
    this.locationRoom,
    this.locationFurniture,
    this.wearCount = 0,
    this.lastWearDate,
    required this.createdAt,
    this.updatedAt,
    this.tags = const [],
    this.isFavorite = false,
    this.notes,
    this.material,
    this.thickness = 2,
    this.tempMin,
    this.tempMax,
    this.occasions = const [],
    this.originalImagePath,
    this.cutoutImagePath,
    this.maskPath,
    this.sourceType,
    this.sourcePhotoId,
    this.bboxX,
    this.bboxY,
    this.bboxW,
    this.bboxH,
    this.aiCategory,
    this.aiTags,
    this.aiColors,
    this.aiConfidence,
    this.userEdited,
    this.gatewayProfileId,
    this.cutoutStatus,
    this.wardrobeId,
    this.customName,
    this.extraAttributes,
  });

  /// 展示用图片：优先抠图，其次白底商品图（本地路径），最后原图。
  /// 大模型白底图存在 imageUrl 里（本地文件），这里不能只看 cutout/original，
  /// 否则卡片、3D 衣橱、搭配预览里都只会显示原图。
  String? get displayImagePath {
    final cut = cutoutImagePath;
    if (cut != null && cut.isNotEmpty) return cut;
    final u = imageUrl;
    if (u.isNotEmpty && !u.startsWith('data:') && !u.startsWith('http')) {
      return u;
    }
    return originalImagePath;
  }

  /// 是否属于指定衣橱空间（null 空间只看 wardrobeId 为空的老数据）
  bool belongsTo(String? spaceId) {
    if (spaceId == null) return wardrobeId == null;
    return wardrobeId == spaceId;
  }

  bool get isAutoSplit => sourceType == 'autoSplit';

  BBox? get bbox {
    final x = bboxX, y = bboxY, w = bboxW, h = bboxH;
    if (x == null || y == null || w == null || h == null) return null;
    return BBox(x: x, y: y, w: w, h: h);
  }

  set bbox(BBox? value) {
    bboxX = value?.x;
    bboxY = value?.y;
    bboxW = value?.w;
    bboxH = value?.h;
  }

  /// #14 展示名统一「颜色 + 中文名称」（自定义名优先），全站共用：
  /// 衣橱卡片标题、详情、日历/记录「本月统计」聚合、分享文案都走这里。
  /// 品牌词不再进标题（挪到副标题/详情字段），避免「Uniqlo 白色 t_shirt」。
  String get displayName => clothingDisplayName(this);

  /// 综合保暖评分 0-10：材质保暖度为主，厚度修正
  double get warmthScore {
    final materialWarmth = _materialWarmth();
    var score = materialWarmth * 0.6 + thickness * 1.0;
    if (score > 10) score = 10;
    return score;
  }

  /// 透气评分 0-10（运动/夏季场景用）
  double get breathabilityScore {
    final materialBreath = _materialBreath();
    return (materialBreath * 0.7 + (4 - thickness) * 1.0).clamp(0.0, 10.0);
  }

  /// 温度是否落在适穿区间（未填区间视为适穿）
  bool matchesTemp(double temp) {
    if (tempMin != null && temp < tempMin!) return false;
    if (tempMax != null && temp > tempMax!) return false;
    return true;
  }

  bool matchesOccasion(String? occasion) {
    if (occasion == null) return true;
    if (occasions.isEmpty) return true;
    return occasions.contains(occasion);
  }

  /// 是否可穿（不在洗、不在干洗）
  bool get wearable =>
      locationStatus == 'in_wardrobe' || locationStatus == 'storage';

  /// 单次穿着成本（Cost Per Wear）：购入价 ÷ 穿着次数
  /// 没填价格时返回 null；一次没穿时按 1 次计算（显示原价）
  double? get cpw {
    final p = price;
    if (p == null || p <= 0) return null;
    return p / (wearCount == 0 ? 1 : wearCount);
  }

  /// 闲置天数（未穿过返回自录入起的天数）
  int idleDays() {
    final ref = lastWearDate ?? createdAt;
    return DateTime.now().difference(ref).inDays;
  }

  double _materialWarmth() {
    switch (material) {
      case 'down':
        return 10;
      case 'cashmere':
        return 9;
      case 'wool':
        return 8;
      case 'leather':
        return 7;
      case 'denim':
        return 5;
      case 'cotton':
      case 'blended':
      case 'polyester':
        return 4;
      case 'nylon':
        return 3;
      case 'linen':
      case 'silk':
      case 'quick_dry':
        return 2;
      default:
        return 4;
    }
  }

  double _materialBreath() {
    switch (material) {
      case 'linen':
        return 9;
      case 'quick_dry':
        return 9;
      case 'cotton':
      case 'silk':
        return 8;
      case 'wool':
      case 'cashmere':
        return 6;
      case 'blended':
        return 5;
      case 'denim':
      case 'nylon':
        return 4;
      case 'polyester':
        return 3;
      case 'down':
        return 3;
      case 'leather':
        return 1;
      default:
        return 5;
    }
  }

  void incrementWearCount() {
    wearCount++;
    lastWearDate = DateTime.now();
    updatedAt = DateTime.now();
  }
}
