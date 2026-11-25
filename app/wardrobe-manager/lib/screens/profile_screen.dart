import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';

import '../data/clothing_naming.dart';
import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../services/platform_image.dart';
import '../theme/app_theme.dart';
import '../widgets/kit.dart';
import 'insights_screen.dart';
import 'settings_page.dart';
import '../features/auto_split/auto_split_page.dart';
import '../features/laundry/laundry_page.dart';
import '../features/wishlist/wishlist_page.dart';
import '../features/calendar/outfit_calendar_page.dart';
import '../features/style_analysis/style_analysis_page.dart';
import '../features/try_on/try_on_page.dart';
import '../features/virtual_closet/virtual_closet_page.dart';
import '../features/virtual_closet/digital_avatar_page.dart';
import '../features/spaces/space_page.dart';

/// 「我的」页：个人卡 + 数字形象 + 功能中心 + 衣物统计。
///
/// 设置已经拆到独立的 [SettingsPage]（右上角齿轮进入），
/// 业务功能集中在「功能中心」宫格，不再堆在设置列表里。
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const Map<String, String> _genderNames = {
    'male': '男',
    'female': '女',
    'other': '保密',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(84),
        child: SafeArea(
          bottom: false,
          child: ScreenHeader(
            title: '我的',
            eyebrow: 'PROFILE',
            actions: [
              RoundIconButton(
                icon: Icons.settings_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Consumer<WardrobeProvider>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildProfileCard(context, provider),
                const SizedBox(height: 16),
                _buildAvatarHero(context, provider),
                const SizedBox(height: 18),
                _buildFeatureCenter(context, provider),
                const SizedBox(height: 18),
                _buildStatsCard(context, provider),
                const SizedBox(height: 16),
                _buildAboutCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============ 个人卡 ============

  Widget _buildProfileCard(BuildContext context, WardrobeProvider provider) {
    final profile = provider.profile;
    final gender = profile?.gender;
    final height = profile?.height;
    final weight = profile?.weight;
    final styles = profile?.stylePreferences ?? const <String>[];
    final achievementCount =
        (profile?.achievements ?? const <String>[]).length;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editNickname(context, provider),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      gender == 'female'
                          ? Icons.face_3_outlined
                          : Icons.person_outline,
                      size: 28,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                profile?.nickname ?? '衣橱达人',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: AppColors.inkSubtle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '点击修改昵称',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editBodyInfo(context, provider),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _infoTile('性别', _genderLabel(gender)),
                    ),
                    _verticalDivider(),
                    Expanded(
                      child: _infoTile(
                        '身高',
                        height != null ? '$height cm' : '未填',
                      ),
                    ),
                    _verticalDivider(),
                    Expanded(
                      child: _infoTile(
                        '体重',
                        weight != null ? '$weight kg' : '未填',
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.inkSubtle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _metricColumn('${profile?.points ?? 0}', '积分')),
              _verticalDivider(height: 22),
              Expanded(
                child: _metricColumn(
                  '${provider.streakDays} 天',
                  '连续打卡',
                ),
              ),
              _verticalDivider(height: 22),
              Expanded(
                child: _metricColumn('$achievementCount 枚', '成就'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _sectionLabel('风格偏好'),
              const Spacer(),
              ActionChip(
                avatar: const Icon(
                  Icons.tune,
                  size: 14,
                  color: AppColors.primary,
                ),
                label: const Text('编辑'),
                onPressed: () => _editStyles(context, provider),
              ),
            ],
          ),
          if (styles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '还没有偏好风格，点右上「编辑」挑选',
                style: TextStyle(fontSize: 12, color: AppColors.inkSubtle),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in styles)
                    TagPill(
                      label: StyleTag.names[id] ?? id,
                      iconEmoji: '✨',
                      background: AppColors.accentSoft,
                      foreground: AppColors.accent,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _genderLabel(String? gender) =>
      _genderNames[gender ?? 'other'] ?? '保密';

  Widget _infoTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppColors.inkSubtle),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _metricColumn(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.inkSubtle),
        ),
      ],
    );
  }

  Widget _verticalDivider({double height = 26}) {
    return Container(
      width: 1,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: AppColors.hairline,
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.inkMuted,
        letterSpacing: 0.3,
      ),
    );
  }

  // ============ 衣物统计卡 ============

  Widget _buildStatsCard(BuildContext context, WardrobeProvider provider) {
    final utilization = provider.getUtilization();
    final categoryStats = provider.getCategoryStats();
    final materialStats = provider.getMaterialStats();
    final mostWorn = provider.getMostWornClothes(limit: 5);
    final idleList = provider.getIdleClothes();

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('衣物统计'),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(utilization * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                      height: 1.0,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '衣橱利用率',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.inkSubtle,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _metricColumn('${provider.totalClothes}', '件数'),
                    ),
                    Expanded(
                      child: _metricColumn(
                        '${provider.records.length}',
                        '记录数',
                      ),
                    ),
                    Expanded(
                      child: _metricColumn(
                        '${provider.totalOutfits}',
                        '搭配数',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _sectionLabel('分类分布 · Top6'),
          const SizedBox(height: 10),
          _buildCategoryBars(categoryStats),
          const SizedBox(height: 8),
          _sectionLabel('材质分布'),
          const SizedBox(height: 10),
          _buildMaterialChips(materialStats),
          const Divider(height: 24),
          _sectionLabel('最常穿 Top5'),
          const SizedBox(height: 6),
          _buildMostWornList(mostWorn),
          const Divider(height: 24),
          _sectionLabel('闲置提醒 · 超 90 天未穿'),
          const SizedBox(height: 6),
          _buildIdleList(context, idleList),
        ],
      ),
    );
  }

  Widget _buildCategoryBars(Map<String, int> stats) {
    final entries = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const Text(
        '暂无衣物，先去衣橱添加几件吧',
        style: TextStyle(fontSize: 12, color: AppColors.inkSubtle),
      );
    }
    final top = entries.take(6).toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in top) _buildCategoryBarRow(e, total),
      ],
    );
  }

  static IconData _categoryIcon(String key) {
    switch (key) {
      case ClothingCategory.tops:
        return Icons.checkroom;
      case ClothingCategory.bottoms:
        return Icons.dry_cleaning;
      case ClothingCategory.dress:
        return Icons.woman;
      case ClothingCategory.outerwear:
        return Icons.ac_unit;
      case ClothingCategory.shoes:
        return Icons.ice_skating;
      case ClothingCategory.accessories:
        return Icons.shopping_bag_outlined;
    }
    return Icons.checkroom;
  }

  Widget _buildCategoryBarRow(MapEntry<String, int> entry, int total) {
    final fraction = total > 0 ? entry.value / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _categoryIcon(entry.key),
                size: 14,
                color: AppColors.inkSubtle,
              ),
              const SizedBox(width: 6),
              Text(
                ClothingCategory.names[entry.key] ?? entry.key,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${entry.value} 件',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LayoutBuilder(
            builder: (context, constraints) {
              var barWidth = constraints.maxWidth * fraction;
              if (barWidth < 3) barWidth = 3;
              return Container(
                height: 6,
                width: constraints.maxWidth,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(99),
                ),
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 6,
                  width: barWidth,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialChips(Map<String, int> stats) {
    if (stats.isEmpty) {
      return const Text(
        '暂无材质数据',
        style: TextStyle(fontSize: 12, color: AppColors.inkSubtle),
      );
    }
    final entries = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in entries)
          TagPill(
            label: '${MaterialType.name(e.key)} ×${e.value}',
            background: _materialTagBg(e.key),
            foreground: AppColors.inkMuted,
          ),
      ],
    );
  }

  Color _materialTagBg(String id) {
    switch (id) {
      case 'wool':
      case 'cashmere':
      case 'down':
      case 'leather':
        return AppColors.tagWarm;
      case 'linen':
      case 'silk':
      case 'quick_dry':
        return AppColors.tagCool;
      default:
        return AppColors.tagNeutral;
    }
  }

  Widget _buildMostWornList(List<Clothing> clothes) {
    if (clothes.isEmpty) {
      return const Text(
        '暂无穿着记录',
        style: TextStyle(fontSize: 12, color: AppColors.inkSubtle),
      );
    }
    return Column(
      children: [
        for (final c in clothes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Text(
                  ClothingCategory.icons[c.category] ?? '👕',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TagPill(
                  label: '${c.wearCount} 次',
                  iconEmoji: '🔥',
                  background: AppColors.primarySoft,
                  foreground: AppColors.primary,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildIdleList(BuildContext context, List<Clothing> clothes) {
    if (clothes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 15, color: AppColors.ok),
            SizedBox(width: 6),
            Text(
              '衣橱活跃，无闲置衣物 ✓',
              style: TextStyle(fontSize: 12.5, color: AppColors.ok),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final c in clothes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Text(
                  ClothingCategory.icons[c.category] ?? '👕',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TagPill(
                  label: '闲置 ${c.idleDays()} 天',
                  background: AppColors.warn.withValues(alpha: 0.14),
                  foreground: AppColors.warn,
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => _wakeUp(context, c),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    minimumSize: const Size(44, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('唤醒它'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _wakeUp(BuildContext context, Clothing c) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '建议把「${c.displayName}」编入最近的搭配，先穿一次再决定去留。',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============ 数字形象 Hero + 功能中心 ============

  Widget _buildAvatarHero(BuildContext context, WardrobeProvider provider) {
    final sheetPath = provider.profile?.avatarSheetPath;
    final img = fileImageWidget(sheetPath, fit: BoxFit.cover);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DigitalAvatarPage()),
      ),
      child: Container(
        height: 118,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              width: 76,
              height: 92,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: img ??
                  const Icon(Icons.face_retouching_natural,
                      size: 32, color: Colors.white38),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Eyebrow('DIGITAL AVATAR', color: AppColors.lime),
                  const SizedBox(height: 5),
                  Text(
                    sheetPath != null ? '我的数字形象' : '创建照片数字人',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.3,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sheetPath != null ? '切换视角 · 带着形象去试穿' : '一张全身照，生成正 / 侧 / 背三视角',
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.white60),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _groupHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: .4,
                color: AppColors.inkMuted)),
      );

  Widget _buildFeatureCenter(BuildContext context, WardrobeProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _groupHeader('AI 造型'),
        Row(
          children: [
            Expanded(
                child: _featureCell(context,
                    icon: Icons.auto_awesome_motion,
                    title: 'AI 拆衣',
                    subtitle: '拍照拆单入库',
                    page: const AutoSplitPage())),
            const SizedBox(width: 10),
            Expanded(
                child: _featureCell(context,
                    icon: Icons.accessibility_new,
                    title: '虚拟试穿',
                    subtitle: '看到上身效果',
                    page: const TryOnPage())),
            const SizedBox(width: 10),
            Expanded(
                child: _featureCell(context,
                    icon: Icons.face_retouching_natural,
                    title: '风格画像',
                    subtitle: '衣橱风格解读',
                    page: const StyleAnalysisPage())),
          ],
        ),
        const SizedBox(height: 18),
        _groupHeader('衣橱工具'),
        Row(
          children: [
            Expanded(
                child: _featureCell(context,
                    icon: Icons.view_in_ar_outlined,
                    title: '数字展厅',
                    subtitle: '环形陈列单品',
                    page: const VirtualClosetPage())),
            const SizedBox(width: 10),
            Expanded(
                child: _featureCell(context,
                    icon: Icons.local_laundry_service_outlined,
                    title: '洗护中心',
                    subtitle:
                        '${provider.laundryItems.length} 件在外',
                    page: const LaundryPage())),
            const SizedBox(width: 10),
            Expanded(
                child: _featureCell(context,
                    icon: Icons.favorite_border,
                    title: '愿望清单',
                    subtitle:
                        '${provider.activeWishes.length} 件想买',
                    page: const WishlistPage())),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _featureCell(context,
                    icon: Icons.door_sliding_outlined,
                    title: '衣橱空间',
                    subtitle: '${provider.spaces.length} 个衣橱',
                    page: const SpaceManagerPage())),
            const SizedBox(width: 10),
            Expanded(
                child: _featureCell(context,
                    icon: Icons.insights,
                    title: '衣橱体检',
                    subtitle: '利用率与断舍离',
                    page: const InsightsScreen())),
            const SizedBox(width: 10),
            Expanded(
                child: _featureCell(context,
                    icon: Icons.calendar_month_outlined,
                    title: '穿搭日历',
                    subtitle:
                        '${provider.records.where((r) => r.date.month == DateTime.now().month && r.date.year == DateTime.now().year).map((r) => r.date.day).toSet().length} 天有记录',
                    page: const OutfitCalendarPage())),
          ],
        ),
      ],
    );
  }

  Widget _featureCell(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return GestureDetector(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.inkSubtle)),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard() {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🧺', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          const Text(
            '衣橱管家 v1.8 · 本地数据优先 · AI 由管理员统一开通',
            style: TextStyle(fontSize: 12, color: AppColors.inkSubtle),
          ),
        ],
      ),
    );
  }

  // ============ 弹窗 ============

  Future<void> _editNickname(
    BuildContext context,
    WardrobeProvider provider,
  ) async {
    final controller = TextEditingController(
      text: provider.profile?.nickname ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改昵称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(
            labelText: '昵称',
            hintText: '给自己起个名字',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final nickname = controller.text.trim();
    controller.dispose();
    if (confirmed == true && nickname.isNotEmpty) {
      await provider.updateProfile(nickname: nickname);
    }
  }

  Future<void> _editBodyInfo(
    BuildContext context,
    WardrobeProvider provider,
  ) async {
    final profile = provider.profile;
    if (profile == null) return;
    final heightController = TextEditingController(
      text: profile.height?.toString() ?? '',
    );
    final weightController = TextEditingController(
      text: profile.weight?.toString() ?? '',
    );
    var gender = profile.gender ?? 'other';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('身材数据'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in _genderNames.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: gender == entry.key,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => gender = entry.key);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: heightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '身高 (cm)',
                  prefixIcon: Icon(Icons.straighten),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: weightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '体重 (kg)',
                  prefixIcon: Icon(Icons.monitor_weight_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    final height = int.tryParse(heightController.text.trim());
    final weight = int.tryParse(weightController.text.trim());
    heightController.dispose();
    weightController.dispose();
    if (confirmed != true) return;
    await provider.updateProfile(
      gender: gender,
      height: height ?? profile.height,
      weight: weight ?? profile.weight,
    );
  }

  Future<void> _editStyles(
    BuildContext context,
    WardrobeProvider provider,
  ) async {
    final profile = provider.profile;
    if (profile == null) return;
    final selected = List<String>.from(profile.stylePreferences);
    final customCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          void addCustom(String text, {bool select = true}) {
            final v = text.trim();
            if (v.isEmpty) return;
            if (!provider.customStyles.contains(v)) {
              provider.setCustomStyles([...provider.customStyles, v]);
            }
            if (select && !selected.contains(v)) selected.add(v);
            setState(() {});
            customCtrl.clear();
          }

          return AlertDialog(
            title: const Text('风格偏好（可自定义）'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('内置预设',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in StyleTag.names.entries)
                          FilterChip(
                            label: Text(entry.value),
                            selected: selected.contains(entry.key),
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  selected.add(entry.key);
                                } else {
                                  selected.remove(entry.key);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('更多风格（点一下即保存为自定义）',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in StylePresets.builtin)
                          FilterChip(
                            label: Text(s, style: const TextStyle(fontSize: 11)),
                            selected: selected.contains(s),
                            onSelected: (v) {
                              if (v) {
                                addCustom(s);
                              } else {
                                setState(() => selected.remove(s));
                              }
                            },
                          ),
                      ],
                    ),
                    if (provider.customStyles.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text('我自定义的',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final s in provider.customStyles)
                            Chip(
                              label: Text(s),
                              onDeleted: () {
                                selected.remove(s);
                                provider.setCustomStyles(
                                    provider.customStyles
                                        .where((e) => e != s)
                                        .toList());
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customCtrl,
                            decoration: const InputDecoration(
                                isDense: true,
                                hintText: '输入自定义风格，如 山系穿搭',
                                border: OutlineInputBorder()),
                            onSubmitted: addCustom,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => addCustom(customCtrl.text),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    customCtrl.dispose();
    if (confirmed == true) {
      await provider.updateProfile(stylePreferences: selected);
    }
  }

  // 城市切换与天气刷新在「设置」页（SettingsPage），不再堆在「我的」。
}

