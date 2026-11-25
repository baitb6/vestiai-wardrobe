export 'bbox.dart';
export 'clothing.dart';
export 'outfit.dart';
export 'outfit_record.dart';
export 'user_profile.dart';
export 'packing_list.dart';
export 'split_candidate.dart';
export 'split_task.dart';
export 'try_on_task.dart';
export 'wish_item.dart';
export 'wardrobe_space.dart';

// 衣服分类常量
class ClothingCategory {
  static const String tops = 'tops';
  static const String bottoms = 'bottoms';
  static const String dress = 'dress';
  static const String outerwear = 'outerwear';
  static const String shoes = 'shoes';
  static const String accessories = 'accessories';

  static const Map<String, String> names = {
    tops: '上衣',
    bottoms: '下装',
    dress: '裙装',
    outerwear: '外套',
    shoes: '鞋子',
    accessories: '配饰',
  };

  static const Map<String, String> icons = {
    tops: '👕',
    bottoms: '👖',
    dress: '👗',
    outerwear: '🧥',
    shoes: '👟',
    accessories: '👜',
  };
}

// 衣服子分类
class ClothingSubCategory {
  static const Map<String, List<String>> subCategories = {
    'tops': ['t_shirt', 'shirt', 'sweater', 'hoodie', 'blouse', 'tank_top', 'polo'],
    'bottoms': ['jeans', 'trousers', 'shorts', 'skirt', 'leggings', 'joggers'],
    'dress': ['mini_dress', 'midi_dress', 'maxi_dress', 'casual_dress', 'formal_dress'],
    'outerwear': ['coat', 'jacket', 'blazer', 'vest', 'windbreaker', 'cardigan'],
    'shoes': ['sneakers', 'boots', 'heels', 'flats', 'sandals', 'loafers'],
    'accessories': ['bag', 'hat', 'scarf', 'belt', 'watch', 'jewelry', 'sunglasses'],
  };

  static const Map<String, String> names = {
    't_shirt': 'T恤',
    'shirt': '衬衫',
    'sweater': '毛衣',
    'hoodie': '卫衣',
    'blouse': '女衬衫',
    'tank_top': '背心',
    'polo': 'Polo衫',
    'jeans': '牛仔裤',
    'trousers': '西裤',
    'shorts': '短裤',
    'skirt': '裙子',
    'leggings': '紧身裤',
    'joggers': '运动裤',
    'mini_dress': '短裙',
    'midi_dress': '中长裙',
    'maxi_dress': '长裙',
    'casual_dress': '休闲裙',
    'formal_dress': '正装裙',
    'coat': '大衣',
    'jacket': '夹克',
    'blazer': '西装外套',
    'vest': '马甲',
    'windbreaker': '风衣',
    'cardigan': '针织开衫',
    'sneakers': '运动鞋',
    'boots': '靴子',
    'heels': '高跟鞋',
    'flats': '平底鞋',
    'sandals': '凉鞋',
    'loafers': '乐福鞋',
    'bag': '包',
    'hat': '帽子',
    'scarf': '围巾',
    'belt': '腰带',
    'watch': '手表',
    'jewelry': '首饰',
    'sunglasses': '太阳镜',
  };
}

// 风格标签
class StyleTag {
  static const String casual = 'casual';
  static const String formal = 'formal';
  static const String sporty = 'sporty';
  static const String dating = 'dating';
  static const String business = 'business';
  static const String party = 'party';
  static const String minimalist = 'minimalist';
  static const String vintage = 'vintage';
  static const String streetwear = 'streetwear';

  static const Map<String, String> names = {
    casual: '休闲',
    formal: '正式',
    sporty: '运动',
    dating: '约会',
    business: '商务',
    party: '派对',
    minimalist: '极简',
    vintage: '复古',
    streetwear: '街头',
  };
}

// 季节
class Season {
  static const String spring = 'spring';
  static const String summer = 'summer';
  static const String autumn = 'autumn';
  static const String winter = 'winter';

  static const Map<String, String> names = {
    spring: '春季',
    summer: '夏季',
    autumn: '秋季',
    winter: '冬季',
  };
}

// 位置状态
class LocationStatus {
  static const String inWardrobe = 'in_wardrobe';
  static const String washing = 'washing';
  static const String wearing = 'wearing';
  static const String storage = 'storage';
  static const String dryCleaning = 'dry_cleaning';

  static const Map<String, String> names = {
    inWardrobe: '在衣柜',
    washing: '在洗',
    wearing: '正在穿',
    storage: '收纳中',
    dryCleaning: '干洗中',
  };

  static const Map<String, String> icons = {
    inWardrobe: '🏠',
    washing: '🧺',
    wearing: '👔',
    storage: '📦',
    dryCleaning: '🏪',
  };
}

// 场合
class Occasion {
  static const String daily = 'daily';
  static const String work = 'work';
  static const String dating = 'dating';
  static const String party = 'party';
  static const String interview = 'interview';
  static const String travel = 'travel';
  static const String sport = 'sport';
  static const String home = 'home';

  static const Map<String, String> names = {
    daily: '日常',
    work: '工作',
    dating: '约会',
    party: '聚会',
    interview: '面试',
    travel: '旅行',
    sport: '运动',
    home: '居家',
  };

  static const Map<String, String> icons = {
    daily: '☀️',
    work: '💼',
    dating: '💑',
    party: '🎉',
    interview: '👔',
    travel: '✈️',
    sport: '🏃',
    home: '🏠',
  };
}

// 材质（差异化核心维度：保暖/透气/运动适配）
class MaterialType {
  static const String cotton = 'cotton'; // 纯棉
  static const String wool = 'wool'; // 羊毛
  static const String cashmere = 'cashmere'; // 羊绒
  static const String linen = 'linen'; // 亚麻
  static const String silk = 'silk'; // 真丝
  static const String quickDry = 'quick_dry'; // 速干
  static const String denim = 'denim'; // 牛仔
  static const String polyester = 'polyester'; // 聚酯纤维
  static const String nylon = 'nylon'; // 锦纶
  static const String down = 'down'; // 羽绒
  static const String leather = 'leather'; // 皮革
  static const String blended = 'blended'; // 混纺
  static const String other = 'other'; // 其他

  static const List<String> all = [
    cotton, wool, cashmere, linen, silk, quickDry,
    denim, polyester, nylon, down, leather, blended, other,
  ];

  static const Map<String, String> names = {
    cotton: '纯棉',
    wool: '羊毛',
    cashmere: '羊绒',
    linen: '亚麻',
    silk: '真丝',
    quickDry: '速干',
    denim: '牛仔',
    polyester: '聚酯纤维',
    nylon: '锦纶',
    down: '羽绒',
    leather: '皮革',
    blended: '混纺',
    other: '其他',
  };

  /// 保暖度 0-10（10 最暖）
  static const Map<String, int> warmth = {
    down: 10, cashmere: 9, wool: 8, leather: 7, denim: 5,
    cotton: 4, blended: 4, polyester: 4, nylon: 3,
    linen: 2, silk: 2, quickDry: 2, other: 4,
  };

  /// 透气度 0-10（10 最透气）
  static const Map<String, int> breathability = {
    linen: 9, quickDry: 9, cotton: 8, silk: 8,
    wool: 6, cashmere: 6, blended: 5,
    denim: 4, nylon: 4, polyester: 3, down: 3, leather: 1, other: 5,
  };

  /// 运动/户外适配 0-10（排汗速干优先，纯棉吸汗扣分）
  static const Map<String, int> sportSuitability = {
    quickDry: 10, nylon: 7, polyester: 6, wool: 5, blended: 5,
    linen: 4, silk: 3, denim: 3, cotton: 3, down: 2, leather: 1, other: 4,
  };

  /// 适合温度提示（经验区间）
  static const Map<String, String> tempHint = {
    down: '≤ 5°C',
    cashmere: '0 ~ 12°C',
    wool: '5 ~ 15°C',
    leather: '5 ~ 18°C',
    denim: '10 ~ 22°C',
    cotton: '15 ~ 28°C',
    blended: '10 ~ 26°C',
    polyester: '10 ~ 26°C',
    nylon: '8 ~ 24°C',
    linen: '≥ 25°C',
    silk: '18 ~ 30°C',
    quickDry: '运动四季',
    other: '不限',
  };

  static String name(String? id) => names[id ?? ''] ?? (id ?? '未知');

  static int warmthOf(String? id) => warmth[id ?? other] ?? 4;

  static int breathabilityOf(String? id) => breathability[id ?? other] ?? 5;

  static int sportOf(String? id) => sportSuitability[id ?? other] ?? 4;
}

// 厚度等级
class ThicknessLevel {
  static const Map<int, String> names = {
    0: '极薄',
    1: '薄',
    2: '适中',
    3: '厚',
    4: '特厚',
  };

  static String name(int level) => names[level] ?? '适中';
}

// 户外场景（户外模式）
class OutdoorScenario {
  static const String hiking = 'hiking'; // 徒步
  static const String longRun = 'long_run'; // 长跑

  static const Map<String, String> names = {
    hiking: '徒步',
    longRun: '长跑',
  };

  static const Map<String, String> icons = {
    hiking: '🥾',
    longRun: '🏃',
  };

  static const Map<String, String> descriptions = {
    hiking: '分层穿衣 + 防风防雨，按海拔与温差选装备',
    longRun: '速干排汗优先，轻量透气，防磨防反光安全',
  };
}

// 目的地气候（行李清单用）
class ClimateType {
  static const String hot = 'hot'; // 炎热 ≥24°C
  static const String mild = 'mild'; // 温和 12~24°C
  static const String cold = 'cold'; // 寒冷 <12°C
  static const String variable = 'variable'; // 多变/跨度大

  static const Map<String, String> names = {
    hot: '炎热',
    mild: '温和',
    cold: '寒冷',
    variable: '多变',
  };

  static const Map<String, String> icons = {
    hot: '🔥',
    mild: '🌤️',
    cold: '❄️',
    variable: '🌡️',
  };
}
