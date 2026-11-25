import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/wardrobe_provider.dart';
import '../../services/wardrobe_backend.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';

/// AI 服务状态（只读）。
///
/// 这里刻意不放任何输入框：模型、密钥、接口地址全部由管理员在后台统一配置，
/// 用户只需要知道「能不能用」。
class AiServicePage extends StatefulWidget {
  const AiServicePage({super.key});

  @override
  State<AiServicePage> createState() => _AiServicePageState();
}

class _AiServicePageState extends State<AiServicePage> {
  late final WardrobeBackend _backend;
  BackendConfig? _config;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _backend = WardrobeBackend(context.read<WardrobeProvider>().storage);
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);
    final cfg = force ? await _backend.refresh() : await _backend.config();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: const Text('AI 服务',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(force: true),
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '重新检测',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          const ScreenHeader(
            title: '由管理员统一开通',
            subtitle: '你不需要填写任何密钥或地址',
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (cfg == null)
            const SizedBox.shrink()
          else ...[
            _statusCard(cfg),
            const SizedBox(height: 14),
            SoftCard(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Column(
                children: [
                  _row(Icons.content_cut, 'AI 拆衣', '上传全身照，自动拆成单品',
                      cfg.online && cfg.vision),
                  const Divider(height: 1),
                  _row(Icons.insights_outlined, '风格建议', '按你的衣橱数据写建议',
                      cfg.online && cfg.text),
                  const Divider(height: 1),
                  _row(Icons.accessibility_new, '虚拟试穿', '把搭配穿到你的照片上',
                      cfg.online && cfg.edit),
                  const Divider(height: 1),
                  _row(
                    Icons.wallpaper_outlined,
                    '白底商品图',
                    cfg.whiteBgMode == 'server'
                        ? '由服务器生成，速度更快（单张图仅转发不保存）'
                        : '在手机上本地处理，照片不出手机',
                    cfg.online && cfg.whiteBgMode != 'off',
                    hint: cfg.online && cfg.whiteBgReady
                        ? null
                        : '当前走本地处理，不需要模型',
                  ),
                ],
              ),
            ),
            if (cfg.notice.isNotEmpty) ...[
              const SizedBox(height: 14),
              SoftCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.campaign_outlined,
                        size: 17, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(cfg.notice,
                          style: const TextStyle(
                              fontSize: 12.5, height: 1.5)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'AI 功能由衣橱管家服务端提供，模型与密钥由管理员维护。'
              '关闭或不可用时，记录衣物、搭配、打卡等核心功能不受影响。',
              style: TextStyle(
                  fontSize: 11.5, height: 1.6, color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(BackendConfig cfg) {
    final online = cfg.online;
    final color = !online
        ? AppColors.inkMuted
        : cfg.aiEnabled
            ? AppColors.ok
            : AppColors.warn;
    final title = !online
        ? '暂时连不上 AI 服务'
        : cfg.aiEnabled
            ? 'AI 服务已连接'
            : '管理员已暂停 AI 服务';
    final desc = !online
        ? (cfg.error.isEmpty ? '请检查网络后重试' : cfg.error)
        : cfg.aiEnabled
            ? (cfg.anyAi
                ? '下面标绿的功能可以直接使用'
                : '管理员正在配置模型，稍后再来看看')
            : '衣物管理、搭配、打卡都能正常使用';
    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              online && cfg.aiEnabled
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              color: color,
              size: 21,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(desc,
                    style: TextStyle(
                        fontSize: 12, height: 1.45, color: AppColors.inkMuted)),
              ],
            ),
          ),
          if (online)
            TextButton(
              onPressed: () => _load(force: true),
              child: const Text('刷新'),
            ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String title, String subtitle, bool ready,
      {String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.inkSubtle),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: ready
                  ? AppColors.ok.withValues(alpha: .12)
                  : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              ready ? '可用' : (hint ?? '未开通'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ready ? AppColors.ok : AppColors.inkSubtle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
