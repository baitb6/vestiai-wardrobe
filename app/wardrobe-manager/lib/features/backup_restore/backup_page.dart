import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/wardrobe_provider.dart';
import '../../services/backup_service.dart';
import '../../services/image_store.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

/// 本地备份：导出 zip（JSON + 图片）、恢复、看占用
class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.storage});

  final StorageService storage;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  List<BackupEntry> _entries = [];
  bool _busy = false;
  int _usage = 0;
  String? _message;
  bool _messageOk = true;

  @override
  void initState() {
    super.initState();
    BackupService.instance.bind(widget.storage);
    _refresh();
  }

  Future<void> _refresh() async {
    final entries = await BackupService.instance.listBackups();
    final usage = await ImageStore.instance.usageBytes();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _usage = usage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: const Text('备份与恢复',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (!BackupService.instance.available)
            _notice('网页版没有文件系统，备份功能请在 App 内使用', ok: false),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('导出备份',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4,
                        color: AppColors.ink)),
                const SizedBox(height: 5),
                const Text(
                  '把一个 zip 存到手机上：里面是 data.json（衣物、搭配、OOTD）和所有照片。'
                  '换手机、重装都能用它恢复。',
                  style: TextStyle(fontSize: 11.5, height: 1.55, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _stat('${widget.storage.totalClothes}', '件衣物'),
                    const SizedBox(width: 16),
                    _stat('${(_usage / 1024 / 1024).toStringAsFixed(1)} MB', '图片占用'),
                  ],
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _busy ? null : _export,
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_busy)
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        else
                          const Icon(Icons.archive_outlined,
                              size: 16, color: Colors.white),
                        const SizedBox(width: 7),
                        Text(_busy ? '打包中…' : '导出全部数据',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // #17：导入备份——从系统文件选择器选 zip 恢复
                //（换手机/重装后把导出的 zip 找回来；同 ID 覆盖、新增追加）
                GestureDetector(
                  onTap: _busy ? null : _import,
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_busy)
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.ink),
                          )
                        else
                          const Icon(Icons.file_upload_outlined,
                              size: 16, color: AppColors.inkMuted),
                        const SizedBox(width: 7),
                        const Text('导入备份（选 zip 文件）',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.inkMuted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              '备份里有你的衣物照片和穿着记录，属于个人数据。分享或上传网盘前请自行评估风险；'
              '本应用不会自动上传任何备份。',
              style: TextStyle(fontSize: 11, height: 1.5, color: Color(0xFF8E2A1E)),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            _notice(_message!, ok: _messageOk),
          ],
          const SizedBox(height: 20),
          const SectionTitle('本机备份', eyebrow: 'ON THIS DEVICE'),
          const SizedBox(height: 10),
          if (_entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('还没有备份',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSubtle)),
            )
          else
            for (final e in _entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SoftCard(
                  padding: const EdgeInsets.all(13),
                  radius: 16,
                  child: Row(
                    children: [
                      const Icon(Icons.folder_zip_outlined,
                          size: 20, color: AppColors.inkMuted),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              '${e.sizeLabel} · ${_date(e.createdAt)}',
                              style: const TextStyle(
                                  fontSize: 10.5, color: AppColors.inkSubtle),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _busy ? null : () => _restore(e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text('恢复',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.inkMuted)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _share(e),
                        child: const Icon(Icons.ios_share,
                            size: 17, color: AppColors.inkSubtle),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -.6,
                color: AppColors.ink)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 10.5, color: AppColors.inkSubtle)),
      ],
    );
  }

  Widget _notice(String text, {required bool ok}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? AppColors.limeSoft : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: ok ? const Color(0xFF4C5A0F) : const Color(0xFF8E2A1E))),
    );
  }

  String _date(DateTime d) =>
      '${d.year}/${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _export() async {
    setState(() => _busy = true);
    final result = await BackupService.instance.export();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.message;
      _messageOk = result.ok;
    });
    await _refresh();
    if (result.ok && result.path != null) {
      await _sharePath(result.path!, result.message);
    }
  }

  Future<void> _share(BackupEntry e) =>
      _sharePath(e.path, '衣橱管家备份 ${e.name}');

  Future<void> _sharePath(String path, String text) async {
    try {
      await Share.shareXFiles([XFile(path)], text: text);
    } catch (_) {
      // 桌面/模拟器可能没有分享目标，不影响文件本身
    }
  }

  /// #17 从系统文件选择器选一个备份 zip 导入恢复（换手机/重装后找回导出的 zip）。
  /// image_picker 只能选图片选不了 zip，所以走 file_picker。
  /// 用户取消选择器时静默返回；选了但拿不到路径（网页版）才提示。
  Future<void> _import() async {
    if (_busy) return;
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
    } catch (_) {
      // 某些设备的系统选择器异常：按取消处理，不崩页面
      picked = null;
    }
    if (picked == null) return;
    final path =
        picked.files.isEmpty ? null : picked.files.single.path;
    if (path == null) {
      if (!mounted) return;
      setState(() {
        _message = '没有读到所选文件，请在 App 内选择 zip 备份';
        _messageOk = false;
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('导入这份备份？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(
          '同 ID 的衣物会被覆盖，新增的会追加。现有数据不会删除。\n\n'
          '${path.split('/').last}',
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入',
                  style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final result = await BackupService.instance.restore(path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.message;
      _messageOk = result.ok;
    });
    // 导入成功后同步 Provider：衣橱、日历、愿望清单立即看到恢复的数据
    if (result.ok) {
      await context.read<WardrobeProvider>().reloadFromStorage();
    }
    await _refresh();
  }

  Future<void> _restore(BackupEntry e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('恢复这份备份？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(
          '同 ID 的衣物会被覆盖，新增的会追加。现有数据不会删除。\n\n${e.name}',
          style: const TextStyle(fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('恢复', style: TextStyle(color: AppColors.primary))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final result = await BackupService.instance.restore(e.path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.message;
      _messageOk = result.ok;
    });
    // 把恢复进 Hive 的数据同步回 Provider，返回首页就能看到（含衣橱/愿望）
    if (result.ok) {
      await context.read<WardrobeProvider>().reloadFromStorage();
    }
    await _refresh();
  }
}
