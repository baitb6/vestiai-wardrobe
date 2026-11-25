import 'package:hive/hive.dart';

part 'wish_item.g.dart';

/// 愿望清单条目。
///
/// 与 Clothing 分离：想要的单品往往还没有照片、没有价格记录，
/// 单独一张表能把「种草 → 冷静 → 到底买不买」这条链路记全。
@HiveType(typeId: 8)
class WishItem extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  /// 分类（复用 ClothingCategory 常量）
  @HiveField(2)
  String category;

  @HiveField(3)
  String? subCategory;

  @HiveField(4)
  String? color;

  /// 期望价格
  @HiveField(5)
  double? price;

  /// 为什么会想要它 / 想搭配什么
  @HiveField(6)
  String? note;

  /// 参考图（商品图或街拍截图）
  @HiveField(7)
  String? imagePath;

  /// 1 想要 / 2 很想 / 3 立刻就要
  @HiveField(8)
  int priority;

  @HiveField(9)
  DateTime createdAt;

  /// 已购入时间；null 表示还在清单里
  @HiveField(10)
  DateTime? purchasedAt;

  /// 购入后转成的衣物 id
  @HiveField(11)
  String? clothingId;

  /// 冷静期结束日（7 天后才建议下单）
  @HiveField(12)
  DateTime? cooldownUntil;

  WishItem({
    required this.id,
    required this.name,
    required this.category,
    this.subCategory,
    this.color,
    this.price,
    this.note,
    this.imagePath,
    this.priority = 1,
    required this.createdAt,
    this.purchasedAt,
    this.clothingId,
    this.cooldownUntil,
  });

  bool get purchased => purchasedAt != null;

  /// 冷静期内不催买，只提示还剩几天
  bool get inCooldown {
    final until = cooldownUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  int get cooldownDaysLeft {
    final until = cooldownUntil;
    if (until == null) return 0;
    final diff = until.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff + 1;
  }

  /// 在清单里待了多久（帮用户看清冲动消费）
  int get waitingDays => DateTime.now().difference(createdAt).inDays;
}
