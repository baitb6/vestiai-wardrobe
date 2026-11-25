import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../data/clothing_naming.dart';
import '../data/style_presets.dart';
import '../features/laundry/laundry_page.dart';
import '../features/share/share_card_page.dart';
import '../features/try_on/try_on_page.dart';
import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../services/recommendation_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/add_clothing_sheet.dart';
import '../widgets/clothing_card.dart';
import '../widgets/kit.dart';
import '../widgets/outfit_preview.dart';
import '../widgets/style_sheet.dart';
import 'insights_screen.dart';
import 'outfit_screen.dart';
import 'profile_screen.dart';
import 'record_screen.dart';
import 'wardrobe_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _screens = <Widget>[
    _DashboardTab(),
    WardrobeScreen(),
    OutfitScreen(),
    RecordScreen(),
    ProfileScreen(),
  ];

  void switchTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: SafeArea(
        top: false,
        child: FloatingNavBar(index: _index, onChanged: switchTab),
      ),
    );
  }
}

// ============================================================
// 今天
// ============================================================

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  /// 今日场合约束（null = 不限）
  String? _occasion;

  /// 打卡进行中标记：防止「就穿这套」连点插入重复 OutfitRecord
  bool _punching = false;

  _HomeScreenState? _home(BuildContext context) =>
      context.findAncestorStateOfType<_HomeScreenState>();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final plan = p.recommendToday(occasion: _occasion);
    final hour = DateTime.now().hour;
    final greet = hour < 6
        ? '还没睡？'
        : hour < 11
            ? '早上好'
            : hour < 18
                ? '下午好'
                : '晚上好';

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.ink,
          onRefresh: () async {
            // 防抖：后台已在刷新（如启动时的自动刷新）时不叠加网络请求，
            // 避免两次 refreshWeather 并发导致 _weatherLoading 状态互相覆盖。
            if (p.weatherLoading) return;
            await p.refreshWeather();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
            children: [
              _topBar(context, p, greet),
              const SizedBox(height: 22),
              _headline(context, p, plan),
              const SizedBox(height: 20),
              _heroCard(context, p, plan),
              const SizedBox(height: 12),
              _occasionRow(p),
              if ((p.aiService?.notice ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                _serviceNotice(p.aiService!.notice),
              ],
              const SizedBox(height: 14),
              _statsStrip(context, p),
              if (p.insights.washingCount > 0) ...[
                const SizedBox(height: 10),
                _laundryBanner(context, p),
              ],
              const SizedBox(height: 30),
              SectionTitle('灵感风格',
                  eyebrow: 'MOOD BOARD',
                  trailing: _link('随便逛逛', () => _home(context)?.switchTab(2))),
              const SizedBox(height: 12),
              _styleBoard(context),
              const SizedBox(height: 30),
              SectionTitle('本周穿什么',
                  eyebrow: 'WEEK PLAN',
                  trailing:
                      _link('看日历', () => _home(context)?.switchTab(3))),
              const SizedBox(height: 12),
              _weekPlan(context, p),
              const SizedBox(height: 30),
              SectionTitle('衣橱体检',
                  eyebrow: 'WARDROBE CHECK',
                  trailing: _link('完整报告',
                      () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const InsightsScreen()),
                          ))),
              const SizedBox(height: 12),
              _healthCard(context, p),
              const SizedBox(height: 30),
              SectionTitle('最近添加',
                  eyebrow: 'RECENT',
                  trailing: _link('全部', () => _home(context)?.switchTab(1))),
              const SizedBox(height: 12),
              _recent(context, p),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 顶部 ----------

  Widget _topBar(BuildContext context, WardrobeProvider p, String greet) {
    final now = DateTime.now();
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('$greet · ${now.month}月${now.day}日 周${week[now.weekday - 1]}'),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Text('衣橱管家',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text('BETA',
                        style: TextStyle(
                            fontSize: 8,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            color: AppColors.lime)),
                  ),
                ],
              ),
            ],
          ),
        ),
        RoundIconButton(
          icon: Icons.search,
          onTap: () => _home(context)?.switchTab(1),
        ),
        const SizedBox(width: 8),
        RoundIconButton(
          icon: Icons.insights_outlined,
          dark: true,
          badge: p.insights.washingCount > 0 ? '!' : null,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const InsightsScreen())),
        ),
      ],
    );
  }

  // ---------- 大标题 + 天气 ----------

  Widget _headline(BuildContext context, WardrobeProvider p, OutfitPlan? plan) {
    final w = p.weather;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 40,
              height: 1.02,
              fontWeight: FontWeight.w900,
              letterSpacing: -2,
              color: AppColors.ink,
              fontFamily: null,
            ),
            children: [
              const TextSpan(text: '今天穿'),
              TextSpan(
                text: '什么',
                style: TextStyle(
                  color: AppColors.primary,
                  fontStyle: FontStyle.italic,
                  shadows: [
                    Shadow(
                        color: AppColors.primary.withValues(alpha: .25),
                        offset: const Offset(1.5, 1.5)),
                  ],
                ),
              ),
              const TextSpan(text: '？'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  // #19 加载动画：天气刷新时转小圈，而不是干等文字
                  p.weatherLoading
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.6, color: AppColors.inkMuted),
                        )
                      : Icon(w != null ? Icons.wb_cloudy_outlined : Icons.cloud_off,
                          size: 14, color: AppColors.inkMuted),
                  const SizedBox(width: 6),
                  Text(
                    w != null
                        ? '${p.city} ${w.temperature.round()}°C ${w.conditionText}'
                        : '${p.city} · 天气加载中',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (w != null && w.tips.isNotEmpty)
              Flexible(
                child: Text(
                  w.tips.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.inkSubtle),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ---------- 主推荐卡 ----------

  Widget _heroCard(BuildContext context, WardrobeProvider p, OutfitPlan? plan) {
    final hasPlan = plan != null && plan.pieces.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
              color: Color(0x2A15110E), blurRadius: 30, offset: Offset(0, 14)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow("TODAY'S PICK", color: AppColors.lime),
                  const SizedBox(height: 4),
                  Text(
                    hasPlan ? '这套最合今天' : '还差几件衣服',
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.white),
                  ),
                ],
              ),
              const Spacer(),
              if (hasPlan)
                ScoreRing(
                  value: plan.score,
                  size: 58,
                  stroke: 5,
                  color: AppColors.lime,
                  label: '适配',
                  textColor: Colors.white,
                  subColor: Colors.white38,
                  trackColor: Colors.white12,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasPlan)
            _heroEmpty(context, p)
          else ...[
            OutfitPiecesRow(
              items: plan.pieces.take(5).toList(),
              size: 64,
              fit: true,
              onTap: (c) => showClothingDetail(context, c),
            ),
            const SizedBox(height: 12),
            Text(
              plan.reasoning,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, height: 1.6, color: Colors.white60),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _ghostOnDark(
                  '换一套',
                  Icons.refresh,
                  () {
                    // #8 换一套：排除当前上衣 + 场合/性别透传 + 时间种子，
                    // 保证每次点都真的换；凑不出另一套时给出明确反馈。
                    final now = DateTime.now();
                    final alt = p.engine.recommend(
                      clothes: p.clothes,
                      temperature: p.currentTemperature,
                      occasion: _occasion,
                      gender: p.profile?.gender,
                      excludeIds: {plan.top?.id ?? ''},
                      seed: now.year * 100000 +
                          now.month * 1000 +
                          now.day * 1000 +
                          now.hour * 10 +
                          now.minute, // 分钟级种子：连点两次也换
                    ) ??
                        p.engine.recommend(
                          // 排除当前上衣后凑不齐一套（如只有一件上衣）：
                          // 退回不排除、只靠种子轮换下装/鞋/配饰
                          clothes: p.clothes,
                          temperature: p.currentTemperature,
                          occasion: _occasion,
                          gender: p.profile?.gender,
                          seed: now.millisecondsSinceEpoch ~/ 1000,
                        );
                    if (alt == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('可选单品不够换一套，先补一件上衣或下装')),
                      );
                      return;
                    }
                    showModalBottomSheet(
                      context: context,
                      builder: (_) => _AltOutfitSheet(plan: alt),
                    );
                  },
                ),
                const SizedBox(width: 10),
                _ghostIcon(
                  Icons.accessibility_new,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TryOnPage(initialItems: plan.pieces)),
                  ),
                ),
                const SizedBox(width: 10),
                _ghostIcon(
                  Icons.ios_share,
                  () => showShareCard(
                    context,
                    pieces: plan.pieces,
                    // #7 命名规则：颜色+衣服名（如「白色T恤×黑色阔腿裤」）
                    title: outfitAutoName(plan.pieces),
                    subtitle: p.weather == null
                        ? plan.reasoning
                        : '${p.weather!.emoji} ${p.weather!.temperature.round()}°C · ${p.weather!.conditionText}',
                    occasion: _occasion == null
                        ? null
                        : Occasion.names[_occasion!],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PillButton(
                    label: '就穿这套',
                    icon: Icons.check,
                    variant: PillVariant.lime,
                    expand: true,
                    onTap: _punching
                        ? null
                        : () async {
                            setState(() => _punching = true);
                            try {
                              await p.addOutfitRecord(OutfitRecord(
                                id: 'record_${const Uuid().v4()}',
                                date: DateTime.now(),
                                clothingIds: plan.clothingIds,
                                occasion: Occasion.daily,
                                createdAt: DateTime.now(),
                              ));
                            } finally {
                              if (mounted) {
                                setState(() => _punching = false);
                              }
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        '已打卡，连续 ${p.streakDays} 天 · 积分 +5')),
                              );
                            }
                          },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroEmpty(BuildContext context, WardrobeProvider p) {
    final empty = p.clothes.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          empty
              ? '先放进第一件衣服，\n我就能开始帮你搭。'
              : '当前温度下可选单品不够，\n补一件上衣或下装就行。',
          style: const TextStyle(
              fontSize: 14, height: 1.7, color: Colors.white70),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: empty ? '拍照录入' : '打开衣橱',
                icon: empty ? Icons.add_a_photo_outlined : Icons.checkroom,
                variant: PillVariant.lime,
                expand: true,
                onTap: () {
                  if (empty) {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const AddClothingSheet(),
                    );
                  } else {
                    _home(context)?.switchTab(1);
                  }
                },
              ),
            ),
            if (empty) ...[
              const SizedBox(width: 10),
              _ghostOnDark('先看示例', Icons.auto_awesome, () async {
                await p.seedDemoData();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已载入 12 件示例衣物，随便玩玩')),
                  );
                }
              }),
            ],
          ],
        ),
      ],
    );
  }

  Widget _ghostOnDark(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white70),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _ghostIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, size: 17, color: Colors.white70),
      ),
    );
  }

  // ---------- 场合约束 ----------

  Widget _occasionRow(WardrobeProvider p) {
    const options = <({String? value, String label})>[
      (value: null, label: '不限场合'),
      (value: Occasion.work, label: '通勤'),
      (value: Occasion.dating, label: '约会'),
      (value: Occasion.sport, label: '运动'),
      (value: Occasion.interview, label: '面试'),
      (value: Occasion.travel, label: '旅行'),
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final o = options[i];
          final active = _occasion == o.value;
          return GestureDetector(
            onTap: () => setState(() => _occasion = o.value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.ink : AppColors.surface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                    color: active ? AppColors.ink : AppColors.hairline),
              ),
              child: Text(
                o.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.inkMuted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- 洗护提醒 ----------

  Widget _serviceNotice(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign_outlined, size: 16, color: AppColors.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _laundryBanner(BuildContext context, WardrobeProvider p) {
    final n = p.insights.washingCount;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LaundryPage()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.lime.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lime),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_laundry_service_outlined,
                size: 16, color: AppColors.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                p.laundryOverdueCount > 0
                    ? '$n 件还在洗护中，其中 ${p.laundryOverdueCount} 件超过 3 天没收回'
                    : '$n 件还在洗护中，收回来记得点一下',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ink),
          ],
        ),
      ),
    );
  }

  // ---------- 数据条 ----------

  Widget _statsStrip(BuildContext context, WardrobeProvider p) {
    final ins = p.insights;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: StatTile(
              value: '${p.streakDays}',
              unit: '天',
              label: '连续打卡',
              color: AppColors.primary,
              align: CrossAxisAlignment.center,
            ),
          ),
          _divider(),
          Expanded(
            child: StatTile(
              value: '${ins.itemCount}',
              unit: '件',
              label: '衣橱单品',
              align: CrossAxisAlignment.center,
            ),
          ),
          _divider(),
          Expanded(
            child: StatTile(
              value: '${(ins.utilization * 100).round()}',
              unit: '%',
              label: '利用率',
              align: CrossAxisAlignment.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 30, color: AppColors.hairline);

  // ---------- 灵感 ----------

  Widget _styleBoard(BuildContext context) {
    return SizedBox(
      height: 186,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kStylePresets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final s = kStylePresets[i];
          return GestureDetector(
            onTap: () => showStyleSheet(context, s),
            child: Container(
              width: 158,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: s.gradient,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Eyebrow(s.en,
                          color: AppColors.ink.withValues(alpha: .5), size: 9),
                      const Spacer(),
                      Icon(Icons.north_east,
                          size: 14,
                          color: AppColors.ink.withValues(alpha: .45)),
                    ],
                  ),
                  const Spacer(),
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 19,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.7)),
                  const SizedBox(height: 6),
                  Text(s.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          color: AppColors.ink.withValues(alpha: .65))),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('#${s.tags.first}',
                        style: const TextStyle(
                            fontSize: 9.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- 一周计划 ----------

  Widget _weekPlan(BuildContext context, WardrobeProvider p) {
    if (p.clothes.isEmpty) {
      return SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('录几件衣服，我帮你把一周排好',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('会优先用闲置的单品，并避免连续两天穿同一件上衣。',
                style: TextStyle(
                    fontSize: 12, height: 1.6, color: AppColors.inkMuted)),
          ],
        ),
      );
    }
    final days = p.weekPlan;
    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => DayPlanCard(
          day: days[i],
          onTap: () => _home(context)?.switchTab(3),
        ),
      ),
    );
  }

  // ---------- 衣橱体检 ----------

  Widget _healthCard(BuildContext context, WardrobeProvider p) {
    final ins = p.insights;
    final score = ins.healthScore;
    final tier = score >= 80
        ? '很健康'
        : score >= 60
            ? '还不错'
            : score > 0
                ? '有点偏'
                : '待体检';
    return SoftCard(
      padding: const EdgeInsets.all(18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const InsightsScreen()),
      ),
      child: Row(
        children: [
          ScoreRing(
            value: score,
            size: 78,
            label: tier,
            color: score >= 80
                ? AppColors.ok
                : (score >= 60 ? AppColors.warn : AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tip in ins.tips.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 5, right: 6),
                          child: Icon(Icons.circle,
                              size: 5, color: AppColors.inkSubtle),
                        ),
                        Expanded(
                          child: Text(tip,
                              style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: AppColors.inkMuted)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.inkSubtle, size: 20),
        ],
      ),
    );
  }

  // ---------- 最近添加 ----------

  Widget _recent(BuildContext context, WardrobeProvider p) {
    final list = p.clothes.take(6).toList();
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: list.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == list.length) {
            return GestureDetector(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const AddClothingSheet(),
              ),
              child: Container(
                width: 96,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: .2)),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: AppColors.primary, size: 22),
                    SizedBox(height: 6),
                    Text('添加',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ],
                ),
              ),
            );
          }
          final c = list[i];
          return GestureDetector(
            onTap: () => showClothingDetail(context, c),
            child: SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 104,
                    child: ClothingThumb(clothing: c, radius: 18),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ClothingSubCategory.names[c.subCategory] ?? c.subCategory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _link(String text, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              Text(text,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkMuted)),
              const Icon(Icons.arrow_forward, size: 13, color: AppColors.inkMuted),
            ],
          ),
        ),
      );
}

/// 「换一套」结果
class _AltOutfitSheet extends StatefulWidget {
  const _AltOutfitSheet({required this.plan});
  final OutfitPlan plan;

  @override
  State<_AltOutfitSheet> createState() => _AltOutfitSheetState();
}

class _AltOutfitSheetState extends State<_AltOutfitSheet> {
  /// 打卡进行中标记：防止「用这套打卡」连点插入重复记录
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('换个方向', eyebrow: 'ANOTHER LOOK'),
          const SizedBox(height: 14),
          OutfitPiecesRow(items: plan.pieces.take(5).toList(), size: 64, fit: true),
          const SizedBox(height: 10),
          Text(plan.reasoning,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.6, color: AppColors.inkMuted)),
          const SizedBox(height: 18),
          PillButton(
            label: '用这套打卡',
            expand: true,
            icon: Icons.check,
            onTap: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    final p = context.read<WardrobeProvider>();
                    await p.addOutfitRecord(OutfitRecord(
                      id: 'record_${const Uuid().v4()}',
                      date: DateTime.now(),
                      clothingIds: plan.clothingIds,
                      occasion: Occasion.daily,
                      createdAt: DateTime.now(),
                    ));
                    if (mounted) Navigator.pop(context);
                  },
          ),
        ],
      ),
    );
  }
}
