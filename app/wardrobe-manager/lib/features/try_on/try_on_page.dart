import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/wardrobe_provider.dart';
import '../../services/image_store.dart';
import '../../services/platform_image.dart';
import '../../services/share_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/kit.dart';
import '../ai_gateway/ai_service_page.dart';
import 'try_on_provider.dart';

/// 2D 虚拟试穿：把一套搭配「穿」到你自己的照片上。
///
/// 失败不阻塞：网关没配、模型不支持、生成报错，都会退回搭配预览，
/// 用户仍然能看到这套衣服长什么样、能不能入库成记录。
class TryOnPage extends StatelessWidget {
  const TryOnPage({super.key, this.initialItems, this.initialPersonPath});

  /// 从首页「试穿看看」带过来的搭配
  final List<Clothing>? initialItems;

  /// 从照片数字人带过来的本人照片：直接当人像，少选一次图
  final String? initialPersonPath;

  @override
  Widget build(BuildContext context) {
    final storage = context.read<WardrobeProvider>().storage;
    return ChangeNotifierProvider(
      create: (_) => TryOnProvider(storage)..load(),
      child: _TryOnBody(
          initialItems: initialItems, initialPersonPath: initialPersonPath),
    );
  }
}

class _TryOnBody extends StatefulWidget {
  const _TryOnBody({this.initialItems, this.initialPersonPath});

  final List<Clothing>? initialItems;
  final String? initialPersonPath;

  @override
  State<_TryOnBody> createState() => _TryOnBodyState();
}

class _TryOnBodyState extends State<_TryOnBody> {
  String? _personPath;
  List<Clothing> _items = [];
  String? _extraNote;
  TryOnTask? _result;
  bool _pickingPerson = false;

  @override
  void initState() {
    super.initState();
    _items = widget.initialItems ?? const [];
    _personPath = widget.initialPersonPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<WardrobeProvider>();
      // 没带搭配时，自动用今天推荐的一套，减少操作
      if (_items.isEmpty) {
        final plan = p.recommendToday();
        if (plan != null) {
          _items = plan.pieces;
          setState(() {});
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final tp = context.watch<TryOnProvider>();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: '虚拟试穿',
              eyebrow: 'TRY ON · 2D',
              subtitle: '用你自己的照片看到上身效果',
              actions: [
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
                  if (tp.profile != null &&
                      !(tp.serviceConfig?.edit ?? false))
                    _gatewayHint(),
                  _stepHeader('1', '你的照片', done: _personPath != null),
                  const SizedBox(height: 10),
                  _personCard(),
                  const SizedBox(height: 20),
                  _stepHeader('2', '穿哪一套', done: _items.isNotEmpty),
                  const SizedBox(height: 10),
                  _outfitPicker(p),
                  // #4：给长按删除一个可见提示
                  if (p.outfits.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 2),
                      child: Text(
                        '点按选一套 · 长按删除这套',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.inkSubtle),
                      ),
                    ),
                  if (_items.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _itemStrip(p),
                  ],
                  const SizedBox(height: 18),
                  _noteField(),
                  const SizedBox(height: 18),
                  _generateButton(tp, p),
                  const SizedBox(height: 22),
                  _resultSection(tp, p),
                  const SizedBox(height: 24),
                  _history(tp, p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 顶部提示 ----------

  Widget _gatewayHint() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.brush_outlined, size: 17, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('试穿暂未开通',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
                const SizedBox(height: 3),
                const Text(
                  '管理员还没开通试穿模型。不影响使用：可以直接看搭配预览，或先记录今天的穿搭。',
                  style: TextStyle(
                      fontSize: 11, height: 1.55, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const AiServicePage()));
                    if (context.mounted) {
                      await context.read<TryOnProvider>().refreshGateway();
                    }
                  },
                  child: const Text('查看 AI 服务状态 →',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepHeader(String index, String title, {required bool done}) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: done ? AppColors.ink : AppColors.surfaceAlt,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : Text(index,
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.inkSubtle)),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: -.2)),
      ],
    );
  }

  // ---------- 人像 ----------

  Widget _personCard() {
    final image = fileImageWidget(_personPath, fit: BoxFit.cover);
    return GestureDetector(
      onTap: _pickPerson,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: image != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('换一张',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                        color: AppColors.surfaceAlt, shape: BoxShape.circle),
                    child: _pickingPerson
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_outline,
                            size: 26, color: AppColors.inkSubtle),
                  ),
                  const SizedBox(height: 12),
                  const Text('上传一张全身照',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('正面、光线均匀、背景干净效果最好',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.inkSubtle)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _smallAction(Icons.photo_library_outlined, '相册'),
                      const SizedBox(width: 8),
                      _smallAction(Icons.photo_camera_outlined, '拍照'),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _smallAction(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.ink),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Future<void> _pickPerson() async {
    setState(() => _pickingPerson = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final path = await ImageStore.instance
          .saveBytes(Uint8List.fromList(bytes), prefix: 'tryon_person');
      if (path != null && mounted) {
        setState(() {
          _personPath = path;
          _result = null;
        });
      }
    } finally {
      if (mounted) setState(() => _pickingPerson = false);
    }
  }

  // ---------- 搭配 ----------

  Widget _outfitPicker(WardrobeProvider p) {
    final outfits = p.outfits.take(6).toList();
    if (outfits.isEmpty) {
      return GestureDetector(
        onTap: () => _pickItemsManually(p),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              const Icon(Icons.checkroom, size: 17, color: AppColors.inkMuted),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('还没有保存的搭配，从衣橱里手动挑几件',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.inkSubtle),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: outfits.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == outfits.length) {
            return GestureDetector(
              onTap: () => _pickItemsManually(p),
              child: Container(
                width: 96,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 18, color: AppColors.inkMuted),
                    SizedBox(height: 4),
                    Text('自己挑',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMuted)),
                  ],
                ),
              ),
            );
          }
          final o = outfits[i];
          final items = p.allClothes
              .where((c) => o.clothingIds.contains(c.id))
              .toList();
          final selected = _items.isNotEmpty &&
              items.length == _items.length &&
              items.every((e) => _items.any((x) => x.id == e.id));
          return GestureDetector(
            onTap: () => setState(() {
              _items = items;
              _result = null;
            }),
            // #4 删除试穿衣橱条目：长按搭配卡弹确认删除
            onLongPress: () => _confirmDeleteOutfit(p, o),
            child: Container(
              width: 96,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? AppColors.ink : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected ? AppColors.ink : AppColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    children: items.take(4).map((c) {
                      final img = fileImageWidget(c.displayImagePath,
                          fit: BoxFit.cover);
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Container(
                          width: 20,
                          height: 20,
                          color: selected
                              ? Colors.white24
                              : AppColors.surfaceAlt,
                          alignment: Alignment.center,
                          child: img ??
                              Text(ClothingCategory.icons[c.category] ?? '👕',
                                  style: const TextStyle(fontSize: 10)),
                        ),
                      );
                    }).toList(),
                  ),
                  Text(
                    o.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// #4：删除试穿页里保存的搭配（长按卡片触发，带确认）
  Future<void> _confirmDeleteOutfit(WardrobeProvider p, Outfit o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('删掉这套搭配？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text('「${o.name}」会从「我的搭配」里删除，穿搭记录不受影响。',
            style: const TextStyle(
                fontSize: 12.5, height: 1.6, color: AppColors.inkMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('留着')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除',
                  style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      // 当前选中的就是被删的这套时，同步清空选择，避免界面引用已删数据
      final wasSelected = _items.isNotEmpty &&
          o.clothingIds.length == _items.length &&
          _items.every((x) => o.clothingIds.contains(x.id));
      await p.deleteOutfit(o.id);
      if (mounted && wasSelected) {
        setState(() => _items = const []);
      }
    }
  }

  Widget _itemStrip(WardrobeProvider p) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _items
                  .map((c) =>
                      '${ClothingCategory.names[c.category] ?? ''}·${c.color}')
                  .join(' + '),
              maxLines: 2,
              style: const TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkMuted),
            ),
          ),
          Text('${_items.length} 件',
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkSubtle)),
        ],
      ),
    );
  }

  Future<void> _pickItemsManually(WardrobeProvider p) async {
    final picked = await showModalBottomSheet<List<Clothing>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemPickerSheet(
        clothes: p.allClothes,
        initial: _items,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _items = picked;
        _result = null;
      });
    }
  }

  Widget _noteField() {
    return TextField(
      style: const TextStyle(fontSize: 12.5),
      maxLines: 2,
      onChanged: (v) => _extraNote = v,
      decoration: InputDecoration(
        hintText: '补充要求（可选）：比如「想看到配球鞋的样子」',
        hintStyle: const TextStyle(
            fontSize: 12, color: AppColors.inkSubtle, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
      ),
    );
  }

  // ---------- 生成 ----------

  Widget _generateButton(TryOnProvider tp, WardrobeProvider p) {
    final ready = _personPath != null && _items.isNotEmpty && !tp.busy;
    return SizedBox(
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: tp.busy ? AppColors.inkMuted : AppColors.ink,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        onPressed: ready
            ? () async {
                final task = await tp.generate(
                  personImagePath: _personPath!,
                  items: _items,
                  extraNote: _extraNote,
                );
                if (mounted) setState(() => _result = task);
              }
            : null,
        child: tp.busy
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('生成中，通常 30-90 秒',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              )
            : Text(
                _personPath == null
                    ? '先上传一张照片'
                    : _items.isEmpty
                        ? '先选一套搭配'
                        : '开始试穿',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }

  // ---------- 结果 ----------

  Widget _resultSection(TryOnProvider tp, WardrobeProvider p) {
    final task = _result ?? (tp.tasks.isEmpty ? null : tp.tasks.first);
    if (task == null) return const SizedBox.shrink();
    if (task.isRunning || task.status == TryOnStatus.running) {
      return const SizedBox.shrink();
    }

    if (task.isSuccess) return _successCard(task);

    // 失败 ↔ 降级预览
    return _fallbackCard(task);
  }

  Widget _successCard(TryOnTask task) {
    final img = fileImageWidget(task.resultImagePath, fit: BoxFit.cover);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MicroLabel('试穿结果 · ${task.displayName}'),
                  if (task.outfitCategory != null ||
                      (task.outfitTags?.isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        [
                          task.outfitCategory,
                          ...?task.outfitTags,
                        ].whereType<String>().join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.inkSubtle),
                      ),
                    ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _editMeta(task),
              child: const Text('编辑',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () async {
                final bytes = await context.read<TryOnProvider>().resultBytes(task);
                if (bytes == null) return;
                final path = await ShareService.sharePng(
                  bytes,
                  fileName: 'tryon_${task.id}.png',
                  text: '我的虚拟试穿',
                );
                if (path == null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('当前设备无法调起分享'),
                        behavior: SnackBarBehavior.floating),
                  );
                }
              },
              child: const Text('分享',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: GestureDetector(
            onTap: () => ImageViewerPage.open(context,
                path: task.resultImagePath, title: '试穿结果'),
            child: Container(
              height: 360,
              width: double.infinity,
              color: AppColors.surfaceAlt,
              child: img ?? const SizedBox.shrink(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('点开可放大拖动查看；生成图只存在本机，仅本次请求会经服务转发给 AI 模型。',
            style: TextStyle(fontSize: 10.5, color: AppColors.inkSubtle)),
      ],
    );
  }

  /// 编辑这套试穿搭配的名称、分类与标签
  Future<void> _editMeta(TryOnTask task) async {
    final nameCtrl = TextEditingController(text: task.outfitName ?? '');
    final catCtrl = TextEditingController(text: task.outfitCategory ?? '');
    final tagCtrl =
        TextEditingController(text: (task.outfitTags ?? const []).join('，'));
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('编辑搭配信息',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: '名称', hintText: '如 周五约会那套'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: catCtrl,
                  decoration: const InputDecoration(
                      labelText: '分类', hintText: '如 通勤 / 约会 / 度假'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in const ['通勤', '约会', '休闲', '度假', '运动', '派对'])
                      ActionChip(
                        label: Text(c, style: const TextStyle(fontSize: 11)),
                        onPressed: () => catCtrl.text = c,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tagCtrl,
                  decoration: const InputDecoration(
                      labelText: '标签', hintText: '用逗号分隔，如 显瘦，春季'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存',
                    style: TextStyle(color: AppColors.primary))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final tags = tagCtrl.text
          .split(RegExp(r'[,，;；]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await context.read<TryOnProvider>().updateMeta(
            task,
            name: nameCtrl.text,
            category: catCtrl.text,
            tags: tags,
          );
    } finally {
      nameCtrl.dispose();
      catCtrl.dispose();
      tagCtrl.dispose();
    }
  }

  Widget _fallbackCard(TryOnTask task) {
    final degraded = task.degraded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: MicroLabel(degraded ? '搭配预览（降级模式）' : '生成失败'),
            ),
            if (!degraded)
              GestureDetector(
                onTap: () async {
                  final p = context.read<WardrobeProvider>();
                  final items = p.allClothes
                      .where((c) => task.itemIds.contains(c.id))
                      .toList();
                  final newTask =
                      await context.read<TryOnProvider>().retry(task, items);
                  if (mounted) setState(() => _result = newTask);
                },
                child: const Text('重试',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _outfitPreview(task),
        if (task.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(task.errorMessage!,
              style: const TextStyle(
                  fontSize: 11, height: 1.5, color: AppColors.inkMuted)),
        ],
      ],
    );
  }

  /// 降级时用「配色板」代替结果图：不假装能试穿，但能看出这套的气质
  Widget _outfitPreview(TryOnTask task) {
    final p = context.watch<WardrobeProvider>();
    final items = p.allClothes
        .where((c) => task.itemIds.contains(c.id))
        .toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: items.take(4).map((c) {
              final img =
                  fileImageWidget(c.displayImagePath, fit: BoxFit.cover);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 110,
                      color: AppColors.surfaceAlt,
                      alignment: Alignment.center,
                      child: img ??
                          Text(ClothingCategory.icons[c.category] ?? '👕',
                              style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items.map((c) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${ClothingCategory.names[c.category] ?? ''} · ${c.color}',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 12, color: AppColors.inkSubtle),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '这是这套搭配的实际单品，先看看风格是否合适；'
                    '管理员开通试穿后就能看到上身效果。',
                    style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
                        color: AppColors.inkSubtle),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 历史 ----------

  Widget _history(TryOnProvider tp, WardrobeProvider p) {
    final done = tp.tasks.where((t) => t.isSuccess).toList();
    if (done.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MicroLabel('历史试穿'),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: done.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final t = done[i];
              final img = fileImageWidget(t.resultImagePath, fit: BoxFit.cover);
              return GestureDetector(
                onTap: () => ImageViewerPage.open(context,
                    path: t.resultImagePath, title: '历史试穿'),
                onLongPress: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: const Text('删掉这张试穿图？',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('留着')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('删除',
                                style: TextStyle(color: AppColors.primary))),
                      ],
                    ),
                  );
                  if (ok == true && mounted) {
                    await context.read<TryOnProvider>().deleteTask(t.id);
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 88,
                    color: AppColors.surfaceAlt,
                    child: img ?? const SizedBox.shrink(),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        const Text('点开可放大查看 · 长按可删除',
            style: TextStyle(fontSize: 10, color: AppColors.inkSubtle)),
      ],
    );
  }
}

// ---------- 手动挑单品 ----------

class _ItemPickerSheet extends StatefulWidget {
  const _ItemPickerSheet({required this.clothes, required this.initial});

  final List<Clothing> clothes;
  final List<Clothing> initial;

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial.map((c) => c.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: AppColors.canvasTop,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.hairline,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text('挑 ${_selected.length} 件',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  widget.clothes
                      .where((c) => _selected.contains(c.id))
                      .toList(),
                ),
                child: const Text('确定',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.builder(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
              ),
              itemCount: widget.clothes.length,
              itemBuilder: (_, i) {
                final c = widget.clothes[i];
                final on = _selected.contains(c.id);
                final img =
                    fileImageWidget(c.displayImagePath, fit: BoxFit.cover);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (on) {
                      _selected.remove(c.id);
                    } else {
                      _selected.add(c.id);
                    }
                  }),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: on ? AppColors.ink : AppColors.hairline,
                        width: on ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: AppColors.surfaceAlt,
                          alignment: Alignment.center,
                          child: img ??
                              Text(
                                  ClothingCategory.icons[c.category] ?? '👕',
                                  style: const TextStyle(fontSize: 22)),
                        ),
                        if (on)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Container(
                              width: 17,
                              height: 17,
                              decoration: const BoxDecoration(
                                  color: AppColors.ink,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.check,
                                  size: 11, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
