import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';
import '../data/clothing_naming.dart';
import '../data/style_presets.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../providers/wardrobe_provider.dart';
import 'profile_screen.dart';
import '../services/recommendation_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/clothing_card.dart';
import '../widgets/kit.dart';
import '../widgets/outfit_preview.dart';
import '../widgets/style_sheet.dart';

class OutfitScreen extends StatefulWidget {
  const OutfitScreen({super.key});

  @override
  State<OutfitScreen> createState() => _OutfitScreenState();
}

class _OutfitScreenState extends State<OutfitScreen> {
  final _promptCtrl = TextEditingController();
  String? _occasion;
  OutfitSuggestion? _suggestion;
  bool _loading = false;

  /// 保存/打卡进行中标记：防止「保存这套」「今天穿这套」连点插入重复数据
  bool _savingOutfit = false;
  bool _punching = false;

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final plan = p.recommendToday(occasion: _occasion);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            ScreenHeader(
              title: '搭配实验室',
              eyebrow: 'STYLE LAB',
              actions: [
                if (p.weather != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: TagPill(
                      label: '${p.weather!.temperature.round()}°C',
                      background: AppColors.surface,
                      foreground: AppColors.inkMuted,
                      border: true,
                    ),
                  ),
                RoundIconButton(
                  icon: Icons.shuffle,
                  onTap: () {
                    final alt = p.engine.recommend(
                      clothes: p.clothes,
                      temperature: p.currentTemperature,
                      excludeIds: {plan?.top?.id ?? ''},
                      gender: p.profile?.gender,
                    );
                    if (alt != null) {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) =>
                            _PlanSheet(plan: alt, reasons: p.reasonsOf(alt)),
                      );
                    }
                  },
                ),
              ],
            ),
            _aiCard(context, p),
            if (_suggestion != null) ...[
              const SizedBox(height: 14),
              _suggestionCard(context, p, _suggestion!),
            ],
            const SizedBox(height: 26),
            const SectionTitle('规则引擎方案', eyebrow: 'INSTANT LOOK'),
            const SizedBox(height: 12),
            _planCard(context, p, plan),
            const SizedBox(height: 26),
            const SectionTitle('换个风格试试', eyebrow: 'MOOD BOARD'),
            const SizedBox(height: 12),
            _styleList(context),
            const SizedBox(height: 26),
            SectionTitle('我的搭配',
                eyebrow: 'SAVED',
                trailing: Text('${p.outfits.length} 套',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.inkSubtle))),
            const SizedBox(height: 12),
            _savedOutfits(context, p),
          ],
        ),
      ),
    );
  }

  // ---------- AI 输入 ----------

  Widget _aiCard(BuildContext context, WardrobeProvider p) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('ASK THE STYLIST', color: AppColors.lime),
              const Spacer(),
              TagPill(
                label: p.weather != null
                    ? '${p.city} ${p.weather!.temperature.round()}°C'
                    : '天气离线',
                background: Colors.white.withValues(alpha: .08),
                foreground: Colors.white70,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('今天要\n穿成什么样？',
              style: TextStyle(
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  color: Colors.white)),
          const SizedBox(height: 14),
          TextField(
            controller: _promptCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13.5, color: Colors.white),
            decoration: InputDecoration(
              hintText: '例：下午面试，晚上还要和朋友吃饭',
              hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: .35)),
              fillColor: Colors.white.withValues(alpha: .08),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in Occasion.names.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: GestureDetector(
                      onTap: () => setState(() =>
                          _occasion = _occasion == e.key ? null : e.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _occasion == e.key
                              ? AppColors.lime
                              : Colors.white.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _occasion == e.key
                                ? AppColors.ink
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PillButton(
            label: _loading ? '正在想…' : '生成搭配建议',
            icon: Icons.auto_awesome,
            variant: PillVariant.lime,
            expand: true,
            onTap: _loading ? null : () => _generate(p),
          ),
          const SizedBox(height: 8),
          const Text('AI 只写点评，具体单品由本地规则引擎挑，结果可解释。',
              style: TextStyle(fontSize: 10, color: Colors.white38)),
        ],
      ),
    );
  }

  Future<void> _generate(WardrobeProvider p) async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty && _occasion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('说一句需求，或者选个场合')),
      );
      return;
    }
    setState(() => _loading = true);
    final s = await p.generateOutfitSuggestion(
      prompt: prompt.isEmpty
          ? '我要${Occasion.names[_occasion] ?? ''}穿搭'
          : prompt,
      occasion: _occasion,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _suggestion = s;
    });
  }

  Widget _suggestionCard(
      BuildContext context, WardrobeProvider p, OutfitSuggestion s) {
    final fallback = s.isFallback;
    return SoftCard(
      padding: const EdgeInsets.all(16),
      color: fallback ? AppColors.surfaceAlt : AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TagPill(
                label: fallback ? '离线建议' : 'AI 点评',
                background:
                    fallback ? AppColors.tagNeutral : AppColors.accentSoft,
                foreground: fallback ? AppColors.inkMuted : AppColors.accent,
                icon: fallback ? Icons.wifi_off : Icons.auto_awesome,
                dense: true,
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _suggestion = null),
                child: const Icon(Icons.close,
                    size: 16, color: AppColors.inkSubtle),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(s.name,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(s.description,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.65, color: AppColors.inkMuted)),
          if (s.styleTips != null && s.styleTips!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.limeSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 14, color: AppColors.ink),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(s.styleTips!,
                        style:
                            const TextStyle(fontSize: 11.5, height: 1.5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 规则方案 ----------

  Widget _planCard(BuildContext context, WardrobeProvider p, OutfitPlan? plan) {
    if (p.clothes.isEmpty) {
      return const EmptyState(
        title: '衣橱里还没有单品',
        desc: '录入 3 件以上（上衣 + 下装 + 鞋），这里会立刻给出今天的组合。',
      );
    }
    if (plan == null || plan.pieces.isEmpty) {
      return const EmptyState(
        icon: Icons.thermostat,
        title: '这个温度下没有合适的单品',
        desc: '检查一下衣物的「适穿温度」，或者补一件当季的。',
      );
    }
    // #8 推荐理由（旁路：provider 从引擎纯函数取/重算）
    final reasons = p.reasonsOf(plan);
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ScoreRing(
                value: plan.score,
                size: 62,
                stroke: 6,
                label: '适配度',
                color: AppColors.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.currentTemperature.round()}°C · ${p.weather?.conditionText ?? '天气离线'}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan.reasoning,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.55,
                          color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutfitPiecesRow(
            items: plan.pieces.take(5).toList(),
            size: 62,
            fit: true,
            onTap: (c) => showClothingDetail(context, c),
          ),
          // #8 推荐理由行：小字 muted，仿既有 note 样式
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            _reasonLines(reasons),
          ],
          // #6 性别未填：轻提示，点击去「我的」补充
          if (p.needsGenderHint) ...[
            const SizedBox(height: 8),
            _genderHint(context),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: _savingOutfit ? '保存中…' : '保存这套',
                  icon: Icons.bookmark_border,
                  variant: PillVariant.ghost,
                  onTap: _savingOutfit
                      ? null
                      : () => _saveOutfit(p, plan),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                  label: '今天穿这套',
                  icon: Icons.check,
                  onTap: _punching
                      ? null
                      : () async {
                          setState(() => _punching = true);
                          try {
                            await p.addOutfitRecord(OutfitRecord(
                              id: DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              date: DateTime.now(),
                              clothingIds: plan.clothingIds,
                              occasion: _occasion ?? Occasion.daily,
                              createdAt: DateTime.now(),
                            ));
                          } finally {
                            if (mounted) {
                              setState(() => _punching = false);
                            }
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已打卡进日历')),
                            );
                          }
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// #9 保存这套：先弹命名框（预填「颜色+衣服名」自动名），确认后落库。
  /// 旧版直接存成「NN°C 搭配」，既不能自定义也看不出是哪套。
  Future<void> _saveOutfit(WardrobeProvider p, OutfitPlan plan) async {
    final defaultName = outfitAutoName(plan.pieces,
        fallback: '${p.currentTemperature.round()}°C 搭配');
    final controller = TextEditingController(text: defaultName);
    String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('给这套起个名字',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '如 白色T恤×黑色阔腿裤',
              counterText: '',
              filled: true,
              fillColor: AppColors.surfaceAlt,
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.ink),
                onPressed: () =>
                    Navigator.pop(ctx, controller.text.trim()),
                child: const Text('保存')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _savingOutfit = true);
    try {
      await p.addOutfit(Outfit(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        clothingIds: plan.clothingIds,
        occasion: _occasion ?? Occasion.daily,
        description: plan.reasoning,
        isAiGenerated: false,
        createdAt: DateTime.now(),
      ));
    } finally {
      if (mounted) {
        setState(() => _savingOutfit = false);
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「$name」已存入我的搭配')),
      );
    }
  }

  /// #8 推荐理由行：小字 muted 色，仿既有 note 样式
  Widget _reasonLines(List<String> reasons) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_rounded,
                    size: 12, color: AppColors.inkSubtle),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    r,
                    style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: AppColors.inkSubtle),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// #6 性别未填的轻提示：点击跳「我的」页（性别在「身材数据」弹窗里选）
  Widget _genderHint(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            Icon(Icons.person_outline, size: 13, color: AppColors.primary),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                '补充性别后推荐更准，点这里去设置',
                style: TextStyle(
                    fontSize: 11, height: 1.4, color: AppColors.primary),
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // ---------- 风格 ----------

  Widget _styleList(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kStylePresets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = kStylePresets[i];
          return GestureDetector(
            onTap: () => showStyleSheet(context, s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: s.gradient),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Icon(Icons.north_east,
                      size: 12, color: AppColors.ink.withValues(alpha: .5)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- 已保存 ----------

  Widget _savedOutfits(BuildContext context, WardrobeProvider p) {
    if (p.outfits.isEmpty) {
      return const EmptyState(
        icon: Icons.bookmark_border,
        title: '还没有保存的搭配',
        desc: '看到满意的组合，点「保存这套」，之后就能直接复用。',
      );
    }
    return Column(
      children: [
        for (final o in p.outfits)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _outfitRow(p, o),
          ),
      ],
    );
  }

  Widget _outfitRow(WardrobeProvider p, Outfit o) {
    // #9 图片显示：按 id 解析存活单品要用全量衣橱（allClothes），
    // 之前用 p.clothes（受空间/筛选过滤），换了空间或开着筛选时缩略图会消失
    final byId = {for (final c in p.allClothes) c.id: c};
    final thumbs = <Clothing>[
      for (final id in o.clothingIds.take(2))
        if (byId.containsKey(id)) byId[id]!,
    ];
    final more = o.clothingIds.length - thumbs.length;
    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: thumbs.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.checkroom,
                        size: 24, color: AppColors.inkSubtle),
                  )
                : Stack(
                    children: [
                      Row(
                        children: [
                          for (final c in thumbs)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: ClothingThumb(
                                  clothing: c,
                                  radius: 10,
                                  showStatus: false,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // #9：超过两件时给出 +N 角标，不再像「图丢了」
                      if (more > 0)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.ink,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text('+$more',
                                style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${o.clothingIds.length} 件 · ${Occasion.names[o.occasion] ?? '日常'}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.inkSubtle),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => p.deleteOutfit(o.id),
            child: const Icon(Icons.delete_outline,
                size: 18, color: AppColors.inkSubtle),
          ),
        ],
      ),
    );
  }
}

class _PlanSheet extends StatefulWidget {
  const _PlanSheet({required this.plan, this.reasons = const []});
  final OutfitPlan plan;

  /// #8 换一套方案的理由（旁路传入，弹窗里不再依赖 provider）
  final List<String> reasons;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  /// 打卡进行中标记：防止「就穿这套」连点插入重复记录
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
          const SectionTitle('换一套', eyebrow: 'SHUFFLE'),
          const SizedBox(height: 14),
          OutfitPiecesRow(items: plan.pieces.take(5).toList(), size: 66, fit: true),
          const SizedBox(height: 8),
          Text(plan.reasoning,
              style: const TextStyle(
                  fontSize: 12.5, height: 1.6, color: AppColors.inkMuted)),
          // #8 推荐理由行（小字 muted，仿 note 样式）
          if (widget.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in widget.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_rounded,
                        size: 12, color: AppColors.inkSubtle),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        r,
                        style: const TextStyle(
                            fontSize: 11,
                            height: 1.5,
                            color: AppColors.inkSubtle),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          PillButton(
            label: '就穿这套',
            expand: true,
            onTap: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    await context.read<WardrobeProvider>().addOutfitRecord(
                          OutfitRecord(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            date: DateTime.now(),
                            clothingIds: plan.clothingIds,
                            occasion: Occasion.daily,
                            createdAt: DateTime.now(),
                          ),
                        );
                    if (mounted) Navigator.pop(context);
                  },
          ),
        ],
      ),
    );
  }
}
