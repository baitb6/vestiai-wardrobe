import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../models/models.dart';
import '../../services/file_bytes.dart';
import '../../services/platform_image.dart';
import '../../theme/app_theme.dart';

/// 单个识别出来的单品卡片：缩略图 + 可编辑字段 + 勾选/删除/合并
class SplitCandidateCard extends StatelessWidget {
  const SplitCandidateCard({
    super.key,
    required this.candidate,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onEditBox,
    required this.onRecut,
    required this.onToggle,
    this.onMerge,
    this.cutting = false,
  });

  final SplitCandidate candidate;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onEditBox;
  final VoidCallback onRecut;
  final VoidCallback onToggle;
  final VoidCallback? onMerge;
  final bool cutting;

  @override
  Widget build(BuildContext context) {
    final selected = candidate.selected;
    return Opacity(
      opacity: selected ? 1 : .5,
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        radius: 20,
        borderColor: selected ? AppColors.hairline : AppColors.hairline,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _thumb(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${ClothingCategory.names[candidate.category] ?? '单品'} · '
                              '${ClothingSubCategory.names[candidate.subCategory] ?? candidate.subCategory}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.2,
                                  color: AppColors.ink),
                            ),
                          ),
                          _check(selected),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        [
                          candidate.colors.isEmpty
                              ? '颜色未知'
                              : candidate.colors.join(' / '),
                          if (candidate.seasons.isNotEmpty)
                            candidate.seasons
                                .map((s) => Season.names[s] ?? s)
                                .join('·'),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _conf(candidate.confidence),
                          const SizedBox(width: 6),
                          if (candidate.userEdited)
                            const TagPill(
                              label: '已改',
                              dense: true,
                              background: AppColors.tagCool,
                              foreground: Color(0xFF2A5D9E),
                            ),
                          if (candidate.cutoutStatus == 'failed')
                            const TagPill(
                              label: '裁剪图',
                              dense: true,
                              background: AppColors.tagWarm,
                              foreground: Color(0xFFB4592E),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (candidate.duplicateHint != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.limeSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.content_copy,
                        size: 13, color: Color(0xFF5D6B12)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        candidate.duplicateHint!,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF5D6B12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (candidate.cutoutNote != null && candidate.cutoutStatus == 'failed')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  candidate.cutoutNote!,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.inkSubtle),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _action(Icons.edit_outlined, '改分类/颜色', onEdit),
                _action(Icons.crop_free, '调框', onEditBox),
                _action(Icons.refresh, cutting ? '处理中' : '重裁', cutting ? null : onRecut),
                if (onMerge != null) _action(Icons.merge_type, '合并', onMerge),
                _action(Icons.delete_outline, '删掉', onDelete, danger: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb() {
    final file = fileImageWidget(
      candidate.imagePath,
      fit: BoxFit.contain,
      width: 74,
      height: 74,
    );
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline),
          image: file == null
              ? null
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: file ??
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.inkSubtle),
              ),
            ),
      ),
    );
  }

  Widget _check(bool selected) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.hairline, width: 1.4),
        ),
        child: selected
            ? const Icon(Icons.check, size: 14, color: Colors.white)
            : null,
      ),
    );
  }

  Widget _conf(double v) {
    final pct = (v * 100).round();
    final color = v >= .8
        ? AppColors.ok
        : v >= .55
            ? AppColors.warn
            : AppColors.bad;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$pct%',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap,
      {bool danger = false}) {
    final color = onTap == null
        ? AppColors.inkSubtle
        : danger
            ? AppColors.bad
            : AppColors.inkMuted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

/// 编辑分类 / 颜色 / 风格 / 季节
class CandidateEditSheet extends StatefulWidget {
  const CandidateEditSheet({super.key, required this.candidate});

  final SplitCandidate candidate;

  @override
  State<CandidateEditSheet> createState() => _CandidateEditSheetState();
}

class _CandidateEditSheetState extends State<CandidateEditSheet> {
  late String _category;
  late String _sub;
  late List<String> _colors;
  late List<String> _styles;
  late List<String> _seasons;

  static const _palette = [
    '白', '黑', '灰', '米', '藏青', '牛仔蓝', '驼', '棕', '红', '粉', '绿', '黄', '紫'
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.candidate;
    _category = c.category;
    _sub = c.subCategory;
    _colors = [...c.colors];
    _styles = [...c.styleTags];
    _seasons = [...c.seasons];
  }

  @override
  Widget build(BuildContext context) {
    final subs = ClothingSubCategory.subCategories[_category] ?? const [];
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('修正识别结果',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                      color: AppColors.ink)),
              const SizedBox(height: 4),
              Text('改完直接入库，原始识别结果会留在 aiCategory 里',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
              const SizedBox(height: 16),
              _label('分类'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in ClothingCategory.names.entries)
                    _chip(e.value, _category == e.key, () {
                      setState(() {
                        _category = e.key;
                        final list =
                            ClothingSubCategory.subCategories[e.key] ?? const [];
                        if (!list.contains(_sub)) {
                          _sub = list.isEmpty ? 't_shirt' : list.first;
                        }
                      });
                    }),
                ],
              ),
              const SizedBox(height: 14),
              _label('细分'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in subs)
                    _chip(ClothingSubCategory.names[s] ?? s, _sub == s,
                        () => setState(() => _sub = s)),
                ],
              ),
              const SizedBox(height: 14),
              _label('颜色（点选主色）'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in _palette)
                    _chip(c, _colors.isNotEmpty && _colors.first == c, () {
                      setState(() {
                        _colors = [c, ..._colors.where((e) => e != c)];
                      });
                    }),
                ],
              ),
              const SizedBox(height: 14),
              _label('风格'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in StyleTag.names.entries)
                    _chip(e.value, _styles.contains(e.key), () {
                      setState(() {
                        _styles.contains(e.key)
                            ? _styles.remove(e.key)
                            : _styles.add(e.key);
                      });
                    }),
                ],
              ),
              const SizedBox(height: 14),
              _label('季节'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in Season.names.entries)
                    _chip(e.value, _seasons.contains(e.key), () {
                      setState(() {
                        _seasons.contains(e.key)
                            ? _seasons.remove(e.key)
                            : _seasons.add(e.key);
                      });
                    }),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text('取消',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkMuted)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () {
                        final result = SplitCandidate(
                          category: _category,
                          subCategory: _sub,
                          bbox: widget.candidate.bbox,
                          colors: _colors,
                          styleTags: _styles,
                          seasons: _seasons,
                          confidence: widget.candidate.confidence,
                          rawCategory: widget.candidate.rawCategory,
                          extraTags: widget.candidate.extraTags,
                        );
                        Navigator.pop(context, result);
                      },
                      child: Container(
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text('保存修改',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
                color: AppColors.inkSubtle)),
      );

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.ink : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.inkMuted)),
      ),
    );
  }
}

/// 全屏调整包围盒：拖动框体移动，拖右下角改大小
class BBoxEditorPage extends StatefulWidget {
  const BBoxEditorPage({
    super.key,
    required this.imagePath,
    required this.initial,
  });

  final String imagePath;
  final BBox initial;

  @override
  State<BBoxEditorPage> createState() => _BBoxEditorPageState();
}

class _BBoxEditorPageState extends State<BBoxEditorPage> {
  late BBox _box;
  Uint8List? _bytes;
  double _aspect = 1;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _box = widget.initial;
    _load();
  }

  Future<void> _load() async {
    final bytes = await readFileBytes(widget.imagePath);
    if (bytes != null) {
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.height > 0) {
        _aspect = decoded.width / decoded.height;
      }
    }
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        title: const Text('调整范围',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _box),
            child: const Text('完成',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    '拖动框体移动，拖右下角改大小。只框住这件衣物，不要带到旁边的东西。',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AspectRatio(
                        aspectRatio: _aspect,
                        child: LayoutBuilder(builder: (context, c) {
                          final w = c.maxWidth;
                          final h = c.maxHeight;
                          return GestureDetector(
                            onPanUpdate: (d) {
                              setState(() {
                                _box = _box.copyWith(
                                  x: _box.x + d.delta.dx / w,
                                  y: _box.y + d.delta.dy / h,
                                );
                              });
                            },
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _bytes == null
                                      ? Container(color: AppColors.surfaceAlt)
                                      : Image.memory(_bytes!, fit: BoxFit.fill),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _BoxPainter(_box),
                                  ),
                                ),
                                Positioned(
                                  left: _box.x * w,
                                  top: _box.y * h,
                                  width: _box.w * w,
                                  height: _box.h * h,
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: GestureDetector(
                                          onPanUpdate: (d) {
                                            setState(() {
                                              _box = _box.copyWith(
                                                w: _box.w + d.delta.dx / w,
                                                h: _box.h + d.delta.dy / h,
                                              );
                                            });
                                          },
                                          child: Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              color: AppColors.primary,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.open_in_full,
                                                size: 15, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Text(
                    '范围 ${(_box.w * 100).round()}% × ${(_box.h * 100).round()}%，'
                    '位置 (${(_box.x * 100).round()}%, ${(_box.y * 100).round()}%)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.inkSubtle),
                  ),
                ),
              ],
            ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.box);

  final BBox box;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
        box.x * size.width, box.y * size.height, box.w * size.width, box.h * size.height);
    final overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = const Color(0x8015110E),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.lime
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) => old.box != box;
}
