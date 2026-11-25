import '../models/models.dart';

/// 一次风格分析的结构化结果
class StyleReport {
  final String persona;
  final List<StyleMix> styleMix;
  final List<String> strengths;
  final List<StyleGap> gaps;
  final String colorStory;
  final List<BuySuggestion> buyNext;
  final List<String> avoid;

  /// 模型原始返回，便于排查
  final String raw;

  const StyleReport({
    required this.persona,
    this.styleMix = const [],
    this.strengths = const [],
    this.gaps = const [],
    this.colorStory = '',
    this.buyNext = const [],
    this.avoid = const [],
    this.raw = '',
  });

  static const empty = StyleReport(persona: '');
}

class StyleMix {
  final String name;
  final double ratio;
  const StyleMix(this.name, this.ratio);
}

class StyleGap {
  final String category;
  final String reason;
  const StyleGap(this.category, this.reason);
}

class BuySuggestion {
  final String item;
  final String why;
  final String priority;
  const BuySuggestion(this.item, this.why, this.priority);

  bool get isHigh => priority == 'high';
}

/// 构造给模型的衣橱摘要：只给统计，不给图片、不给品牌与价格明细，
/// 尽量少暴露隐私，同时保证结论有据可依。
class WardrobeDigest {
  final int total;
  final Map<String, int> byCategory;
  final Map<String, int> byColor;
  final Map<String, int> byStyle;
  final Map<String, int> bySeason;
  final Map<String, int> byMaterial;
  final int neverWorn;
  final int idle90d;
  final double avgWears;
  final double utilization;
  final List<String> mostWorn;
  final List<String> leastWorn;
  final int laundryCount;
  final int wishCount;

  const WardrobeDigest({
    required this.total,
    this.byCategory = const {},
    this.byColor = const {},
    this.byStyle = const {},
    this.bySeason = const {},
    this.byMaterial = const {},
    this.neverWorn = 0,
    this.idle90d = 0,
    this.avgWears = 0,
    this.utilization = 0,
    this.mostWorn = const [],
    this.leastWorn = const [],
    this.laundryCount = 0,
    this.wishCount = 0,
  });

  static WardrobeDigest from({
    required List<Clothing> clothes,
    int wishCount = 0,
    int laundryCount = 0,
  }) {
    final byCategory = <String, int>{};
    final byColor = <String, int>{};
    final byStyle = <String, int>{};
    final bySeason = <String, int>{};
    final byMaterial = <String, int>{};
    var neverWorn = 0;
    var idle90 = 0;
    var wears = 0;

    for (final c in clothes) {
      final cat = ClothingCategory.names[c.category] ?? c.category;
      byCategory[cat] = (byCategory[cat] ?? 0) + 1;
      if (c.color.trim().isNotEmpty) {
        byColor[c.color.trim()] = (byColor[c.color.trim()] ?? 0) + 1;
      }
      for (final s in c.styles) {
        final name = StyleTag.names[s] ?? s;
        byStyle[name] = (byStyle[name] ?? 0) + 1;
      }
      for (final s in c.seasons) {
        final name = Season.names[s] ?? s;
        bySeason[name] = (bySeason[name] ?? 0) + 1;
      }
      if (c.material != null) {
        final name = MaterialType.name(c.material);
        byMaterial[name] = (byMaterial[name] ?? 0) + 1;
      }
      wears += c.wearCount;
      if (c.wearCount == 0) neverWorn++;
      if (c.idleDays() >= 90) idle90++;
    }

    final sorted = [...clothes]..sort((a, b) => b.wearCount.compareTo(a.wearCount));
    String label(Clothing c) {
      final cat = ClothingCategory.names[c.category] ?? c.category;
      final sub = ClothingSubCategory.names[c.subCategory] ?? '';
      return '$cat${sub.isEmpty ? '' : '·$sub'}（${c.color}）';
    }

    return WardrobeDigest(
      total: clothes.length,
      byCategory: byCategory,
      byColor: byColor,
      byStyle: byStyle,
      bySeason: bySeason,
      byMaterial: byMaterial,
      neverWorn: neverWorn,
      idle90d: idle90,
      avgWears: clothes.isEmpty ? 0 : wears / clothes.length,
      utilization: clothes.isEmpty ? 0 : (clothes.length - neverWorn) / clothes.length,
      mostWorn: sorted.take(3).where((c) => c.wearCount > 0).map(label).toList(),
      leastWorn: sorted.reversed.take(3).map(label).toList(),
      laundryCount: laundryCount,
      wishCount: wishCount,
    );
  }

  Map<String, dynamic> toJson() => {
        '单品总数': total,
        '分类分布': byCategory,
        '颜色分布': byColor,
        '风格分布': byStyle,
        '季节分布': bySeason,
        '材质分布': byMaterial,
        '买来没穿过': neverWorn,
        '超过90天没穿': idle90d,
        '平均穿着次数': double.parse(avgWears.toStringAsFixed(1)),
        '利用率': '${(utilization * 100).round()}%',
        '最常穿': mostWorn,
        '最少穿': leastWorn,
        '正在洗护': laundryCount,
        '愿望清单件数': wishCount,
      };
}
