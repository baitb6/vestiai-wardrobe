import '../models/models.dart';

/// 推荐出来的整套穿搭方案
class OutfitPlan {
  final Clothing? top;
  final Clothing? bottom;
  final Clothing? outer;
  final Clothing? shoes;
  final Clothing? accessory;
  final double score;
  final String reasoning;

  const OutfitPlan({
    this.top,
    this.bottom,
    this.outer,
    this.shoes,
    this.accessory,
    required this.score,
    required this.reasoning,
  });

  /// 按穿戴顺序展示：帽子 → 上衣/裙装 → 下装 → 外套 → 鞋子 → 其余配饰。
  /// 所有展示面（首页主卡 / 换一套弹层 / 风格页 / 分享卡）统一走本顺序。
  static int _wearRank(Clothing c) {
    if (c.category == ClothingCategory.accessories) {
      final sub = c.subCategory.toLowerCase();
      if (sub.contains('hat') || sub.contains('cap') || c.subCategory.contains('帽')) {
        return 0; // 帽子最先上身
      }
      return 5;
    }
    switch (c.category) {
      case ClothingCategory.tops:
        return 1;
      case ClothingCategory.dress:
        return 1;
      case ClothingCategory.bottoms:
        return 2;
      case ClothingCategory.outerwear:
        return 3;
      case ClothingCategory.shoes:
        return 4;
      default:
        return 5;
    }
  }

  List<Clothing> get pieces {
    final list = [top, bottom, outer, shoes, accessory]
        .whereType<Clothing>()
        .toList();
    // 每个槽位至多一件，rank 互不相同，排序即穿戴顺序
    list.sort((a, b) => _wearRank(a).compareTo(_wearRank(b)));
    return list;
  }

  List<String> get clothingIds => pieces.map((c) => c.id).toList();

  /// 整套保暖评分（上衣全额，外套 0.9，下装 0.5）
  double get warmthTotal {
    var w = 0.0;
    if (top != null) w += top!.warmthScore;
    if (outer != null) w += outer!.warmthScore * 0.9;
    if (bottom != null) w += bottom!.warmthScore * 0.5;
    return w;
  }
}

/// 户外方案：穿搭 + 装备清单
class OutdoorPlan {
  final OutfitPlan outfit;
  final List<PackingItem> gears;
  final String scenario;
  final double temperature;
  final int precipProb;

  const OutdoorPlan({
    required this.outfit,
    required this.gears,
    required this.scenario,
    required this.temperature,
    required this.precipProb,
  });
}

/// 推荐结果 + 元信息（#6 按性别搭配 / #8 推荐理由 的旁路包装）。
///
/// OutfitPlan 本体的字段结构保持原样（与 Hive 侧 Outfit 的持久化互不相干），
/// 推荐理由与「性别未填」提示挂在本包装类上，由 provider 层转发给界面，
/// 不触碰任何 HiveObject / .g.dart。
class OutfitRecommendation {
  final OutfitPlan? plan;
  final List<String> reasons;
  final bool needsGenderHint;

  const OutfitRecommendation({
    this.plan,
    this.reasons = const [],
    this.needsGenderHint = false,
  });
}

/// 规则审计结论（纯数据，便于单测断言）
class RuleAudit {
  final bool pass;
  final String? reason;
  const RuleAudit(this.pass, this.reason);
}

/// 穿搭审美 / 性别规则集（#6 + #8）—— 全部纯函数：
/// 输入衣物列表 + 天气 + 场合 → 输出过滤结果 / 分数 / 违规 / 理由，
/// 不依赖引擎实例，便于 test/recommendation_rules_test.dart 单测。
class OutfitRules {
  // ===== #6 按性别过滤 =====

  /// 明显女装的子品类；拿不准的（配饰 / leggings / polo 等）不过滤。
  static const Set<String> _femaleOnlySubs = {'skirt', 'blouse', 'heels'};

  /// 明显男装专属的子品类：当前品类词表里没有确定项
  /// （西装 / Polo / 马甲男女皆穿），保守留空 —— female 用户不过滤任何单品。
  static const Set<String> maleOnlySubs = {};

  static bool isFemaleOnlyPiece(Clothing c) {
    if (c.category == ClothingCategory.dress) return true;
    final sub = c.subCategory.toLowerCase();
    if (_femaleOnlySubs.contains(sub)) return true;
    // AI 自由文本兜底：带 dress / skirt / 裙 字样按裙装处理
    return sub.contains('dress') ||
        sub.contains('skirt') ||
        c.subCategory.contains('裙');
  }

  static bool isMaleOnlyPiece(Clothing c) =>
      maleOnlySubs.contains(c.subCategory.toLowerCase());

  /// 按性别过滤候选（纯函数）：male 剔除明显女装，female 剔除明显男装，
  /// null / other / 未知值原样返回（返回新列表，不改入参）。
  static List<Clothing> filterByGender(List<Clothing> clothes, String? gender) {
    switch (gender) {
      case 'male':
        return clothes.where((c) => !isFemaleOnlyPiece(c)).toList();
      case 'female':
        return clothes.where((c) => !isMaleOnlyPiece(c)).toList();
      default:
        return clothes.toList();
    }
  }

  // ===== #8 温度 / 场合硬排除 =====

  /// 温度硬规则：比用户自填的适穿区间（matchesTemp）更「硬」——
  /// 即使单品没填区间，也按品类常识排除严重不符的单品，组合自然不出现。
  static bool passesTempHardRule(Clothing c, double temperature) {
    if (temperature >= 26) {
      // 盛夏：厚外套 / 厚毛衣 / 厚卫衣不出
      if (c.category == ClothingCategory.outerwear &&
          (c.thickness >= 3 || c.warmthScore >= 7)) {
        return false;
      }
      if ((c.subCategory == 'sweater' || c.subCategory == 'hoodie') &&
          c.thickness >= 3) {
        return false;
      }
    }
    if (temperature <= 10) {
      // 严冬：短裤 / 凉鞋 / 背心不出（裙装配保暖袜是合理穿法，不过滤）
      if (const ['shorts', 'sandals', 'tank_top'].contains(c.subCategory)) {
        return false;
      }
    }
    return true;
  }

  /// 场合硬规则：明显穿不出去的组合不出（其余场合只走打分软约束）。
  static bool passesOccasionHardRule(Clothing c, String? occasion) {
    switch (occasion) {
      case Occasion.sport:
        if (c.category == ClothingCategory.dress) return false;
        if (const ['skirt', 'heels'].contains(c.subCategory)) return false;
        break;
      case Occasion.interview:
        if (const ['shorts', 'tank_top', 'sandals'].contains(c.subCategory)) {
          return false;
        }
        break;
    }
    return true;
  }

  /// 组合级硬规则审计（单测 / 展示用）：任何单品触犯温度 / 场合硬规则，
  /// 或全身主色超过 3 个即 fail。
  static RuleAudit auditHardRules(
    List<Clothing> pieces, {
    required double temperature,
    String? occasion,
  }) {
    for (final c in pieces) {
      if (!passesTempHardRule(c, temperature)) {
        return RuleAudit(
            false, '「${c.displayName}」不适合 ${temperature.round()}°C');
      }
      if (!passesOccasionHardRule(c, occasion)) {
        return RuleAudit(false, '「${c.displayName}」不适合该场合');
      }
    }
    if (mainColorCount(pieces) > 3) {
      return const RuleAudit(false, '全身主色超过 3 个');
    }
    return const RuleAudit(true, null);
  }

  // ===== #8 主色上限 + 色系冲突表 =====

  /// 色系冲突表（两边都是大面积非中性主色时视为撞色）
  static const List<Set<String>> clashPairs = [
    {'red', 'green'},
    {'purple', 'yellow'},
    {'red', 'purple'},
  ];

  /// 颜色 → 色系家族（引擎 _colorHarmony 的单一实现来源）
  static String? colorFamilyOf(String color) {
    final c = color.toLowerCase();
    const map = {
      '白': 'neutral', '黑': 'neutral', '灰': 'neutral', '米': 'neutral', '杏': 'neutral',
      '藏': 'navy', '牛': 'navy', '蓝': 'blue', '青': 'blue',
      '红': 'red', '粉': 'red', '橘': 'red', '橙': 'red', '黄': 'yellow',
      '绿': 'green', '军': 'green', '卡': 'beige', '驼': 'beige', '棕': 'brown', '褐': 'brown', '咖': 'brown',
      '紫': 'purple', '花': 'pattern', '金': 'yellow', '银': 'neutral',
      'white': 'neutral', 'black': 'neutral', 'gray': 'neutral', 'grey': 'neutral',
      'beige': 'beige', 'khaki': 'beige', 'blue': 'blue', 'navy': 'navy',
      'red': 'red', 'pink': 'red', 'green': 'green', 'yellow': 'yellow',
      'brown': 'brown', 'purple': 'purple',
    };
    for (final e in map.entries) {
      if (c.contains(e.key)) return e.value;
    }
    return null;
  }

  /// 非中性主色家族（中性色黑白灰米驼卡其不计入主色数；花色按 1 个主色算）
  static List<String> mainColorFamilies(List<Clothing> pieces) {
    final s = <String>{};
    for (final c in pieces) {
      final f = colorFamilyOf(c.color);
      if (f != null && f != 'neutral') s.add(f);
    }
    return s.toList()..sort();
  }

  /// 全身主色数量（≤3 为合格，经典穿搭上限）
  static int mainColorCount(List<Clothing> pieces) =>
      mainColorFamilies(pieces).length;

  static bool hasColorClash(List<Clothing> pieces) {
    final mains = mainColorFamilies(pieces).toSet();
    for (final pair in clashPairs) {
      if (mains.containsAll(pair)) return true;
    }
    return false;
  }

  // ===== #8 版型平衡 =====

  /// 版型表（上宽下窄 / 上窄下宽偏好）；拿不准的子品类返回 null 不参与。
  static const Map<String, String> _silhouetteBySub = {
    'hoodie': 'loose',
    'windbreaker': 'loose',
    'cardigan': 'loose',
    'skirt': 'loose',
    'tank_top': 'slim',
    'leggings': 'slim',
  };

  static String? silhouetteOf(Clothing c) => _silhouetteBySub[c.subCategory];

  /// 选品时的审美加减分（纯函数）：
  /// 主色将超 3 个 → -6；与已选主色撞色系 → -4；上/下版型反向 +2.5、同向 -2.5。
  static double aestheticDelta({
    required Clothing candidate,
    Clothing? referenceTop,
    Set<String>? existingFamilies,
  }) {
    var d = 0.0;
    final f = colorFamilyOf(candidate.color);
    final nonNeutral = f != null && f != 'neutral';
    if (existingFamilies != null && nonNeutral) {
      if (!existingFamilies.contains(f) && existingFamilies.length >= 3) {
        d -= 6; // 全身主色将超过 3 个
      } else {
        for (final pair in clashPairs) {
          if (pair.contains(f) && existingFamilies.any(pair.contains)) {
            d -= 4; // 色系冲突
            break;
          }
        }
      }
    }
    if (referenceTop != null &&
        candidate.category == ClothingCategory.bottoms &&
        referenceTop.category == ClothingCategory.tops) {
      final st = silhouetteOf(referenceTop);
      final sb = silhouetteOf(candidate);
      if (st != null && sb != null) d += st == sb ? -2.5 : 2.5;
    }
    return d;
  }

  // ===== #8 单品新鲜度 =====

  /// lastWearDate 越久分越高（唤醒闲置）；从未穿过按录入日起算。
  static double freshnessScore(Clothing c) {
    final days = c.idleDays();
    if (days >= 90) return 10;
    if (days >= 30) return 7;
    if (days >= 14) return 4;
    if (days >= 7) return 2;
    return 0.5;
  }

  // ===== #8 中文理由生成 =====

  static const Map<String, String> _familyNames = {
    'navy': '藏蓝',
    'blue': '蓝',
    'red': '红',
    'yellow': '黄',
    'green': '绿',
    'beige': '大地色',
    'brown': '棕',
    'purple': '紫',
    'pattern': '花色',
  };

  /// 每套推荐生成 2-3 条中文理由。
  /// 优先级：温度 → 配色（主色上限/冲突） → 版型 → 场合 → 新鲜度，取前 3 条。
  static List<String> buildReasons({
    required List<Clothing> pieces,
    required double temperature,
    String? occasion,
  }) {
    if (pieces.isEmpty) return const [];
    final t = temperature.round();
    Clothing? byCat(String cat) {
      for (final c in pieces) {
        if (c.category == cat) return c;
      }
      return null;
    }

    final top = byCat(ClothingCategory.tops);
    final bottom = byCat(ClothingCategory.bottoms);
    final outer = byCat(ClothingCategory.outerwear);

    final reasons = <String>[];

    // 温度
    if (temperature <= 10) {
      reasons.add('$t°C 低温，厚实组合锁温优先');
    } else if (temperature >= 26) {
      reasons.add('$t°C 偏热，轻薄透气优先');
    } else if (outer != null) {
      reasons.add('内搭轻薄 + ${MaterialType.name(outer.material)}外套挡风，适配 $t°C');
    } else {
      reasons.add('$t°C 舒适区间，厚度适中');
    }

    // 配色（主色 ≤ 3）
    final mains = mainColorFamilies(pieces);
    if (hasColorClash(pieces)) {
      reasons.add('主色撞色大胆，个性但挑场合');
    } else if (mains.isEmpty) {
      reasons.add('全身中性色，百搭不易出错');
    } else if (mains.length == 1) {
      reasons.add('同色系深浅过渡，整体和谐');
    } else if (mains.length <= 3) {
      final labels = mains.map((f) => _familyNames[f] ?? f).join(' + ');
      reasons.add('主色 $labels 控制在 3 色内，主次分明');
    } else {
      reasons.add('全身主色 ${mains.length} 个，略超 3 色上限');
    }

    // 版型
    final st = top == null ? null : silhouetteOf(top);
    final sb = bottom == null ? null : silhouetteOf(bottom);
    if (st != null && sb != null && st != sb) {
      reasons.add(st == 'loose' ? '上宽下窄，比例平衡' : '上窄下宽，显高利落');
    }

    // 场合
    if (occasion == Occasion.work || occasion == Occasion.interview) {
      if (pieces.any((c) => c.styles.contains(StyleTag.formal))) {
        reasons.add(
            '偏正式单品，适合${occasion == Occasion.interview ? '面试' : '通勤'}');
      }
    } else if (occasion == Occasion.sport &&
        pieces.any((c) => c.material == MaterialType.quickDry)) {
      reasons.add('速干材质排汗快，运动更自在');
    }

    // 新鲜度
    Clothing? idlest;
    for (final c in pieces) {
      if (idlest == null || c.idleDays() > idlest.idleDays()) idlest = c;
    }
    if (idlest != null && idlest.idleDays() >= 30) {
      reasons.add('唤醒「${idlest.displayName}」，已闲置 ${idlest.idleDays()} 天');
    }

    // 不足 2 条时补一条材质说明，凑足 2-3 条
    if (reasons.length < 2 && top != null) {
      reasons.add(
          '${MaterialType.name(top.material)}材质，${temperature >= 22 ? '透气舒适' : '触感扎实'}');
    }
    return reasons.take(3).toList();
  }
}

/// 规则推荐引擎 —— 材质维度核心：保暖/透气/排汗评分 + 场合匹配 + 颜色协调 + 轮换均衡
/// + #6 性别过滤 + #8 审美硬规则（主色上限 / 温度硬排除 / 版型平衡 / 新鲜度）
class RecommendationEngine {
  /// 主推荐：今日穿搭
  ///
  /// [excludeIds] 用于「一周计划」这类需要连续出多套不同方案的场景：
  /// 传入上次已经用过的单品 id，避免一周穿同一件上衣。
  ///
  /// [gender] 用户资料里的性别（male/female/other/null）：
  /// male 剔除明显女装、female 反向剔除明显男装；null/other 不过滤。
  ///
  /// [seed] 多样性种子（#12）：null = 纯分数最优（旧行为）；
  /// 传日期盐可让「每天/每次换一套」真的换——引擎会在每个槽位的
  /// top-3 候选里按种子轮换，质量下界仍是 top-3，不会翻车。
  OutfitPlan? recommend({
    required List<Clothing> clothes,
    required double temperature,
    String? occasion,
    String? scenario,
    Set<String> excludeIds = const {},
    String? styleKey,
    String? gender,
    int? seed,
  }) {
    var pool = clothes
        .where((c) =>
            c.wearable &&
            c.matchesTemp(temperature) &&
            !excludeIds.contains(c.id))
        .toList();
    if (pool.isEmpty) return null;

    // #6 按性别搭配：male 剔除明显女装、female 反向；
    // 上衣/下装任一被筛空时回退不过滤（宁可出方案，不可空手而归）
    if (gender == 'male' || gender == 'female') {
      final gendered = OutfitRules.filterByGender(pool, gender);
      final hasTop =
          gendered.any((c) => c.category == ClothingCategory.tops);
      final hasBottom =
          gendered.any((c) => c.category == ClothingCategory.bottoms);
      if (hasTop && hasBottom) pool = gendered;
    }

    // #8 硬排除：温度/场合严重不符的单品不进组合
    pool = pool
        .where((c) =>
            OutfitRules.passesTempHardRule(c, temperature) &&
            OutfitRules.passesOccasionHardRule(c, occasion))
        .toList();

    final needOuter = temperature <= 20;
    final isSport = scenario == OutdoorScenario.hiking ||
        scenario == OutdoorScenario.longRun ||
        occasion == Occasion.sport;

    final tops = pool.where((c) => c.category == ClothingCategory.tops).toList();
    final bottoms = pool.where((c) => c.category == ClothingCategory.bottoms).toList();
    final outers = pool.where((c) => c.category == ClothingCategory.outerwear).toList();
    final shoes = pool.where((c) => c.category == ClothingCategory.shoes).toList();
    final accessories = pool.where((c) => c.category == ClothingCategory.accessories).toList();

    if (tops.isEmpty || bottoms.isEmpty) return null;

    final top = _best(tops, temperature, occasion, isSport, null, styleKey,
        null, seed, 'top');
    // #8 已选主色家族（中性色不计），供后续单品做主色上限/冲突判断
    final chosenFamilies = <String>{};
    void trackFamily(Clothing? c) {
      final f = c == null ? null : OutfitRules.colorFamilyOf(c.color);
      if (f != null && f != 'neutral') chosenFamilies.add(f);
    }

    trackFamily(top);
    final bottom = _best(bottoms, temperature, occasion, isSport, top, styleKey,
        chosenFamilies, seed, 'bottom');
    trackFamily(bottom);
    final outer = needOuter && outers.isNotEmpty
        ? _best(outers, temperature, occasion, isSport, top, styleKey,
            chosenFamilies, seed, 'outer')
        : null;
    trackFamily(outer);
    final shoe = shoes.isNotEmpty
        ? _best(shoes, temperature, occasion, isSport, top, styleKey,
            chosenFamilies, seed, 'shoes')
        : null;
    trackFamily(shoe);
    final acc = accessories.isNotEmpty
        ? _best(accessories, temperature, occasion, isSport, top, styleKey,
            chosenFamilies, seed, 'acc')
        : null;

    final plan = OutfitPlan(
      top: top,
      bottom: bottom,
      outer: outer,
      shoes: shoe,
      accessory: acc,
      score: _matchPercent(top, bottom, outer, temperature),
      reasoning: _buildReasoning(top, bottom, outer, temperature, isSport),
    );
    return plan;
  }

  /// 整套与当前温度的匹配度（0–100），用于界面上显示「适配度」
  double _matchPercent(
      Clothing? top, Clothing? bottom, Clothing? outer, double temp) {
    final ideal = _idealWarmth(temp);
    final parts = <Clothing?>[top, bottom, outer];
    final values = parts.whereType<Clothing>().map((c) {
      final diff = (c.warmthScore - ideal).abs();
      return (10 - diff * 0.9).clamp(0.0, 10.0) / 10;
    }).toList();
    if (values.isEmpty) return 0;
    final avg = values.reduce((a, b) => a + b) / values.length;
    return (avg * 100).clamp(45.0, 99.0);
  }

  /// 户外模式：穿搭 + 装备（[gender] 语义同 recommend，可选）
  OutdoorPlan recommendOutdoor({
    required List<Clothing> clothes,
    required double temperature,
    required String scenario,
    int precipProb = 0,
    double windSpeed = 0,
    String? gender,
  }) {
    final outfit = recommend(
      clothes: clothes,
      temperature: temperature,
      occasion: Occasion.sport,
      scenario: scenario,
      gender: gender,
    ) ??
        const OutfitPlan(score: 0, reasoning: '衣橱数据不足，先录入衣物后可获得完整推荐');

    return OutdoorPlan(
      outfit: outfit,
      gears: _buildGears(scenario, temperature, precipProb, windSpeed),
      scenario: scenario,
      temperature: temperature,
      precipProb: precipProb,
    );
  }

  /// #6/#8 入口：推荐 + 理由 + 性别提示。
  ///
  /// 旁路设计：OutfitPlan 结构不动，理由与 needsGenderHint 挂在
  /// [OutfitRecommendation] 包装类上，由 provider 转发给界面。
  OutfitRecommendation recommendWithReasons({
    required List<Clothing> clothes,
    required double temperature,
    String? occasion,
    String? scenario,
    Set<String> excludeIds = const {},
    String? styleKey,
    String? gender,
    int? seed,
  }) {
    final plan = recommend(
      clothes: clothes,
      temperature: temperature,
      occasion: occasion,
      scenario: scenario,
      excludeIds: excludeIds,
      styleKey: styleKey,
      gender: gender,
      seed: seed,
    );
    final reasons = plan == null
        ? const <String>[]
        : OutfitRules.buildReasons(
            pieces: plan.pieces,
            temperature: temperature,
            occasion: occasion,
          );
    // null/空 → 提示补充；'other'（不愿说）视为已表态，不提示
    return OutfitRecommendation(
      plan: plan,
      reasons: reasons,
      needsGenderHint: gender == null || gender.isEmpty,
    );
  }

  /// 行李清单生成：按天数 × 气候 × 场合
  List<PackingItem> buildPackingItems({
    required List<Clothing> clothes,
    required int days,
    required String climate,
    List<String> occasions = const [],
    double? avgTemp,
  }) {
    final temp = avgTemp ?? _climateTemp(climate);
    final items = <PackingItem>[];
    final n = (id, name, cat, qty, {cid, note}) => PackingItem(
      id: 'pk_$id',
      name: name,
      category: cat,
      quantity: qty,
      clothingId: cid,
      note: note,
    );

    // —— 衣物（优先从衣橱挑，挑不够就给通用条目）——
    final pool = clothes.where((c) => c.wearable && c.matchesTemp(temp)).toList();

    void pickFromWardrobe(
      String category,
      int count,
      String fallbackName) {
      final candidates = pool
          .where((c) => c.category == category)
          .toList()
        ..sort((a, b) => _rotationScore(b).compareTo(_rotationScore(a)));
      final chosen = candidates.take(count).toList();
      for (final c in chosen) {
        items.add(n(c.id, c.displayName, category, 1, cid: c.id,
            note: _materialNote(c)));
      }
      final gap = count - chosen.length;
      if (gap > 0) {
        items.add(n('gen_${category}_$gap', fallbackName, category, gap,
            note: '衣橱中符合条件的不足，需自行准备'));
      }
    }

    final hasSport = occasions.contains(Occasion.sport);
    final hasFormal =
        occasions.contains(Occasion.interview) || occasions.contains(Occasion.work);
    final hasDating = occasions.contains(Occasion.dating);

    pickFromWardrobe(ClothingCategory.tops, days, '上衣 x$days');
    pickFromWardrobe(ClothingCategory.bottoms, (days / 2).ceil(), '下装 x${(days / 2).ceil()}');

    if (temp < 18) {
      pickFromWardrobe(ClothingCategory.outerwear,
          climate == ClimateType.variable ? 2 : 1, '外套');
    }
    pickFromWardrobe(ClothingCategory.shoes, hasSport || hasFormal ? 2 : 1, '鞋子');

    if (hasSport) {
      items.add(n('gear_sport_wear', '速干运动套装', 'gear', 1, note: '含运动场景'));
    }
    if (hasFormal) {
      // 按「风格 = 正式」从衣橱里挑，而不是按不存在的 'formal' 分类
      final formalPieces = clothes
          .where((c) =>
              c.wearable &&
              c.styles.contains(StyleTag.formal) &&
              c.matchesTemp(temp))
          .take(3)
          .toList();
      if (formalPieces.isEmpty) {
        items.add(n('gen_formal', '正装一套（衬衫/西裤/外套）', 'gear', 1,
            note: '衣橱里没有标记「正式」的单品，需自行准备'));
      } else {
        for (final c in formalPieces) {
          items.add(n(c.id, c.displayName, c.category, 1,
              cid: c.id, note: _materialNote(c)));
        }
      }
    }
    if (hasDating) {
      items.add(n('gear_date_look', '约会配饰（首饰/手表）', ClothingCategory.accessories, 1));
    }

    // —— 基础必带 ——
    items.add(n('ess_underwear', '内衣裤', 'essentials', days));
    items.add(n('ess_socks', '袜子', 'essentials', days + 1));
    items.add(n('ess_charger', '充电器 + 充电线', 'essentials', 1));
    items.add(n('ess_toiletries', '洗漱包（牙刷/护肤小样）', 'toiletries', 1));

    // —— 气候附加 ——
    switch (climate) {
      case ClimateType.hot:
        items.add(n('gear_sunscreen', '防晒霜 + 帽子 + 墨镜', 'gear', 1));
        items.add(n('gear_umbrella_uv', '遮阳伞', 'gear', 1));
        break;
      case ClimateType.cold:
        items.add(n('gear_scarf_gloves', '围巾 + 手套', 'gear', 1));
        items.add(n('gear_heat_tech', '保暖内衣', 'essentials', 1));
        break;
      case ClimateType.variable:
        items.add(n('gear_layering', '轻便叠穿马甲/开衫', 'gear', 1, note: '应对温差'));
        items.add(n('gear_umbrella', '雨伞', 'gear', 1));
        break;
      default:
        items.add(n('gear_umbrella_default', '折叠雨伞', 'gear', 1));
    }

    // —— 证件 ——
    items.add(PackingItem(
      id: 'doc_id',
      name: '身份证/证件 + 少量现金',
      category: 'documents',
    ));

    return items;
  }

  // ============ 私有评分逻辑 ============

  /// 单品综合评分
  double _scorePiece(Clothing c, double temp, String? occasion, bool isSport,
      Clothing? reference, [String? styleKey]) {
    var score = 0.0;

    // 材质温度匹配
    final ideal = _idealWarmth(temp);
    final pieceWarmth = c.warmthScore;
    if (c.category == ClothingCategory.outerwear) {
      score += (10 - (pieceWarmth - ideal).abs() * 0.8).clamp(0.0, 10.0) * 0.9;
    } else if (c.category == ClothingCategory.bottoms) {
      score += (10 - (pieceWarmth - ideal).abs() * 0.6).clamp(0.0, 10.0) * 0.5;
    } else {
      score += (10 - (pieceWarmth - ideal).abs() * 0.7).clamp(0.0, 10.0);
    }

    // 场合匹配
    if (occasion != null) {
      if (c.matchesOccasion(occasion)) {
        score += 6;
      } else {
        // 用户明确标注了适穿场合且不含当前场合 → 软惩罚（#11）：
        // 让切换场合能真实改变推荐结果
        score -= 4;
      }
      final occasionStyle = _occasionStyle(occasion);
      if (occasionStyle != null && c.styles.contains(occasionStyle)) score += 4;
    }

    // 风格偏好（灵感卡片：CLEAN FIT / Y2K 等）
    if (styleKey != null) {
      if (c.styles.contains(styleKey) ||
          (c.aiTags ?? const []).contains(styleKey)) {
        // #10：风格权重提到 9（超过温度分差），选中的风格要肉眼可见地变
        score += 9;
      } else {
        // 不符合当前风格 → 小幅降权，拉开风格间差距
        score -= 1.5;
      }
    }

    // 运动/户外：材质运动适配 + 透气
    if (isSport) {
      score += MaterialType.sportOf(c.material) * 0.9;
      score += c.breathabilityScore * 0.5;
      if (c.material == MaterialType.cotton) score -= 4; // 纯棉吸汗难受
      if (c.subCategory == 'sneakers' || c.subCategory == 'joggers' ||
          c.subCategory == 'leggings' || c.subCategory == 'hoodie' ||
          c.subCategory == 'windbreaker') score += 3;
    } else {
      // 日常透气需求（高温时）
      if (temp >= 26) score += c.breathabilityScore * 0.6;
    }

    // 颜色协调（与参考上衣）
    if (reference != null) {
      score += _colorHarmony(reference.color, c.color) * 1.2;
    }

    // 穿着轮换（优先闲置）
    score += _rotationScore(c) * 0.6;

    // 季节匹配
    final month = DateTime.now().month;
    final currentSeason = month <= 2 || month == 12
        ? Season.winter
        : month <= 5 ? Season.spring
        : month <= 8 ? Season.summer : Season.autumn;
    if (c.seasons.contains(currentSeason)) score += 3;

    return score;
  }

  Clothing? _best(List<Clothing> candidates, double temp, String? occasion,
      bool isSport, Clothing? reference,
      [String? styleKey,
      Set<String>? existingFamilies,
      int? seed,
      String slot = '']) {
    if (candidates.isEmpty) return null;
    final scored = <(Clothing, double)>[];
    for (final c in candidates) {
      var s = _scorePiece(c, temp, occasion, isSport, reference, styleKey);
      // #8 审美规则（主色上限 / 色系冲突 / 版型平衡）作为加减分并入
      s += OutfitRules.aestheticDelta(
        candidate: c,
        referenceTop: reference,
        existingFamilies: existingFamilies,
      );
      scored.add((c, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    // #12 多样性：seed 为空时保持纯分数最优（旧语义不变）；
    // 有 seed 时在 top-3 里做稳定轮换——质量下界是 top-3，观感不翻车，
    // 但同一天稳定、换一天/换一次真换。
    if (seed == null) return scored.first.$1;
    final window = scored.length < 3 ? scored.length : 3;
    if (window <= 1) return scored.first.$1;
    var h = seed & 0x3fffffff;
    for (final code in slot.codeUnits) {
      h = (h * 31 + code) & 0x3fffffff;
    }
    return scored[h % window].$1;
  }

  /// 该温度下的理想单品保暖度
  double _idealWarmth(double temp) {
    if (temp >= 30) return 1.5;
    if (temp >= 26) return 3;
    if (temp >= 22) return 4.5;
    if (temp >= 18) return 6;
    if (temp >= 12) return 7.5;
    if (temp >= 6) return 8.5;
    return 9.5;
  }

  /// 颜色协调 0-10：中性色百搭，同色系高级，撞色谨慎
  double _colorHarmony(String colorA, String colorB) {
    final a = _colorFamily(colorA);
    final b = _colorFamily(colorB);
    if (a == null || b == null) return 5;
    if (a == 'neutral' || b == 'neutral') return 8;
    if (a == b) return 7; // 同色系
    // 经典搭配
    const classic = {
      {'blue', 'white'}, {'blue', 'beige'}, {'navy', 'white'},
      {'red', 'beige'}, {'green', 'beige'}, {'brown', 'beige'},
    };
    if (classic.contains(a.compareTo(b) < 0 ? {a, b} : {b, a})) return 6.5;
    return 4; // 撞色
  }

  /// 颜色 → 色系家族（委托 [OutfitRules.colorFamilyOf]，单一实现来源）
  String? _colorFamily(String color) => OutfitRules.colorFamilyOf(color);

  /// 轮换分：越久没穿过分越高（唤醒闲置）—— 委托 [OutfitRules.freshnessScore]
  double _rotationScore(Clothing c) => OutfitRules.freshnessScore(c);

  String? _occasionStyle(String occasion) {
    switch (occasion) {
      case Occasion.work:
      case Occasion.interview:
        return StyleTag.formal;
      case Occasion.sport:
        return StyleTag.sporty;
      case Occasion.dating:
        return StyleTag.dating;
      case Occasion.party:
        return StyleTag.party;
      case Occasion.daily:
        return StyleTag.casual;
    }
    return null;
  }

  double _climateTemp(String climate) {
    switch (climate) {
      case ClimateType.hot:
        return 28;
      case ClimateType.cold:
        return 5;
      case ClimateType.variable:
        return 16;
      default:
        return 18;
    }
  }

  String _materialNote(Clothing c) {
    final m = c.material;
    if (m == null) return '';
    return '${MaterialType.name(m)} · ${MaterialType.tempHint[m] ?? ''}';
  }

  String _buildReasoning(Clothing? top, Clothing? bottom, Clothing? outer, double temp, bool isSport) {
    final parts = <String>[];
    if (temp <= 10) {
      parts.add('${temp.round()}°C 低温，保暖优先');
    } else if (temp >= 28) {
      parts.add('${temp.round()}°C 高温，透气清凉优先');
    } else {
      parts.add('${temp.round()}°C 舒适区间，材质舒适度平衡');
    }
    if (outer != null) {
      parts.add('带${MaterialType.name(outer.material)}外套应对${(temp - 6).round()}°C 早晚凉');
    } else if (temp <= 20) {
      parts.add('未找到合适外套，注意早晚温差');
    }
    if (isSport && top != null) {
      parts.add('运动场景：${MaterialType.name(top.material)}排汗${top.breathabilityScore >= 7 ? '良好' : '一般'}');
    }
    if (top != null && bottom != null) {
      parts.add('${_colorHarmony(top.color, bottom.color) >= 6 ? '配色协调' : '撞色大胆'}');
    }
    return parts.join('；');
  }

  List<PackingItem> _buildGears(String scenario, double temp, int precipProb, double windSpeed) {
    final g = <PackingItem>[];
    void add(String id, String name, [String? note]) =>
        g.add(PackingItem(id: 'gear_$id', name: name, category: 'gear', note: note));

    if (scenario == OutdoorScenario.hiking) {
      add('hiking_shoes', '徒步鞋/登山鞋', '防滑高帮优先');
      add('backpack', '徒步背包 20-30L');
      add('water', '水 1.5L+');
      add('snack', '能量补给（能量胶/坚果）');
      if (temp >= 20) add('sun', '防晒霜 + 遮阳帽', '紫外线强');
      if (precipProb >= 40) add('rain', '雨衣/防雨壳', '降水概率 $precipProb%');
      if (windSpeed >= 20) add('windproof', '防风壳', '风力较大');
      if (temp <= 10) add('warm_layers', '保暖中间层（抓绒/羽绒）');
      add('first_aid', '急救包（创可贴/弹性绷带）');
      add('phone_power', '充电宝', '导航耗电快');
    } else {
      // 长跑
      add('run_shoes', '跑步鞋', '缓震适合长距离');
      add('quickdry_set', '速干上衣 + 跑步短裤');
      if (temp >= 20) add('cap', '空顶帽', '防晒排汗');
      if (temp <= 12) add('gloves_hat', '手套 + 保暖帽');
      add('hydration', '水壶腰包/软水壶');
      add('anti_chafe', '防磨膏/创可贴');
      if (windSpeed >= 15 || precipProb >= 40) add('wind_jacket', '轻量防风衣');
      add('reflective', '反光装备', '夜跑安全');
    }
    return g;
  }
}
