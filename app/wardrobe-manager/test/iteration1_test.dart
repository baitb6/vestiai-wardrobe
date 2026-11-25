import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wardrobe_manager/features/auto_split/auto_split_provider.dart';
import 'package:wardrobe_manager/models/models.dart';
import 'package:wardrobe_manager/services/exif_cleaner.dart';
import 'package:wardrobe_manager/services/image_usage.dart';
import 'package:wardrobe_manager/services/insights_service.dart';
import 'package:wardrobe_manager/services/recommendation_engine.dart';

Clothing _item({
  String id = '1',
  String category = ClothingCategory.tops,
  double? price,
  int wearCount = 0,
  int createdDaysAgo = 0,
  int? lastWearDaysAgo,
}) {
  final now = DateTime.now();
  return Clothing(
    id: id,
    imageUrl: '',
    category: category,
    subCategory: 't-shirt',
    color: '黑色',
    price: price,
    wearCount: wearCount,
    lastWearDate: lastWearDaysAgo == null
        ? null
        : now.subtract(Duration(days: lastWearDaysAgo)),
    createdAt: now.subtract(Duration(days: createdDaysAgo)),
  );
}

void main() {
  group('EXIF 清理', () {
    test('大图被缩到长边 1280，输出不带 EXIF', () {
      final src = img.Image(width: 2000, height: 1000);
      img.fill(src, color: img.ColorRgb8(120, 130, 140));
      final raw = img.encodeJpg(src, quality: 95);

      final clean = ExifCleaner.prepare(raw);
      expect(clean, isNotNull);
      expect(clean!.width, 1280);
      expect(clean.height, 640);
      expect(clean.changed, isTrue);

      final decoded = img.decodeImage(clean.bytes)!;
      // 解码器会造一个空的 ifd0 容器，这里断言里面没有任何标签
      expect(decoded.exif['ifd0'].keys, isEmpty);
      // 字节层面也不应该有 APP1/Exif 段
      expect(_hasExifSegment(clean.bytes), isFalse);
      expect(clean.bytes.length, lessThan(raw.length));
    });

    test('小图保持原尺寸，仍然重编码成 JPEG', () {
      final src = img.Image(width: 320, height: 240);
      img.fill(src, color: img.ColorRgb8(10, 20, 30));
      final clean = ExifCleaner.prepare(img.encodePng(src));
      expect(clean, isNotNull);
      expect(clean!.width, 320);
      expect(clean.height, 240);
      // JPEG 头
      expect(clean.bytes[0], 0xFF);
      expect(clean.bytes[1], 0xD8);
    });

    test('不是图片时返回 null，由调用方退回原字节', () {
      expect(ExifCleaner.prepare(_bytesOf('not an image')), isNull);
      expect(ExifCleaner.prepare(_bytesOf('')), isNull);
    });
  });

  group('闲置与投入统计', () {
    test('从未穿过、闲置率、分类投入金额', () {
      final clothes = [
        _item(id: '1', price: 300, createdDaysAgo: 200),
        _item(id: '2', price: 200, wearCount: 5, lastWearDaysAgo: 3),
        _item(
            id: '3',
            category: ClothingCategory.shoes,
            price: 800,
            wearCount: 2,
            lastWearDaysAgo: 120),
      ];
      final ins = InsightsService().analyze(clothes);

      expect(ins.neverWorn, 1);
      expect(ins.idleCount, 2); // 200 天没穿 + 120 天没穿
      expect(ins.idleRate, closeTo(2 / 3, 0.001));
      expect(ins.avgIdleDays, greaterThan(90));
      expect(ins.valueByCategory[ClothingCategory.tops], 500);
      expect(ins.valueByCategory[ClothingCategory.shoes], 800);
      expect(ins.totalValue, 1300);
    });

    test('空衣橱不会除零', () {
      final ins = InsightsService().analyze([]);
      expect(ins.idleRate, 0);
      expect(ins.avgIdleDays, 0);
      expect(ins.valueByCategory, isEmpty);
    });

    test('全部穿过时闲置率为 0', () {
      final ins = InsightsService().analyze([
        _item(id: '1', wearCount: 1, lastWearDaysAgo: 1),
        _item(id: '2', wearCount: 1, lastWearDaysAgo: 2),
      ]);
      expect(ins.idleRate, 0);
      expect(ins.neverWorn, 0);
    });
  });

  group('场合约束推荐', () {
    test('指定场合时优先选带该场合标签的单品', () {
      Clothing top(String id, List<String> occ, int wear) => Clothing(
            id: id,
            imageUrl: '',
            category: ClothingCategory.tops,
            subCategory: 'shirt',
            color: '白色',
            material: MaterialType.cotton,
            thickness: 2,
            occasions: occ,
            wearCount: wear,
            createdAt: DateTime.now().subtract(const Duration(days: 5)),
          );
      final bottom = Clothing(
        id: 'b',
        imageUrl: '',
        category: ClothingCategory.bottoms,
        subCategory: 'jeans',
        color: '黑色',
        material: MaterialType.denim,
        occasions: const [Occasion.work, Occasion.daily],
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      );

      final engine = RecommendationEngine();
      final work = engine.recommend(
        clothes: [
          top('t1', const [Occasion.daily], 20),
          top('t2', const [Occasion.work], 0),
          bottom,
        ],
        temperature: 18,
        occasion: Occasion.work,
      );
      expect(work, isNotNull);
      expect(work!.top!.id, 't2');

      final daily = engine.recommend(
        clothes: [
          top('t1', const [Occasion.daily], 20),
          top('t2', const [Occasion.work], 0),
          bottom,
        ],
        temperature: 18,
        occasion: Occasion.daily,
      );
      expect(daily!.top!.id, 't1');
    });
  });

  group('上传体积信息', () {
    test('MB / KB 展示与节省比例', () {
      const info = UploadInfo(
        originalBytes: 4404019, // ≈4.2 MB
        uploadedBytes: 389120, // 380 KB
        width: 1280,
        height: 1707,
      );
      expect(info.originalLabel, '4.2 MB');
      expect(info.uploadedLabel, '380 KB');
      expect(info.sizeLabel, '1280×1707');
      expect(info.savedRatio, greaterThan(0.9));
    });
  });

  group('图片仓库类型识别', () {
    test('按前缀归类并格式化体积', () {
      final now = DateTime.now();
      final a = StoredImage(
          path: '/x/fullbody_1.jpg',
          name: 'fullbody_1.jpg',
          bytes: 2 * 1024 * 1024,
          modified: now);
      final b = StoredImage(
          path: '/x/piece_1.png',
          name: 'piece_1.png',
          bytes: 900,
          modified: now);
      expect(a.kind, 'fullbody');
      expect(b.kind, 'piece');
      expect(a.sizeLabel, '2.0 MB');
      expect(b.sizeLabel, '900 B');
      expect(formatBytes(1536), '2 KB');
      expect(formatBytes(1024 * 1024 * 1024), '1.00 GB');
    });
  });
}

// 把字符串转成字节，模拟「不是图片」的输入
Uint8List _bytesOf(String s) => Uint8List.fromList(s.codeUnits);

/// 扫描 JPEG 段，判断是否还带着 Exif APP1
bool _hasExifSegment(Uint8List jpeg) {
  var i = 2;
  while (i + 4 <= jpeg.length) {
    if (jpeg[i] != 0xFF) return false;
    final marker = jpeg[i + 1];
    if (marker == 0xD9) return false;
    final len = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (len < 2) return false;
    if (marker == 0xE1 &&
        i + 8 <= jpeg.length &&
        jpeg[i + 4] == 0x45 &&
        jpeg[i + 5] == 0x78 &&
        jpeg[i + 6] == 0x69 &&
        jpeg[i + 7] == 0x66) {
      return true;
    }
    i += 2 + len;
  }
  return false;
}
