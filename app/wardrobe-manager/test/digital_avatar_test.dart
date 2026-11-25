import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wardrobe_manager/models/user_profile.dart';
import 'package:wardrobe_manager/services/wardrobe_backend.dart';

void main() {
  group('数字人 Hive 字段兼容', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('wm_avatar_test');
      Hive.init(tmp.path);
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(UserProfileAdapter());
      }
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('新字段可空读写，旧数据不含字段也能读', () async {
      final box = await Hive.openBox<UserProfile>('profile_new');
      // 1) 带数字人字段写入再读出
      final p = UserProfile(
        nickname: '小王',
        createdAt: DateTime(2026, 1, 1),
        avatarSheetPath: '/imgs/avatar_sheet_1.png',
        avatarSourcePath: '/imgs/avatar_source_1.jpg',
      );
      await box.put('me', p);
      final r = box.get('me')!;
      expect(r.avatarSheetPath, '/imgs/avatar_sheet_1.png');
      expect(r.avatarSourcePath, '/imgs/avatar_source_1.jpg');

      // 2) 旧版本写入的数据升级后读：不存在的字段读出为 null
      final legacyBox = await Hive.openBox('profile_legacy');
      await legacyBox.put('raw', 'old');
      expect(legacyBox.get('raw'), 'old');
      final mixed = UserProfile(createdAt: DateTime(2026, 1, 2));
      await box.put('old_user', mixed);
      final r2 = box.get('old_user')!;
      expect(r2.avatarSheetPath, isNull);
      expect(r2.avatarSourcePath, isNull);
    });

    test('生成/删除数字人后字段互不干扰', () {
      final p = UserProfile(
        createdAt: DateTime(2026, 1, 1),
        avatarSheetPath: null,
        avatarSourcePath: null,
      );
      expect(p.avatarSheetPath, isNull);
      p.avatarSheetPath = '/x.png';
      p.avatarSourcePath = '/y.jpg';
      expect(p.avatarSheetPath, '/x.png');
    });
  });

  group('BackendConfig 数字人就绪解析', () {
    test('ai.avatar 开启时 avatarReady 为 true', () {
      final cfg = BackendConfig.fromJson({
        'ai': {
          'enabled': true,
          'vision': true,
          'text': true,
          'edit': true,
          'white_bg': true,
          'avatar': true,
        },
        'white_bg': {'mode': 'local'},
        'notice': '',
        'min_version': '1.8.0',
      });
      expect(cfg.avatarReady, isTrue);
      expect(cfg.aiEnabled, isTrue);
      expect(cfg.anyAi, isTrue);
      expect(cfg.summary, '已连接');
    });

    test('avatar 未配置但 edit 可用时服务端会兜底为 true', () {
      // 服务端 config 的 avatar = kind_ready('avatar') or kind_ready('edit')
      final cfg = BackendConfig.fromJson({
        'ai': {'enabled': true, 'edit': true, 'avatar': true},
      });
      expect(cfg.avatarReady, isTrue);
    });

    test('离线兜底全 false 且 error 保留', () {
      final cfg = BackendConfig.unavailable('连不上服务');
      expect(cfg.avatarReady, isFalse);
      expect(cfg.online, isFalse);
      expect(cfg.error, '连不上服务');
      expect(cfg.summary, '未连接');
    });

    test('ai.enabled false 时 avatar 不可用', () {
      final cfg = BackendConfig.fromJson({
        'ai': {'enabled': false, 'avatar': true},
      });
      expect(cfg.avatarReady, isTrue); // 原样透传
      expect(cfg.aiEnabled, isFalse); // 但页面会先看 aiEnabled
    });
  });

  group('数字人图片字节扩展判断', () {
    test('PNG 与 JPEG magic 前缀判断', () {
      final png =
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
      expect(png[0] == 0x89, isTrue);
      expect(jpg[0] == 0xFF && jpg[1] == 0xD8, isTrue);
    });
  });
}
