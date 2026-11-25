import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_manager/models/models.dart';
import 'package:wardrobe_manager/services/recommendation_engine.dart';

/// 与 wardrobe_test.dart 同构的单品构造 helper（各测试文件私有，不共享）。
Clothing piece(
  String id,
  String category,
  String sub, [
  String color = '黑色',
  String material = MaterialType.cotton,
]) {
  return Clothing(
    id: id,
    imageUrl: '',
    category: category,
    subCategory: sub,
    color: color,
    material: material,
    createdAt: DateTime.now().subtract(const Duration(days: 10)),
  );
}

Clothing worn(String id, int daysAgo) => Clothing(
      id: id,
      imageUrl: '',
      category: ClothingCategory.tops,
      subCategory: 't_shirt',
      color: '白色',
      wearCount: 3,
      lastWearDate: DateTime.now().subtract(Duration(days: daysAgo)),
      createdAt: DateTime.now().subtract(const Duration(days: 200)),
    );

void main() {
  final engine = RecommendationEngine();

  group('#6 按性别过滤', () {
    test('male 过滤裙装/女衬衫/高跟鞋/连衣裙，保留普通单品', () {
      final clothes = [
        piece('t1', ClothingCategory.tops, 't_shirt', '白色'),
        piece('b1', ClothingCategory.bottoms, 'jeans', '藏青'),
        piece('b2', ClothingCategory.bottoms, 'skirt', '红色'),
        piece('d1', ClothingCategory.dress, 'midi_dress', '奶油白'),
        piece('s1', ClothingCategory.shoes, 'heels', '黑色'),
        piece('x1', ClothingCategory.tops, 'blouse', '粉色'),
      ];
      final kept =
          OutfitRules.filterByGender(clothes, 'male').map((c) => c.id).toSet();
      expect(kept, {'t1', 'b1'});
    });

    test('female / null / other 不丢件（词表无男装专属，保守不过滤）', () {
      final clothes = [
        piece('t1', ClothingCategory.tops, 't_shirt'),
        piece('b1', ClothingCategory.bottoms, 'jeans'),
      ];
      expect(OutfitRules.filterByGender(clothes, 'female').length, 2);
      expect(OutfitRules.filterByGender(clothes, null).length, 2);
      expect(OutfitRules.filterByGender(clothes, 'other').length, 2);
    });

    test('recommend(gender: male) 不拿裙子当底；不传 gender 时裙子分高会被选中', () {
      final clothes = [
        piece('t1', ClothingCategory.tops, 't_shirt', '白色')
          ..styles = [StyleTag.casual],
        piece('b2', ClothingCategory.bottoms, 'skirt', '米色')
          ..styles = [StyleTag.casual]
          ..occasions = [Occasion.daily],
        piece('b1', ClothingCategory.bottoms, 'jeans', '红色'),
      ];
      final neutral = engine.recommend(
          clothes: clothes, temperature: 18, occasion: Occasion.daily);
      expect(neutral?.bottom?.subCategory, 'skirt');
      final male = engine.recommend(
        clothes: clothes,
        temperature: 18,
        occasion: Occasion.daily,
        gender: 'male',
      );
      expect(male?.bottom?.subCategory, isNot('skirt'));
    });

    test('男性衣橱下装只剩裙子时回退不过滤，仍能出方案', () {
      final clothes = [
        piece('t1', ClothingCategory.tops, 't_shirt', '白色'),
        piece('b2', ClothingCategory.bottoms, 'skirt', '黑色'),
      ];
      final plan =
          engine.recommend(clothes: clothes, temperature: 18, gender: 'male');
      expect(plan, isNotNull);
      expect(plan!.bottom?.subCategory, 'skirt');
    });
  });

  group('#8 主色上限与冲突表', () {
    test('全身非中性主色 ≤ 3：4 主色违规，中性色不计入', () {
      final four = [
        piece('a', ClothingCategory.tops, 't_shirt', '红色'),
        piece('b', ClothingCategory.bottoms, 'jeans', '蓝色'),
        piece('c', ClothingCategory.shoes, 'sneakers', '绿色'),
        piece('d', ClothingCategory.accessories, 'bag', '黄色'),
      ];
      expect(OutfitRules.mainColorCount(four), 4);
      expect(OutfitRules.auditHardRules(four, temperature: 18).pass, isFalse);

      final neutralPlusOne = [
        piece('a', ClothingCategory.tops, 't_shirt', '白色'),
        piece('b', ClothingCategory.bottoms, 'jeans', '黑色'),
        piece('c', ClothingCategory.shoes, 'sneakers', '灰色'),
        piece('d', ClothingCategory.accessories, 'bag', '红色'),
      ];
      expect(OutfitRules.mainColorCount(neutralPlusOne), 1);
    });

    test('色系冲突表：红绿撞色，红蓝不撞', () {
      expect(
        OutfitRules.hasColorClash([
          piece('a', ClothingCategory.tops, 't_shirt', '红色'),
          piece('b', ClothingCategory.bottoms, 'jeans', '绿色'),
        ]),
        isTrue,
      );
      expect(
        OutfitRules.hasColorClash([
          piece('a', ClothingCategory.tops, 't_shirt', '红色'),
          piece('b', ClothingCategory.bottoms, 'jeans', '蓝色'),
        ]),
        isFalse,
      );
    });

    test('选品加减分：超 3 主色扣分、上下版型反向加分同向扣分', () {
      final bag = piece('x', ClothingCategory.accessories, 'bag', '黄色');
      expect(
        OutfitRules.aestheticDelta(
            candidate: bag, existingFamilies: {'red', 'green', 'blue'}),
        lessThan(0),
      );
      final hoodie = piece('h', ClothingCategory.tops, 'hoodie');
      final leggings = piece('l', ClothingCategory.bottoms, 'leggings');
      expect(
        OutfitRules.aestheticDelta(candidate: leggings, referenceTop: hoodie),
        greaterThan(0),
      );
      final skirt = piece('s', ClothingCategory.bottoms, 'skirt');
      expect(
        OutfitRules.aestheticDelta(candidate: skirt, referenceTop: hoodie),
        lessThan(0),
      );
    });
  });

  group('#8 温度/场合硬排除', () {
    test('5°C 不出背心+短裤组合（单品未填适穿区间也被排除）', () {
      final pieces = [
        piece('t', ClothingCategory.tops, 'tank_top', '白色'),
        piece('b', ClothingCategory.bottoms, 'shorts', '卡其'),
      ];
      expect(OutfitRules.auditHardRules(pieces, temperature: 5).pass, isFalse);
      expect(engine.recommend(clothes: pieces, temperature: 5), isNull);
    });

    test('高温不出厚外套/厚卫衣；运动场合不出高跟鞋', () {
      final coat = piece('o', ClothingCategory.outerwear, 'coat', '黑色')
        ..thickness = 3;
      expect(OutfitRules.passesTempHardRule(coat, 30), isFalse);
      final hoodie = piece('h', ClothingCategory.tops, 'hoodie', '灰色')
        ..thickness = 3;
      expect(OutfitRules.passesTempHardRule(hoodie, 28), isFalse);
      final heels = piece('s', ClothingCategory.shoes, 'heels', '黑色');
      expect(OutfitRules.passesOccasionHardRule(heels, Occasion.sport),
          isFalse);
      expect(OutfitRules.passesOccasionHardRule(heels, null), isTrue);
    });
  });

  group('#8 新鲜度与理由', () {
    test('lastWearDate 越久分越高', () {
      expect(OutfitRules.freshnessScore(worn('a', 100)),
          greaterThan(OutfitRules.freshnessScore(worn('b', 2))));
      expect(OutfitRules.freshnessScore(worn('a', 100)), 10);
    });

    test('每套推荐产出 2-3 条非空中文理由', () {
      final pieces = [
        piece('t', ClothingCategory.tops, 't_shirt', '白色'),
        piece('b', ClothingCategory.bottoms, 'jeans', '藏青'),
        piece('o', ClothingCategory.outerwear, 'jacket', '黑色'),
      ];
      final reasons = OutfitRules.buildReasons(
          pieces: pieces, temperature: 12, occasion: Occasion.work);
      expect(reasons, isNotEmpty);
      expect(reasons.length, inInclusiveRange(2, 3));
      expect(reasons.first, contains('°C'));
      expect(OutfitRules.buildReasons(pieces: [], temperature: 20), isEmpty);
    });

    test('recommendWithReasons：性别未填带提示，male/other 不带', () {
      final clothes = [
        piece('t', ClothingCategory.tops, 't_shirt', '白色'),
        piece('b', ClothingCategory.bottoms, 'jeans', '藏青'),
      ];
      final r =
          engine.recommendWithReasons(clothes: clothes, temperature: 16);
      expect(r.plan, isNotNull);
      expect(r.needsGenderHint, isTrue);
      expect(r.reasons.length, inInclusiveRange(2, 3));
      final male = engine.recommendWithReasons(
          clothes: clothes, temperature: 16, gender: 'male');
      expect(male.needsGenderHint, isFalse);
      final other = engine.recommendWithReasons(
          clothes: clothes, temperature: 16, gender: 'other');
      expect(other.needsGenderHint, isFalse);
    });
  });
}
