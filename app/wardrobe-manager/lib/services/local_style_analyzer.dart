import 'style_digest.dart';

/// 离线风格分析：没有配置文本网关时也能给出可用的结论。
///
/// 全部基于本地统计推导，不联网、不发数据。
/// 措辞刻意保守——规则能看出的只是结构问题，不是审美判断。
class LocalStyleAnalyzer {
  const LocalStyleAnalyzer();

  StyleReport analyze(WardrobeDigest d) {
    if (d.total == 0) {
      return const StyleReport(
        persona: '衣橱还是空的',
        strengths: [],
        avoid: ['先别急着买，把已有的穿起来再补'],
      );
    }

    final cat = d.byCategory;
    int count(String name) => cat[name] ?? 0;

    // 风格画像：按占比最高的风格 + 数量判断
    final style = _dominant(d.byStyle);
    final persona = d.total < 5
        ? '刚起步的 ${style ?? '基础'} 衣橱'
        : '${style ?? '日常'}为主，共 ${d.total} 件';

    // 结构缺口
    final gaps = <StyleGap>[];
    final baseline = {
      '上衣': '没有上衣就搭不起来整套',
      '下装': '下装是搭配的骨架，至少要两条',
      '鞋子': '鞋决定了整身的场合',
      '外套': '换季和通勤需要一件能压场的外套',
    };
    baseline.forEach((name, reason) {
      final n = count(name);
      if (n == 0) {
        gaps.add(StyleGap(name, '$reason（现在一件都没有）'));
      } else if (n == 1) {
        gaps.add(StyleGap(name, '$reason（只有 1 件，替换周期太紧）'));
      }
    });
    if (gaps.length > 3) gaps.removeRange(3, gaps.length);

    // 配色诊断
    final topColors = _topKeys(d.byColor, 3);
    final neutralOnly = topColors.isNotEmpty &&
        topColors.every((c) => _isNeutral(c));
    final colorStory = topColors.isEmpty
        ? '还没有颜色数据，录入时把颜色填上才能分析配色'
        : neutralOnly
            ? '主色集中在${topColors.join('、')}，整体偏稳；可以用一件低饱和的点缀色（雾蓝、苔绿、砖红）提亮'
            : '主色是${topColors.join('、')}，层次已经够了；如果想更统一，把第三个颜色收敛到同一色系';

    // 建议补货：从缺口里取，最多 3 条
    final buys = <BuySuggestion>[];
    for (final g in gaps.take(3)) {
      final priority = count(g.category) == 0 ? 'high' : 'medium';
      final suggestion = _suggestionFor(g.category);
      buys.add(BuySuggestion(suggestion, g.reason, priority));
    }

    // 别买什么
    final avoid = <String>[];
    if (d.neverWorn >= (d.total * 0.3).ceil() && d.total >= 5) {
      avoid.add('${d.neverWorn} 件还没穿过，先别买同类新衣服');
    }
    d.byCategory.forEach((name, n) {
      if (n >= 8) avoid.add('$name 已有 $n 件，属于饱和品类');
    });
    if (avoid.isEmpty) avoid.add('清单里没有明显饱和的品类，按缺口补就好');

    // 优势：真实存在才写
    final strengths = <String>[];
    if (d.utilization >= 0.7) {
      strengths.add('利用率 ${(d.utilization * 100).round()}%，说明买回来的都在穿');
    }
    if (d.byColor.length >= 4) {
      strengths.add('颜色跨度 ${d.byColor.length} 种，搭配空间比较大');
    }
    if (d.byCategory.length >= 5) {
      strengths.add('品类覆盖 ${d.byCategory.length} 类，场景基本齐全');
    }
    if (strengths.isEmpty) {
      strengths.add('先把现有单品的穿着次数提上来，比添新件更划算');
    }

    return StyleReport(
      persona: persona,
      styleMix: _mixFrom(d.byStyle),
      strengths: strengths,
      gaps: gaps,
      colorStory: colorStory,
      buyNext: buys,
      avoid: avoid.take(2).toList(),
      raw: 'local',
    );
  }

  String _suggestionFor(String category) {
    switch (category) {
      case '上衣':
        return '一件白色或浅蓝的衬衫';
      case '下装':
        return '一条直筒深色长裤';
      case '鞋子':
        return '一双白色低帮板鞋';
      case '外套':
        return '一件深色单排扣外套';
      default:
        return '一件$category基础款';
    }
  }

  List<StyleMix> _mixFrom(Map<String, int> byStyle) {
    final total = byStyle.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const [];
    final entries = byStyle.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(4)
        .map((e) => StyleMix(e.key, e.value / total))
        .toList();
  }

  String? _dominant(Map<String, int> map) {
    if (map.isEmpty) return null;
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }

  List<String> _topKeys(Map<String, int> map, int n) {
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).map((e) => e.key).toList();
  }

  bool _isNeutral(String color) {
    for (final k in ['黑', '白', '灰', '米', '驼', '藏青', '海军']) {
      if (color.contains(k)) return true;
    }
    return false;
  }
}
