import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../services/insights_service.dart';
import '../theme/app_theme.dart';
import '../widgets/clothing_card.dart';
import '../widgets/kit.dart';
import '../widgets/outfit_preview.dart';

/// 衣橱体检报告：健康度、CPW、配色、断舍离建议
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final ins = p.insights;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
          children: [
            Row(
              children: [
                RoundIconButton(
                    icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
                const Spacer(),
                Eyebrow('REPORT · ${ins.itemCount} ITEMS'),
              ],
            ),
            const SizedBox(height: 18),
            const Text('衣橱体检',
                style: TextStyle(
                    fontSize: 34,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.4)),
            const SizedBox(height: 6),
            const Text('不评价贵不贵，只看穿不穿得上。',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
            const SizedBox(height: 20),
            _scoreCard(ins),
            const SizedBox(height: 14),
            _moneyRow(ins),
            const SizedBox(height: 14),
            _idleCard(ins),
            const SizedBox(height: 26),
            const SectionTitle('给你的建议', eyebrow: 'ACTIONS'),
            const SizedBox(height: 12),
            _tips(ins),
            const SizedBox(height: 26),
            const SectionTitle('配色分布', eyebrow: 'PALETTE'),
            const SizedBox(height: 12),
            _palette(ins),
            const SizedBox(height: 26),
            const SectionTitle('分类构成', eyebrow: 'CATEGORY'),
            const SizedBox(height: 12),
            _categories(p),
            const SizedBox(height: 26),
            const SectionTitle('单次成本榜', eyebrow: 'COST PER WEAR'),
            const SizedBox(height: 12),
            _cpwLists(ins),
            if (ins.washingCount > 0) ...[
              const SizedBox(height: 26),
              const SectionTitle('洗护中', eyebrow: 'LAUNDRY'),
              const SizedBox(height: 12),
              _laundry(context, p),
            ],
            const SizedBox(height: 30),
            _dataTools(context, p),
          ],
        ),
      ),
    );
  }

  Widget _scoreCard(WardrobeInsights ins) {
    final score = ins.healthScore;
    final tier = score >= 80
        ? '状态很健康'
        : score >= 60
            ? '还行，有优化空间'
            : ins.isEmpty
                ? '还没有数据'
                : '有点偏科';
    final color = score >= 80
        ? AppColors.ok
        : (score >= 60 ? AppColors.warn : AppColors.primary);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          ScoreRing(
            value: score,
            size: 108,
            stroke: 9,
            color: color,
            label: '健康度',
            textColor: Colors.white,
            subColor: Colors.white38,
            trackColor: Colors.white12,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('WARDROBE HEALTH', color: AppColors.lime),
                const SizedBox(height: 8),
                Text(tier,
                    style: const TextStyle(
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.white)),
                const SizedBox(height: 8),
                Text(
                  '利用率 ${(ins.utilization * 100).round()}% · 闲置 ${ins.idleCount} 件 · 覆盖 ${ins.categoryCount}/5 类',
                  style: const TextStyle(
                      fontSize: 11.5, height: 1.6, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(WardrobeInsights ins) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
              child: StatTile(
                  value: ins.totalValue > 0
                      ? '¥${(ins.totalValue / 1000).toStringAsFixed(1)}k'
                      : '—',
                  label: '衣橱总价值',
                  align: CrossAxisAlignment.center)),
          Container(width: 1, height: 30, color: AppColors.hairline),
          Expanded(
              child: StatTile(
                  value: ins.avgCpw > 0 ? '¥${ins.avgCpw.round()}' : '—',
                  label: '平均单次成本',
                  color: AppColors.primary,
                  align: CrossAxisAlignment.center)),
          Container(width: 1, height: 30, color: AppColors.hairline),
          Expanded(
              child: StatTile(
                  value: '${ins.totalWears}',
                  label: '累计穿着',
                  align: CrossAxisAlignment.center)),
        ],
      ),
    );
  }

  /// 闲置率 + 成本结构
  Widget _idleCard(WardrobeInsights ins) {
    final idlePct = (ins.idleRate * 100).round();
    final byCat = ins.valueByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxValue = byCat.isEmpty ? 1.0 : byCat.first.value;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('闲置与投入',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const Spacer(),
              Eyebrow('IDLE ${ins.neverWorn} NEVER WORN'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('$idlePct',
                            style: TextStyle(
                                fontSize: 30,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.4,
                                color: ins.idleRate >= .3
                                    ? AppColors.primary
                                    : AppColors.ink)),
                        const Text('%',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkSubtle)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('90 天以上没穿（${ins.idleCount} 件）',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.inkMuted)),
                  ],
                ),
              ),
              Container(width: 1, height: 34, color: AppColors.hairline),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${ins.avgIdleDays.round()}',
                            style: const TextStyle(
                                fontSize: 30,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.4)),
                        const Text(' 天',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkSubtle)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('平均闲置时长',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
          if (byCat.isNotEmpty) ...[
            const SizedBox(height: 18),
            const MicroLabel('钱花在哪了', trailing: '按分类'),
            const SizedBox(height: 10),
            for (final e in byCat.take(4)) ...[
              Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      ClothingCategory.names[e.key] ?? e.key,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.inkMuted),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Stack(
                        children: [
                          Container(height: 6, color: AppColors.surfaceAlt),
                          FractionallySizedBox(
                            widthFactor: (e.value / maxValue).clamp(.04, 1.0),
                            child: Container(
                                height: 6, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 58,
                    child: Text(
                      '¥${e.value >= 10000 ? '${(e.value / 1000).toStringAsFixed(1)}k' : e.value.round()}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 4),
          Text(
            ins.neverWorn > 0
                ? '有 ${ins.neverWorn} 件从买来就没穿过，是最容易变成「沉没成本」的一批。'
                : '每件都穿过至少一次，利用率不错。',
            style: const TextStyle(
                fontSize: 11, height: 1.6, color: AppColors.inkSubtle),
          ),
        ],
      ),
    );
  }

  Widget _tips(WardrobeInsights ins) {
    return Column(
      children: [
        for (var i = 0; i < ins.tips.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: AppColors.ink, shape: BoxShape.circle),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.lime)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(ins.tips[i],
                      style: const TextStyle(
                          fontSize: 13, height: 1.6, color: AppColors.ink)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _palette(WardrobeInsights ins) {
    final entries = ins.colorFamilies.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const Text('还没有颜色数据',
          style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted));
    }
    const palette = {
      '中性': Color(0xFFD9D2C7),
      '蓝色': Color(0xFF6C8FB8),
      '深蓝': Color(0xFF2E3C55),
      '红色': Color(0xFFD2554A),
      '粉色': Color(0xFFE4A9B6),
      '橙色': Color(0xFFDE8A4E),
      '黄色': Color(0xFFE0C15C),
      '绿色': Color(0xFF74886A),
      '紫色': Color(0xFF8C7BB0),
      '大地色': Color(0xFFC9A47A),
      '其他': Color(0xFFB9B2A8),
    };
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Row(
              children: [
                for (final e in entries)
                  Expanded(
                    flex: e.value,
                    child: Container(
                      height: 14,
                      color: palette[e.key] ?? AppColors.inkSubtle,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final e in entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette[e.key] ?? AppColors.inkSubtle,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${e.key} ${(e.value / total * 100).round()}%',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.inkMuted),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categories(WardrobeProvider p) {
    final stats = p.getCategoryStats();
    final total = stats.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return const Text('还没有衣物',
          style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted));
    }
    final entries = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SoftCard(
      child: Column(
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(ClothingCategory.names[e.key] ?? e.key,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: e.value / stats.values.reduce((a, b) => a > b ? a : b),
                        minHeight: 8,
                        backgroundColor: AppColors.surfaceAlt,
                        valueColor: const AlwaysStoppedAnimation(AppColors.ink),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${e.value}',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMuted)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cpwLists(WardrobeInsights ins) {
    if (ins.costs.isEmpty) {
      return SoftCard(
        child: Row(
          children: [
            const Icon(Icons.sell_outlined, size: 18, color: AppColors.inkSubtle),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '填上购入价后，这里会算出每件衣服「穿一次多少钱」。',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.inkMuted),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        _cpwBlock('最划算', ins.bestValue, AppColors.ok, '穿得越多越值'),
        const SizedBox(height: 10),
        _cpwBlock('该断舍离', ins.worstValue, AppColors.primary, '买来没穿 / 单次成本高'),
      ],
    );
  }

  Widget _cpwBlock(
      String title, List<ItemCost> list, Color color, String hint) {
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(hint,
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.inkSubtle)),
            ],
          ),
          const SizedBox(height: 12),
          for (final c in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    height: 44,
                    child: ClothingThumb(
                        clothing: c.item, radius: 9, showStatus: false),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.item.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(
                          c.hasWears
                              ? '穿 ${c.wears} 次 · 入手 ¥${c.price.round()}'
                              : '还没穿过 · 入手 ¥${c.price.round()}',
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.inkSubtle),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    c.hasWears ? '¥${c.cpw.round()}/次' : '0 次',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: c.hasWears ? color : AppColors.inkSubtle),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _laundry(BuildContext context, WardrobeProvider p) {
    final washing = p.clothes
        .where((c) =>
            c.locationStatus == LocationStatus.washing ||
            c.locationStatus == LocationStatus.dryCleaning)
        .toList();
    return SoftCard(
      child: Column(
        children: [
          for (final c in washing)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 46,
                    child: ClothingThumb(
                        clothing: c, radius: 10, showStatus: false),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(c.displayName,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  GestureDetector(
                    onTap: () => p.setLocationStatus(
                        c.id, LocationStatus.inWardrobe),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text('收回来',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataTools(BuildContext context, WardrobeProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('DATA'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: '载入示例衣橱',
                variant: PillVariant.ghost,
                icon: Icons.auto_awesome,
                onTap: () async {
                  await p.seedDemoData();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已载入示例数据（已有衣物时不会覆盖）')),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空所有数据？',
                        style: TextStyle(fontSize: 17)),
                    content: const Text('衣物、搭配、记录都会删除，且无法恢复。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('清空',
                              style: TextStyle(color: AppColors.primary))),
                    ],
                  ),
                );
                if (ok == true) await p.resetAll();
              },
              child: Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text('数据只存在这台设备上，换设备不会同步。',
            style: TextStyle(fontSize: 10.5, color: AppColors.inkSubtle)),
      ],
    );
  }
}
