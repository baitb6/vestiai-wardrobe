import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import 'auto_split_provider.dart';

/// 拆分任务历史：看状态、重试、删任务、翻原始响应
class SplitTaskListPage extends StatelessWidget {
  const SplitTaskListPage({super.key, required this.provider});

  final AutoSplitProvider provider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AutoSplitProvider>.value(
      value: provider,
      child: Consumer<AutoSplitProvider>(
        builder: (context, p, _) {
          final tasks = p.tasks;
          return Scaffold(
            backgroundColor: AppColors.canvas,
            appBar: AppBar(
              backgroundColor: AppColors.canvas,
              elevation: 0,
              title: const Text('拆分记录',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
            ),
            body: tasks.isEmpty
                ? const Center(
                    child: Text('还没有记录',
                        style: TextStyle(fontSize: 12.5, color: AppColors.inkSubtle)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final t = tasks[i];
                      return SoftCard(
                        padding: const EdgeInsets.all(13),
                        radius: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _statusDot(t.status),
                                const SizedBox(width: 7),
                                Text(
                                  SplitStatus.names[t.status] ?? t.status,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800),
                                ),
                                const Spacer(),
                                Text(_time(t.createdAt),
                                    style: const TextStyle(
                                        fontSize: 10.5,
                                        color: AppColors.inkSubtle)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              t.errorMessage ??
                                  '识别 ${t.itemCount ?? 0} 件'
                                      '${(t.importedCount ?? 0) > 0 ? ' · 入库 ${t.importedCount} 件' : ''}',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.45,
                                color: t.status == SplitStatus.failed
                                    ? AppColors.bad
                                    : AppColors.inkMuted,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                if (t.status == SplitStatus.failed)
                                  _mini('重试', () => p.retryTask(t.id)),
                                if (t.resultJson != null)
                                  _mini('原始响应', () => _showRaw(context, t)),
                                const Spacer(),
                                _mini('删除', () => p.deleteTask(t.id),
                                    danger: true),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  Widget _statusDot(String status) {
    final color = status == SplitStatus.failed
        ? AppColors.bad
        : status == SplitStatus.success
            ? AppColors.warn
            : status == SplitStatus.imported
                ? AppColors.ok
                : AppColors.inkSubtle;
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

  void _showRaw(BuildContext context, SplitTask t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (_, ctrl) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('模型原始响应',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  controller: ctrl,
                  child: SelectableText(
                    t.resultJson ?? '',
                    style: const TextStyle(fontSize: 11, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
