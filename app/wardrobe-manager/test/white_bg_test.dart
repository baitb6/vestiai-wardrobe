import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_manager/services/gateway_profile.dart';
import 'package:wardrobe_manager/services/vision_gateway_service.dart';
import 'package:wardrobe_manager/services/white_background_service.dart';

GatewayProfile _editProfile({bool supportsImageEdit = true}) => GatewayProfile(
      kind: GatewayKind.edit,
      baseUrl: 'https://example.com/v1',
      model: 'gpt-image-1',
      supportsImageEdit: supportsImageEdit,
    );

void main() {
  group('白底商品图', () {
    test('没配置网关时抛中文提示，不发网络请求', () async {
      final service = WhiteBackgroundService();
      await expectLater(
        service.generate(
          source: Uint8List.fromList([1, 2, 3]),
          profile: GatewayProfile(kind: GatewayKind.edit),
        ),
        throwsA(
          isA<GatewayException>()
              .having((e) => e.kind, 'kind', GatewayErrorKind.unsupported)
              .having((e) => e.message, 'message', contains('图像编辑')),
        ),
      );
    });

    test('配置了地址但模型不支持图像编辑时也拒绝', () async {
      final service = WhiteBackgroundService();
      await expectLater(
        service.generate(
          source: Uint8List.fromList([1, 2, 3]),
          profile: _editProfile(supportsImageEdit: false),
        ),
        throwsA(isA<GatewayException>()
            .having((e) => e.kind, 'kind', GatewayErrorKind.unsupported)),
      );
    });

    test('提示词要求白底、只留单品、保留款式', () {
      final prompt = WhiteBackgroundService.buildPrompt(
        category: '上衣',
        color: '雾霾蓝',
      );
      expect(prompt, contains('pure white background'));
      expect(prompt, contains('#FFFFFF'));
      expect(prompt, contains('Remove the person'));
      expect(prompt, contains('Do not invent extra garments'));
      expect(prompt, contains('类别：上衣'));
      expect(prompt, contains('颜色：雾霾蓝'));
      // 白底图和虚拟试穿是两个任务，提示词不能混
      expect(prompt.toLowerCase(), isNot(contains('try-on')));
    });

    test('类别和颜色为空时不写空标签', () {
      final prompt = WhiteBackgroundService.buildPrompt();
      expect(prompt, isNot(contains('类别：')));
      expect(prompt, isNot(contains('颜色：')));
    });

    test('按文件头识别扩展名', () {
      final png = WhiteBackgroundResult(
        bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]),
        endpoint: '/images/edits',
      );
      final jpg = WhiteBackgroundResult(
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0]),
        endpoint: '/images/edits',
      );
      expect(png.isPng, isTrue);
      expect(png.extension, 'png');
      expect(jpg.isPng, isFalse);
      expect(jpg.extension, 'jpg');
    });
  });
}
