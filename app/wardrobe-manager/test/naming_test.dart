import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_manager/data/clothing_naming.dart';
import 'package:wardrobe_manager/models/models.dart';

Clothing _c({
  String color = '白色',
  String sub = 't_shirt',
  String? customName,
  Map<String, String>? extra,
  String? material,
}) =>
    Clothing(
      id: 'x',
      imageUrl: '',
      category: ClothingCategory.tops,
      subCategory: sub,
      color: color,
      createdAt: DateTime(2025),
      customName: customName,
      extraAttributes: extra,
      material: material,
    );

void main() {
  group('中文完整名称', () {
    test('颜色 + 类型，不带额外英文标签', () {
      expect(clothingDisplayName(_c()), '白色T恤');
      expect(clothingDisplayName(_c(color: '雾霾蓝', sub: 'jeans')), '雾霾蓝牛仔裤');
    });

    test('自定义名称优先', () {
      expect(clothingDisplayName(_c(customName: '周末那件白T')), '周末那件白T');
      expect(clothingDisplayName(_c(customName: '  ')), '白色T恤');
    });

    test('颜色里已经写了类型时不重复', () {
      expect(clothingDisplayName(_c(color: '白色T恤')), '白色T恤');
    });

    test('副标题包含材质与自定义属性', () {
      final c = _c(material: 'cotton', extra: {'版型': '宽松'});
      final label = clothingSecondaryLabel(c);
      expect(label, contains('纯棉'));
      expect(label, contains('宽松'));
    });

    test('颜色与风格预设足够丰富且都是中文', () {
      expect(ColorPresets.all.length, greaterThan(35));
      expect(MaterialPresets.all.length, greaterThan(15));
      expect(StylePresets.builtin.length, greaterThanOrEqualTo(12));
      for (final c in ColorPresets.all) {
        expect(c, isNot(contains(RegExp(r'[A-Za-z]'))));
      }
    });
  });

  group('#1 英文标签 → 中文（toChineseColor / toChinesePattern）', () {
    test('常见颜色英文 → 中文', () {
      expect(toChineseColor('white'), '白色');
      expect(toChineseColor('black'), '黑色');
      expect(toChineseColor('light gray'), '浅灰');
      expect(toChineseColor('beige'), '米色');
      expect(toChineseColor('camel'), '驼色');
      expect(toChineseColor('navy'), '藏青');
      expect(toChineseColor('navy blue'), '藏青');
      expect(toChineseColor('sage green'), '灰豆绿');
      expect(toChineseColor('mustard yellow'), '姜黄色');
    });

    test('中文颜色原样返回，未映射英文返回 null', () {
      expect(toChineseColor('藏青'), '藏青');
      expect(toChineseColor('白色'), '白色');
      expect(toChineseColor('chartreuseish'), isNull);
    });

    test('图案英文 → 中文', () {
      expect(toChinesePattern('solid'), '纯色');
      expect(toChinesePattern('striped'), '条纹');
      expect(toChinesePattern('floral'), '印花');
      expect(toChinesePattern('格子'), '格子');
    });
  });

  group('#1 toChineseClothingName / parseChineseClothingName', () {
    test('内部 key 与常见英文标签 → 颜色+品类', () {
      expect(toChineseClothingName('t_shirt'), 'T恤');
      expect(toChineseClothingName('T-shirt', colorHint: 'light gray'), '浅灰T恤');
      expect(toChineseClothingName('light gray t-shirt'), '浅灰T恤');
      expect(toChineseClothingName('camel coat'), '驼色大衣');
      expect(toChineseClothingName('black jeans'), '黑色牛仔裤');
      expect(toChineseClothingName('white shirt'), '白色衬衫');
      expect(toChineseClothingName('wine blouse'), '酒红女衬衫');
      expect(toChineseClothingName('navy blue dress'), '藏青休闲裙');
      expect(toChineseClothingName('mustard yellow sweater'), '姜黄色毛衣');
      expect(toChineseClothingName('Sage Green Hoodie'), '灰豆绿卫衣');
    });

    test('驼峰 / 连字符变体归一', () {
      expect(toChineseClothingName('LightGray TShirt'), '浅灰T恤');
      expect(toChineseClothingName('Wool_Blazer'), '西装外套');
    });

    test('colorHint 在原文缺颜色时兜底（中文或英文提示）', () {
      expect(toChineseClothingName('cardigan', colorHint: '米色'), '米色针织开衫');
      expect(toChineseClothingName('jeans', colorHint: '藏青'), '藏青牛仔裤');
      expect(toChineseClothingName('cardigan', colorHint: 'beige'), '米色针织开衫');
    });

    test('品牌词剥离：词典命中', () {
      final a = parseChineseClothingName('Uniqlo Beige Cardigan');
      expect(a.name, '米色针织开衫');
      expect(a.brand, 'Uniqlo');
      expect(a.hasCategory, isTrue);

      final b = parseChineseClothingName('ZARA navy wool coat');
      expect(b.name, '藏青大衣');
      expect(b.brand, 'ZARA');

      final c = parseChineseClothingName('Nike sneakers');
      expect(c.name, '运动鞋');
      expect(c.brand, 'Nike');
    });

    test('品牌词剥离：中文品牌与首字母大写专名', () {
      final a = parseChineseClothingName('优衣库 白色T恤');
      expect(a.name, '白色T恤');
      expect(a.brand, '优衣库');

      final b = parseChineseClothingName('Comfy XL');
      expect(b.name, '');
      expect(b.brand, 'Comfy');
    });

    test('无法映射的英文词直接丢弃（宁缺毋滥）', () {
      final a = parseChineseClothingName('frobnicate widget');
      expect(a.name, isEmpty);
      expect(a.brand, isNull);
      expect(a.hasCategory, isFalse);
      expect(toChineseClothingName(''), isEmpty);
      // 纯颜色没有品类：hasCategory=false，调用方不写 customName
      expect(parseChineseClothingName('white').hasCategory, isFalse);
    });

    test('中文透传：中英混写补品类，不重复加颜色', () {
      expect(toChineseClothingName('米色 cardigan'), '米色针织开衫');
      expect(toChineseClothingName('白色T恤'), '白色T恤');
      final keep = parseChineseClothingName('开衫', colorHint: '米色');
      expect(keep.name, '米色开衫');
      expect(keep.hasCategory, isTrue);
    });
  });
}
