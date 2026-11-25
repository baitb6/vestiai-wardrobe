import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:wardrobe_manager/data/ai_mapping.dart';
import 'package:wardrobe_manager/models/models.dart';
import 'package:wardrobe_manager/services/cutout_service.dart';
import 'package:wardrobe_manager/services/duplicate_detector.dart';
import 'package:wardrobe_manager/services/vision_gateway_service.dart';

void main() {
  group('JSON 容错', () {
    test('从 markdown 代码块里抽 JSON', () {
      const raw = '好的，结果如下：\n```json\n{"items":[{"category":"上衣"}]}\n```\n希望有帮助';
      final json = VisionGatewayService.extractJson(raw);
      expect(json, contains('"items"'));
      final decoded = jsonDecode(json!) as Map;
      expect(decoded['items'], isA<List>());
    });

    test('字符串里带花括号不误判', () {
      const raw = '{"items":[{"note":"{不是括号}"}],"total":1}';
      final json = VisionGatewayService.extractJson(raw);
      expect(json, raw);
    });

    test('完全没有 JSON 时返回 null', () {
      expect(VisionGatewayService.extractJson('抱歉，我无法识别这张图'), isNull);
    });
  });

  group('候选单品解析', () {
    final service = VisionGatewayService();

    test('中文分类归一 + 过滤过小框 + 配饰限量', () {
      final raw = jsonEncode({
        'items': [
          {
            'category': '上衣',
            'subCategory': 'T恤',
            'bbox': {'x': 0.1, 'y': 0.1, 'w': 0.4, 'h': 0.3},
            'colors': ['黑色'],
            'styleTags': ['休闲', '法式'],
            'season': ['春', '秋'],
            'confidence': 0.86,
          },
          {
            'category': '下装',
            'subCategory': '牛仔裤',
            'bbox': {'x': 0.1, 'y': 0.5, 'w': 0.4, 'h': 0.35},
            'colors': ['牛仔蓝色'],
            'confidence': 0.7,
          },
          {
            // 面积 0.1% 的误识别，应被丢掉
            'category': '配饰',
            'subCategory': '手表',
            'bbox': {'x': 0.5, 'y': 0.5, 'w': 0.03, 'h': 0.03},
            'confidence': 0.4,
          },
        ]
      });
      final items = service.parseItems(raw);
      expect(items.length, 2);
      final top =
          items.firstWhere((e) => e.category == ClothingCategory.tops);
      final bottom =
          items.firstWhere((e) => e.category == ClothingCategory.bottoms);
      expect(top.subCategory, 't_shirt');
      expect(top.seasons, containsAll([Season.spring, Season.autumn]));
      expect(top.styleTags, contains(StyleTag.casual));
      expect(top.extraTags, contains('法式'));
      expect(bottom.subCategory, 'jeans');
      // 「牛仔蓝色」→ 去掉「色」→ 牛仔蓝
      expect(bottom.colors.first, '牛仔蓝');
    });

    test('配饰超过 5 件按置信度截断', () {
      final items = List.generate(
        8,
        (i) => {
          'category': '配饰',
          'subCategory': '包',
          'bbox': {'x': 0.1 * i % 0.8, 'y': 0.1, 'w': 0.1, 'h': 0.1},
          'confidence': 0.5 + i * 0.05,
        },
      );
      final parsed = service.parseItems(jsonEncode({'items': items}));
      expect(parsed.where((e) => e.category == ClothingCategory.accessories).length, 5);
    });

    test('items 为空时给出可读错误', () {
      expect(
        () => service.parseItems('{"items":[]}'),
        throwsA(isA<GatewayException>()
            .having((e) => e.kind, 'kind', GatewayErrorKind.empty)),
      );
    });

    test('非 JSON 输出保留原始响应', () {
      try {
        service.parseItems('这套挺好看的');
        fail('应该抛异常');
      } on GatewayException catch (e) {
        expect(e.kind, GatewayErrorKind.parse);
        expect(e.raw, '这套挺好看的');
        expect(e.message, contains('JSON'));
      }
    });
  });

  group('标签映射', () {
    test('分类兜底', () {
      expect(AiMapping.category('外套'), ClothingCategory.outerwear);
      expect(AiMapping.category('连衣裙'), ClothingCategory.dress);
      expect(AiMapping.category('运动鞋'), ClothingCategory.shoes);
      expect(AiMapping.category('挎包'), ClothingCategory.accessories);
      expect(AiMapping.category(''), ClothingCategory.tops);
    });

    test('子分类按关键词命中', () {
      expect(AiMapping.subCategory('连帽卫衣', ClothingCategory.tops), 'hoodie');
      expect(AiMapping.subCategory('西裤', ClothingCategory.bottoms), 'trousers');
      expect(AiMapping.subCategory('未知', ClothingCategory.shoes), 'sneakers');
    });

    test('季节中英混合', () {
      expect(AiMapping.seasons(['春', 'Summer', '冬季']),
          containsAll([Season.spring, Season.summer, Season.winter]));
      expect(AiMapping.seasons(['四季']), isEmpty);
    });
  });

  group('BBox', () {
    test('百分比自动归一', () {
      final b = BBox.fromJson({'x': 10, 'y': 20, 'w': 30, 'h': 40});
      expect(b.x, closeTo(0.1, 0.001));
      expect(b.h, closeTo(0.4, 0.001));
    });

    test('超出边界被夹住', () {
      final b = BBox.fromJson({'x': 0.9, 'y': 0.9, 'w': 0.5, 'h': 0.5});
      expect(b.x + b.w, lessThanOrEqualTo(1.0001));
      expect(b.y + b.h, lessThanOrEqualTo(1.0001));
    });

    test('IOU', () {
      const a = BBox(x: 0, y: 0, w: 0.5, h: 0.5);
      const b = BBox(x: 0, y: 0, w: 0.5, h: 0.5);
      expect(a.iou(b), 1);
    });
  });

  group('抠图', () {
    test('纯背景会被去掉，得到透明 PNG', () async {
      // 200x200 白底 + 中间蓝色方块
      final canvas = img.Image(width: 200, height: 200);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(canvas,
          x1: 60, y1: 60, x2: 140, y2: 140, color: img.ColorRgb8(35, 80, 200));
      final bytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 95));

      const service = LocalEdgeCutoutService();
      final result = await service.process(
        bytes,
        const BBox(x: 0.25, y: 0.25, w: 0.5, h: 0.5),
      );
      expect(result.transparent, isTrue);
      expect(result.bytes.length, greaterThan(0));

      final decoded = img.decodePng(result.bytes);
      expect(decoded, isNotNull);
      // 左上角应当是透明的
      expect(decoded!.getPixel(0, 0).a, 0);
    });

    test('背景太杂时降级为矩形裁片', () async {
      // 随机噪点背景，四边颜色标准差很大
      final canvas = img.Image(width: 120, height: 120);
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 120; x++) {
          canvas.setPixelRgba(x, y, (x * 7) % 255, (y * 11) % 255, (x + y) % 255, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 80));
      const service = LocalEdgeCutoutService();
      final result = await service.process(
        bytes,
        const BBox(x: 0, y: 0, w: 1, h: 1),
      );
      expect(result.transparent, isFalse);
      expect(result.note, isNotNull);
    });
  });

  group('重复检测', () {
    Clothing make(String id, String color) => Clothing(
          id: id,
          imageUrl: '',
          category: ClothingCategory.tops,
          subCategory: 't_shirt',
          color: color,
          createdAt: DateTime.now(),
        );

    test('同图命中相似提示，且不阻止入库', () async {
      final canvas = img.Image(width: 64, height: 64);
      img.fill(canvas, color: img.ColorRgb8(30, 30, 30));
      img.fillRect(canvas,
          x1: 10, y1: 10, x2: 40, y2: 40, color: img.ColorRgb8(240, 240, 240));
      final bytes = Uint8List.fromList(img.encodePng(canvas));

      final detector = DuplicateDetector();
      final hit = await detector.findBest(
        candidateBytes: bytes,
        existing: [make('a', '黑'), make('b', '白')],
        category: ClothingCategory.tops,
        color: '黑',
      );
      // 没有图片的已有衣物只能用分类+颜色兜底
      expect(hit, isNotNull);
      expect(hit!.similarity, greaterThan(0));
      expect(hit.reason, isNotEmpty);
    });

    test('没有可比数据时返回 null', () async {
      final canvas = img.Image(width: 32, height: 32);
      img.fill(canvas, color: img.ColorRgb8(10, 10, 10));
      final bytes = Uint8List.fromList(img.encodePng(canvas));
      final detector = DuplicateDetector();
      final hit = await detector.findBest(
        candidateBytes: bytes,
        existing: const [],
      );
      expect(hit, isNull);
    });
  });

  group('任务状态', () {
    test('状态常量与展示名齐全', () {
      for (final s in [
        SplitStatus.pending,
        SplitStatus.running,
        SplitStatus.success,
        SplitStatus.failed,
        SplitStatus.imported,
      ]) {
        expect(SplitStatus.names[s], isNotNull);
      }
    });
  });
}
