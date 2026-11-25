import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/wardrobe_provider.dart';
import '../../services/image_store.dart';
import '../../services/platform_image.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';

/// 愿望清单：种草 → 冷静期 → 到底买不买。
///
/// 设计取舍：不做「一键下单」，只做「记下来 + 等 7 天 + 到手后归档」。
/// 目的不是促成购买，而是让冲动有个缓冲带。
class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  int _tab = 0; // 0 = 想要，1 = 已入

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final wanted = p.activeWishes;
    final bought = p.purchasedWishes;
    final list = _tab == 0 ? wanted : bought;

    final budget = wanted.fold<double>(0, (a, w) => a + (w.price ?? 0));
    final cooling = wanted.where((w) => w.inCooldown).length;
    final urgent = wanted.where((w) => w.priority >= 3).length;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: '愿望清单',
              eyebrow: 'WISHLIST',
              subtitle: '想买的先记下来，冷静 7 天再决定',
              actions: [
                RoundIconButton(
                  icon: Icons.add,
                  onTap: () => _openEditor(context),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  _summaryCard(wanted.length, budget, cooling, urgent),
                  const SizedBox(height: 16),
                  _tabs(wanted.length, bought.length),
                  const SizedBox(height: 14),
                  if (list.isEmpty)
                    EmptyState(
                      title: _tab == 0 ? '清单是空的' : '还没有买回来的',
                      desc: _tab == 0
                          ? '看到想买的先加进来，放几天再看还想不想'
                          : '把清单里的东西标记「已购入」，它会自动变成衣橱单品',
                      icon: _tab == 0
                          ? Icons.favorite_border
                          : Icons.inventory_2_outlined,
                      action: _tab == 0
                          ? PillButton(
                              label: '加一件想要的',
                              icon: Icons.add,
                              onTap: () => _openEditor(context),
                            )
                          : null,
                    )
                  else
                    ...list.map((w) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _WishCard(
                            item: w,
                            onTap: () => _openEditor(context, existing: w),
                            onBuy: w.purchased
                                ? null
                                : () => _markBought(context, w),
                            onDelete: () => _confirmDelete(context, w),
                          ),
                        )),
                  if (_tab == 0 && wanted.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _cooldownNote(cooling),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(int count, double budget, int cooling, int urgent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '$count',
                  unit: '件',
                  label: '清单里',
                  color: Colors.white,
                ),
              ),
              Container(width: 1, height: 34, color: Colors.white24),
              Expanded(
                child: StatTile(
                  value: '¥${budget.toStringAsFixed(0)}',
                  label: '合计预算',
                  color: AppColors.lime,
                  align: CrossAxisAlignment.center,
                ),
              ),
              Container(width: 1, height: 34, color: Colors.white24),
              Expanded(
                child: StatTile(
                  value: '$urgent',
                  unit: '件',
                  label: '很想买',
                  color: Colors.white,
                  align: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          if (cooling > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_bottom,
                      size: 13, color: AppColors.lime),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '$cooling 件还在冷静期，现在下单的冲动大概率三天后就没了',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tabs(int wanted, int bought) {
    Widget chip(String label, int index, int count) {
      final on = _tab == index;
      return GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: on ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on ? AppColors.ink : AppColors.hairline),
          ),
          child: Text(
            '$label ${count > 0 ? count : ''}'.trim(),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: on ? Colors.white : AppColors.inkMuted,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('想要', 0, wanted),
        const SizedBox(width: 8),
        chip('已入', 1, bought),
      ],
    );
  }

  Widget _cooldownNote(int cooling) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.ac_unit, size: 15, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              cooling > 0
                  ? '冷静期不是不让你买，是让「想要」经过一次冷却。过了 7 天还想要，那大概率是真需要。'
                  : '清单里的东西都过了冷静期，可以认真考虑下单了。',
              style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 编辑 ----------

  Future<void> _openEditor(BuildContext context, {WishItem? existing}) async {
    final result = await showModalBottomSheet<_WishDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WishEditorSheet(existing: existing),
    );
    if (result == null || !mounted) return;
    final p = context.read<WardrobeProvider>();

    if (existing == null) {
      final now = DateTime.now();
      await p.addWish(WishItem(
        id: 'wish_${now.millisecondsSinceEpoch}',
        name: result.name,
        category: result.category,
        color: result.color,
        price: result.price,
        note: result.note,
        imagePath: result.imagePath,
        priority: result.priority,
        createdAt: now,
        cooldownUntil: now.add(
            const Duration(days: WardrobeProvider.wishCooldownDays)),
      ));
    } else {
      existing
        ..name = result.name
        ..category = result.category
        ..color = result.color
        ..price = result.price
        ..note = result.note
        ..imagePath = result.imagePath
        ..priority = result.priority;
      await p.updateWish(existing);
    }
  }

  Future<void> _markBought(BuildContext context, WishItem item) async {
    final controller =
        TextEditingController(text: item.price?.toStringAsFixed(0) ?? '');
    final price = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('买回来了？',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「${item.name}」会直接变成衣橱里的一件单品。',
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AppColors.inkMuted)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '实付价格（可留空）',
                prefixText: '¥ ',
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.ink),
            onPressed: () => Navigator.pop(
                ctx, double.tryParse(controller.text.trim()) ?? 0),
            child: const Text('确认购入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (price == null || price < 0 || !mounted) return;
    await context.read<WardrobeProvider>().purchaseWish(
          item.id,
          price: price > 0 ? price : null,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已入库：${item.name}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WishItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('从清单移除？',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: Text('「${item.name}」会被删掉，不会影响衣橱里的单品。',
            style: const TextStyle(
                fontSize: 12.5, height: 1.6, color: AppColors.inkMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('留着')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<WardrobeProvider>().deleteWish(item.id);
    }
  }
}

// ---------- 卡片 ----------

class _WishCard extends StatelessWidget {
  const _WishCard({
    required this.item,
    required this.onTap,
    this.onBuy,
    required this.onDelete,
  });

  final WishItem item;
  final VoidCallback onTap;
  final VoidCallback? onBuy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final image = fileImageWidget(item.imagePath, fit: BoxFit.cover);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 64,
                height: 64,
                color: AppColors.surfaceAlt,
                alignment: Alignment.center,
                child: image ??
                    Text(
                      ClothingCategory.names[item.category] ?? '单品',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkSubtle),
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: item.purchased
                                ? AppColors.inkSubtle
                                : AppColors.ink,
                            decoration: item.purchased
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      _priorityStars(item.priority),
                      // #5 删除入口：此前 onDelete 回调传了但卡片根本没渲染
                      GestureDetector(
                        onTap: onDelete,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.close,
                              size: 16, color: AppColors.inkSubtle),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      ClothingCategory.names[item.category] ?? item.category,
                      if (item.color != null && item.color!.isNotEmpty)
                        item.color!,
                      if (item.price != null)
                        '¥${item.price!.toStringAsFixed(0)}',
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkSubtle,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (item.purchased)
                    Text(
                      '已购入 ${_date(item.purchasedAt!)}'
                      '${item.clothingId != null ? ' · 已入衣橱' : ''}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkSubtle,
                          fontWeight: FontWeight.w600),
                    )
                  else
                    Row(
                      children: [
                        _tag(
                          item.inCooldown
                              ? '冷静期 ${item.cooldownDaysLeft} 天'
                              : '已等 ${item.waitingDays} 天',
                          item.inCooldown ? AppColors.surfaceAlt : AppColors.lime,
                          item.inCooldown
                              ? AppColors.inkMuted
                              : AppColors.ink,
                        ),
                        const Spacer(),
                        if (onBuy != null)
                          GestureDetector(
                            onTap: onBuy,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.ink,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                '已购入',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priorityStars(int p) {
    if (p <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        p,
        (_) => const Padding(
          padding: EdgeInsets.only(left: 1),
          child: Icon(Icons.star_rounded, size: 12, color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(7)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
      );

  String _date(DateTime d) => '${d.month} 月 ${d.day} 日';
}

// ---------- 编辑弹层 ----------

class _WishDraft {
  final String name;
  final String category;
  final String? color;
  final double? price;
  final String? note;
  final String? imagePath;
  final int priority;

  _WishDraft({
    required this.name,
    required this.category,
    this.color,
    this.price,
    this.note,
    this.imagePath,
    this.priority = 1,
  });
}

class _WishEditorSheet extends StatefulWidget {
  const _WishEditorSheet({this.existing});

  final WishItem? existing;

  @override
  State<_WishEditorSheet> createState() => _WishEditorSheetState();
}

class _WishEditorSheetState extends State<_WishEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _color;
  late final TextEditingController _price;
  late final TextEditingController _note;
  late String _category;
  late int _priority;
  String? _imagePath;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _color = TextEditingController(text: e?.color ?? '');
    _price = TextEditingController(
        text: e?.price == null ? '' : e!.price!.toStringAsFixed(0));
    _note = TextEditingController(text: e?.note ?? '');
    _category = e?.category ?? ClothingCategory.tops;
    _priority = e?.priority ?? 1;
    _imagePath = e?.imagePath;
  }

  @override
  void dispose() {
    _name.dispose();
    _color.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final path = await ImageStore.instance
          .saveBytes(Uint8List.fromList(bytes), prefix: 'wish');
      if (path != null && mounted) setState(() => _imagePath = path);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final image = fileImageWidget(_imagePath, fit: BoxFit.cover);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.canvasTop,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: SingleChildScrollView(
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
              const SizedBox(height: 16),
              Text(
                widget.existing == null ? '想要什么' : '改一下',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -.5),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.hairline),
                      ),
                      alignment: Alignment.center,
                      child: _picking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : image ??
                              const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      size: 20, color: AppColors.inkSubtle),
                                  SizedBox(height: 4),
                                  Text('参考图',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.inkSubtle,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                      decoration: _dec('名称，比如「米色风衣」'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _label('分类'),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: ClothingCategory.names.entries.map((e) {
                  final on = _category == e.key;
                  return _chip(
                    '${ClothingCategory.icons[e.key]} ${e.value}',
                    on,
                    () => setState(() => _category = e.key),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _color,
                      style: const TextStyle(fontSize: 14),
                      decoration: _dec('颜色'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14),
                      decoration: _dec('预期价格'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _label('想要的程度'),
              Row(
                children: [1, 2, 3].map((v) {
                  final labels = ['有点想', '很想', '立刻要'];
                  final on = _priority == v;
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _chip(
                      ('⭐' * v) + ' ' + labels[v - 1],
                      on,
                      () => setState(() => _priority = v),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLines: 2,
                style: const TextStyle(fontSize: 13.5),
                decoration: _dec('为什么想要它 / 打算搭什么'),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                  onPressed: _submit,
                  child: const Text('存进清单',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先给它起个名字')),
      );
      return;
    }
    Navigator.pop(
      context,
      _WishDraft(
        name: name,
        category: _category,
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        price: double.tryParse(_price.text.trim()),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        imagePath: _imagePath,
        priority: _priority,
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontSize: 13, color: AppColors.inkSubtle, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: MicroLabel(t),
      );

  Widget _chip(String text, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on ? AppColors.ink : AppColors.hairline),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : AppColors.inkMuted,
            ),
          ),
        ),
      );
}
