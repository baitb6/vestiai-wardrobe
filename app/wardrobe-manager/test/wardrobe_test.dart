import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_manager/models/models.dart';
import 'package:wardrobe_manager/services/insights_service.dart';
import 'package:wardrobe_manager/services/recommendation_engine.dart';

Clothing piece(
  String id,
  String category,
  String sub,
  String color,
  String material, {
  int? price,
  int thickness = 2,
  int? tempMin,
  int? tempMax,
  List<String> styles = const [],
  List<String> occasions = const [],
  int wearCount = 0,
  String status = LocationStatus.inWardrobe,
  int createdDaysAgo = 10,
  int? lastWornDaysAgo,
}) {
  return Clothing(
    id: id,
    imageUrl: '',
    category: category,
    subCategory: sub,
    color: color,
    material: material,
    price: price?.toDouble(),
    thickness: thickness,
    tempMin: tempMin,
    tempMax: tempMax,
    styles: styles,
    occasions: occasions,
    wearCount: wearCount,
    locationStatus: status,
    createdAt: DateTime.now().subtract(Duration(days: createdDaysAgo)),
    lastWearDate: lastWornDaysAgo == null
        ? null
        : DateTime.now().subtract(Duration(days: lastWornDaysAgo)),
  );
}

List<Clothing> wardrobe() => [
      piece('t1', ClothingCategory.tops, 't_shirt', '白色', MaterialType.cotton,
          tempMin: 15, tempMax: 30, wearCount: 8, lastWornDaysAgo: 3),
      piece('t2', ClothingCategory.tops, 'hoodie', '灰色', MaterialType.polyester,
          thickness: 3,
          tempMin: 0,
          tempMax: 18,
          styles: [StyleTag.streetwear],
          lastWornDaysAgo: 40,
          createdDaysAgo: 100),
      piece('b1', ClothingCategory.bottoms, 'jeans', '藏青', MaterialType.denim,
          tempMin: 0, tempMax: 26, wearCount: 20, lastWornDaysAgo: 1),
      piece('b2', ClothingCategory.bottoms, 'shorts', '卡其', MaterialType.linen,
          tempMin: 20, tempMax: 38),
      piece('o1', ClothingCategory.outerwear, 'jacket', '黑色', MaterialType.leather,
          thickness: 3, tempMin: 0, tempMax: 18, price: 1200),
      piece('s1', ClothingCategory.shoes, 'sneakers', '白色', MaterialType.leather,
          tempMin: 0, tempMax: 40, price: 600, wearCount: 30,
          lastWornDaysAgo: 2),
      piece('a1', ClothingCategory.accessories, 'bag', '黑色', MaterialType.leather,
          tempMin: 0, tempMax: 40, price: 900, wearCount: 5),
    ];

void main() {
  group('推荐引擎', () {
    final engine = RecommendationEngine();

    test('16°C 能给出完整的上下装', () {
      final plan = engine.recommend(clothes: wardrobe(), temperature: 16);
      expect(plan, isNotNull);
      expect(plan!.top, isNotNull);
      expect(plan.bottom, isNotNull);
      expect(plan.score, greaterThan(0));
      expect(plan.score, lessThanOrEqualTo(100));
      expect(plan.reasoning, isNotEmpty);
    });

    test('低温会带上外套，高温不带', () {
      final cold = engine.recommend(clothes: wardrobe(), temperature: 6);
      expect(cold?.outer, isNotNull);
      final hot = engine.recommend(clothes: wardrobe(), temperature: 30);
      expect(hot?.outer, isNull);
    });

    test('excludeIds 生效（一周计划不重样）', () {
      final plan = engine.recommend(
        clothes: wardrobe(),
        temperature: 16,
        excludeIds: {'t1'},
      );
      expect(plan?.top?.id, isNot('t1'));
    });

    test('风格偏好会提高同风格单品的优先级', () {
      final plan = engine.recommend(
        clothes: wardrobe(),
        temperature: 12,
        occasion: Occasion.daily,
        styleKey: StyleTag.streetwear,
      );
      expect(plan?.top?.id, 't2');
    });

    test('单品不足时返回 null 而不是瞎凑', () {
      final onlyTops = [
        piece('x1', ClothingCategory.tops, 't_shirt', '白色', MaterialType.cotton),
      ];
      expect(engine.recommend(clothes: onlyTops, temperature: 20), isNull);
    });
  });

  group('衣橱洞察', () {
    final service = InsightsService();

    test('CPW = 价格 ÷ 穿着次数', () {
      final c = piece('c1', ClothingCategory.tops, 't_shirt', '白色',
          MaterialType.cotton,
          price: 300, wearCount: 3);
      expect(c.cpw, closeTo(100, 0.001));
    });

    test('没填价格时 CPW 为 null', () {
      final c = piece('c2', ClothingCategory.tops, 't_shirt', '白色',
          MaterialType.cotton);
      expect(c.cpw, isNull);
    });

    test('健康度在 0–100 之间，且给出建议', () {
      final ins = service.analyze(wardrobe());
      expect(ins.healthScore, inInclusiveRange(0, 100));
      expect(ins.tips, isNotEmpty);
      expect(ins.itemCount, 7);
      expect(ins.utilization, greaterThan(0));
    });

    test('空衣橱不会崩，并提示先录入', () {
      final ins = service.analyze([]);
      expect(ins.isEmpty, isTrue);
      expect(ins.tips.single, contains('空'));
    });

    test('颜色归一到色系', () {
      expect(InsightsService.colorFamily('藏青'), '深蓝');
      expect(InsightsService.colorFamily('奶油白'), '中性');
      expect(InsightsService.colorFamily('驼色'), '大地色');
    });

    test('一周计划产出 7 天且尽量不重复上衣', () {
      final plans = service.weekPlan(clothes: wardrobe(), temperature: 16);
      expect(plans.length, 7);
      final tops = plans
          .map((d) => d.plan?.top?.id)
          .whereType<String>()
          .toList();
      expect(tops.length, 7);
      // 只有 2 件上衣，轮完会重置，不应抛异常
      expect(tops.toSet().length, greaterThanOrEqualTo(1));
    });
  });
}
