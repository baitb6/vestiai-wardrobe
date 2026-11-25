import 'package:hive/hive.dart';

part 'packing_list.g.dart';

/// 行李清单（按行程生成）
@HiveType(typeId: 4)
class PackingList extends HiveObject {
  @HiveField(0)
  String id;

  /// 行程名称，如「十一日本行」
  @HiveField(1)
  String name;

  /// 目的地（用于取当地气候）
  @HiveField(2)
  String? destination;

  @HiveField(3)
  DateTime startDate;

  @HiveField(4)
  DateTime endDate;

  /// 目的地气候：hot / mild / cold / variable
  @HiveField(5)
  String climate;

  /// 行程中会出现的场合（Occasion 常量）
  @HiveField(6)
  List<String> occasions;

  /// 目的地日均温度（°C，可选）
  @HiveField(7)
  double? avgTemp;

  @HiveField(8)
  List<PackingItem> items;

  @HiveField(9)
  DateTime createdAt;

  PackingList({
    required this.id,
    required this.name,
    this.destination,
    required this.startDate,
    required this.endDate,
    this.climate = 'mild',
    this.occasions = const [],
    this.avgTemp,
    required this.items,
    required this.createdAt,
  });

  int get days =>
      endDate.difference(startDate).inDays + 1;

  int get packedCount => items.where((i) => i.packed).length;

  double get progress =>
      items.isEmpty ? 0 : packedCount / items.length;

  bool get isPast => DateTime.now().isAfter(endDate);

  void togglePacked(String itemId) {
    final index = items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;
    items[index].packed = !items[index].packed;
    save();
  }
}

/// 清单条目：可关联衣橱单品，也可以是非衣物物品（装备/洗漱/证件…）
@HiveType(typeId: 5)
class PackingItem extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  /// 衣物类：ClothingCategory 常量；非衣物：gear / essentials / documents / toiletries / other
  @HiveField(2)
  String category;

  @HiveField(3)
  int quantity;

  @HiveField(4)
  bool packed;

  /// 关联衣橱单品 id（可选）
  @HiveField(5)
  String? clothingId;

  @HiveField(6)
  String? note;

  PackingItem({
    required this.id,
    required this.name,
    required this.category,
    this.quantity = 1,
    this.packed = false,
    this.clothingId,
    this.note,
  });
}
