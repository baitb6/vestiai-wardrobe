import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/wardrobe_provider.dart';
import '../../services/gateway_profile.dart';
import '../../services/gateway_store.dart';
import '../../services/local_style_analyzer.dart';
import '../../services/style_digest.dart';
import '../../services/text_gateway_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';
import '../ai_gateway/ai_service_page.dart';

/// 风格分析：先给本地统计结论（秒出、不联网），
/// 再让用户按需触发 AI 深度解读。
class StyleAnalysisPage extends StatefulWidget {
  const StyleAnalysisPage({super.key, this.occasion, this.goal});

  /// 进入页面时预设的诉求（比如从体检页带「通勤」进来）
  final String? occasion;
  final String? goal;

  @override
  State<StyleAnalysisPage> createState() => _StyleAnalysisPageState();
}

class _StyleAnalysisPageState extends State<StyleAnalysisPage> {
  final _textService = TextGatewayService();
  StyleReport? _report;
  WardrobeDigest? _digest;
  bool _loading = false;
  bool _aiUsed = false;
  bool _gatewayReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runLocal();
      _checkGateway();
    });
  }

  void _runLocal() {
    final p = context.read<WardrobeProvider>();
    final digest = WardrobeDigest.from(
      clothes: p.allClothes,
      wishCount: p.wishCount,
      laundryCount: p.laundryItems.length,
    );
    setState(() {
      _digest = digest;
      _report = const LocalStyleAnalyzer().analyze(digest);
      _aiUsed = false;
      _error = null;
    });
  }

  Future<void> _checkGateway() async {
    final p = context.read<WardrobeProvider>();
    final store = GatewayStore(p.storage);
    final profile = await store.load(GatewayKind.text);
    if (!mounted) return;
    setState(() => _gatewayReady = profile.configured);
  }

  Future<void> _runAi() async {
    final p = context.read<WardrobeProvider>();
    final store = GatewayStore(p.storage);
    final profile = await store.load(GatewayKind.text);
    if (!mounted) return;
    if (!profile.configured) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('还没配文本模型',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          content: const Text(
            'AI 深度分析由管理员统一开通。只会发送衣橱统计摘要（不含照片）。',
            style: TextStyle(
                fontSize: 12.5, height: 1.6, color: AppColors.inkMuted),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('先用本地的')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('查看 AI 服务'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const AiServicePage()));
        if (mounted) await _checkGateway();
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final key = await store.readKey(GatewayKind.text);
      final report = await _textService.analyzeStyle(
        digest: _digest ?? WardrobeDigest.from(clothes: p.allClothes),
        profile: profile,
        apiKey: key,
        occasion: widget.occasion,
        goal: widget.goal,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _aiUsed = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    final report = _report;
    final digest = _digest;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: '风格画像',
              eyebrow: 'STYLE',
              subtitle: _aiUsed
                  ? '由你配置的文本模型生成 · 可点重算'
                  : '基于本地统计的快速诊断',
              actions: [
                RoundIconButton(
                  icon: _aiUsed ? Icons.refresh : Icons.auto_awesome,
                  onTap: _loading ? null : _runAi,
                  dark: !_aiUsed,
                ),
                const SizedBox(width: 8),
                RoundIconButton(
                  icon: Icons.close,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: AppColors.primary,
                ),
              ),
            Expanded(
              child: p.allClothes.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                      children: [
                        EmptyState(
                          title: '先有几件衣服再分析',
                          desc: '录入 5 件以上，结论才有参考价值。',
                          icon: Icons.checkroom,
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      children: [
                        if (_error != null) _errorCard(),
                        if (report != null) ...[
                          _personaCard(report),
                          const SizedBox(height: 14),
                          if (digest != null) _digestRow(digest),
                          if (report.styleMix.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            const MicroLabel('风格构成'),
                            const SizedBox(height: 10),
                            _mixCard(report.styleMix),
                          ],
                          if (report.strengths.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            const MicroLabel('你做得好的地方'),
                            const SizedBox(height: 10),
                            _bulletCard(report.strengths,
                                icon: Icons.check_circle,
                                color: const Color(0xFF3F9D5A)),
                          ],
                          if (report.gaps.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            const MicroLabel('结构缺口'),
                            const SizedBox(height: 10),
                            _gapsCard(report.gaps),
                          ],
                          if (report.colorStory.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            const MicroLabel('配色诊断'),
                            const SizedBox(height: 10),
                            _quoteCard(report.colorStory),
                          ],
                          if (report.buyNext.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            Row(
                              children: [
                                const Expanded(child: MicroLabel('可以考虑入手')),
                                Text('${report.buyNext.length} 条',
                                    style: const TextStyle(
                                        fontSize: 10.5,
                                        color: AppColors.inkSubtle)),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ...report.buyNext.map((b) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _buyCard(b),
                                )),
                          ],
                          if (report.avoid.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _avoidCard(report.avoid),
                          ],
                          const SizedBox(height: 20),
                          _footer(report),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 17, color: AppColors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _runAi,
                  child: const Text('再试一次',
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

  Widget _personaCard(StyleReport r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _aiUsed ? AppColors.lime : Colors.white24,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _aiUsed ? 'AI 深度' : '本地诊断',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: _aiUsed ? AppColors.ink : Colors.white,
                    letterSpacing: .5,
                  ),
                ),
              ),
              const Spacer(),
              if (!_aiUsed && _gatewayReady)
                GestureDetector(
                  onTap: _loading ? null : _runAi,
                  child: const Text('用 AI 再深看一层 →',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.lime)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            r.persona,
            style: const TextStyle(
              fontSize: 24,
              height: 1.3,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _aiUsed ? '结论来自你的衣橱统计，不评价身材与长相。' : 'AI 没开通也能用：结论完全由本地数据推导。',
            style: const TextStyle(
                fontSize: 11, height: 1.5, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _digestRow(WardrobeDigest d) {
    return Row(
      children: [
        Expanded(
          child: _miniStat('${d.total}', '件单品'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat('${(d.utilization * 100).round()}%', '利用率'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat('${d.neverWorn}', '没穿过'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniStat('${d.idle90d}', '闲置 90 天'),
        ),
      ],
    );
  }

  Widget _miniStat(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.inkSubtle,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _mixCard(List<StyleMix> mix) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: mix.map((m) {
          final pct = (m.ratio * 100).round();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(m.name,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    Text('$pct%',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.inkMuted)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: m.ratio.clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceAlt,
                    color: pct >= 40 ? AppColors.primary : AppColors.ink,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _bulletCard(List<String> items,
      {required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: items
            .map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(icon, size: 14, color: color),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(t,
                            style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.55,
                                color: AppColors.ink,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _gapsCard(List<StyleGap> gaps) {
    return Column(
      children: gaps.map((g) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  ClothingCategory.icons[_categoryOf(g.category)] ?? '＋',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.category,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    if (g.reason.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(g.reason,
                          style: const TextStyle(
                              fontSize: 11.3,
                              height: 1.45,
                              color: AppColors.inkMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _quoteCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12.5,
              height: 1.7,
              color: AppColors.ink,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _buyCard(BuySuggestion b) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          if (b.isHigh)
            Container(
              width: 3,
              height: 34,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.item,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                if (b.why.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(b.why,
                      style: const TextStyle(
                          fontSize: 11.2,
                          height: 1.45,
                          color: AppColors.inkMuted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _addToWish(b),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('加进清单',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avoidCard(List<String> items) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🛑', style: TextStyle(fontSize: 13)),
              SizedBox(width: 7),
              Text('先别急着买',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: .3)),
            ],
          ),
          const SizedBox(height: 9),
          ...items.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('· $t',
                    style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: Colors.white70)),
              )),
        ],
      ),
    );
  }

  Widget _footer(StyleReport r) {
    return Center(
      child: Text(
        _aiUsed
            ? 'AI 建议仅供参考，钱还是你花'
            : '本地规则看的是结构，不是审美',
        style: const TextStyle(fontSize: 10.5, color: AppColors.inkSubtle),
      ),
    );
  }

  Future<void> _addToWish(BuySuggestion b) async {
    final p = context.read<WardrobeProvider>();
    final now = DateTime.now();
    final category = _categoryOf(b.item);
    await p.addWish(WishItem(
      id: 'wish_${now.millisecondsSinceEpoch}',
      name: b.item,
      category: category,
      color: _colorOf(b.item),
      priority: b.isHigh ? 2 : 1,
      note: b.why.isEmpty ? null : b.why,
      createdAt: now,
      cooldownUntil:
          now.add(const Duration(days: WardrobeProvider.wishCooldownDays)),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已加入愿望清单：${b.item}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 从建议文案里猜分类：够用即可，猜错用户能在清单里改
  String _categoryOf(String text) {
    const map = {
      ClothingCategory.tops: ['衬衫', 'T恤', '针织', '卫衣', '上衣', '毛衣', 'polo'],
      ClothingCategory.bottoms: ['裤', '牛仔', '裙裤'],
      ClothingCategory.dress: ['连衣裙', '裙子', '吊带裙'],
      ClothingCategory.outerwear: ['外套', '大衣', '夹克', '西装', '风衣', '羽绒'],
      ClothingCategory.shoes: ['鞋', '靴', '乐福', '板鞋', '运动鞋'],
      ClothingCategory.accessories: ['包', '帽', '围巾', '腰带', '首饰', '表'],
    };
    for (final e in map.entries) {
      for (final k in e.value) {
        if (text.contains(k)) return e.key;
      }
    }
    return ClothingCategory.tops;
  }

  String? _colorOf(String text) {
    const colors = ['黑', '白', '灰', '米', '驼', '藏青', '蓝', '绿', '红', '棕', '黄', '粉', '紫'];
    for (final c in colors) {
      if (text.contains(c)) {
        return c == '蓝'
            ? '蓝色'
            : c == '绿'
                ? '绿色'
                : c == '红'
                    ? '红色'
                    : c == '棕'
                        ? '棕色'
                        : c == '黄'
                            ? '黄色'
                            : c == '粉'
                                ? '粉色'
                                : c == '紫'
                                    ? '紫色'
                                    : '$c色';
      }
    }
    return null;
  }
}
