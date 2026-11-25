import '../models/models.dart';
import 'recommendation_engine.dart';

/// 单品成本核算：单次穿着成本（Cost Per Wear）
class ItemCost {
  final Clothing item;
  final double price;
  final int wears;
  const ItemCost(this.item, this.price, this.wears);

  double get cpw => price / (wears == 0 ? 1 : wears);
  bool get hasWears => wears > 0;
}

/// 一周中的一天
class DayPlan {
  final DateTime date;
  final OutfitPlan? plan;
  const DayPlan(this.date, this.plan);

  bool get isToday {
    final n = DateTime.now();
    return date.year == n.year && date.month == n.month && date.day == n.day;
  }
}

/// 衣橱体检结果
class WardrobeInsights {
  final int itemCount;
  final int categoryCount;
  final int idleCount;
  final int washingCount;
  final int totalWears;
  final double totalValue;
  final double utilization;
  final double healthScore;
  final double avgCpw;
  final Map<String, int> colorFamilies;
  final List<Clothing> idleItems;
  final List<ItemCost> costs;
  final List<String> tips;
  final List<String> missingCategories;

  /// 闲置率 0-1（90 天没穿 / 总数）
  final double idleRate;

  /// 平均闲置天数（所有单品）
  final double avgIdleDays;

  /// 从未穿过的件数
  final int neverWorn;

  /// 各分类投入金额
  final Map<String, double> valueByCategory;

  const WardrobeInsights({
    required this.itemCount,
    required this.categoryCount,
    required this.idleCount,
    required this.washingCount,
    required this.totalWears,
    required this.totalValue,
    required this.utilization,
    required this.healthScore,
    required this.avgCpw,
    required this.colorFamilies,
    required this.idleItems,
    required this.costs,
    required this.tips,
    required this.missingCategories,
    this.idleRate = 0,
    this.avgIdleDays = 0,
    this.neverWorn = 0,
    this.valueByCategory = const {},
  });

  bool get isEmpty => itemCount == 0;

  /// 最划算的三件（单次成本最低且穿过）
  List<ItemCost> get bestValue {
    final list = costs.where((c) => c.hasWears).toList()
      ..sort((a, b) => a.cpw.compareTo(b.cpw));
    return list.take(3).toList();
  }

  /// 最该断舍离的三件（单次成本最高 / 从没穿过）
  List<ItemCost> get worstValue {
    final list = costs.toList()
      ..sort((a, b) {
        if (a.hasWears != b.hasWears) return a.hasWears ? 1 : -1;
        return b.cpw.compareTo(a.cpw);
      });
    return list.take(3).toList();
  }
}

class InsightsService {
  /// 顺序敏感：更具体的词（藏/牛/军）必须排在通用词（蓝/青/绿）之前
  static const _colorFamilies = <String, String>{
    '藏': '深蓝', '牛': '深蓝', 'navy': '深蓝',
    '军': '绿色', '卡': '大地色', '驼': '大地色', '棕': '大地色',
    '褐': '大地色', '咖': '大地色', 'beige': '大地色', 'brown': '大地色',
    'khaki': '大地色',
    '橘': '橙色', '橙': '橙色', '金': '黄色', '粉': '粉色',
    '白': '中性', '黑': '中性', '灰': '中性', '米': '中性', '杏': '中性',
    '银': '中性', 'white': '中性', 'black': '中性', 'gray': '中性',
    'grey': '中性',
    '蓝': '蓝色', '青': '蓝色', 'blue': '蓝色',
    '红': '红色', 'red': '红色',
    '黄': '黄色', 'yellow': '黄色',
    '绿': '绿色', 'green': '绿色',
    '紫': '紫色', 'purple': '紫色',
    'pink': '粉色',
  };

  static String colorFamily(String color) {
    final c = color.toLowerCase();
    for (final e in _colorFamilies.entries) {
      if (c.contains(e.key)) return e.value;
    }
    return '其他';
  }

  WardrobeInsights analyze(List<Clothing> clothes) {
    final itemCount = clothes.length;
    if (itemCount == 0) {
      return const WardrobeInsights(
        itemCount: 0,
        categoryCount: 0,
        idleCount: 0,
        washingCount: 0,
        totalWears: 0,
        totalValue: 0,
        utilization: 0,
        healthScore: 0,
        avgCpw: 0,
        colorFamilies: {},
        idleItems: [],
        costs: [],
        tips: ['衣橱还是空的，先录入 5 件常穿的单品就能开始体检'],
        missingCategories: [],
      );
    }

    final idle = clothes.where((c) => c.idleDays() >= 90).toList();
    final washing = clothes
        .where((c) =>
            c.locationStatus == LocationStatus.washing ||
            c.locationStatus == LocationStatus.dryCleaning)
        .toList();
    final totalWears = clothes.fold<int>(0, (s, c) => s + c.wearCount);
    final worn = clothes.where((c) => c.wearCount > 0).length;
    final priced = clothes.where((c) => (c.price ?? 0) > 0).toList();
    final totalValue = priced.fold<double>(0, (s, c) => s + (c.price ?? 0));
    final cpwAll = priced.fold<double>(
        0, (s, c) => s + (c.price ?? 0) / (c.wearCount == 0 ? 1 : c.wearCount));

    final colorFamilies = <String, int>{};
    for (final c in clothes) {
      final f = colorFamily(c.color);
      colorFamilies[f] = (colorFamilies[f] ?? 0) + 1;
    }

    // 分类覆盖：上衣/下装/外套/鞋/配饰
    const keyCategories = [
      ClothingCategory.tops,
      ClothingCategory.bottoms,
      ClothingCategory.outerwear,
      ClothingCategory.shoes,
      ClothingCategory.accessories,
    ];
    final present =
        keyCategories.where((k) => clothes.any((c) => c.category == k)).length;
    final missing =
        keyCategories.where((k) => !clothes.any((c) => c.category == k)).toList();

    final util = worn / itemCount;
    final idleRatio = idle.length / itemCount;
    var health = util * 45 + (1 - idleRatio) * 30 + (present / keyCategories.length) * 25;
    // 洗护堆积额外扣分
    if (washing.length > 3) health -= 5;
    health = health.clamp(0.0, 100.0);

    final costs = priced
        .map((c) => ItemCost(c, c.price ?? 0, c.wearCount))
        .toList()
      ..sort((a, b) => a.cpw.compareTo(b.cpw));

    final neverWorn = clothes.where((c) => c.wearCount == 0).length;
    final idleDaysTotal =
        clothes.fold<int>(0, (s, c) => s + c.idleDays());
    final valueByCategory = <String, double>{};
    for (final c in priced) {
      valueByCategory[c.category] =
          (valueByCategory[c.category] ?? 0) + (c.price ?? 0);
    }

    final tips = <String>[];
    if (idle.isNotEmpty) {
      tips.add('有 ${idle.length} 件超过 90 天没穿，断舍离或重新搭配一下');
    }
    if (util < 0.5) {
      tips.add('只有 ${(util * 100).round()}% 的衣服穿过，试试让规则引擎帮你轮换');
    }
    final dominant = colorFamilies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (dominant.isNotEmpty && dominant.first.value / itemCount > 0.5) {
      tips.add('${dominant.first.key}占了衣橱一半，加一件撞色会更出彩');
    }
    if (missing.contains(ClothingCategory.shoes)) {
      tips.add('还没有录入鞋子，搭配推荐会少一环');
    }
    if (missing.contains(ClothingCategory.outerwear) && clothes.length > 8) {
      tips.add('没有外套，春秋早晚会不好搭');
    }
    if (washing.length >= 3) {
      tips.add('${washing.length} 件还在洗护中，记得收回来');
    }
    if (costs.isNotEmpty) {
      final worst = costs.last;
      if (!worst.hasWears && worst.price >= 300) {
        tips.add('「${worst.item.displayName}」买来还没穿过，今天安排一下？');
      }
    }
    final neverWornCount = clothes.where((c) => c.wearCount == 0).length;
    if (neverWornCount >= 3 && neverWornCount / itemCount > 0.3) {
      tips.add('有 $neverWornCount 件一次都没穿过，先给它们排一天试试');
    }
    if (tips.isEmpty) {
      tips.add('衣橱状态很健康，保持这个利用率');
    }

    return WardrobeInsights(
      itemCount: itemCount,
      categoryCount: present,
      idleCount: idle.length,
      washingCount: washing.length,
      totalWears: totalWears,
      totalValue: totalValue,
      utilization: util,
      healthScore: health,
      avgCpw: priced.isEmpty ? 0 : cpwAll / priced.length,
      colorFamilies: colorFamilies,
      idleItems: idle..sort((a, b) => b.idleDays().compareTo(a.idleDays())),
      costs: costs,
      tips: tips,
      missingCategories: missing,
      idleRate: idleRatio,
      avgIdleDays: idleDaysTotal / itemCount,
      neverWorn: neverWorn,
      valueByCategory: valueByCategory,
    );
  }

  /// 一周计划：连续 7 天，尽量不重复上衣
  ///
  /// #12：每天按日期盐做 top-3 轮换——上衣够就靠 excludeIds 轮换，
  /// 上衣不够时下装/鞋/配饰也会随日期变化，不再整周一模一样。
  List<DayPlan> weekPlan({
    required List<Clothing> clothes,
    required double temperature,
    RecommendationEngine? engine,
  }) {
    final e = engine ?? RecommendationEngine();
    final used = <String>{};
    final today = DateTime.now();
    final plans = <DayPlan>[];
    for (var i = 0; i < 7; i++) {
      final date = DateTime(today.year, today.month, today.day + i);
      // 日期盐：同一天内稳定，跨天必变
      final daySeed = date.year * 100000 + date.month * 1000 + date.day;
      var plan = e.recommend(
        clothes: clothes,
        temperature: temperature,
        excludeIds: used,
        seed: daySeed,
      );
      if (plan == null) {
        // 单品不够轮换时退回全集（仍带日期盐，避免退回后 7 天全同）
        used.clear();
        plan = e.recommend(
          clothes: clothes,
          temperature: temperature,
          seed: daySeed,
        );
      }
      if (plan?.top != null) used.add(plan!.top!.id);
      if (plan?.bottom != null) used.add(plan!.bottom!.id);
      plans.add(DayPlan(date, plan));
    }
    return plans;
  }
}
