import '../models/models.dart';

/// 模型输出的中文标签 → 本地内部常量。
/// 模型五花八门，这里做一次归一，避免脏数据把统计和推荐打乱。
class AiMapping {
  /// 分类：中文/英文 → 内部 key
  static String category(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s.isEmpty) return ClothingCategory.tops;

    const direct = {
      'tops': ClothingCategory.tops,
      'outerwear': ClothingCategory.outerwear,
      'bottoms': ClothingCategory.bottoms,
      'shoes': ClothingCategory.shoes,
      'accessories': ClothingCategory.accessories,
      'dress': ClothingCategory.dress,
      'bag': ClothingCategory.accessories,
      'bags': ClothingCategory.accessories,
    };
    if (direct.containsKey(s)) return direct[s]!;

    if (s.contains('外套') || s.contains('大衣') || s.contains('夹克') ||
        s.contains('风衣') || s.contains('羽绒') || s.contains('coat') ||
        s.contains('jacket')) {
      return ClothingCategory.outerwear;
    }
    if (s.contains('连衣裙') || s.contains('裙子') ||
        s.contains('dress') && !s.contains('trousers')) {
      return ClothingCategory.dress;
    }
    if (s.contains('下装') || s.contains('裤') || s.contains('短裤') ||
        s.contains('裙') || s.contains('pants') || s.contains('jeans') ||
        s.contains('skirt')) {
      return ClothingCategory.bottoms;
    }
    if (s.contains('鞋') || s.contains('靴') || s.contains('shoe') ||
        s.contains('boot') || s.contains('sneaker') || s.contains('sandal')) {
      return ClothingCategory.shoes;
    }
    if (s.contains('包') || s.contains('帽') || s.contains('围巾') ||
        s.contains('腰带') || s.contains('首饰') || s.contains('眼镜') ||
        s.contains('配饰') || s.contains('bag') || s.contains('hat') ||
        s.contains('scarf') || s.contains('belt') || s.contains('watch')) {
      return ClothingCategory.accessories;
    }
    if (s.contains('上衣') || s.contains('t恤') || s.contains('衬衫') ||
        s.contains('毛衣') || s.contains('卫衣') || s.contains('背心') ||
        s.contains('shirt') || s.contains('top') || s.contains('sweater') ||
        s.contains('hoodie')) {
      return ClothingCategory.tops;
    }
    return ClothingCategory.tops;
  }

  static const Map<String, String> _subKeywords = {
    't_shirt': 't恤,tee,t-shirt,短袖',
    'shirt': '衬衫,shirt',
    'sweater': '毛衣,针织衫,sweater,knit',
    'hoodie': '卫衣,hoodie,sweatshirt',
    'blouse': '女衬衫,blouse',
    'tank_top': '背心,tank,吊带',
    'polo': 'polo',
    'jeans': '牛仔,jeans,denim',
    'trousers': '西裤,长裤,休闲裤,trousers,pants,slacks',
    'shorts': '短裤,shorts',
    'skirt': '半身裙,skirt',
    'leggings': '紧身裤,leggings,打底裤',
    'joggers': '运动裤,joggers,sweatpants',
    'coat': '大衣,coat',
    'jacket': '夹克,jacket,外套',
    'blazer': '西装,blazer,suit',
    'vest': '马甲,vest',
    'windbreaker': '风衣,防风,windbreaker',
    'cardigan': '开衫,cardigan',
    'sneakers': '运动鞋,球鞋,sneaker,sneakers,板鞋',
    'boots': '靴,boot',
    'heels': '高跟,heels',
    'flats': '平底,flats,单鞋',
    'sandals': '凉鞋,sandal',
    'loafers': '乐福,loafer',
    'bag': '包,bag,背包,手提包,tote',
    'hat': '帽,hat,cap',
    'scarf': '围巾,scarf',
    'belt': '腰带,皮带,belt',
    'watch': '手表,watch',
    'jewelry': '首饰,项链,耳环,jewelry,necklace,earring',
    'sunglasses': '墨镜,太阳镜,sunglasses',
  };

  /// 子分类：中文/英文 → 内部 key；找不到就按主分类兜底
  static String subCategory(String? raw, String category) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s.isNotEmpty) {
      // 已经是合法 key 就直接用
      if (ClothingSubCategory.names.containsKey(s)) return s;
      for (final entry in _subKeywords.entries) {
        for (final kw in entry.value.split(',')) {
          if (kw.isNotEmpty && s.contains(kw)) return entry.key;
        }
      }
    }
    final list = ClothingSubCategory.subCategories[category];
    if (list != null && list.isNotEmpty) return list.first;
    return 't_shirt';
  }

  static const Map<String, String> _styleMap = {
    '休闲': StyleTag.casual,
    '日常': StyleTag.casual,
    '通勤': StyleTag.business,
    '商务': StyleTag.business,
    '正式': StyleTag.formal,
    '运动': StyleTag.sporty,
    '户外': StyleTag.sporty,
    '约会': StyleTag.dating,
    '派对': StyleTag.party,
    '极简': StyleTag.minimalist,
    '简约': StyleTag.minimalist,
    '复古': StyleTag.vintage,
    '街头': StyleTag.streetwear,
    '潮流': StyleTag.streetwear,
  };

  static List<String> styles(List<String>? raw) {
    final out = <String>{};
    for (final r in raw ?? const <String>[]) {
      final s = r.trim().toLowerCase();
      if (s.isEmpty) continue;
      if (StyleTag.names.containsKey(s)) {
        out.add(s);
      } else if (_styleMap.containsKey(r.trim())) {
        out.add(_styleMap[r.trim()]!);
      } else {
        // 未知标签保留原文，进 tags 而不是 styles
      }
    }
    return out.toList();
  }

  /// 模型给的未知标签（比如「法式」「学院」）保留成自由标签
  static List<String> extraTags(List<String>? raw) {
    final out = <String>[];
    for (final r in raw ?? const <String>[]) {
      final t = r.trim();
      if (t.isEmpty) continue;
      if (StyleTag.names.containsKey(t.toLowerCase())) continue;
      if (_styleMap.containsKey(t)) continue;
      out.add(t);
    }
    return out;
  }

  static const Map<String, String> _seasonMap = {
    '春': Season.spring,
    '春季': Season.spring,
    'spring': Season.spring,
    '夏': Season.summer,
    '夏季': Season.summer,
    'summer': Season.summer,
    '秋': Season.autumn,
    '秋季': Season.autumn,
    'autumn': Season.autumn,
    'fall': Season.autumn,
    '冬': Season.winter,
    '冬季': Season.winter,
    'winter': Season.winter,
    '四季': '',
  };

  static List<String> seasons(List<String>? raw) {
    final out = <String>{};
    for (final r in raw ?? const <String>[]) {
      final key = r.trim().toLowerCase();
      final mapped = _seasonMap[key] ?? _seasonMap[r.trim()];
      if (mapped != null && mapped.isNotEmpty) out.add(mapped);
    }
    return out.toList();
  }

  /// 颜色清洗：去空白、去「色」后缀、去重
  static List<String> colors(List<String>? raw) {
    final out = <String>[];
    for (final r in raw ?? const <String>[]) {
      var c = r.trim();
      if (c.isEmpty) continue;
      if (c.length > 1 && c.endsWith('色')) c = c.substring(0, c.length - 1);
      if (c.length > 6) continue;
      if (!out.contains(c)) out.add(c);
    }
    return out;
  }

  /// 按厚度/温度补一个默认材质，避免推荐引擎拿到 null
  static String? materialFromCategory(String category) {
    switch (category) {
      case ClothingCategory.shoes:
        return MaterialType.leather;
      case ClothingCategory.accessories:
        return MaterialType.other;
      default:
        return null;
    }
  }
}
