import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_manager/models/models.dart';
import 'package:wardrobe_manager/services/local_style_analyzer.dart';
import 'package:wardrobe_manager/services/style_digest.dart';
import 'package:wardrobe_manager/services/text_gateway_service.dart';
import 'package:wardrobe_manager/services/try_on_service.dart';
import 'package:wardrobe_manager/services/vision_gateway_service.dart';

Clothing _c({
  required String id,
  required String category,
  String sub = 'shirt',
  String color = '白色',
  List<String> styles = const ['casual'],
  List<String> seasons = const ['spring'],
  String? material = 'cotton',
  int wearCount = 0,
  int daysAgo = 10,
}) =>
    Clothing(
      id: id,
      imageUrl: '',
      category: category,
      subCategory: sub,
      color: color,
      styles: styles,
      seasons: seasons,
      material: material,
      wearCount: wearCount,
      createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
      lastWearDate: wearCount > 0
          ? DateTime.now().subtract(Duration(days: daysAgo))
          : null,
    );

void main() {
  group('衣橱摘要统计', () {
    test('分类、颜色、利用率、从未穿过都算对', () {
      final digest = WardrobeDigest.from(clothes: [
        _c(id: '1', category: ClothingCategory.tops, wearCount: 5),
        _c(id: '2', category: ClothingCategory.tops, color: '黑色'),
        _c(id: '3', category: ClothingCategory.bottoms, sub: 'jeans'),
        _c(id: '4', category: ClothingCategory.shoes, sub: 'sneakers'),
      ]);
      expect(digest.total, 4);
      expect(digest.byCategory['上衣'], 2);
      expect(digest.byCategory['下装'], 1);
      expect(digest.byColor['白色'], 3);
      expect(digest.neverWorn, 3);
      expect(digest.utilization, closeTo(0.25, 0.001));
      expect(digest.avgWears, closeTo(1.25, 0.001));
    });

    test('空衣橱不除零', () {
      final d = WardrobeDigest.from(clothes: []);
      expect(d.total, 0);
      expect(d.utilization, 0);
      expect(d.avgWears, 0);
      expect(d.byCategory, isEmpty);
    });

    test('toJson 里的键是中文，方便模型理解', () {
      final d = WardrobeDigest.from(clothes: [
        _c(id: '1', category: ClothingCategory.tops),
      ]);
      final json = d.toJson();
      expect(json.containsKey('分类分布'), isTrue);
      expect(json.containsKey('利用率'), isTrue);
      expect(json['单品总数'], 1);
    });
  });

  group('本地风格分析', () {
    test('空衣橱给保守建议，不生成购买清单', () {
      final r = const LocalStyleAnalyzer()
          .analyze(WardrobeDigest.from(clothes: []));
      expect(r.persona, contains('空'));
      expect(r.buyNext, isEmpty);
      expect(r.avoid, isNotEmpty);
    });

    test('缺基础品类时给出结构缺口', () {
      final r = const LocalStyleAnalyzer().analyze(
        WardrobeDigest.from(clothes: [
          _c(id: '1', category: ClothingCategory.tops),
          _c(id: '2', category: ClothingCategory.tops),
          _c(id: '3', category: ClothingCategory.tops),
        ]),
      );
      final cats = r.gaps.map((g) => g.category).toList();
      expect(cats, contains('下装'));
      expect(cats, contains('鞋子'));
      expect(r.buyNext.first.priority, 'high');
    });

    test('中性色为主时给出点缀色建议', () {
      final r = const LocalStyleAnalyzer().analyze(
        WardrobeDigest.from(clothes: [
          _c(id: '1', category: ClothingCategory.tops, color: '黑色'),
          _c(id: '2', category: ClothingCategory.tops, color: '白色'),
          _c(id: '3', category: ClothingCategory.bottoms, color: '灰色'),
          _c(id: '4', category: ClothingCategory.shoes, color: '黑色'),
          _c(id: '5', category: ClothingCategory.outerwear, color: '米色'),
        ]),
      );
      expect(r.colorStory, contains('点缀色'));
    });

    test('某品类过多时提示饱和', () {
      final clothes = List.generate(
        9,
        (i) => _c(id: 't$i', category: ClothingCategory.tops),
      );
      final r = const LocalStyleAnalyzer()
          .analyze(WardrobeDigest.from(clothes: clothes));
      expect(r.avoid.any((a) => a.contains('饱和')), isTrue);
    });
  });

  group('风格报告解析', () {
    test('标准 JSON 正常解析', () {
      final report = TextGatewayService().parseReport(jsonEncode({
        'persona': '通勤为主，克制但完整',
        'styleMix': [
          {'name': '通勤', 'ratio': 0.5},
          {'name': '休闲', 'ratio': 0.5},
        ],
        'strengths': ['利用率高'],
        'gaps': [
          {'category': '外套', 'reason': '换季不够'}
        ],
        'colorStory': '黑白灰为主，可补一点雾蓝',
        'buyNext': [
          {'item': '白色衬衫', 'why': '补基础款', 'priority': 'high'}
        ],
        'avoid': ['先别买第 10 件卫衣'],
      }));
      expect(report.persona, contains('通勤'));
      expect(report.styleMix.length, 2);
      expect(report.gaps.first.category, '外套');
      expect(report.buyNext.first.isHigh, isTrue);
      expect(report.avoid, isNotEmpty);
    });

    test('围栏 + 前后废话也能提取', () {
      final report = TextGatewayService().parseReport(
        '好的，分析如下：\n```json\n'
        '{"persona":"极简派","styleMix":[],"strengths":[],"gaps":[],'
        '"colorStory":"","buyNext":[],"avoid":[]}\n'
        '```\n希望有帮助',
      );
      expect(report.persona, '极简派');
    });

    test('ratio 是字符串或越界时被修正', () {
      final report = TextGatewayService().parseReport(jsonEncode({
        'persona': 'x',
        'styleMix': [
          {'name': 'A', 'ratio': '0.6'},
          {'name': 'B', 'ratio': 3},
          {'name': 'C'},
          {'ratio': 0.1},
        ],
      }));
      expect(report.styleMix.length, 3); // 没有 name 的被丢弃
      expect(report.styleMix[0].ratio, 0.6);
      expect(report.styleMix[1].ratio, 1.0);
      expect(report.styleMix[2].ratio, 0.0);
    });

    test('priority 非法值退回 medium', () {
      final report = TextGatewayService().parseReport(jsonEncode({
        'persona': 'x',
        'buyNext': [
          {'item': '白衬衫', 'priority': 'urgent'},
        ],
      }));
      expect(report.buyNext.first.priority, 'medium');
      expect(report.buyNext.first.isHigh, isFalse);
    });

    test('没有 persona 视为解析失败', () {
      expect(
        () => TextGatewayService().parseReport('{"styleMix":[]}'),
        throwsA(isA<GatewayException>()),
      );
    });

    test('完全不是 JSON 时报解析错误', () {
      expect(
        () => TextGatewayService().parseReport('我觉得你的衣橱还行'),
        throwsA(isA<GatewayException>()),
      );
    });
  });

  group('试穿提示词', () {
    test('包含单品描述与保持人物一致的约束', () {
      final prompt = TryOnService().buildPrompt([
        _c(id: '1', category: ClothingCategory.tops, sub: 'shirt', color: '白色'),
        _c(id: '2', category: ClothingCategory.bottoms, sub: 'jeans', color: '蓝色'),
      ]);
      expect(prompt, contains('上衣(衬衫, 白色)'));
      expect(prompt, contains('下装(牛仔裤, 蓝色)'));
      expect(prompt, contains('Keep the same person'));
      expect(prompt, contains('Only change the clothing'));
    });

    test('附加要求会拼进去', () {
      final prompt = TryOnService().buildPrompt(
        [_c(id: '1', category: ClothingCategory.shoes, sub: 'sneakers')],
        extraNote: '想配白袜',
      );
      expect(prompt, contains('想配白袜'));
    });
  });

  group('愿望清单', () {
    test('冷静期内不催买，倒计时按天算', () {
      final item = WishItem(
        id: 'w1',
        name: '风衣',
        category: ClothingCategory.outerwear,
        createdAt: DateTime.now(),
        cooldownUntil: DateTime.now().add(const Duration(days: 7)),
      );
      expect(item.purchased, isFalse);
      expect(item.inCooldown, isTrue);
      expect(item.cooldownDaysLeft, 7);
    });

    test('没有冷静期时视为已过', () {
      final item = WishItem(
        id: 'w2',
        name: '包',
        category: ClothingCategory.accessories,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(item.inCooldown, isFalse);
      expect(item.waitingDays, greaterThanOrEqualTo(29));
    });

    test('购入后 purchased 为真', () {
      final item = WishItem(
        id: 'w3',
        name: '鞋',
        category: ClothingCategory.shoes,
        createdAt: DateTime.now(),
        purchasedAt: DateTime.now(),
        clothingId: 'c1',
      );
      expect(item.purchased, isTrue);
    });
  });

  group('多衣橱归属', () {
    test('老数据 wardrobeId 为空，归默认衣橱', () {
      final c = _c(id: '1', category: ClothingCategory.tops);
      expect(c.wardrobeId, isNull);
      expect(c.belongsTo(null), isTrue);
      expect(c.belongsTo('space_x'), isFalse);
    });

    test('指定空间后只属于该空间', () {
      final c = _c(id: '1', category: ClothingCategory.tops)
        ..wardrobeId = 'space_dorm';
      expect(c.belongsTo('space_dorm'), isTrue);
      expect(c.belongsTo(null), isFalse);
    });

    test('内置衣橱是默认且 id 固定', () {
      final s = WardrobeSpace.builtin();
      expect(s.id, WardrobeSpace.defaultId);
      expect(s.isDefault, isTrue);
    });
  });

  group('试穿任务', () {
    test('coversItems 判断搭配是否覆盖全部单品', () {
      final t = TryOnTask(
        id: 't1',
        personImagePath: '/tmp/a.jpg',
        itemIds: const ['a', 'b', 'c'],
        createdAt: DateTime.now(),
      );
      expect(t.coversItems(['a', 'b']), isTrue);
      expect(t.coversItems(['a', 'z']), isFalse);
      expect(t.coversItems([]), isFalse);
    });

    test('状态中文名齐全', () {
      for (final s in [
        TryOnStatus.pending,
        TryOnStatus.running,
        TryOnStatus.success,
        TryOnStatus.failed,
      ]) {
        expect(TryOnStatus.name(s), isNot(s));
      }
    });
  });
}
