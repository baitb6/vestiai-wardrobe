import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide MaterialType;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/wardrobe_provider.dart';
import '../../services/image_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/image_viewer.dart';
import '../../widgets/kit.dart';
import '../try_on/try_on_page.dart';

/// 照片数字人：用本人全身照生成「正面 / 四分之三 / 背面」三视角形象，
/// 左右滑动切换视角，点击可放大查看，还能直接带着这个形象去虚拟试穿。
///
/// 隐私原则：照片只在用户点「生成」那一刻上传给后台已配置的模型，
/// 服务器只做内存转发不落盘；生成结果保存在手机本地，随时可删除。
class DigitalAvatarPage extends StatefulWidget {
  const DigitalAvatarPage({super.key});

  @override
  State<DigitalAvatarPage> createState() => _DigitalAvatarPageState();
}

class _DigitalAvatarPageState extends State<DigitalAvatarPage> {
  ui.Image? _sheet;
  String? _sheetPath;

  /// 形象图是否为「三联图」（正面/四分之三/背面三格横排）。
  /// #2：模型可能只回单张人像——按宽高比判定（≥1.8 视为三联），
  /// 单张就整图展示，不再硬按 1/3 裁导致「图放大一倍只显示一半」。
  bool _sheetTriptych = true;

  /// 试穿用的人像路径（三联图第 0 格裁出的正面形象，本地派生缓存）。
  /// 换形象 / 删除形象时作废重裁。
  String? _tryOnPersonPath;
  bool _generating = false;
  String? _error;
  int _pageIndex = 0;
  late final PageController _page =
      PageController(initialPage: 0, keepPage: false);

  static const _viewNames = ['正面', '四分之三', '背面'];

  @override
  void initState() {
    super.initState();
    final profile = context.read<WardrobeProvider>().profile;
    _sheetPath = profile?.avatarSheetPath;
    if (_sheetPath != null) _decodeSheet(_sheetPath!);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _decodeSheet(String path) async {
    try {
      final data = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(data);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      // 释放旧解码图，避免换形象/重解码时 ui.Image 泄漏
      setState(() {
        _sheet?.dispose();
        _sheet = frame.image;
        // 三联判定：三格横排的宽高比 ≈ 3×单格比例；单张人像通常 < 1.8
        _sheetTriptych =
            frame.image.width / frame.image.height >= 1.8;
        _pageIndex = 0;
      });
    } catch (_) {
      // 文件损坏或已被清理：回到未生成状态，不崩溃
      if (mounted) {
        setState(() {
          _sheet = null;
          // #2 状态一致性：路径还挂着但图解不出来时，同时清路径，
          // 否则页面显示「还没有形象」却与 profile 里的头像状态打架
          _sheetPath = null;
        });
      }
    }
  }

  /// 裁出三联图第 0 格（正面）存成本地 PNG，作为试穿人像。
  ///
  /// 「用此形象去试穿」必须带生成后的形象，不能带用户上传的原图
  /// （原图姿态/背景不定，试穿效果差，也和按钮文案不符）。
  /// 首次点击时裁一次并缓存；裁不出时调用方退回整张形象图。
  Future<String?> _deriveTryOnPerson() async {
    if (_tryOnPersonPath != null) return _tryOnPersonPath;
    final sheet = _sheet;
    if (sheet == null) return null;
    // 单张形象图：整图就是人像，直接用原图，不做 1/3 裁切
    if (!_sheetTriptych) return _sheetPath;
    final w = sheet.width ~/ 3;
    if (w <= 0 || sheet.height <= 0) return null;
    try {
      final src = Rect.fromLTWH(0, 0, w.toDouble(), sheet.height.toDouble());
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        sheet,
        src,
        Offset.zero & src.size,
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final panel = await picture.toImage(w, sheet.height);
      picture.dispose();
      final data = await panel.toByteData(format: ui.ImageByteFormat.png);
      panel.dispose();
      if (data == null) return null;
      final path = await ImageStore.instance.saveBytes(
          data.buffer.asUint8List(),
          prefix: 'avatar_person',
          ext: 'png');
      if (path != null && mounted) {
        setState(() => _tryOnPersonPath = path);
      }
      return path;
    } catch (e) {
      debugPrint('裁切正面形象图失败：$e');
      return null;
    }
  }

  Future<void> _pickAndGenerate() async {
    if (_generating) return;
    final p = context.read<WardrobeProvider>();

    // 隐私确认：明确照片会去哪、能不能删
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('用照片生成形象？'),
        content: const Text(
          '上传一张清晰的全身照，AI 会生成你的正面 / 侧面 / 背面形象，'
          '保存在手机本地。\n\n照片只在你点「生成」时上传一次，由服务器'
          '转发给管理员配置的模型，服务器不保存、不展示给任何人。'
          '生成的形象随时可以在这里删除。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('同意并选照片')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      imageQuality: 92,
    );
    if (file == null || !mounted) return;

    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final bytes = Uint8List.fromList(await file.readAsBytes());
      final cfg = await p.backend.config();
      if (!(cfg.aiEnabled && cfg.avatarReady)) {
        throw StateError(cfg.online
            ? '管理员还没有开通形象生成模型，先试试虚拟试穿吧'
            : '连不上 AI 服务，请检查网络后再试');
      }
      final sheet = await p.backend.generateAvatar(bytes);

      // 先把本人照片存进仓库（备份/恢复会带上；试穿改用生成的形象图），
      // 再存三联形象图
      final sourcePath = await ImageStore.instance
          .saveBytes(bytes, prefix: 'avatar_source', ext: 'jpg');
      if (sourcePath == null) {
        throw StateError('手机存储不可用，形象没能保存，请重试');
      }
      final sheetPath = await ImageStore.instance.saveBytes(sheet,
          prefix: 'avatar_sheet',
          ext: sheet.length > 8 && sheet[0] == 0x89 ? 'png' : 'jpg');
      if (sheetPath == null) {
        throw StateError('手机存储不可用，形象没能保存，请重试');
      }
      await p.saveDigitalAvatar(
          sheetPath: sheetPath, sourcePath: sourcePath);
      if (!mounted) return;
      // 换了新形象：旧的正面派生图作废清理，缓存重置等下次点击重裁
      final stalePerson = _tryOnPersonPath;
      setState(() {
        _sheetPath = sheetPath;
        _tryOnPersonPath = null;
      });
      ImageStore.instance.deleteQuietly(stalePerson);
      // #2 关键修复：首次生成成功时 PageView 还没 build（_sheet 尚未解码，
      // hasAvatar=false 走的是空态），此时 jumpToPage 在 release 下走
      // `_positions.single` 抛 StateError("Bad state: No element")——
      // 即用户看到「成功也报 No element」的来源。先解码再跳页，且带 hasClients 守卫。
      await _decodeSheet(sheetPath);
      if (_page.hasClients) {
        _page.jumpToPage(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e is StateError ? e.message : '生成失败，请稍后再试');
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _deleteAvatar() async {
    final p = context.read<WardrobeProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('删除数字人形象？'),
        content: const Text('形象图和上传的全身照都会从手机里删除，'
            '不影响衣橱和穿搭记录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await p.clearDigitalAvatar();
    if (!mounted) return;
    final personFile = _tryOnPersonPath;
    setState(() {
      _sheet?.dispose();
      _sheet = null;
      _sheetPath = null;
      _tryOnPersonPath = null;
    });
    // 形象删除后派生图也不能留（否则成孤儿文件）
    ImageStore.instance.deleteQuietly(personFile);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final hasAvatar = _sheetPath != null && _sheet != null;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: '照片数字人',
              eyebrow: 'DIGITAL AVATAR',
              subtitle: '用你自己的照片，生成可换装的数字形象',
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
                  if (_error != null) ...[
                    _errorCard(_error!),
                    const SizedBox(height: 14),
                  ],
                  if (hasAvatar) ...[
                    _avatarStage(),
                    const SizedBox(height: 12),
                    _viewTabs(),
                    const SizedBox(height: 18),
                    _actions(p),
                  ] else
                    _emptyStage(),
                  const SizedBox(height: 20),
                  _privacyNote(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 展示区 ----------

  Widget _avatarStage() {
    return AspectRatio(
      aspectRatio: 0.78,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ImageViewerPage(
                  path: _sheetPath, title: '数字人形象')),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.hairline),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x1415110E), blurRadius: 24, offset: Offset(0, 10)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: PageView.builder(
            controller: _page,
            // #2：单张形象图只有一页；三联图才分三视角
            itemCount: _sheetTriptych ? 3 : 1,
            onPageChanged: (i) => setState(() => _pageIndex = i),
            itemBuilder: (context, i) =>
                _PanelView(image: _sheet!, index: i, triptych: _sheetTriptych),
          ),
        ),
      ),
    );
  }

  Widget _viewTabs() {
    // #2：单张形象图没有视角可切，给一个「完整形象」的状态 chip
    if (!_sheetTriptych) {
      return const Center(
        child: Text('完整形象',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.inkMuted)),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _viewNames.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              if (!_page.hasClients) return;
              _page.animateToPage(i,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: i == _pageIndex ? AppColors.ink : AppColors.surface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                    color:
                        i == _pageIndex ? AppColors.ink : AppColors.hairline),
              ),
              child: Text(_viewNames[i],
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: i == _pageIndex
                          ? Colors.white
                          : AppColors.inkMuted)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _actions(WardrobeProvider p) {
    // 试穿的门槛是「有生成好的形象」，不再是「有上传原图」
    final canTryOn = _sheet != null;
    return Row(
      children: [
        Expanded(
          child: PillButton(
            label: '用此形象去试穿',
            icon: Icons.checkroom,
            variant: PillVariant.lime,
            expand: true,
            onTap: canTryOn
                ? () async {
                    // 带「生成的正面形象」去试穿；派生失败退回整张三联图，
                    // 绝不回退到用户上传的原图
                    final person = await _deriveTryOnPerson();
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TryOnPage(
                              initialPersonPath: person ?? _sheetPath)),
                    );
                  }
                : null,
          ),
        ),
        const SizedBox(width: 10),
        _roundAction(Icons.autorenew, '换个形象', _pickAndGenerate,
            enabled: !_generating),
        const SizedBox(width: 10),
        _roundAction(Icons.delete_outline, '删除', _deleteAvatar,
            enabled: !_generating),
      ],
    );
  }

  Widget _roundAction(IconData icon, String tooltip, VoidCallback onTap,
      {bool enabled = true}) {
    // #2 按钮状态：生成中给出禁用视觉（降透明度 + 不可点），
    // 不再「点了没反应」；点击回调自身也有 _generating 二次守卫
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hairline),
          ),
          child: Icon(icon, size: 19, color: AppColors.inkMuted),
        ),
      ),
    );
  }

  // ---------- 空态 ----------

  Widget _emptyStage() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
                color: AppColors.primarySoft, shape: BoxShape.circle),
            child: const Icon(Icons.face_retouching_natural,
                size: 38, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text('还没有你的数字形象',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -.3)),
          const SizedBox(height: 6),
          const Text(
            '上传一张全身照，AI 生成正面 / 侧面 / 背面三视角形象。\n'
            '试穿时可以直接用这个形象，看衣服穿在自己身上的样子。',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5, height: 1.7, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 20),
          PillButton(
            label: _generating ? '生成中…（约半分钟）' : '选照片生成形象',
            icon: Icons.auto_awesome,
            variant: PillVariant.lime,
            expand: true,
            onTap: _generating ? null : _pickAndGenerate,
          ),
          if (_generating) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
                minHeight: 3, color: AppColors.primary),
          ] else ...[
            const SizedBox(height: 10),
            const Text('照片建议：正面站直、全身入镜、光线均匀',
                style: TextStyle(
                    fontSize: 11, color: AppColors.inkSubtle)),
          ],
        ],
      ),
    );
  }

  Widget _errorCard(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.warn.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.warn.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.warn),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, height: 1.55, color: AppColors.inkMuted)),
          ),
        ],
      ),
    );
  }

  Widget _privacyNote() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '照片只在你点「生成」时上传一次，服务器内存转发、不保存；'
        '形象与照片保存在本机，可随时删除。AI 未开通时手工功能不受影响。',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 10.5, height: 1.7, color: AppColors.inkSubtle),
      ),
    );
  }
}

/// 单个视角面板：三联图的第 [index] 格铺满（cover）；
/// [triptych]=false 时整图 contain 居中显示（单张人像不裁切）。
class _PanelView extends StatelessWidget {
  const _PanelView({required this.image, required this.index, this.triptych = true});

  final ui.Image image;
  final int index;
  final bool triptych;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PanelPainter(image: image, index: index, triptych: triptych),
      size: Size.infinite,
    );
  }
}

class _PanelPainter extends CustomPainter {
  _PanelPainter({required this.image, required this.index, this.triptych = true});

  final ui.Image image;
  final int index;
  final bool triptych;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (!triptych) {
      // #2 单张形象：contain 完整显示（旧逻辑按 1/3 裁导致放大一倍只见一半）
      final scale =
          math.min(size.width / image.width, size.height / image.height);
      final w = image.width * scale;
      final h = image.height * scale;
      final dst = Rect.fromLTWH(
          (size.width - w) / 2, (size.height - h) / 2, w, h);
      canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          dst,
          Paint()..filterQuality = FilterQuality.medium);
      return;
    }

    final panelW = image.width / 3.0;
    var src = Rect.fromLTWH(panelW * index, 0, panelW, image.height.toDouble());

    // cover：源面板与目标区域比例不一致时，只允许在第 index 格内部裁剪。
    // 两个分支对应「面板偏宽→裁宽、面板偏高→裁高」；一旦写反，会把采样
    // 矩形扩到相邻格（人物重合）甚至图纸外（边缘钳制成白边）。
    final srcAspect = src.width / src.height;
    final dstAspect = size.width / size.height;
    if (srcAspect > dstAspect) {
      // 面板偏宽：保持整格高度，横向居中裁窄
      final w = src.height * dstAspect;
      src = Rect.fromLTWH(src.left + (src.width - w) / 2, src.top, w, src.height);
    } else if (srcAspect < dstAspect) {
      // 面板偏高：保持整格宽度，纵向居中裁矮
      final h = src.width / dstAspect;
      src = Rect.fromLTWH(src.left, src.top + (src.height - h) / 2, src.width, h);
    }
    canvas.drawImageRect(image, src, Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_PanelPainter old) =>
      old.image != image || old.index != index || old.triptych != triptych;
}
