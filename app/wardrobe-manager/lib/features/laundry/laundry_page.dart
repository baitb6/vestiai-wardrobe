import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/wardrobe_provider.dart';
import '../../services/platform_image.dart';
import '../../theme/app_theme.dart';
import '../../widgets/clothing_card.dart';
import '../../widgets/kit.dart';

/// 洗护中心：谁在洗、洗了几天、一键收回 / 补送洗
class LaundryPage extends StatelessWidget {
  const LaundryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final items = p.laundryItems;
    final dry = items
        .where((c) => c.locationStatus == LocationStatus.dryCleaning)
        .length;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: const Text('洗护中心',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
        actions: [
          IconButton(
            tooltip: '送洗',
            onPressed: () => _pickToWash(context, p),
            icon: const Icon(Icons.add, size: 22, color: AppColors.ink),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          _summaryCard(p, items.length, dry),
          const SizedBox(height: 14),
          if (items.isEmpty)
            EmptyState(
              title: '没有待洗的衣物',
              desc: '衣服送洗时记一下，回到衣柜时再收回，\n洗护天数就不会忘。',
              icon: Icons.local_laundry_service_outlined,
              action: PillButton(
                label: '从衣橱挑几件',
                icon: Icons.add,
                variant: PillVariant.dark,
                onTap: () => _pickToWash(context, p),
              ),
            )
          else ...[
            const SectionTitle('在洗 / 干洗中', eyebrow: 'IN LAUNDRY'),
            const SizedBox(height: 10),
            for (final c in items) ...[
              _laundryTile(context, p, c),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            _tip(),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(WardrobeProvider p, int count, int dry) {
    final overdue = p.laundryOverdueCount;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('LAUNDRY', color: Colors.white38),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$count',
                  style: const TextStyle(
                      fontSize: 40,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2,
                      color: Colors.white)),
              const SizedBox(width: 6),
              const Text('件在外面',
                  style: TextStyle(fontSize: 12, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _mini('干洗 $dry 件'),
              const SizedBox(width: 8),
              _mini(overdue > 0 ? '$overdue 件超 3 天' : '都在 3 天内',
                  warn: overdue > 0),
              const Spacer(),
              const Text('收回来记得点一下',
                  style: TextStyle(fontSize: 9.5, color: Colors.white30)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String text, {bool warn = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: warn ? AppColors.primary : Colors.white12,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: warn ? Colors.white : Colors.white70),
      ),
    );
  }

  Widget _laundryTile(
      BuildContext context, WardrobeProvider p, Clothing c) {
    final days = p.laundryDays(c);
    final isDry = c.locationStatus == LocationStatus.dryCleaning;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 52,
              height: 52,
              child: _thumb(c),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isDry ? AppColors.warn : AppColors.accent)
                            .withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(isDry ? '干洗' : '水洗',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isDry ? AppColors.warn : AppColors.accent)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      days == 0 ? '今天送的' : '$days 天前送的',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: days >= 3
                              ? AppColors.primary
                              : AppColors.inkSubtle,
                          fontWeight:
                              days >= 3 ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await p.collectFromLaundry(c.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('「${c.displayName}」已收回衣柜')),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.ink,
              backgroundColor: AppColors.lime,
              minimumSize: const Size(56, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99)),
            ),
            child: const Text('收回',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _thumb(Clothing c) {
    final local = c.displayImagePath;
    final file = fileImageWidget(local, fit: BoxFit.cover);
    if (file != null && local != null && local.isNotEmpty) return file;
    final url = c.imageUrl;
    if (url.startsWith('data:image')) {
      final comma = url.indexOf(',');
      if (comma != -1) {
        try {
          return Image.memory(base64Decode(url.substring(comma + 1)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _block(c));
        } catch (_) {
          return _block(c);
        }
      }
    }
    return _block(c);
  }

  Widget _block(Clothing c) {
    final base = clothingColor(c.color);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, Colors.white, .12)!,
            Color.lerp(base, Colors.black, .06)!,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.checkroom, size: 20, color: base.computeLuminance() < .45
          ? Colors.white54
          : AppColors.ink.withValues(alpha: .5)),
    );
  }

  Widget _tip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 15, color: AppColors.inkMuted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '送洗中的衣物不会出现在搭配推荐里。超过 3 天没收的会标红提醒，'
              '也别把羊毛、真丝丢进洗衣机。',
              style: TextStyle(
                  fontSize: 11, height: 1.6, color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 送洗选择 ----------

  Future<void> _pickToWash(
      BuildContext context, WardrobeProvider p) async {
    final candidates = p.allClothes
        .where((c) => c.locationStatus == LocationStatus.inWardrobe)
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('衣柜里没有可送洗的衣物')),
      );
      return;
    }

    final picked = <String>{};
    var dryClean = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.hairline,
                        borderRadius: BorderRadius.circular(99)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('选择要送洗的衣物',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.4)),
                    const Spacer(),
                    Text('已选 ${picked.length}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.inkMuted)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _modeChip('水洗', !dryClean,
                        () => setSheet(() => dryClean = false)),
                    const SizedBox(width: 8),
                    _modeChip('干洗', dryClean,
                        () => setSheet(() => dryClean = true)),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 300,
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final c = candidates[i];
                      final on = picked.contains(c.id);
                      return InkWell(
                        onTap: () => setSheet(() {
                          on ? picked.remove(c.id) : picked.add(c.id);
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: _thumb(c)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(c.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              Icon(
                                on
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 20,
                                color: on ? AppColors.primary : AppColors.hairline,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                PillButton(
                  label: picked.isEmpty
                      ? '至少选一件'
                      : '送${dryClean ? '干洗' : '水洗'} ${picked.length} 件',
                  icon: Icons.local_laundry_service_outlined,
                  variant: PillVariant.dark,
                  expand: true,
                  onTap: picked.isEmpty
                      ? null
                      : () async {
                          for (final id in picked) {
                            await p.sendToLaundry(id, dryClean: dryClean);
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _modeChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.ink : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.inkMuted)),
      ),
    );
  }
}
