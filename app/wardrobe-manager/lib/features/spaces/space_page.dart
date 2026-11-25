import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/wardrobe_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';

/// 快捷切换衣橱空间（衣橱页顶部点一下就出来）
Future<void> showSpaceSwitcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SpaceSwitcherSheet(),
  );
}

class _SpaceSwitcherSheet extends StatelessWidget {
  const _SpaceSwitcherSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final spaces = p.spaces;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.canvasTop,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
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
          Row(
            children: [
              const Expanded(
                child: Text('切换衣橱',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4)),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SpaceManagerPage()));
                },
                child: const Text('管理',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '切换只改变浏览范围，推荐与统计仍按全部单品计算',
            style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle),
          ),
          const SizedBox(height: 14),
          ...spaces.map((s) {
            final on = s.id == p.currentSpaceId ||
                (p.currentSpaceId == null && s.isDefault);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () async {
                  await context
                      .read<WardrobeProvider>()
                      .setCurrentSpace(s.isDefault ? null : s.id);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: on ? AppColors.ink : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: on ? AppColors.ink : AppColors.hairline),
                  ),
                  child: Row(
                    children: [
                      Text(s.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: on ? Colors.white : AppColors.ink,
                              ),
                            ),
                            if (s.note != null)
                              Text(
                                s.note!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: on
                                        ? Colors.white54
                                        : AppColors.inkSubtle),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${p.countInSpace(s.isDefault ? null : s.id)} 件',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: on ? Colors.white70 : AppColors.inkMuted,
                        ),
                      ),
                      if (on)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.check_circle,
                              size: 17, color: AppColors.lime),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          PillButton(
            label: '新建一个衣橱',
            icon: Icons.add,
            expand: true,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SpaceManagerPage()));
            },
          ),
        ],
      ),
    );
  }
}

/// 空间管理：新建、改名、删除
class SpaceManagerPage extends StatefulWidget {
  const SpaceManagerPage({super.key});

  @override
  State<SpaceManagerPage> createState() => _SpaceManagerPageState();
}

class _SpaceManagerPageState extends State<SpaceManagerPage> {
  static const _emojis = ['🏠', '🛏️', '🧳', '🏢', '🏫', '🏋️', '🏖️', '📦'];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: '我的衣橱',
              eyebrow: 'SPACES',
              subtitle: '按位置分开管理',
              actions: [
                RoundIconButton(
                  icon: Icons.add,
                  onTap: () => _openEditor(context),
                ),
                const SizedBox(width: 8),
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
                  ...p.spaces.map((s) {
                    final isDefault = s.isDefault;
                    final count = p.countInSpace(isDefault ? null : s.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              alignment: Alignment.center,
                              child: Text(s.emoji,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(s.name,
                                          style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w800)),
                                      if (isDefault) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceAlt,
                                            borderRadius:
                                                BorderRadius.circular(5),
                                          ),
                                          child: const Text('默认',
                                              style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.inkMuted)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$count 件单品${s.note == null ? '' : ' · ${s.note}'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.inkSubtle),
                                  ),
                                ],
                              ),
                            ),
                            if (!isDefault)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 19, color: AppColors.inkSubtle),
                                onPressed: () => _confirmDelete(context, s, count),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 15, color: AppColors.inkMuted),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '删除衣橱不会删衣服，里面的单品会退回「主衣橱」。\n在衣橱列表长按任意一件，可以把它移到别的衣橱。',
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.6,
                                color: AppColors.inkMuted,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WardrobeSpace space, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('删除「${space.name}」？',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: Text(
          count > 0
              ? '里面的 $count 件单品会退回到「主衣橱」，不会被删除。'
              : '这个衣橱是空的，删除不影响任何单品。',
          style: const TextStyle(
              fontSize: 12.5, height: 1.6, color: AppColors.inkMuted),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('删除', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final moved =
        await context.read<WardrobeProvider>().deleteSpace(space.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(moved > 0 ? '已删除，$moved 件单品退回主衣橱' : '已删除'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final result = await showModalBottomSheet<_SpaceDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SpaceEditorSheet(emojis: _emojis),
    );
    if (result == null || !context.mounted) return;
    await context
        .read<WardrobeProvider>()
        .addSpace(result.name, emoji: result.emoji, note: result.note);
  }
}

class _SpaceDraft {
  final String name;
  final String emoji;
  final String? note;
  _SpaceDraft(this.name, this.emoji, this.note);
}

class _SpaceEditorSheet extends StatefulWidget {
  const _SpaceEditorSheet({required this.emojis});
  final List<String> emojis;

  @override
  State<_SpaceEditorSheet> createState() => _SpaceEditorSheetState();
}

class _SpaceEditorSheetState extends State<_SpaceEditorSheet> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  String _emoji = '🛏️';

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.canvasTop,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
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
            const Text('新建衣橱',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5)),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '比如「宿舍」「老家衣柜」',
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.emojis.map((e) {
                final on = _emoji == e;
                return GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: on ? AppColors.ink : AppColors.surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                          color: on ? AppColors.ink : AppColors.hairline),
                    ),
                    alignment: Alignment.center,
                    child: Text(e, style: const TextStyle(fontSize: 19)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: '备注（可留空）',
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
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
                onPressed: () {
                  final name = _name.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('给它起个名字')));
                    return;
                  }
                  Navigator.pop(
                    context,
                    _SpaceDraft(
                      name,
                      _emoji,
                      _note.text.trim().isEmpty ? null : _note.text.trim(),
                    ),
                  );
                },
                child: const Text('创建',
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
