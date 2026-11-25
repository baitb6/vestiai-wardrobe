import 'dart:async';

import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../services/white_bg_replace.dart';
import '../theme/app_theme.dart';
import '../widgets/add_clothing_sheet.dart';
import '../widgets/clothing_card.dart';
import '../widgets/kit.dart';
import '../features/auto_split/auto_split_page.dart';
import '../features/intake/intake_provider.dart';
import '../features/intake/intake_task_list_page.dart';
import '../features/spaces/space_page.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  String? _category;
  String? _material;
  String? _status;
  final _searchCtrl = TextEditingController();
  bool _searching = false;

  /// #2 后台入库队列：徽标 + 任务列表页共用。
  /// IndexedStack 保活，切页不销毁；内存队列重启即清空。
  late final IntakeProvider _intake;

  @override
  void initState() {
    super.initState();
    _intake =
        IntakeProvider(wardrobe: context.read<WardrobeProvider>());
  }

  @override
  void dispose() {
    _intake.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final list = p.clothes;
    final hasFilter = _material != null || _status != null;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _intakeBadge(),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _add(context),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x33FF3B2F),
                        blurRadius: 18,
                        offset: Offset(0, 8)),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text('添加',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenHeader(
              title: '我的衣橱',
              eyebrow: 'WARDROBE',
              subtitle:
                  '${p.currentSpace.name} · ${p.clothes.length} 件'
                  '${p.spaces.length > 1 ? ' / 共 ${p.totalClothes} 件' : ''}',
              actions: [
                RoundIconButton(
                  icon: Icons.door_sliding_outlined,
                  onTap: () => showSpaceSwitcher(context),
                ),
                const SizedBox(width: 6),
                RoundIconButton(
                  icon: Icons.auto_awesome_motion,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AutoSplitPage()),
                  ),
                ),
                const SizedBox(width: 6),
                RoundIconButton(
                  icon: _searching ? Icons.close : Icons.search,
                  onTap: () {
                    setState(() => _searching = !_searching);
                    if (!_searching) {
                      _searchCtrl.clear();
                      p.setSearchQuery('');
                    }
                  },
                ),
              ],
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: (v) => p.setSearchQuery(v),
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: '颜色 / 品类 / 品牌 / 材质',
                    prefixIcon: const Icon(Icons.search,
                        size: 18, color: AppColors.inkSubtle),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : GestureDetector(
                            onTap: () {
                              _searchCtrl.clear();
                              p.setSearchQuery('');
                              setState(() {});
                            },
                            child: const Icon(Icons.close,
                                size: 16, color: AppColors.inkSubtle),
                          ),
                  ),
                ),
              ),
            _categoryRow(p),
            const SizedBox(height: 8),
            _filterRow(context, p, hasFilter),
            const SizedBox(height: 6),
            Expanded(
              child: list.isEmpty
                  ? _empty(context, p)
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 18,
                        childAspectRatio: 0.66,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, i) =>
                          ClothingCard(
                            clothing: list[i],
                            onLongPress: () => _showItemActions(context, list[i]),
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 后台入库徽标 ----------

  /// 上传入口旁的进度徽标：进行中 N / 快速入库，点开任务列表页
  Widget _intakeBadge() {
    return ListenableBuilder(
      listenable: _intake,
      builder: (context, _) {
        final n = _intake.activeCount;
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IntakeTaskListPage(provider: _intake),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: n > 0 ? AppColors.primary : AppColors.ink,
              borderRadius: BorderRadius.circular(99),
              boxShadow: n > 0
                  ? const [
                      BoxShadow(
                          color: Color(0x33FF3B2F),
                          blurRadius: 12,
                          offset: Offset(0, 5)),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  n > 0 ? Icons.bolt : Icons.auto_awesome,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  n > 0 ? '进行中 $n' : 'AI 快速入库',
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- 分类 ----------

  Widget _categoryRow(WardrobeProvider p) {
    final entries = ClothingCategory.names.entries.toList();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _pill('全部', _category == null, () {
            setState(() => _category = null);
            p.setCategoryFilter(null);
          }),
          for (final e in entries)
            _pill(e.value, _category == e.key, () {
              setState(() => _category = _category == e.key ? null : e.key);
              p.setCategoryFilter(_category);
            }),
        ],
      ),
    );
  }

  Widget _pill(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
                color: active ? AppColors.ink : AppColors.hairline),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 材质 / 状态筛选 ----------

  Widget _filterRow(
      BuildContext context, WardrobeProvider p, bool hasFilter) {
    final label = [
      if (_material != null) MaterialType.name(_material),
      if (_status != null) LocationStatus.names[_status],
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _openFilter(context, p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: hasFilter ? AppColors.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                    color: hasFilter ? Colors.transparent : AppColors.hairline),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune,
                      size: 14,
                      color: hasFilter ? AppColors.accent : AppColors.inkMuted),
                  const SizedBox(width: 5),
                  Text(hasFilter ? label : '筛选',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: hasFilter
                              ? AppColors.accent
                              : AppColors.inkMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (hasFilter)
            GestureDetector(
              onTap: () {
                setState(() {
                  _material = null;
                  _status = null;
                });
                p.setMaterialFilter(null);
                p.setLocationFilter(null);
              },
              child: const Text('清除',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.inkSubtle,
                      decoration: TextDecoration.underline)),
            ),
          const Spacer(),
          Text('${p.clothes.length} 件',
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.inkSubtle)),
        ],
      ),
    );
  }


  /// 长按单品：移动到别的衣橱（多衣橱的实际操作入口）
  Future<void> _showItemActions(BuildContext context, Clothing item) async {
    final p = context.read<WardrobeProvider>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.canvasTop,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              item.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -.3),
            ),
            const SizedBox(height: 4),
            const Text('把它放到哪个衣橱',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle)),
            const SizedBox(height: 12),
            // #13：长按快捷入口——补做/重做白底图（后台处理，卡片上显示进度）
            ListenableBuilder(
              listenable: WhiteBgReplaceController.instance,
              builder: (ctx, _) {
                final whiteBg = WhiteBgReplaceController.instance;
                final running = whiteBg.isRunning(item.id);
                final failed = whiteBg.hasFailed(item.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: running
                        ? null
                        : () {
                            unawaited(whiteBg.replace(item, p));
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(failed
                                      ? '正在后台重试白底图，完成后自动更新'
                                      : '正在后台生成白底图，完成后自动更新')),
                            );
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      child: Row(
                        children: [
                          if (running)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent),
                            )
                          else ...[
                            const Icon(Icons.auto_fix_high_outlined,
                                size: 16, color: AppColors.inkMuted),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              running
                                  ? '白底处理中…'
                                  : (failed ? '重试换白底图' : '换白底图'),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink),
                            ),
                          ),
                          if (failed)
                            const Icon(Icons.refresh,
                                size: 15, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            ...p.spaces.map((s) {
              final target = s.isDefault ? null : s.id;
              final on = item.wardrobeId == target;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () async {
                    await p.moveToSpace(item.id, target);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: on ? AppColors.ink : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: on ? AppColors.ink : AppColors.hairline),
                    ),
                    child: Row(
                      children: [
                        Text(s.emoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: on ? Colors.white : AppColors.ink,
                            ),
                          ),
                        ),
                        if (on)
                          const Icon(Icons.check_circle,
                              size: 16, color: AppColors.lime),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilter(BuildContext context, WardrobeProvider p) async {
    var material = _material;
    var status = _status;
    var color = p.selectedColor;
    var season = p.selectedSeason;
    var occasion = p.selectedOccasion;
    var tag = p.selectedTag;
    var sort = p.sort;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .72,
          maxChildSize: .92,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 18),
              const SectionTitle('筛选与排序', eyebrow: 'FILTER / SORT'),
              const SizedBox(height: 16),
              const MicroLabel('排序'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in WardrobeSort.values)
                    _choice(s.label, sort == s, () => setSheet(() => sort = s)),
                ],
              ),
              const SizedBox(height: 18),
              const MicroLabel('材质'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in MaterialType.all)
                    _choice(
                      MaterialType.name(m),
                      material == m,
                      () => setSheet(() => material = material == m ? null : m),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const MicroLabel('状态'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in LocationStatus.names.entries)
                    _choice(
                      e.value,
                      status == e.key,
                      () => setSheet(() => status = status == e.key ? null : e.key),
                    ),
                ],
              ),
              if (p.availableColors.isNotEmpty) ...[
                const SizedBox(height: 18),
                const MicroLabel('颜色'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in p.availableColors)
                      _choice(c, color == c,
                          () => setSheet(() => color = color == c ? null : c)),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              const MicroLabel('季节'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in Season.names.entries)
                    _choice(e.value, season == e.key,
                        () => setSheet(() => season = season == e.key ? null : e.key)),
                ],
              ),
              const SizedBox(height: 18),
              const MicroLabel('场合'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in Occasion.names.entries)
                    _choice(e.value, occasion == e.key,
                        () => setSheet(() => occasion = occasion == e.key ? null : e.key)),
                ],
              ),
              if (p.availableTags.isNotEmpty) ...[
                const SizedBox(height: 18),
                const MicroLabel('标签'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in p.availableTags)
                      _choice(t, tag == t,
                          () => setSheet(() => tag = tag == t ? null : t)),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              PillButton(
                label: '查看结果',
                expand: true,
                onTap: () {
                  setState(() {
                    _material = material;
                    _status = status;
                  });
                  p.setMaterialFilter(material);
                  p.setLocationFilter(status);
                  p.setColorFilter(color);
                  p.setSeasonFilter(season);
                  p.setOccasionFilter(occasion);
                  p.setTagFilter(tag);
                  p.setSort(sort);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _material = null;
                    _status = null;
                  });
                  p.clearAllFilters();
                  p.setSort(WardrobeSort.newest);
                  Navigator.pop(ctx);
                },
                child: const Center(
                  child: Text('清除全部筛选',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkSubtle,
                          decoration: TextDecoration.underline)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(99),
          border:
              Border.all(color: active ? AppColors.ink : AppColors.hairline),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.inkMuted)),
      ),
    );
  }

  // ---------- 空状态 ----------

  Widget _empty(BuildContext context, WardrobeProvider p) {
    final noClothes = p.totalClothes == 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 110),
      children: [
        EmptyState(
          icon: noClothes ? Icons.checkroom : Icons.search_off,
          title: noClothes ? '衣橱是空的' : '没有符合条件的单品',
          desc: noClothes
              ? '拍一张就有 AI 帮你填好品类、颜色、材质，10 秒入库。'
              : '换个分类或清掉筛选再试试。',
          action: noClothes
              ? Column(
                  children: [
                    PillButton(
                      label: '拍照添加',
                      icon: Icons.add_a_photo_outlined,
                      onTap: () => _add(context),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => p.seedDemoData(),
                      child: const Text('或者先载入示例衣橱看看效果',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.inkMuted,
                              decoration: TextDecoration.underline)),
                    ),
                  ],
                )
              : null,
        ),
      ],
    );
  }

  void _add(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddClothingSheet(),
    );
  }
}
