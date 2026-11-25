import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';
import '../data/clothing_naming.dart';
import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import '../services/platform_image.dart';
import '../services/white_bg_replace.dart';
import '../theme/app_theme.dart';
import 'kit.dart';

/// 根据中文颜色名给出一个可用的展示色（没有实拍图时用它做「色卡海报」）
Color clothingColor(String color) {
  const map = <String, Color>{
    '白': Color(0xFFEDE7DE),
    '米': Color(0xFFE3D3BC),
    '杏': Color(0xFFE8D2B8),
    '驼': Color(0xFFD2B48C),
    '卡': Color(0xFFD8C3A5),
    '灰': Color(0xFFC7C2BA),
    '银': Color(0xFFCFD2D4),
    '黑': Color(0xFF2C2824),
    '藏': Color(0xFF2E3C55),
    '牛': Color(0xFF5A7A9B),
    '蓝': Color(0xFF6C8FB8),
    '红': Color(0xFFD2554A),
    '粉': Color(0xFFE4A9B6),
    '橙': Color(0xFFDE8A4E),
    '橘': Color(0xFFDE8A4E),
    '黄': Color(0xFFE0C15C),
    '绿': Color(0xFF74886A),
    '军': Color(0xFF6B7355),
    '紫': Color(0xFF8C7BB0),
    '棕': Color(0xFF7A5A43),
    '咖': Color(0xFF7A5A43),
  };
  for (final e in map.entries) {
    if (color.contains(e.key)) return e.value;
  }
  return const Color(0xFFD9D2C7);
}

/// 衣物缩略图：有实拍图用图，没有就用「色卡 + 品类」的排版占位
class ClothingThumb extends StatelessWidget {
  const ClothingThumb({
    super.key,
    required this.clothing,
    this.radius = 18,
    this.showStatus = true,
  });

  final Clothing clothing;
  final double radius;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _image(),
          if (showStatus) ...[
            Positioned(
              left: 8,
              top: 8,
              child: _statusBadge(),
            ),
            if (clothing.wearCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: _countBadge(),
              ),
          ],
        ],
      ),
    );
  }

  Widget _image() {
    final url = clothing.imageUrl;
    if (url.startsWith('data:image')) {
      final comma = url.indexOf(',');
      if (comma != -1) {
        try {
          return Image.memory(base64Decode(url.substring(comma + 1)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _placeholder());
        } catch (_) {
          return _placeholder();
        }
      }
    }
    if (url.startsWith('http')) {
      return Image.network(url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    // 本地文件（大模型白底图、导入的照片）：以前一律落到纯色占位图，
    // 现在按 白底图 → 抠图 → 原图 的顺序找第一张能用的。
    for (final path in <String?>[
      url.isNotEmpty ? url : null,
      clothing.cutoutImagePath,
      clothing.originalImagePath,
    ]) {
      if (path == null || path.isEmpty || path.startsWith('data:')) continue;
      final widget = fileImageWidget(path, fit: BoxFit.cover);
      if (widget != null) return widget;
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final base = clothingColor(clothing.color);
    final isDark = base.computeLuminance() < 0.45;
    final fg = isDark ? Colors.white : AppColors.ink;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, Colors.white, 0.12)!,
            Color.lerp(base, Colors.black, 0.06)!,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -6,
            child: Icon(
              _iconOf(clothing.category),
              size: 92,
              color: fg.withValues(alpha: .13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  clothingDisplayName(clothing),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: fg.withValues(alpha: .92),
                  ),
                ),
                Text(
                  clothingSecondaryLabel(clothing).isEmpty
                      ? '未填写更多属性'
                      : clothingSecondaryLabel(clothing),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: .2,
                    fontWeight: FontWeight.w600,
                    color: fg.withValues(alpha: .55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge() {
    final status = clothing.locationStatus;
    if (status == LocationStatus.inWardrobe) return const SizedBox.shrink();
    final color = status == LocationStatus.washing
        ? AppColors.tagCool
        : (status == LocationStatus.wearing
            ? AppColors.limeSoft
            : AppColors.surface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        LocationStatus.names[status] ?? '',
        style: const TextStyle(
            fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
    );
  }

  Widget _countBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '×${clothing.wearCount}',
        style: const TextStyle(
            fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }

  static IconData _iconOf(String cat) {
    switch (cat) {
      case ClothingCategory.tops:
        return Icons.checkroom;
      case ClothingCategory.bottoms:
        return Icons.dry_cleaning;
      case ClothingCategory.dress:
        return Icons.woman;
      case ClothingCategory.outerwear:
        return Icons.layers_outlined;
      case ClothingCategory.shoes:
        return Icons.ice_skating;
      case ClothingCategory.accessories:
        return Icons.shopping_bag_outlined;
    }
    return Icons.checkroom;
  }
}

/// 衣橱网格卡片
class ClothingCard extends StatelessWidget {
  const ClothingCard({
    super.key,
    required this.clothing,
    this.onTap,
    this.onLongPress,
  });

  final Clothing clothing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cpw = clothing.cpw;
    return GestureDetector(
      onTap: onTap ?? () => showClothingDetail(context, clothing),
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: ClothingThumb(clothing: clothing)),
                // #13：后台换白底图时的进度指示（小圆 + 文案），
                // 完成后 WardrobeProvider 通知重建，卡片自动换新图
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: WhiteBgReplaceController.instance,
                    builder: (context, _) {
                      if (!WhiteBgReplaceController.instance
                          .isRunning(clothing.id)) {
                        return const SizedBox.shrink();
                      }
                      return Container(
                        color: Colors.black.withValues(alpha: .32),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              ),
                              const SizedBox(height: 6),
                              const Text('白底处理中…',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (clothing.idleDays() >= 90)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text('闲置',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            clothing.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, height: 1.2),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text(
                MaterialType.name(clothing.material),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.inkSubtle),
              ),
              const SizedBox(width: 6),
              Container(
                width: 2,
                height: 2,
                decoration: const BoxDecoration(
                    color: AppColors.inkSubtle, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cpw != null ? '单次 ¥${cpw.toStringAsFixed(0)}' : '穿 ${clothing.wearCount} 次',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.inkSubtle),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 衣物详情弹层：数据 + 操作（记穿着 / 改状态 / 设价格 / 删除）
Future<void> showClothingDetail(BuildContext context, Clothing clothing) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ClothingDetailSheet(clothing: clothing),
  );
}

class _ClothingDetailSheet extends StatelessWidget {
  const _ClothingDetailSheet({required this.clothing});

  final Clothing clothing;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WardrobeProvider>();
    final item = provider.clothes.firstWhere((c) => c.id == clothing.id,
        orElse: () => clothing);
    final cpw = item.cpw;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 10, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
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
                    borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  height: 120,
                  child: ClothingThumb(clothing: item, radius: 18),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow('${ClothingCategory.names[item.category]} · ${LocationStatus.names[item.locationStatus]}'),
                      const SizedBox(height: 6),
                      Text(item.displayName,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (item.material != null)
                            TagPill(
                              label: MaterialType.name(item.material),
                              background: AppColors.tagNeutral,
                            ),
                          if (item.tempMin != null && item.tempMax != null)
                            TagPill(
                              label:
                                  '${item.tempMin}–${item.tempMax}°C',
                              background: AppColors.tagCool,
                              foreground: AppColors.inkMuted,
                            ),
                          TagPill(
                            label: ThicknessLevel.name(item.thickness),
                            background: AppColors.surfaceAlt,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                      child: StatTile(
                          value: '${item.wearCount}',
                          label: '穿过',
                          align: CrossAxisAlignment.center)),
                  _vline(),
                  Expanded(
                      child: StatTile(
                          value: cpw == null ? '—' : '¥${cpw.toStringAsFixed(0)}',
                          label: '单次成本',
                          color: AppColors.primary,
                          align: CrossAxisAlignment.center)),
                  _vline(),
                  Expanded(
                      child: StatTile(
                          value: '${item.idleDays()}',
                          unit: '天',
                          label: item.wearCount == 0 ? '入柜' : '没穿',
                          align: CrossAxisAlignment.center)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const MicroLabel('把这件穿出去'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: '记一次穿着',
                    icon: Icons.add,
                    variant: PillVariant.dark,
                    onTap: () async {
                      await context.read<WardrobeProvider>().logWear(item.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已记录，穿着次数 +1')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PillButton(
                    label: '改状态',
                    icon: Icons.local_laundry_service_outlined,
                    variant: PillVariant.ghost,
                    onTap: () => _pickStatus(context, item),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: item.price == null ? '设置购入价' : '¥${item.price!.toStringAsFixed(0)} · 改价格',
                    icon: Icons.sell_outlined,
                    variant: PillVariant.ghost,
                    onTap: () => _editPrice(context, item),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _confirmDelete(context, item),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline,
                        size: 19, color: AppColors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // #13：补做白底图（后台处理，不阻塞前台；失败保留原图可重试）
            ListenableBuilder(
              listenable: WhiteBgReplaceController.instance,
              builder: (context, _) {
                final whiteBg = WhiteBgReplaceController.instance;
                final running = whiteBg.isRunning(item.id);
                final failed = whiteBg.hasFailed(item.id);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PillButton(
                      label: running
                          ? '白底处理中…'
                          : (failed ? '重试换白底图' : '换白底图'),
                      icon: running ? null : Icons.auto_fix_high_outlined,
                      variant: PillVariant.ghost,
                      expand: true,
                      onTap: running
                          ? null
                          : () {
                              unawaited(whiteBg.replace(
                                  item, context.read<WardrobeProvider>()));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('正在后台生成白底图，完成后自动更新')),
                              );
                            },
                    ),
                    if (failed && whiteBg.errorOf(item.id) != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '上次失败：${whiteBg.errorOf(item.id)}（已保留原图）',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.primary),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Text(
              '单次成本 = 购入价 ÷ 穿着次数，越低越值。',
              style: const TextStyle(fontSize: 11, color: AppColors.inkSubtle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vline() => Container(
      width: 1, height: 34, color: AppColors.hairline);

  Future<void> _pickStatus(BuildContext context, Clothing item) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('这件现在在哪？',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final e in LocationStatus.names.entries)
              ListTile(
                title: Text(e.value),
                trailing: item.locationStatus == e.key
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () async {
                  await ctx
                      .read<WardrobeProvider>()
                      .setLocationStatus(item.id, e.key);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _editPrice(BuildContext context, Clothing item) async {
    final ctrl = TextEditingController(
        text: item.price == null ? '' : item.price!.toStringAsFixed(0));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('购入价', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如 399'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('保存')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !context.mounted) return;
    final price = double.tryParse(result.trim());
    await context.read<WardrobeProvider>().setPrice(item.id, price);
  }

  Future<void> _confirmDelete(BuildContext context, Clothing item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移出衣橱？', style: TextStyle(fontSize: 17)),
        content: Text('「${item.displayName}」的穿着记录会一起删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<WardrobeProvider>().deleteClothing(item.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
