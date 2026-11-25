import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/wardrobe_provider.dart';
import '../../services/gateway_store.dart';
import '../../services/image_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';
import '../ai_gateway/ai_service_page.dart';
import 'auto_split_provider.dart';
import 'split_result_card.dart';
import 'split_task_list_page.dart';

/// AI 拆衣入口页：选图 → 队列 → 进度 → 进入确认
class AutoSplitPage extends StatefulWidget {
  const AutoSplitPage({super.key});

  @override
  State<AutoSplitPage> createState() => _AutoSplitPageState();
}

class _AutoSplitPageState extends State<AutoSplitPage> {
  late AutoSplitProvider _p;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final storage = context.read<WardrobeProvider>().storage;
    _p = AutoSplitProvider(
      storage: storage,
      gatewayStore: GatewayStore(storage),
    );
    _p.load();
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _p,
      child: Consumer<AutoSplitProvider>(
        builder: (context, p, _) => Scaffold(
          backgroundColor: AppColors.canvas,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                ScreenHeader(
                  title: 'AI 拆衣',
                  eyebrow: 'AUTO SPLIT',
                  subtitle: '一张全身照，拆成一件件',
                  actions: [
                    RoundIconButton(
                      icon: Icons.history,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SplitTaskListPage(provider: p),
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    children: [
                      _privacyCard(p),
                      const SizedBox(height: 14),
                      _pickCard(p),
                      const SizedBox(height: 20),
                      if (p.pendingTasks.isNotEmpty) ...[
                        const SectionTitle('正在处理', eyebrow: 'IN PROGRESS'),
                        const SizedBox(height: 10),
                        for (final t in p.pendingTasks) _runningTile(t),
                        const SizedBox(height: 18),
                      ],
                      if (_failed(p).isNotEmpty) ...[
                        const SectionTitle('失败', eyebrow: 'FAILED'),
                        const SizedBox(height: 10),
                        for (final t in _failed(p)) _failedTile(t),
                        const SizedBox(height: 18),
                      ],
                      if (_ready(p).isNotEmpty) ...[
                        const SectionTitle('待确认', eyebrow: 'TO REVIEW'),
                        const SizedBox(height: 10),
                        for (final t in _ready(p)) _readyTile(t),
                        const SizedBox(height: 18),
                      ],
                      if (_done(p).isNotEmpty) ...[
                        const SectionTitle('已入库', eyebrow: 'IMPORTED'),
                        const SizedBox(height: 10),
                        for (final t in _done(p)) _doneTile(t),
                      ],
                      if (p.tasks.isEmpty) _empty(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<SplitTask> _failed(AutoSplitProvider p) =>
      p.tasks.where((t) => t.status == SplitStatus.failed).toList();

  List<SplitTask> _ready(AutoSplitProvider p) =>
      p.tasks.where((t) => t.status == SplitStatus.success).toList();

  List<SplitTask> _done(AutoSplitProvider p) =>
      p.tasks.where((t) => t.status == SplitStatus.imported).take(5).toList();

  // ---------- 卡片 ----------

  Widget _privacyCard(AutoSplitProvider p) {
    final hint = p.configHint;
    final ok = hint == null;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ok ? AppColors.limeSoft : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.verified_user_outlined : Icons.info_outline,
                  size: 15, color: AppColors.ink),
              const SizedBox(width: 6),
              Text(ok ? 'AI 拆衣已开通' : '暂未开通',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ok
                ? '全身照会经衣橱管家服务转发给 AI 模型，只用于本次识别，服务端不保存图片。'
                    '识别失败也不会丢原图，可以重试。'
                : hint,
            style: const TextStyle(fontSize: 11.5, height: 1.5, color: AppColors.inkMuted),
          ),
          if (!ok) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AiServicePage()),
                );
                await p.refreshProfile();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text('查看 AI 服务',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pickCard(AutoSplitProvider p) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('选照片',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.4,
                  color: AppColors.ink)),
          const SizedBox(height: 5),
          const Text('一张照片里可以有多件，站着拍、光线均匀、别裁掉鞋',
              style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _picking ? null : () => _pick(multiple: true),
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x33FF3B2F),
                            blurRadius: 16,
                            offset: Offset(0, 8)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_picking)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        else
                          const Icon(Icons.add_photo_alternate_outlined,
                              size: 18, color: Colors.white),
                        const SizedBox(width: 7),
                        Text(_picking ? '读取中…' : '选全身照（可多选）',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _picking ? null : () => _pick(multiple: false),
                child: Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Icon(Icons.photo_camera_outlined,
                      size: 20, color: AppColors.inkMuted),
                ),
              ),
            ],
          ),
          if (!ImageStore.instance.available) ...[
            const SizedBox(height: 10),
            const Text('网页版不支持本地文件存储，请在 App 内使用 AI 拆衣',
                style: TextStyle(fontSize: 10.5, color: AppColors.bad)),
          ],
        ],
      ),
    );
  }

  Widget _runningTile(SplitTask t) {
    final total = t.itemCount ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        radius: 16,
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.status == SplitStatus.running ? '识别中…' : '排队中',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    t.status == SplitStatus.running
                        ? '视觉模型正在看图，大图可能要半分钟'
                        : '排队中，很快就会开始',
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.inkSubtle),
                  ),
                ],
              ),
            ),
            if (total > 0)
              TagPill(label: '$total 件', dense: true),
          ],
        ),
      ),
    );
  }

  Widget _failedTile(SplitTask t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.all(13),
        radius: 16,
        borderColor: const Color(0x33D93B2B),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, size: 15, color: AppColors.bad),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('识别失败',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.bad)),
                ),
                TagPill(
                  label: _ago(t.createdAt),
                  dense: true,
                  background: AppColors.surfaceAlt,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(t.errorMessage ?? '未知错误',
                style: const TextStyle(
                    fontSize: 11.5, height: 1.45, color: AppColors.inkMuted)),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: () => _p.retryTask(t.id),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text('重试',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _p.deleteTask(t.id),
                  child: const Text('删除任务',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.inkSubtle)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _readyTile(SplitTask t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.all(13),
        radius: 16,
        onTap: () => _openReview(t),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.limeSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome, size: 20, color: Color(0xFF5D6B12)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('识别出 ${t.itemCount ?? 0} 件，待你确认',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${_ago(t.createdAt)} · 点开改分类、调框、删误识别',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.inkSubtle)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.inkSubtle),
          ],
        ),
      ),
    );
  }

  Widget _doneTile(SplitTask t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 14, color: AppColors.ok),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_ago(t.createdAt)} · 入库 ${t.importedCount ?? 0} 件',
              style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        children: [
          Icon(Icons.checkroom, size: 44, color: AppColors.hairline),
          const SizedBox(height: 12),
          const Text('还没有拆分记录',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSubtle)),
        ],
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  // ---------- 动作 ----------

  Future<void> _pick({required bool multiple}) async {
    setState(() => _picking = true);
    try {
      final picker = ImagePicker();
      final List<XFile> files;
      if (multiple) {
        files = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 88);
      } else {
        final one = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          imageQuality: 88,
        );
        files = one == null ? const [] : [one];
      }

      final images = <({Uint8List bytes, String name})>[];
      for (final f in files) {
        images.add((bytes: await f.readAsBytes(), name: f.name));
      }
      if (images.isEmpty) return;
      final added = await _p.enqueueImages(images);
      if (added == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有加入队列：网页版或存储不可用')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选图失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _openReview(SplitTask task) async {
    _p.hydrateDraft(task);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SplitReviewPage(taskId: task.id, provider: _p),
      ),
    );
    if (mounted) setState(() {});
  }
}

/// 确认页：逐件修正 → 入库
class _SplitReviewPage extends StatefulWidget {
  const _SplitReviewPage({required this.taskId, required this.provider});

  final String taskId;
  final AutoSplitProvider provider;

  @override
  State<_SplitReviewPage> createState() => _SplitReviewPageState();
}

class _SplitReviewPageState extends State<_SplitReviewPage> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await widget.provider.ensureCutouts(widget.taskId);
    await widget.provider.detectDuplicates(widget.taskId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    return ChangeNotifierProvider.value(
      value: p,
      child: Consumer<AutoSplitProvider>(
        builder: (context, provider, _) {
          final drafts = provider.draftsOf(widget.taskId);
          final selected = drafts.where((d) => d.selected).length;
          final task = provider.tasks.firstWhere(
            (t) => t.id == widget.taskId,
            orElse: () => SplitTask(
              id: widget.taskId,
              sourceImagePath: '',
              createdAt: DateTime.now(),
            ),
          );

          return Scaffold(
            backgroundColor: AppColors.canvas,
            appBar: AppBar(
              backgroundColor: AppColors.canvas,
              elevation: 0,
              title: const Text('确认入库',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(
                    child: Text('${drafts.length} 件',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.inkSubtle)),
                  ),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
              children: [
                _hint(provider, drafts.length),
                const SizedBox(height: 12),
                for (var i = 0; i < drafts.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SplitCandidateCard(
                      candidate: drafts[i],
                      index: i,
                      cutting: provider.isCutoutRunning(widget.taskId),
                      onEdit: () => _edit(drafts[i]),
                      onDelete: () => _delete(drafts[i]),
                      onEditBox: () => _editBox(drafts[i]),
                      onRecut: () => provider.recutCandidate(widget.taskId, drafts[i]),
                      onToggle: () {
                        provider.editCandidate(widget.taskId, drafts[i],
                            selected: !drafts[i].selected);
                      },
                      onMerge: drafts.length > 1
                          ? () => _merge(drafts[i], drafts)
                          : null,
                    ),
                  ),
                if (drafts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text('没有可入库的单品',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.inkSubtle)),
                  ),
              ],
            ),
            bottomSheet: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
              decoration: const BoxDecoration(
                color: AppColors.canvas,
                border: Border(top: BorderSide(color: AppColors.hairline)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final all = drafts.every((d) => d.selected);
                        for (final d in drafts) {
                          provider.editCandidate(widget.taskId, d, selected: !all);
                        }
                      },
                      child: Text(
                        drafts.every((d) => d.selected) ? '取消全选' : '全选',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMuted),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: selected == 0 || _saving
                          ? null
                          : () => _import(task, provider),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 14),
                        decoration: BoxDecoration(
                          color: selected == 0
                              ? AppColors.hairline
                              : AppColors.ink,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          children: [
                            if (_saving)
                              const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            else
                              const Icon(Icons.check,
                                  size: 15, color: Colors.white),
                            const SizedBox(width: 7),
                            Text(
                              _saving ? '写入中…' : '入库 $selected 件',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _hint(AutoSplitProvider p, int count) {
    final running = p.isCutoutRunning(widget.taskId);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (running)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.tips_and_updates_outlined,
                size: 14, color: AppColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              running
                  ? '正在裁剪并尝试抠图，抠不干净会自动留成矩形裁片'
                  : '抠图失败的会保留矩形裁片照常入库，之后可以重试',
              style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(SplitCandidate c) async {
    final result = await showModalBottomSheet<SplitCandidate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => CandidateEditSheet(candidate: c),
    );
    if (result == null) return;
    widget.provider.editCandidate(
      widget.taskId,
      c,
      category: result.category,
      subCategory: result.subCategory,
      colors: result.colors,
      styleTags: result.styleTags,
      seasons: result.seasons,
    );
  }

  void _delete(SplitCandidate c) {
    widget.provider.removeCandidate(widget.taskId, c);
  }

  Future<void> _editBox(SplitCandidate c) async {
    final taskIndex =
        widget.provider.tasks.indexWhere((t) => t.id == widget.taskId);
    if (taskIndex == -1) return;
    final task = widget.provider.tasks[taskIndex];
    final box = await Navigator.push<BBox>(
      context,
      MaterialPageRoute(
        builder: (_) => BBoxEditorPage(
            imagePath: task.sourceImagePath, initial: c.bbox),
      ),
    );
    if (box == null) return;
    widget.provider.editCandidate(widget.taskId, c, bbox: box);
    widget.provider.recutCandidate(widget.taskId, c);
  }

  Future<void> _merge(SplitCandidate source, List<SplitCandidate> all) async {
    final others = all.where((e) => e != source).toList();
    final target = await showModalBottomSheet<SplitCandidate>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('合并到哪一件？',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.4)),
              const SizedBox(height: 4),
              const Text('颜色和标签会合并去重，框取较大的那个',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
              const SizedBox(height: 14),
              for (final o in others)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${ClothingCategory.names[o.category]} · '
                    '${ClothingSubCategory.names[o.subCategory]} · ${o.primaryColor}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.pop(context, o),
                ),
            ],
          ),
        ),
      ),
    );
    if (target == null) return;
    widget.provider.mergeCandidates(widget.taskId, source, target);
  }

  Future<void> _import(SplitTask task, AutoSplitProvider p) async {
    if (task.status == SplitStatus.imported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这批单品已经入库')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final clothes = p.buildClothingFromDrafts(widget.taskId);
      if (clothes.isEmpty) return;
      final wardrobe = context.read<WardrobeProvider>();
      final n = await wardrobe.addClothingBatch(clothes);
      await p.markImported(widget.taskId, n);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已入库 $n 件，去衣橱看看')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('入库失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
