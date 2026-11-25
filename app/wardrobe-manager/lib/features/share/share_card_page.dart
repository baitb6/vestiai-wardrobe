import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide MaterialType;
import 'package:flutter/rendering.dart';

import '../../data/clothing_naming.dart';
import '../../models/models.dart';
import '../../services/platform_image.dart';
import '../../services/share_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/clothing_card.dart';
import '../../widgets/kit.dart';

/// 穿搭分享卡：五种模板（#7 增补「杂志」「波普」两套），
/// 截图成 PNG 走系统分享。水印统一 VestiAI。
class ShareCardPage extends StatefulWidget {
  const ShareCardPage({
    super.key,
    required this.pieces,
    this.title = '今日穿搭',
    this.subtitle,
    this.occasion,
    this.date,
    this.initialTemplate = 0,
  });

  final List<Clothing> pieces;
  final String title;
  final String? subtitle;
  final String? occasion;
  final DateTime? date;

  /// 打开时默认选中的模板（0 海报 / 1 网格 / 2 极简 / 3 杂志 / 4 波普）
  final int initialTemplate;

  @override
  State<ShareCardPage> createState() => _ShareCardPageState();
}

class _ShareCardPageState extends State<ShareCardPage> {
  final GlobalKey _cardKey = GlobalKey();
  int _template = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _template = widget.initialTemplate.clamp(0, 4);
  }

  static const _templateNames = ['海报', '网格', '极简', '杂志', '波普'];

  DateTime get _date => widget.date ?? DateTime.now();

  /// #7 命名规则：调用方没自定义标题时，用「颜色+衣服名」自动命名
  String get _title {
    final t = widget.title.trim();
    if (t.isNotEmpty && t != '今日穿搭') return t;
    return outfitAutoName(widget.pieces, fallback: '今日穿搭');
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _cardKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final bytes = data.buffer.asUint8List();
      final name = 'look_${_date.millisecondsSinceEpoch}.png';
      final path = await ShareService.sharePng(
        bytes,
        fileName: name,
        text: '${_title} · VestiAI',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(path == null
              ? (ShareService.available
                  ? '分享失败，图片已生成在临时目录'
                  : '网页版暂不支持导出，请直接截图保存')
              : '已生成分享卡，选择一个应用发送'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pieces = widget.pieces.take(5).toList();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: const Text('分享穿搭',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: RepaintBoundary(
                  key: _cardKey,
                  child: SizedBox(
                    width: 320,
                    height: 426,
                    child: switch (_template) {
                      0 => _poster(pieces),
                      1 => _grid(pieces),
                      2 => _minimal(pieces),
                      3 => _magazine(pieces),
                      _ => _pop(pieces),
                    },
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  // 5 个模板 chip：窄屏放不下时横向滚动，不硬挤
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < _templateNames.length; i++) ...[
                          _templateChip(i),
                          if (i != _templateNames.length - 1)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  PillButton(
                    label: _busy ? '生成中…' : '保存并分享',
                    icon: Icons.ios_share,
                    variant: PillVariant.dark,
                    expand: true,
                    onTap: _busy ? null : _share,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '分享卡只包含这一套的图片与品类，不含价格、购买渠道等私密字段',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10.5, color: AppColors.inkSubtle),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateChip(int i) {
    final active = i == _template;
    return GestureDetector(
      onTap: () => setState(() => _template = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: active ? AppColors.ink : AppColors.hairline),
        ),
        child: Text(
          _templateNames[i],
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }

  // ---------- 模板 1：海报 ----------

  Widget _poster(List<Clothing> pieces) {
    return Container(
      color: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('TODAY\'S LOOK', color: Colors.white38, size: 8.5),
              const Spacer(),
              Text(_dateLabel(),
                  style: const TextStyle(fontSize: 9, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 30,
              height: 1.06,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.4,
              color: Colors.white,
            ),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Colors.white38)),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              children: [
                for (final c in pieces)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 54,
                              height: 54,
                              child: _pieceImage(c),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  c.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _metaOf(c),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 9.5, color: Colors.white38),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.lime,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(widget.occasion ?? '日常',
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ),
              const Spacer(),
              const Text('VestiAI',
                  style: TextStyle(
                      fontSize: 8, letterSpacing: 1.4, color: Colors.white30)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 模板 2：网格 ----------

  Widget _grid(List<Clothing> pieces) {
    return Container(
      color: const Color(0xFFF1E9DE),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dateLabel(),
            style: const TextStyle(
                fontSize: 9,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
                color: AppColors.inkSubtle),
          ),
          const SizedBox(height: 8),
          Text(
            _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
              color: AppColors.ink,
            ),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.inkMuted)),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                // pieces 可能为空（搭配里的单品被全部删掉）：
                // 列数按 1 兜底，避免除以 0 得到 NaN/Infinity 撑爆布局
                final columns =
                    pieces.length >= 4 ? 2 : pieces.length.clamp(1, 3);
                final rows = (pieces.length / columns).ceil();
                final w = (cons.maxWidth - (columns - 1) * 8) / columns;
                final h = (cons.maxHeight - (rows - 1) * 8) / rows;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in pieces)
                      SizedBox(
                        width: w,
                        height: h.clamp(60, 260),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _pieceImage(c),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                      8, 14, 8, 7),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: .55),
                                      ],
                                    ),
                                  ),
                                  child: Text(
                                    c.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(widget.occasion ?? '日常',
                  style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const Spacer(),
              const Text('VestiAI',
                  style: TextStyle(
                      fontSize: 8.5, color: AppColors.inkSubtle)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 模板 3：极简 ----------

  Widget _minimal(List<Clothing> pieces) {
    return Container(
      color: const Color(0xFFFAF6F1),
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('LOOKBOOK', size: 8.5),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_date.month}'.padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 76,
                  height: .86,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -5,
                  color: AppColors.ink.withValues(alpha: .12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Text(
                  '/${_date.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.inkSubtle),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: AppColors.ink,
            ),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 5),
            Text(widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 10.5, color: AppColors.inkMuted)),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              for (var i = 0; i < pieces.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                      right: 6, top: i.isOdd ? 10 : 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 46,
                      height: 58,
                      child: _pieceImage(pieces[i]),
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          // 深色大字水印，避免中段留白太空
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'VestiAI',
              style: TextStyle(
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: AppColors.ink.withValues(alpha: .07),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: AppColors.hairline),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                pieces.map((e) => e.color).take(3).join(' · '),
                style:
                    const TextStyle(fontSize: 8.5, color: AppColors.inkSubtle),
              ),
              const Spacer(),
              const Text('VestiAI',
                  style:
                      TextStyle(fontSize: 8.5, color: AppColors.inkSubtle)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 模板 4：杂志（#7 新增：白底 + 番茄红竖排点缀） ----------

  Widget _magazine(List<Clothing> pieces) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('VESTI AI LOOK', size: 8.5),
              const Spacer(),
              Text(_dateLabel(),
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.inkSubtle)),
            ],
          ),
          const SizedBox(height: 12),
          // 番茄红小竖条：杂志刊头的视觉锚
          Container(width: 34, height: 3.5, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(
            _title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 25,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.1,
              color: AppColors.ink,
            ),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 5),
            Text(widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5, color: AppColors.inkMuted)),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < pieces.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: _pieceImage(pieces[i]),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              clothingDisplayName(pieces[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink),
                            ),
                          ),
                          Text(_metaOf(pieces[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 9, color: AppColors.inkSubtle)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(height: 1, color: AppColors.hairline),
          const SizedBox(height: 9),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(widget.occasion ?? '日常',
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
              const Spacer(),
              const Text('VestiAI',
                  style: TextStyle(
                      fontSize: 8.5, color: AppColors.inkSubtle)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 模板 5：波普（#7 新增：墨黑底 + 酸性柠檬描边格子） ----------

  Widget _pop(List<Clothing> pieces) {
    return Container(
      color: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('OOTD POP', color: AppColors.lime, size: 8.5),
              const Spacer(),
              Text(_dateLabel(),
                  style: const TextStyle(
                      fontSize: 9, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 27,
              height: 1.08,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
              color: Colors.white,
            ),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 5),
            Text(widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 10.5, color: Colors.white38)),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, cons) {
                final columns = pieces.length >= 4 ? 2 : pieces.length.clamp(1, 3);
                final rows = (pieces.length / columns).ceil();
                final w = (cons.maxWidth - (columns - 1) * 8) / columns;
                final h = (cons.maxHeight - (rows - 1) * 8) / rows;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < pieces.length; i++)
                      SizedBox(
                        width: w,
                        height: h.clamp(56, 260),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _pieceImage(pieces[i]),
                              // 柠檬描边角标：波普感来自色块边框
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                      8, 14, 8, 7),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: .7),
                                      ],
                                    ),
                                    border: Border(
                                      bottom: BorderSide(
                                          color:
                                              AppColors.lime.withValues(alpha: .8),
                                          width: 2.5),
                                    ),
                                  ),
                                  child: Text(
                                    clothingDisplayName(pieces[i]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.lime,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(widget.occasion ?? '日常',
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink)),
              ),
              const Spacer(),
              const Text('VestiAI',
                  style: TextStyle(
                      fontSize: 8, letterSpacing: 1.4, color: Colors.white30)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 工具 ----------

  String _dateLabel() {
    const week = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return '${_date.year}.${_date.month.toString().padLeft(2, '0')}.'
        '${_date.day.toString().padLeft(2, '0')} ${week[_date.weekday - 1]}';
  }

  String _metaOf(Clothing c) {
    final parts = <String>[
      ClothingCategory.names[c.category] ?? c.category,
      c.color,
      if (c.material != null) MaterialType.name(c.material),
    ];
    return parts.where((e) => e.isNotEmpty).join(' · ');
  }

  Widget _pieceImage(Clothing c) {
    final local = c.displayImagePath;
    final file = fileImageWidget(local, fit: BoxFit.cover);
    if (file != null && local != null && local.isNotEmpty) return file;

    final url = c.imageUrl;
    if (url.startsWith('data:image')) {
      final comma = url.indexOf(',');
      if (comma != -1) {
        try {
          return Image.memory(base64Decode(url.substring(comma + 1)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _colorBlock(c));
        } catch (_) {
          return _colorBlock(c);
        }
      }
    }
    if (url.startsWith('http')) {
      return Image.network(url,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _colorBlock(c));
    }
    return _colorBlock(c);
  }

  Widget _colorBlock(Clothing c) {
    final base = clothingColor(c.color);
    final fg = base.computeLuminance() < 0.45 ? Colors.white : AppColors.ink;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, Colors.white, .12)!,
            Color.lerp(base, Colors.black, .08)!,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.checkroom,
        size: 20,
        color: fg.withValues(alpha: .55),
      ),
    );
  }
}

/// 打开分享卡
Future<void> showShareCard(
  BuildContext context, {
  required List<Clothing> pieces,
  String title = '今日穿搭',
  String? subtitle,
  String? occasion,
  DateTime? date,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ShareCardPage(
        pieces: pieces,
        title: title,
        subtitle: subtitle,
        occasion: occasion,
        date: date,
      ),
    ),
  );
}
