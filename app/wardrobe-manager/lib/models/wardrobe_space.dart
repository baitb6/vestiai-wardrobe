import 'package:hive/hive.dart';

part 'wardrobe_space.g.dart';

/// 衣橱空间：一个物理位置（家里主卧、宿舍、老家、健身房柜子…）。
///
/// 设计约束：Clothing.wardrobeId 可空，null 归到「默认衣橱」，
/// 所以老数据不需要迁移，删掉空间也只是让衣物回到默认衣橱。
@HiveType(typeId: 9)
class WardrobeSpace extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  /// 单个 emoji，列表里做视觉锚点
  @HiveField(2)
  String emoji;

  @HiveField(3)
  String? note;

  @HiveField(4)
  DateTime createdAt;

  /// 是否默认衣橱（id 固定为 builtin）
  @HiveField(5)
  bool isDefault;

  static const String defaultId = 'space_default';

  WardrobeSpace({
    required this.id,
    required this.name,
    this.emoji = '🏠',
    this.note,
    required this.createdAt,
    this.isDefault = false,
  });

  static WardrobeSpace builtin() => WardrobeSpace(
        id: defaultId,
        name: '主衣橱',
        emoji: '🏠',
        note: '默认空间，旧数据都在这里',
        createdAt: DateTime(2024),
        isDefault: true,
      );
}
