import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';

import '../features/ai_gateway/ai_service_page.dart';
import '../features/backup_restore/backup_page.dart';
import '../features/image_manager/image_manager_page.dart';
import '../providers/wardrobe_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/kit.dart';

/// 独立设置页：只放真正的「设置」——城市与天气、AI 服务状态、
/// 数据管理（图片管家 / 备份）、关于。
///
/// 业务功能（拆衣、试穿、数字人、洗护、愿望清单…）都在「我的 → 功能中心」，
/// 不再和设置混在一起。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WardrobeProvider>();
    final weather = provider.weather;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: '设置',
              eyebrow: 'SETTINGS',
              subtitle: '城市、天气、AI 服务与数据',
              actions: [
                RoundIconButton(
                  icon: Icons.close,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  _sectionTitle('地区与天气'),
                  _groupCard(context, [
                    _tile(
                      icon: Icons.location_on_outlined,
                      title: '当前城市',
                      subtitle: '用于天气与穿搭推荐',
                      trailing: Text(
                        provider.city,
                        style: const TextStyle(
                            fontSize: 14, color: AppColors.inkMuted),
                      ),
                      onTap: () => _editCity(context, provider),
                    ),
                    _divider(),
                    _tile(
                      icon: Icons.near_me_outlined,
                      title: '使用当前位置',
                      subtitle: '通过网络定位城市；精确位置需系统授予定位权限',
                      onTap: () async {
                        final city = await provider.locateByIp();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(city == null
                                ? (provider.weatherError ??
                                    '自动定位失败，请手动选择城市')
                                : '已定位到「$city」，正在刷新天气')));
                      },
                    ),
                    _divider(),
                    _tile(
                      icon: Icons.cloud_outlined,
                      title: '天气状态',
                      subtitle: weather != null
                          ? '${weather.conditionText} · ${provider.city} · ${provider.weatherSource}'
                          : (provider.weatherError ?? '点右侧按钮刷新天气'),
                      maxLines: 2,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (provider.weatherLoading)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.accent),
                            )
                          else if (weather != null)
                            Text('${weather.emoji} ${weather.temperature.round()}°C',
                                style: const TextStyle(
                                    fontSize: 14, color: AppColors.inkMuted))
                          else
                            const Text('未获取',
                                style: TextStyle(
                                    fontSize: 13, color: AppColors.inkSubtle)),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.refresh,
                                size: 18, color: AppColors.accent),
                            onPressed: () => provider.refreshWeather(),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _sectionTitle('AI 服务'),
                  _groupCard(context, [
                    _tile(
                      icon: Icons.smart_toy_outlined,
                      title: 'AI 服务状态',
                      subtitle: provider.aiService == null
                          ? '正在连接…'
                          : '${provider.aiService!.summary} · 模型由管理员统一配置',
                      maxLines: 2,
                      chevron: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AiServicePage()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _sectionTitle('数据'),
                  _groupCard(context, [
                    _tile(
                      icon: Icons.photo_library_outlined,
                      title: '图片管家',
                      subtitle: '占用统计、清理孤儿图、批量压缩',
                      chevron: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ImageManagerPage()),
                      ),
                    ),
                    _divider(),
                    _tile(
                      icon: Icons.inventory_2_outlined,
                      title: '备份与恢复',
                      subtitle: '导出 zip（含照片）与导入恢复，换手机用',
                      chevron: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                BackupPage(storage: provider.storage)),
                      ),
                    ),
                    _divider(),
                    // #18：说明文案——image_picker 走系统 Photo Picker / 系统相机
                    // Activity，Android 13+ 免照片与相机权限，App 也未声明它们
                    _tile(
                      icon: Icons.photo_camera_outlined,
                      title: '照片与相机权限',
                      subtitle: '照片选择与拍照由系统提供，无需授权',
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _sectionTitle('关于'),
                  _groupCard(context, [
                    _tile(
                      icon: Icons.info_outline,
                      title: '衣橱管家',
                      subtitle:
                          'v1.9.0 · 本地优先：衣物、记录、搭配全部存在手机上；'
                          'AI 能力由管理员统一开通',
                      maxLines: 3,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: .4,
                color: AppColors.inkMuted)),
      );

  Widget _groupCard(BuildContext context, List<Widget> children) => Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _divider() => const Divider(indent: 16, endIndent: 16, height: 1);

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    int maxLines = 1,
    bool chevron = false,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.inkMuted),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14.5, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style:
              const TextStyle(fontSize: 11.5, color: AppColors.inkSubtle)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) Flexible(child: trailing),
          if (chevron)
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.inkSubtle),
        ],
      ),
      onTap: onTap,
    );
  }

  Future<void> _editCity(
    BuildContext context,
    WardrobeProvider provider,
  ) async {
    final controller = TextEditingController(text: provider.city);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('切换城市'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '城市名称',
            hintText: '如：武汉',
            prefixIcon: Icon(Icons.location_city_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    final city = controller.text.trim();
    controller.dispose();
    if (confirmed == true && city.isNotEmpty) {
      await provider.setCity(city);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('城市已切换为「$city」，正在刷新天气…'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
