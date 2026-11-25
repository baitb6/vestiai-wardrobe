import '../models/models.dart';

/// 中文完整名称：优先用户自定义名称，否则「颜色 + 衣物类型」。
/// 只输出中文（类型本身如「T恤」「Polo衫」自带字母属于通用中文写法），
/// 不再追加任何英文标签。颜色是词典外的拉丁词（#15 AI 自报色直存）时
/// 中间补一个空格，避免拼出「CreamT恤」。
String clothingDisplayName(Clothing c) {
  final custom = c.customName?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  final type = ClothingSubCategory.names[c.subCategory] ??
      ClothingCategory.names[c.category] ??
      ClothingCategory.names[ClothingCategory.tops]!;
  final color = c.color.trim();
  if (color.isEmpty) return type;
  if (color.contains(type)) return color; // 用户已写「白色T恤」时不重复
  final sep = _hasCjk(color) ? '' : ' ';
  return '$color$sep$type';
}

/// 整套穿搭的自动命名（#7 / #9 / #16）：
/// 取前 [max] 件按穿戴顺序用「×」连接，如「白色T恤×黑色阔腿裤」。
/// 件数不足或名称全空时回退 [fallback]。
String outfitAutoName(List<Clothing> pieces,
    {int max = 3, String fallback = '今日穿搭'}) {
  final names = pieces
      .take(max)
      .map(clothingDisplayName)
      .where((n) => n.trim().isNotEmpty)
      .toList();
  if (names.isEmpty) return fallback;
  return names.join('×');
}

/// 副标题：材质、图案、品牌、自定义属性，全部中文，最多三段。
String clothingSecondaryLabel(Clothing c) {
  final parts = <String>[];
  final pattern = c.pattern?.trim();
  if (pattern != null && pattern.isNotEmpty) parts.add(pattern);
  final material = c.material?.trim();
  if (material != null && material.isNotEmpty) {
    parts.add(MaterialType.names[material] ?? material);
  }
  final brand = c.brand?.trim();
  if (brand != null && brand.isNotEmpty) parts.add(brand);
  for (final v in c.extraAttributes?.values ?? const <String>[]) {
    if (v.trim().isNotEmpty) parts.add(v.trim());
  }
  if (parts.isEmpty) {
    final season = c.seasons.isNotEmpty ? (Season.names[c.seasons.first] ?? '') : '';
    final style = c.styles.isNotEmpty ? (StyleTag.names[c.styles.first] ?? '') : '';
    return [season, style].where((e) => e.isNotEmpty).join(' · ');
  }
  return parts.take(3).join(' · ');
}

/// 颜色预设：比原来只有 8 个基础色丰富得多，仍允许自由输入。
class ColorPresets {
  static const List<String> all = <String>[
    '白色', '米白', '奶油色', '象牙白', '浅灰', '灰色', '深灰', '炭黑', '黑色',
    '燕麦色', '卡其色', '驼色', '焦糖色', '棕色', '巧克力色', '杏色', '裸粉',
    '粉色', '珊瑚粉', '红色', '酒红', '砖红', '橙色', '南瓜色', '姜黄色',
    '黄色', '鹅黄色', '浅绿', '薄荷绿', '军绿', '橄榄绿', '墨绿', '绿色',
    '天蓝', '雾霾蓝', '浅蓝', '蓝色', '藏青', '深蓝', '牛仔蓝', '紫色',
    '香芋紫', '薰衣草紫', '银色', '金色', '多色', '拼色', '印花',
  ];

  /// 常用色（快捷 chips），其余在「更多颜色」里
  static const List<String> quick = <String>[
    '白色', '黑色', '灰色', '米白', '卡其色', '藏青', '牛仔蓝', '粉色',
    '红色', '墨绿', '焦糖色', '紫色',
  ];
}

/// 材质预设：在系统 13 种之外补充常见叫法，支持自定义。
class MaterialPresets {
  static const List<String> all = <String>[
    '纯棉', '羊毛', '羊绒', '亚麻', '真丝', '速干', '牛仔', '聚酯纤维',
    '锦纶', '羽绒', '皮革', '混纺', '灯芯绒', '天丝', '莫代尔', '醋酸',
    '蕾丝', '针织', '摇粒绒', '雪纺', '棉麻', '帆布', '抓绒', '冲锋衣面料',
  ];
}

/// 风格预设（系统内置，可追加自定义项）。
class StylePresets {
  static const List<String> builtin = <String>[
    '极简', '通勤', '休闲', '运动', '街头', '复古', '学院风', '法式',
    '日系', '甜酷', '辣妹', '户外', '商务', '约会', '度假', '中性风',
  ];
}

// ============================================================
// #1 衣物名称 100% 中文：英文标签 → 「颜色 + 品类」
// ============================================================

/// 英文颜色（含 light gray / navy blue 等组合写法）→ 中文。
/// 键为归一化形式：小写、去掉空格/下划线/连字符/撇号。
const Map<String, String> _enColorNames = {
  // 单词
  'white': '白色', 'black': '黑色', 'gray': '灰色', 'grey': '灰色',
  'silver': '银色', 'platinum': '银色', 'gold': '金色', 'beige': '米色',
  'cream': '米白', 'ivory': '象牙白', 'oyster': '米白', 'ecru': '米白',
  'camel': '驼色', 'brown': '棕色', 'coffee': '咖啡色', 'chestnut': '棕色',
  'walnut': '棕色', 'khaki': '卡其色', 'tan': '棕褐色', 'sandy': '米色',
  'sand': '米色', 'oat': '燕麦色', 'oatmeal': '燕麦色', 'taupe': '灰色',
  'mushroom': '灰色', 'navy': '藏青', 'indigo': '藏青', 'blue': '蓝色',
  'cobalt': '蓝色', 'red': '红色', 'scarlet': '红色', 'vermilion': '红色',
  'wine': '酒红', 'burgundy': '酒红', 'maroon': '酒红', 'berry': '酒红',
  'crimson': '酒红', 'rust': '砖红', 'brick': '砖红', 'pink': '粉色',
  'blush': '裸粉', 'rose': '裸粉', 'nude': '裸粉', 'coral': '珊瑚粉',
  'peach': '杏色', 'apricot': '杏色', 'almond': '杏色', 'orange': '橙色',
  'yellow': '黄色', 'mustard': '姜黄色', 'lemon': '鹅黄色', 'green': '绿色',
  'emerald': '绿色', 'olive': '橄榄绿', 'mint': '薄荷绿', 'teal': '墨绿',
  'forest': '墨绿', 'purple': '紫色', 'lavender': '薰衣草紫',
  'lilac': '薰衣草紫', 'violet': '香芋紫', 'plum': '香芋紫',
  'fuchsia': '粉色', 'magenta': '粉色', 'charcoal': '炭黑', 'onyx': '黑色',
  'jet': '黑色', 'snow': '白色', 'pearl': '米白', 'denim': '牛仔蓝',
  'sage': '灰豆绿', 'slate': '灰色', 'stone': '灰色', 'pewter': '灰色',
  'graphite': '深灰', 'rosebrown': '裸粉', 'caramel': '焦糖色',
  'chocolate': '巧克力色', 'butterscotch': '焦糖色', 'ginger': '姜黄色',
  // 组合词
  'lightgray': '浅灰', 'lightgrey': '浅灰', 'ashgray': '浅灰',
  'foggray': '浅灰', 'smokegray': '灰色', 'silvergray': '银色',
  'steelgray': '灰色', 'darkgray': '深灰', 'darkgrey': '深灰',
  'charcoalgray': '炭黑', 'jetblack': '黑色', 'pureblack': '黑色',
  'offwhite': '米白', 'milkywhite': '米白', 'offblack': '黑色',
  'purewhite': '白色', 'lightblue': '浅蓝', 'babyblue': '浅蓝',
  'aqua': '浅蓝', 'aquaazure': '浅蓝', 'skyblue': '天蓝', 'cyan': '天蓝',
  'turquoise': '天蓝', 'darkblue': '深蓝', 'deepblue': '深蓝',
  'navyblue': '藏青', 'midnightblue': '藏青', 'inkblue': '藏青',
  'royalblue': '宝蓝', 'sapphire': '宝蓝', 'periwinkle': '雾霾蓝',
  'lightgreyblue': '雾霾蓝', 'armygreen': '军绿', 'army': '军绿',
  'militarygreen': '军绿', 'camouflage': '军绿', 'olivegreen': '橄榄绿',
  'sagegreen': '灰豆绿', 'greige': '灰豆绿', 'mintgreen': '薄荷绿',
  'darkgreen': '墨绿', 'forestgreen': '墨绿', 'emeraldgreen': '绿色',
  'lightgreen': '浅绿', 'lime': '浅绿', 'limegreen': '浅绿',
  'darkbrown': '深棕', 'lightbrown': '浅棕', 'coffeebrown': '咖啡色',
  'coralpink': '珊瑚粉', 'palepink': '裸粉', 'dustypink': '裸粉',
  'dustyrose': '裸粉', 'lightpink': '裸粉', 'darkpink': '粉色',
  'rosegold': '金色', 'darkred': '酒红', 'deepred': '酒红',
  'brightred': '红色', 'mustardyellow': '姜黄色', 'lemonyellow': '鹅黄色',
  'darkpurple': '紫色', 'lightpurple': '香芋紫', 'darkviolet': '香芋紫',
};

/// 英文品类（归一化键）→ 内部子分类 key，再经
/// [ClothingSubCategory.names] 得到中文品类名。
const Map<String, String> _enSubKeys = {
  // 上衣
  'tshirt': 't_shirt', 'tee': 't_shirt', 'shirt': 'shirt',
  'dressshirt': 'shirt', 'oxfordshirt': 'shirt', 'sweater': 'sweater',
  'knit': 'sweater', 'knitwear': 'sweater', 'pullover': 'sweater',
  'jumper': 'sweater', 'hoodie': 'hoodie', 'sweatshirt': 'hoodie',
  'blouse': 'blouse', 'tanktop': 'tank_top', 'tank': 'tank_top',
  'camisole': 'tank_top', 'camitop': 'tank_top', 'polo': 'polo',
  'poloshirt': 'polo',
  // 下装
  'jeans': 'jeans', 'denimjeans': 'jeans', 'pants': 'trousers',
  'trousers': 'trousers', 'slacks': 'trousers', 'chinos': 'trousers',
  'khakis': 'trousers', 'suitpants': 'trousers', 'shorts': 'shorts',
  'skirt': 'skirt', 'miniskirt': 'skirt', 'pleatedskirt': 'skirt',
  'leggings': 'leggings', 'joggers': 'joggers', 'sweatpants': 'joggers',
  'trackpants': 'joggers', 'cargopants': 'joggers', 'cargo': 'joggers',
  // 连衣裙
  'dress': 'casual_dress', 'sundress': 'casual_dress', 'gown': 'formal_dress',
  'minidress': 'mini_dress', 'mididress': 'midi_dress', 'maxidress': 'maxi_dress',
  // 外套
  'coat': 'coat', 'overcoat': 'coat', 'parka': 'coat', 'trenchcoat': 'coat',
  'trench': 'coat', 'dufflecoat': 'coat', 'jacket': 'jacket',
  'downjacket': 'jacket', 'pufferjacket': 'jacket', 'puffer': 'jacket',
  'bomberjacket': 'jacket', 'bomber': 'jacket', 'leatherjacket': 'jacket',
  'denimjacket': 'jacket', 'bikerjacket': 'jacket', 'varsityjacket': 'jacket',
  'blazer': 'blazer', 'suit': 'blazer', 'suitjacket': 'blazer',
  'vest': 'vest', 'waistcoat': 'vest', 'windbreaker': 'windbreaker',
  'windcheater': 'windbreaker', 'cardigan': 'cardigan',
  // 鞋
  'sneakers': 'sneakers', 'sneaker': 'sneakers', 'trainers': 'sneakers',
  'runningshoes': 'sneakers', 'boardshoes': 'sneakers', 'boots': 'boots',
  'boot': 'boots', 'ankleboots': 'boots', 'chelseaboots': 'boots',
  'cowboyboots': 'boots', 'heels': 'heels', 'highheels': 'heels',
  'pumps': 'heels', 'stilettos': 'heels', 'flats': 'flats',
  'slippers': 'flats', 'sandals': 'sandals', 'sandal': 'sandals',
  'loafers': 'loafers', 'loafer': 'loafers', 'moccasins': 'loafers',
  // 配饰
  'bag': 'bag', 'handbag': 'bag', 'tote': 'bag', 'totebag': 'bag',
  'backpack': 'bag', 'rucksack': 'bag', 'shoulderbag': 'bag',
  'crossbodybag': 'bag', 'messengerbag': 'bag', 'clutch': 'bag',
  'purse': 'bag', 'wallet': 'bag', 'hat': 'hat', 'cap': 'hat',
  'beanie': 'hat', 'baseballcap': 'hat', 'buckethat': 'hat', 'fedora': 'hat',
  'scarf': 'scarf', 'shawl': 'scarf', 'belt': 'belt', 'watch': 'watch',
  'jewelry': 'jewelry', 'jewellery': 'jewelry', 'necklace': 'jewelry',
  'earrings': 'jewelry', 'bracelet': 'jewelry', 'ring': 'jewelry',
  'sunglasses': 'sunglasses', 'glasses': 'sunglasses',
};

/// 英文主分类（归一化键）→ 内部主分类 key（兜底用）。
const Map<String, String> _enCategoryKeys = {
  'tops': 'tops', 'top': 'tops', 'bottoms': 'bottoms', 'bottom': 'bottoms',
  'outerwear': 'outerwear', 'shoes': 'shoes', 'footwear': 'shoes',
  'accessories': 'accessories', 'accessory': 'accessories',
};

/// 英文图案 → 中文。
const Map<String, String> _enPatternNames = {
  'solid': '纯色', 'plain': '纯色', 'stripe': '条纹', 'striped': '条纹',
  'pinstripe': '细条纹', 'plaid': '格子', 'check': '格子', 'checked': '格子',
  'gingham': '格子', 'tartan': '格子', 'floral': '印花', 'flower': '印花',
  'print': '印花', 'printed': '印花', 'graphic': '印花', 'logo': '印花',
  'dot': '波点', 'dotted': '波点', 'polka': '波点', 'polkadot': '波点',
  'leopard': '豹纹', 'cheetah': '豹纹', 'camo': '迷彩', 'camouflage': '迷彩',
  'tiedye': '扎染', 'patchwork': '拼色', 'geometric': '几何',
  'abstract': '抽象', 'animal': '动物纹',
};

/// 常见品牌词典（归一化键，大小写不敏感）。命中即剥离进 brand。
const Set<String> _knownBrandKeys = {
  'uniqlo', 'zara', 'hm', 'h&m', 'nike', 'adidas', 'puma', 'newbalance',
  'nb', 'muji', 'gucci', 'louisvuitton', 'lv', 'supreme', 'champion',
  'levis', 'lee', 'wrangler', 'thenorthface', 'northface', 'columbia',
  'patagonia', 'underarmour', 'ua', 'lacoste', 'ralphlauren',
  'tommyhilfiger', 'tommy', 'calvinklein', 'ck', 'burberry', 'moncler',
  'canadagoose', 'lululemon', 'fila', 'anta', 'balenciaga', 'prada',
  'chanel', 'dior', 'armani', 'versace', 'kenzo', 'gap', 'oldnavy',
  'bananarepublic', 'everlane', 'cos', 'massimodutti', 'bershka',
  'pullandbear', 'stradivarius', 'jackjones', 'gxg', 'crocs', 'vans',
  'converse', 'skechers', 'sketchers', 'asics', 'mizuno', 'umbro', 'kappa',
  'reebok', 'hollister', 'abercrombie', 'carhartt', 'dickies', 'stussy',
  'bosie', 'onitsukatiger', 'cicadahood',
};

/// 中文品牌词：中文串里出现即剥离进 brand，不进名称。
const Set<String> _cjkBrandWords = {
  '优衣库', '无印良品', '耐克', '阿迪达斯', '阿迪', '李宁', '安踏', '特步',
  '匹克', '波司登', '太平鸟', '海澜之家', '江南布衣', '之禾', '伊芙丽',
  '歌莉娅', '欧时力', '猫人', '都市丽人', '恒源祥',
};

/// 尺码类词：直接丢弃，绝不进名称，也不当品牌。
const Set<String> _sizeKeys = {
  'xs', 's', 'm', 'l', 'xl', 'xxl', 'xxxl', '2xl', '3xl', '4xl',
  'onesize', 'freesize', 'size',
};

final RegExp _cjkRe = RegExp(r'[\u4e00-\u9fff]');
final RegExp _tokenSplitRe = RegExp(r"[^0-9A-Za-z\u4e00-\u9fff&']+");

bool _hasCjk(String s) => _cjkRe.hasMatch(s);

String _normKey(String s) =>
    s.toLowerCase().replaceAll(RegExp(r"[\s_\-·'’]"), '');

/// 英文颜色 → 中文；中文原样返回；映射不到返回 null。
String? toChineseColor(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (_hasCjk(s)) return s;
  return _enColorNames[_normKey(s)];
}

/// #15 AI 自报颜色直存：词典命中 → 标准中文色；中文原文 → 原样保留；
/// 词典外的拉丁字母色 → 保留原文并把首字母大写（cream → Cream）。
/// 预设色只作匹配优先，绝不把 AI 色强改写进固定枚举。
String normalizeAiColor(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  final zh = toChineseColor(s);
  if (zh != null) return zh;
  if (RegExp(r'^[A-Za-z]').hasMatch(s)) {
    return s.substring(0, 1).toUpperCase() + s.substring(1);
  }
  return s;
}

/// 英文图案 → 中文；中文原样返回；映射不到返回 null。
String? toChinesePattern(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (_hasCjk(s)) return s;
  return _enPatternNames[_normKey(s)];
}

/// 解析结果：[name] 是「颜色 + 品类」的中文全名；[brand] 是剥离出的
/// 品牌词（可能为 null，调用方放进详情，不进名称）。
class ChineseClothingName {
  final String name;
  final String? brand;

  /// 名称里是否有品类信息：没有品类（只剩颜色）时调用方不应把
  /// 该名称写进 customName（宁缺毋滥，落回动态「颜色+类型」命名）。
  final bool hasCategory;

  const ChineseClothingName({
    required this.name,
    required this.hasCategory,
    this.brand,
  });

  bool get isEmpty => name.isEmpty && (brand == null || brand!.isEmpty);
}

/// 把一串可能中英混杂的原始衣物描述（模型标签、subCategory、
/// 「Uniqlo Beige Cardigan」之类）解析成中文「颜色 + 品类」与品牌。
///
/// 规则：
/// - 英文颜色/品类/图案按词典映射成中文；
/// - 品牌词（品牌词典或首字母大写专名）剥离进 [ChineseClothingName.brand]；
/// - 映射不到的英文词直接丢弃，宁缺毋滥；
/// - 中文片段原样保留；[colorHint] 在原文没有颜色时兜底。
ChineseClothingName parseChineseClothingName(String raw, {String? colorHint}) {
  final src = raw.trim();
  if (src.isEmpty) {
    final hint = _hintColor(colorHint);
    return ChineseClothingName(
        name: hint ?? '', hasCategory: false, brand: null);
  }

  final tokens = src
      .split(_tokenSplitRe)
      .where((t) => t.isNotEmpty)
      .toList();

  String color = '';
  String? subKey;
  String? categoryKey;
  String? pattern;
  String? brand;
  final zhParts = <String>[];

  var i = 0;
  while (i < tokens.length) {
    final token = tokens[i];
    if (_hasCjk(token)) {
      // 中文品牌词剥离；其余中文原样保留
      if (brand == null && _cjkBrandWords.contains(token)) {
        brand = token;
      } else {
        zhParts.add(token);
      }
      i++;
      continue;
    }

    // 3/2/1-gram：先试长组合（light gray / tank top / The North Face）
    var matched = false;
    for (var n = 3; n >= 1; n--) {
      if (i + n > tokens.length) continue;
      final join = _normKey(tokens.sublist(i, i + n).join(''));
      if (join.isEmpty) continue;
      if (subKey == null && _enSubKeys.containsKey(join)) {
        subKey = _enSubKeys[join]!;
        i += n;
        matched = true;
        break;
      }
      if (color.isEmpty && _enColorNames.containsKey(join)) {
        color = _enColorNames[join]!;
        i += n;
        matched = true;
        break;
      }
      if (pattern == null && _enPatternNames.containsKey(join)) {
        pattern = _enPatternNames[join]!;
        i += n;
        matched = true;
        break;
      }
      if (brand == null && _knownBrandKeys.contains(join)) {
        brand = tokens.sublist(i, i + n).join(' ');
        i += n;
        matched = true;
        break;
      }
      if (categoryKey == null && _enCategoryKeys.containsKey(join)) {
        categoryKey = _enCategoryKeys[join]!;
        i += n;
        matched = true;
        break;
      }
    }
    if (matched) continue;

    // 单词未命中任何词典：尺码丢弃；首字母大写专名视作品牌；
    // 但词典里已有的品类/颜色/图案词（如「Knit Sweater」里的 Sweater、
    // 「Shirt Dress」里的 Dress）不当品牌，否则品牌栏会出现「Sweater」
    final key = _normKey(token);
    if (_sizeKeys.contains(key)) {
      i++;
      continue;
    }
    if (brand == null &&
        _looksLikeBrand(token) &&
        !_enSubKeys.containsKey(key) &&
        !_enCategoryKeys.containsKey(key) &&
        !_enColorNames.containsKey(key) &&
        !_enPatternNames.containsKey(key)) {
      brand = token;
    }
    i++;
  }

  final typeZh = subKey != null
      ? ClothingSubCategory.names[subKey]
      : (categoryKey != null ? ClothingCategory.names[categoryKey] : null);

  if (zhParts.isNotEmpty) {
    var name = zhParts.join();
    // 混写（「米色 cardigan」）：透传中文 + 已映射的英文品类
    if (typeZh != null && !name.contains(typeZh)) {
      name = '$name$typeZh';
    }
    final hint = _hintColor(colorHint) ?? color;
    if (hint != null &&
        hint.isNotEmpty &&
        !name.contains(hint) &&
        !_zhNameHasColor(name)) {
      name = '$hint$name';
    }
    final pureColor = _isZhColorWord(name);
    return ChineseClothingName(
      name: name,
      hasCategory: !pureColor,
      brand: brand,
    );
  }

  final colorPart = color.isNotEmpty ? color : (_hintColor(colorHint) ?? '');
  final name = '$colorPart${typeZh ?? ''}';
  return ChineseClothingName(
    name: name,
    hasCategory: typeZh != null,
    brand: brand,
  );
}

/// 便捷入口：只取中文全名。
String toChineseClothingName(String raw, {String? colorHint}) =>
    parseChineseClothingName(raw, colorHint: colorHint).name;

/// 颜色提示归一：英文翻译成中文；中文单字补「色」；映射不到丢弃。
String? _hintColor(String? hint) {
  final h = hint?.trim();
  if (h == null || h.isEmpty) return null;
  final zh = toChineseColor(h);
  if (zh != null) return zh;
  if (_hasCjk(h)) return h.length == 1 ? '$h色' : h;
  return null;
}

/// 首字母大写、纯字母（允许 & 和 '）且长度 ≥ 2 → 视作品牌专名。
bool _looksLikeBrand(String token) {
  if (token.length < 2) return false;
  final first = token.codeUnitAt(0);
  final upper = first >= 0x41 && first <= 0x5A;
  if (!upper) return false;
  if (!RegExp(r"^[A-Za-z&']+").hasMatch(token)) return false;
  return true;
}

/// 中文名称里是否已带颜色词（避免「藏青藏青连衣裙」式重复）。
bool _zhNameHasColor(String name) {
  for (final preset in ColorPresets.all) {
    if (name.contains(preset)) return true;
  }
  // 词典还会产出 ColorPresets 之外的中文色（米色/宝蓝/咖啡色/棕褐色/
  // 灰豆绿/深棕/浅棕等），同样算已带颜色，避免「蓝色宝蓝连衣裙」式重复
  for (final zh in _enColorNames.values) {
    if (name.contains(zh)) return true;
  }
  // 「白T恤」「黑裙子」：开头单字颜色 + 后续内容也算已带颜色
  if (name.length > 1) {
    final first = name.substring(0, 1);
    if ('黑白灰红蓝绿黄紫粉棕驼米杏青橘'.contains(first)) return true;
  }
  return false;
}

/// 判断中文字符串是不是一个纯颜色词（不是品类）。
bool _isZhColorWord(String w) {
  if (ColorPresets.all.contains(w)) return true;
  if (w.length == 2 && w.endsWith('色')) return true;
  if (w.length == 1 && '黑白灰红蓝绿黄紫粉棕驼米杏青橘'.contains(w)) return true;
  return false;
}
