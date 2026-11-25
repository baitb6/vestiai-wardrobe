import 'dart:io';

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wardrobe_manager/providers/wardrobe_provider.dart';
import 'package:wardrobe_manager/screens/profile_screen.dart';
import 'package:wardrobe_manager/screens/settings_page.dart';
import 'package:wardrobe_manager/features/virtual_closet/digital_avatar_page.dart';

Widget _app(WardrobeProvider p, Widget child) => ChangeNotifierProvider<
        WardrobeProvider>.value(
    value: p,
    child: MaterialApp(
      theme: ThemeData(fontFamily: null, useMaterial3: true),
      home: child,
    ));

void main() {
  late Directory tmp;
  late WardrobeProvider provider;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('wm_ui_test');
    provider = WardrobeProvider();
  });

  tearDownAll(() async {
    provider.dispose();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('「我的」页：功能中心分组 + 数字人入口 + 齿轮设置', (tester) async {
    await tester.pumpWidget(_app(provider, const ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('AI 造型'), findsOneWidget);
    expect(find.text('衣橱工具'), findsOneWidget);
    expect(find.text('创建照片数字人'), findsOneWidget);
    expect(find.text('AI 拆衣'), findsOneWidget);
    expect(find.text('虚拟试穿'), findsOneWidget);
    expect(find.text('风格画像'), findsOneWidget);
    expect(find.text('数字展厅'), findsOneWidget);
    expect(find.text('洗护中心'), findsOneWidget);
    expect(find.text('愿望清单'), findsOneWidget);
    expect(find.text('衣橱空间'), findsOneWidget);
    expect(find.text('衣橱体检'), findsOneWidget);
    expect(find.text('穿搭日历'), findsOneWidget);
    // 设置已经拆走：旧设置卡里的城市/天气/备份不再出现在「我的」
    expect(find.text('当前城市'), findsNothing);
    expect(find.text('天气状态'), findsNothing);
    expect(find.text('备份与恢复'), findsNothing);
    expect(find.text('3D 人物全方位'), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('设置页：只有真正的设置，没有业务功能', (tester) async {
    await tester.pumpWidget(_app(provider, const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('地区与天气'), findsOneWidget);
    expect(find.text('当前城市'), findsOneWidget);
    expect(find.text('使用当前位置'), findsOneWidget);
    expect(find.text('AI 服务状态'), findsOneWidget);
    expect(find.text('图片管家'), findsOneWidget);
    expect(find.text('备份与恢复'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('关于'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('关于'), findsOneWidget);
    // 业务功能绝不能混进设置
    expect(find.text('AI 拆衣'), findsNothing);
    expect(find.text('虚拟试穿'), findsNothing);
    expect(find.text('洗护中心'), findsNothing);
  });

  testWidgets('数字人页空态：隐私说明 + 生成入口', (tester) async {
    await tester.pumpWidget(_app(provider, const DigitalAvatarPage()));
    await tester.pumpAndSettle();

    expect(find.text('还没有你的数字形象'), findsOneWidget);
    expect(find.text('选照片生成形象'), findsOneWidget);
    expect(find.text('照片建议：正面站直、全身入镜、光线均匀'), findsOneWidget);
    expect(find.byIcon(Icons.face_retouching_natural), findsOneWidget);
  });
}
