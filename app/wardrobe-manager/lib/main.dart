import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/wardrobe_provider.dart';
import 'screens/home_screen.dart';
import 'screens/outdoor_screen.dart';
import 'screens/packing_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 奶油底 + 浅色主题：状态栏图标必须是深色，否则透明状态栏上看不清。
  // Android 15 起 targetSdk 35+ 会强制 edge-to-edge，这里显式声明避免系统猜错。
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.canvas,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // 全站按竖屏排版设计，锁竖屏避免横屏下 hero 卡片被拉变形
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final provider = WardrobeProvider();
  // init 内部已有守卫，这里再兜一层：存储彻底不可用时也要能进空衣橱，
  // 而不是停在启动图上。
  try {
    await provider.init();
  } catch (_) {
    // ignore: avoid_print
    debugPrint('provider init failed, starting with empty state');
  }

  runApp(WardrobeApp(provider: provider));
}

class WardrobeApp extends StatelessWidget {
  final WardrobeProvider provider;

  const WardrobeApp({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        title: '衣橱管家',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routes: {
          '/outdoor': (context) => const OutdoorScreen(),
          '/packing': (context) => const PackingScreen(),
        },
        home: const HomeScreen(),
      ),
    );
  }
}
