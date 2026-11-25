import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/clothing_naming.dart';
import '../../services/file_bytes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_clothing_sheet.dart';
import 'intake_provider.dart';

/// #2 后台入库任务列表：看进度、重试、自定义保存、删除。
/// 结构仿 split_task_list_page；失败任务给「重试 / 自定义保存」两条出口，
/// 不弹任何阻塞框。
class IntakeTaskListPage extends StatelessWidget {
  const IntakeTaskListPage({super.key, required this.provider});

  final IntakeProvider provider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<IntakeProvider>.value(
      value: provider,
      child: Consumer<IntakeProvider>(
        builder: (context, p, _) {
          final tasks = p.tasks;
          return Scaffold(
            backgroundColor: AppColors.canvas,
            appBar: AppBar(
              backgroundColor: AppColors.canvas,
              elevation: 0,
              title: const Text('快速入库任务',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
            ),
            floatingActionButton: FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _pick(context, p),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
              label: const Text('选图快速入库',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            body: Column(
              children: [
                _memoryHint(),
                Expanded(
                  child: tasks.isEmpty
                      ? const Center(
                          child: Text('还没有任务',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkSubtle)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                          itemCount: tasks.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) =>
                              _tile(context, p, tasks[i]),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 内存队列说明：重启即清空，已入库衣物不受影响
  Widget _memoryHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 14, color: AppColors.inkMuted),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                '上传后自动「识别 → 命名 → 抠图 → 白底 → 入库」，失败不弹窗，'
                '在这里重试或自定义保存。任务列表保存在内存里，重启 App 后自动清空，'
                '已入库的衣物不受影响。',
                style: TextStyle(
                    fontSize: 10.5, height: 1.5, color: AppColors.inkMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IntakeProvider p, IntakeTask t) {
    return SoftCard(
      padding: const EdgeInsets.all(13),
      radius: 16,
      borderColor: t.status == IntakeStatus.failed ? const Color(0x33D93B2B) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusDot(t.status),
              const SizedBox(width: 7),
              Text(
                t.status == IntakeStatus.running
                    ? t.stepLabel
                    : IntakeStatus.names[t.status] ?? t.status,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(_time(t.createdAt),
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.inkSubtle)),
            ],
          ),
          const SizedBox(height: 5),
          if (t.status == IntakeStatus.completed && t.draft != null)
            Text(
              '已入库 · ${clothingDisplayName(t.draft!)}',
              style: const TextStyle(
                  fontSize: 11.5, height: 1.45, color: AppColors.inkMuted),
            ),
          if (t.status == IntakeStatus.completed && t.draft == null)
            const Text('已完成',
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.inkMuted)),
          if (t.status == IntakeStatus.running)
            Text(
              '后台处理中（${t.stepLabel}），返回后可继续其他操作',
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.inkMuted),
            ),
          if (t.status == IntakeStatus.pending)
            const Text('排队中，一次处理一张，很快开始',
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.inkMuted)),
          if (t.errorMessage != null)
            Text(
              t.errorMessage!,
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: t.status == IntakeStatus.failed
                      ? AppColors.bad
                      : AppColors.inkMuted),
            ),
          if (t.note != null && t.note!.isNotEmpty)
            Text(
              t.note!,
              style: const TextStyle(
                  fontSize: 11, height: 1.45, color: AppColors.inkSubtle),
            ),
          const SizedBox(height: 9),
          Row(
            children: [
              if (t.status == IntakeStatus.failed) ...[
                _mini('重试', () => p.retryTask(t.id)),
                _mini('自定义保存', () => _customSave(context, t)),
              ],
              const Spacer(),
              _mini('删除', () => p.deleteTask(t.id), danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusDot(String status) {
    final color = status == IntakeStatus.failed
        ? AppColors.bad
        : status == IntakeStatus.completed
            ? AppColors.ok
            : AppColors.warn;
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _mini(String label, VoidCallback onTap, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: danger ? AppColors.bad : AppColors.inkMuted)),
      ),
    );
  }

  String _time(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    return '${t.month}/${t.day}';
  }

  // ---------- 动作 ----------

  Future<void> _pick(BuildContext context, IntakeProvider p) async {
    try {
      final picker = ImagePicker();
      final files =
          await picker.pickMultiImage(maxWidth: 1600, imageQuality: 88);
      final images = <({Uint8List bytes, String name})>[];
      for (final f in files) {
        images.add((bytes: await f.readAsBytes(), name: f.name));
      }
      if (images.isEmpty) return;
      final added = await p.enqueue(images);
      if (!context.mounted) return;
      if (added == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有加入队列：网页版或存储不可用')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加入后台队列 $added 张，可继续其他操作')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选图失败：$e')));
      }
    }
  }

  /// 失败出口二：跳到现有 add_clothing_sheet，预填原图与识别草稿
  Future<void> _customSave(BuildContext context, IntakeTask t) async {
    Uint8List? bytes;
    if (t.sourceImagePath.isNotEmpty) {
      try {
        bytes = await readFileBytes(t.sourceImagePath);
      } catch (_) {}
    }
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddClothingSheet(
        initialImageBytes: bytes,
        initialImagePath: bytes == null ? null : t.sourceImagePath,
        prefill: t.draft,
      ),
    );
  }
}
