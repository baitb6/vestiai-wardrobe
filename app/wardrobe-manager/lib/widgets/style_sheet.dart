import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';
import '../data/style_presets.dart';
import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../services/recommendation_engine.dart' show OutfitPlan;
import '../theme/app_theme.dart';
import 'kit.dart';
import 'outfit_preview.dart';

/// 灵感卡片点开后的「一键按风格出方案」
Future<void> showStyleSheet(BuildContext context, StylePreset preset) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _StyleSheet(preset: preset),
  );
}

class _StyleSheet extends StatefulWidget {
  const _StyleSheet({required this.preset});

  final StylePreset preset;

  @override
  State<_StyleSheet> createState() => _StyleSheetState();
}

class _StyleSheetState extends State<_StyleSheet> {
  /// 打卡进行中标记：防止「就穿这套」连点插入重复记录
  bool _saving = false;

  /// #10 「再换一套」的轮换计数：每点一次 +1，作为引擎种子的一部分，
  /// 让同一风格页里连点「再换一套」也能出不同组合（此前按钮只是关弹层）。
  int _shuffle = 0;

  OutfitPlan? _currentPlan(WardrobeProvider provider) {
    final preset = widget.preset;
    final now = DateTime.now();
    final daySalt = now.year * 100000 + now.month * 1000 + now.day;
    return provider.engine.recommend(
      clothes: provider.clothes,
      temperature: provider.currentTemperature,
      occasion: preset.occasion,
      styleKey: preset.styleKey,
      gender: provider.profile?.gender,
      // 风格自身也进种子：不同风格默认探索不同的候选组合
      seed: daySalt ^ preset.id.hashCode ^ (_shuffle * 97),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    final provider = context.watch<WardrobeProvider>();
    final plan = _currentPlan(provider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          0, 0, 0, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: preset.gradient,
                ),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Eyebrow(preset.en, color: AppColors.ink.withValues(alpha: .55)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(preset.name,
                      style: const TextStyle(
                          fontSize: 30,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.2)),
                  const SizedBox(height: 6),
                  Text(preset.desc,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: AppColors.ink.withValues(alpha: .7))),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final t in preset.tags)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .55),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text('#$t',
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Eyebrow('你的衣橱里能穿成这样'),
                      const Spacer(),
                      Text('${provider.currentTemperature.round()}°C',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.inkMuted)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (plan == null || plan.pieces.isEmpty)
                    EmptyState(
                      title: '还没有可以搭的单品',
                      desc: provider.clothes.isEmpty
                          ? '先录入几件常穿的衣服，再来看风格方案'
                          : '当前温度下可选单品不足，补一件上衣或下装试试',
                    )
                  else ...[
                    OutfitPiecesRow(items: plan.pieces.take(5).toList(), size: 62, fit: true),
                    const SizedBox(height: 16),
                    if (plan.reasoning.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 15, color: AppColors.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(plan.reasoning,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.6,
                                      color: AppColors.inkMuted)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: PillButton(
                            label: '再换一套',
                            variant: PillVariant.ghost,
                            icon: Icons.shuffle,
                            // #10：真的重算（换种子），不再只是关掉弹层
                            onTap: () =>
                                setState(() => _shuffle = _shuffle + 1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PillButton(
                            label: '就穿这套',
                            variant: PillVariant.dark,
                            icon: Icons.check,
                            onTap: _saving
                                ? null
                                : () async {
                                    setState(() => _saving = true);
                                    await context
                                        .read<WardrobeProvider>()
                                        .addOutfitRecord(OutfitRecord(
                                      id: DateTime.now()
                                          .millisecondsSinceEpoch
                                          .toString(),
                                      date: DateTime.now(),
                                      clothingIds: plan.clothingIds,
                                      occasion: preset.occasion,
                                      createdAt: DateTime.now(),
                                    ));
                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('已记进今天的穿搭日历')),
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
            ),
          ],
        ),
      ),
    );
  }
}
