import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/wardrobe_provider.dart';
import '../../services/image_maintenance.dart';
import '../../services/image_usage.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';
import '../backup_restore/backup_page.dart';

/// 图片管家：看占用、清孤儿、批量压缩
class ImageManagerPage extends StatefulWidget {
  const ImageManagerPage({super.key});

  @override
  State<ImageManagerPage> createState() => _ImageManagerPageState();
}

class _ImageManagerPageState extends State<ImageManagerPage> {
  ImageUsage? _usage;
  bool _loading = true;
  bool _busy = false;
  String? _message;
  bool _ok = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    final p = context.read<WardrobeProvider>();
    setState(() => _loading = true);
    final usage = await ImageMaintenance.scan(p.referencedImagePaths);
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _loading = false;
    });
  }

  void _toast(String msg, {bool ok = true}) {
    setState(() {
      _message = msg;
      _ok = ok;
    });
  }

  Future<void> _cleanOrphans() async {
    final orphans = _usage?.orphans ?? const <StoredImage>[];
    if (orphans.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('清理无引用图片？',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        content: Text(
          '将删除 ${orphans.length} 个文件，释放 ${formatBytes(_usage!.orphanBytes)}。\n'
          '这些图片没有被任何衣物或任务引用，删除后不影响现有数据。',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('先留着'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final freed = await ImageMaintenance.deleteOrphans(orphans);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast('已释放 ${formatBytes(freed)}');
    await _scan();
  }

  Future<void> _compress() async {
    if (_busy) return;
    final p = context.read<WardrobeProvider>();
    setState(() => _busy = true);
    final freed = await ImageMaintenance.compress(p.referencedImagePaths);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(freed > 0
        ? '压缩完成，省下 ${formatBytes(freed)}'
        : '没有可压缩的大图（阈值 400 KB）');
    await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    final p = context.watch<WardrobeProvider>();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: const Text('图片管家',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
        actions: [
          IconButton(
            onPressed: _loading ? null : _scan,
            icon: const Icon(Icons.refresh, size: 20, color: AppColors.ink),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (_message != null) ...[
            _notice(_message!, ok: _ok),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.ink)),
            )
          else if (usage == null)
            _notice('网页版没有本地文件系统，图片管家请在 App 内使用', ok: false)
          else ...[
            _usageCard(usage, p),
            const SizedBox(height: 14),
            _breakdown(usage),
            const SizedBox(height: 14),
            _actions(usage, p),
            const SizedBox(height: 14),
            _largest(usage),
            const SizedBox(height: 14),
            _privacyNote(),
          ],
        ],
      ),
    );
  }

  // ---------- 占用 ----------

  Widget _usageCard(ImageUsage usage, WardrobeProvider p) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('IMAGE STORE', color: Colors.white38),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.lime,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  usage.isEmpty ? '空' : '${usage.fileCount} 个文件',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatBytes(usage.totalBytes),
                style: const TextStyle(
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.8,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Text('图片占用',
                  style: TextStyle(fontSize: 12, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Row(
              children: [
                for (final e in usage.bytesByKind.entries)
                  Expanded(
                    flex: e.value == 0 ? 1 : (e.value / 1024).clamp(1, 100000).round(),
                    child: Container(
                      height: 8,
                      color: _kindColor(e.key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '衣物 ${p.totalClothes} 件 · 任务原图 ${usage.countByKind['fullbody'] ?? 0} 张',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'fullbody':
        return AppColors.lime;
      case 'piece':
        return AppColors.primary;
      case 'photo':
        return const Color(0xFF8B7CF6);
      case 'restored':
        return const Color(0xFF5AC8FA);
      default:
        return Colors.white24;
    }
  }

  Widget _breakdown(ImageUsage usage) {
    final entries = usage.bytesByKind.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('按类型拆分',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          const SizedBox(height: 12),
          for (final e in entries) ...[
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _kindColor(e.key),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(kImageKindNames[e.key] ?? e.key,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.ink)),
                ),
                Text('${usage.countByKind[e.key] ?? 0} 个 · ${formatBytes(e.value)}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.inkMuted)),
              ],
            ),
            const SizedBox(height: 9),
          ],
          if (entries.isEmpty)
            const Text('还没有图片',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
        ],
      ),
    );
  }

  // ---------- 操作 ----------

  Widget _actions(ImageUsage usage, WardrobeProvider p) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('清理与压缩',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          const SizedBox(height: 4),
          Text(
            usage.orphanCount > 0
                ? '发现 ${usage.orphanCount} 个无引用文件，共 ${formatBytes(usage.orphanBytes)}。'
                    '（24 小时内新生成的裁片不参与清理，避免误删待确认的图）'
                : '没有发现无引用文件。24 小时内新生成的裁片不参与清理。',
            style: const TextStyle(
                fontSize: 11.5, height: 1.6, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: _busy ? '处理中…' : '清理孤儿图',
                  icon: Icons.cleaning_services_outlined,
                  variant: PillVariant.ghost,
                  expand: true,
                  onTap: usage.orphanCount == 0 || _busy ? null : _cleanOrphans,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                  label: _busy ? '处理中…' : '压缩大图',
                  icon: Icons.compress,
                  variant: PillVariant.dark,
                  expand: true,
                  onTap: _busy ? null : _compress,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BackupPage(storage: p.storage)),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 15, color: AppColors.inkSubtle),
                  SizedBox(width: 6),
                  Text('导出备份（含图片）',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted)),
                  Spacer(),
                  Icon(Icons.chevron_right,
                      size: 16, color: AppColors.inkSubtle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _largest(ImageUsage usage) {
    if (usage.largest.isEmpty) return const SizedBox.shrink();
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('占用最大的 5 个文件',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          const SizedBox(height: 10),
          for (final f in usage.largest)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(kImageKindNames[f.kind] ?? f.kind,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.inkMuted)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkSubtle,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                  Text(f.sizeLabel,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _privacyNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: AppColors.inkMuted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '图片全部存在本机 documents/wardrobe_images 目录，Hive 里只记路径。'
              '上传给 AI 前会先旋正、限制长边并重新编码，EXIF 里的定位与机型信息不会带出去。',
              style: TextStyle(
                  fontSize: 11, height: 1.65, color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text, {bool ok = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: (ok ? AppColors.lime : AppColors.warn).withValues(alpha: .18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.info_outline,
              size: 15, color: AppColors.ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, height: 1.5, color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}
