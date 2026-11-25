import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wardrobe_manager/models/models.dart';
import 'package:wardrobe_manager/services/backup_service.dart';
import 'package:wardrobe_manager/services/storage_service.dart';

void main() {
  late Directory tmp;
  late StorageService storage;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('wm_backup_test');

    // path_provider 在测试环境没有宿主，用一个临时目录顶上
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tmp.path);

    storage = StorageService();
    await storage.init();
    BackupService.instance.bind(storage);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('备份包含衣橱/愿望，恢复后衣物归属不丢', () async {
    await storage.saveSpace(WardrobeSpace(
      id: 'space_gym',
      name: '健身房柜',
      emoji: '🏋️',
      createdAt: DateTime(2025, 1, 1),
    ));

    await storage.addClothing(Clothing(
      id: 'c1',
      imageUrl: '',
      category: ClothingCategory.tops,
      subCategory: 't_shirt',
      color: '白色',
      createdAt: DateTime(2025, 1, 2),
      wardrobeId: 'space_gym',
    ));
    await storage.addClothing(Clothing(
      id: 'c2',
      imageUrl: '',
      category: ClothingCategory.bottoms,
      subCategory: 'jeans',
      color: '深蓝',
      createdAt: DateTime(2025, 1, 3),
    ));

    await storage.saveWishItem(WishItem(
      id: 'w1',
      name: '想买的机车夹克',
      category: ClothingCategory.tops,
      price: 899,
      priority: 2,
      createdAt: DateTime(2025, 1, 4),
    ));

    // 数字人形象：两张真实文件，备份恢复后不能丢
    final sheetFile = File(
        '${tmp.path}/wardrobe_images/avatar_sheet_test.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(64, 1));
    final sourceFile = File(
        '${tmp.path}/wardrobe_images/avatar_source_test.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(48, 2));
    await storage.saveProfile(UserProfile(
      nickname: '测试用户',
      createdAt: DateTime(2025, 1, 1),
      avatarSheetPath: sheetFile.path,
      avatarSourcePath: sourceFile.path,
    ));

    final exported = await BackupService.instance.export();
    expect(exported.ok, isTrue, reason: exported.message);
    expect(exported.path, isNotNull);

    // 先看备份文件本身：三个集合都在，衣物带着 wardrobeId
    final zipBytes = await File(exported.path!).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final dataFile =
        archive.files.firstWhere((f) => f.name == 'data.json');
    final data =
        jsonDecode(utf8.decode(dataFile.content as List<int>)) as Map;
    final spaces = (data['spaces'] as List).cast<Map>();
    final clothes = (data['clothes'] as List).cast<Map>();
    final wishes = (data['wishes'] as List).cast<Map>();
    expect(spaces.any((s) => s['id'] == 'space_gym'), isTrue);
    expect(clothes.firstWhere((c) => c['id'] == 'c1')['wardrobeId'],
        'space_gym');
    expect(wishes.single['name'], '想买的机车夹克');

    // 清空后再恢复，模拟换机
    await storage.clearAll();
    expect(storage.getAllClothes(), isEmpty);
    expect(storage.getAllWishItems(), isEmpty);

    final restored = await BackupService.instance.restore(exported.path!);
    expect(restored.ok, isTrue, reason: restored.message);
    expect(restored.clothes, 2);
    expect(restored.message, contains('衣橱新增 1'));
    expect(restored.message, contains('愿望新增 1'));

    // 换机后数字形象也回来了：路径换成新文件但内容还在
    final profile = storage.getProfile();
    expect(profile, isNotNull);
    expect(profile!.avatarSheetPath, isNotNull);
    expect(profile.avatarSourcePath, isNotNull);
    expect(File(profile.avatarSheetPath!).existsSync(), isTrue);
    expect(File(profile.avatarSheetPath!).lengthSync(), 64);
    expect(File(profile.avatarSourcePath!).lengthSync(), 48);

    final gym = storage
        .getAllSpaces()
        .firstWhere((s) => s.id == 'space_gym');
    expect(gym.name, '健身房柜');

    final byId = {for (final c in storage.getAllClothes()) c.id: c};
    expect(byId['c1']!.wardrobeId, 'space_gym');
    expect(byId['c2']!.wardrobeId, isNull);
    expect(storage.getAllWishItems().single.price, 899);
  });
}
