import 'dart:math' as math;

import 'package:flutter/material.dart' hide MaterialType;
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/wardrobe_provider.dart';
import '../../services/platform_image.dart';
import '../../theme/app_theme.dart';

/// 3D 数字衣橱。
///
/// 实现说明（务必如实告知用户）：
/// 这里做的是「真 3D 空间里的环形陈列」——用 Matrix4 透视变换把真实衣物
/// 图片摆在一条椭圆轨道上，可拖拽旋转、近大远小、前后遮挡。
/// 真正的 3D 网格模型（.glb 衣服模型 + 骨骼）需要美术资源，
/// 属于独立的美术管线，不在本轮范围内，页面底部也写明了这一点。
class VirtualClosetPage extends StatefulWidget {
  const VirtualClosetPage({super.key});

  @override
  State<VirtualClosetPage> createState() => _VirtualClosetPageState();
}

class _VirtualClosetPageState extends State<VirtualClosetPage>
    with SingleTickerProviderStateMixin {
  double _angle = 0;
  double _dragStartAngle = 0;
  double _lastVelocity = 0;
  String? _category;
  Clothing? _focused;

  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..addListener(_tick);

  bool _autoSpin = true;
  double _spinSpeed = 0.004;

  void _tick() {
    if (!_autoSpin || _focused != null) return;
    setState(() => _angle += _spinSpeed);
  }

  @override
  void initState() {
    super.initState();
    _idle.repeat();
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<WardrobeProvider>();
    // 不按有没有照片过滤：没有照片的单品用 emoji 占位，照样能陈列
    var items = p.allClothes.toList();
    if (_category != null) {
      items = items.where((c) => c.category == _category).toList();
    }
    // 一屏 6 件：转盘上再多就会互相压住
    items = items.take(6).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0E0A08),
      body: SafeArea(
        child: Column(
          children: [
            _header(items.length, p),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .06),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.checkroom,
                                size: 30, color: Colors.white30),
                          ),
                          const SizedBox(height: 16),
                          const Text('衣橱是空的',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                          const SizedBox(height: 6),
                          const Text('先录入几件单品，转盘才有东西可转',
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.white38)),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, c) => _stage(c, items),
                    ),
            ),
            _bottomBar(p),
          ],
        ),
      ),
    );
  }

  Widget _header(int count, WardrobeProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DIGITAL CLOSET',
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                        color: AppColors.lime)),
                SizedBox(height: 4),
                Text('3D 衣橱',
                    style: TextStyle(
                        fontSize: 24,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: Colors.white)),
                SizedBox(height: 4),
                Text('拖动旋转 · 点一件看细节',
                    style: TextStyle(fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$count',
                  style: const TextStyle(
                      fontSize: 26,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
              const Text('件在展台',
                  style: TextStyle(fontSize: 9.5, color: Colors.white38)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      size: 17, color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stage(BoxConstraints c, List<Clothing> items) {
    final n = items.length;
    final cx = c.maxWidth / 2;
    // 椭圆轨道：横向铺得开，纵向压扁，才有「俯看转盘」的感觉
    // #3 修框：轨道半径再扣掉半张卡宽，保证最前面的卡片（104*scale）
    // 也不越出屏幕——之前 cx+196+52 在 360dp 屏上直接溢出 100+px，
    // 卡片被屏幕边缘裁掉一半，看起来就是「框不对」。
    final radiusX = math.min(
        math.min(c.maxWidth * 0.44, 196.0), c.maxWidth / 2 - 62);
    final radiusY = 58.0;
    final centerY = c.maxHeight * 0.46;

    // 按 depth 排序，远的先画，近的盖在上面
    final placed = <_Placed>[];
    for (var i = 0; i < n; i++) {
      final theta = _angle + i * (2 * math.pi / n);
      final depth = math.cos(theta); // 1 最近，-1 最远
      final x = cx + math.sin(theta) * radiusX;
      // 近的靠下、远的靠上，才有俯视角
      // 卡片底边落在椭圆台面上：近的下沉、远的抬高，形成转盘
      final y = centerY + depth * radiusY;
      // 指数曲线让正前方这件明显更大，空间感靠这个撑起来
      final scale = 0.42 + 0.58 * math.pow((depth + 1) / 2, 1.5);
      placed.add(_Placed(
        item: items[i],
        theta: theta,
        depth: depth,
        x: x,
        y: y,
        scale: scale,
      ));
    }
    placed.sort((a, b) => a.depth.compareTo(b.depth));

    const cardW = 104.0;
    const cardH = 136.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        _dragStartAngle = _angle;
        _lastVelocity = 0;
        setState(() => _autoSpin = false);
      },
      onHorizontalDragUpdate: (d) {
        setState(() {
          _angle = _dragStartAngle + d.localPosition.dx / radiusX;
          _lastVelocity = d.delta.dx;
        });
      },
      onHorizontalDragEnd: (_) {
        // 给一点惯性：按拖动速度多转一点点，然后恢复慢速自转
        setState(() {
          _angle += _lastVelocity.clamp(-14, 14) * 0.012;
          _autoSpin = true;
        });
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 地面光晕
          Positioned(
            left: cx - radiusX * 1.15,
            top: centerY - radiusY,
            width: radiusX * 2.3,
            height: radiusY * 2,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: .2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // 转盘台面：一个压扁的椭圆，卡片底边落在它的边缘上
          Positioned(
            left: cx - radiusX,
            top: centerY - radiusY - 10,
            width: radiusX * 2,
            height: radiusY * 2 + 20,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: .05),
                    Colors.white.withValues(alpha: .01),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.72, 1.0],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .10),
                  width: 1,
                ),
              ),
            ),
          ),
          ...placed.map((pl) {
            final opacity = (0.32 + 0.68 * ((pl.depth + 1) / 2)).clamp(0.0, 1.0);
            final w = cardW * pl.scale;
            final h = cardH * pl.scale;
            return Positioned(
              left: pl.x - w / 2,
              // 底边贴住台面
              top: pl.y - h,
              width: w,
              height: h,
              child: Opacity(
                opacity: opacity,
                child: _Card(
                  item: pl.item,
                  // 侧一点的角度，视觉上更立体
                  tilt: math.sin(pl.theta) * 0.34,
                  active: pl.depth > 0.55,
                  onTap: () => setState(() {
                    _focused = pl.item;
                    _autoSpin = false;
                  }),
                ),
              ),
            );
          }),
          if (_focused != null) _focusOverlay(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            child: Center(
              child: Text(
                _category == null
                    ? '全部 · 拖动换角度'
                    : '${ClothingCategory.names[_category] ?? ''} · 拖动换角度',
                style: const TextStyle(fontSize: 10, color: Colors.white24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 点开单件：卡片下方浮出信息条，不打断旋转上下文
  Widget _focusOverlay() {
    final c = _focused!;
    final img = fileImageWidget(c.displayImagePath, fit: BoxFit.contain);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() {
          _focused = null;
          _autoSpin = true;
        }),
        child: Container(
          color: Colors.black.withValues(alpha: .72),
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: img ??
                      Text(ClothingCategory.icons[c.category] ?? '👕',
                          style: const TextStyle(fontSize: 80)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                c.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.4,
                    color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  ClothingCategory.names[c.category] ?? c.category,
                  c.color,
                  if (c.material != null) MaterialType.name(c.material),
                  '穿 ${c.wearCount} 次',
                ].join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: Colors.white54),
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('点击任意处返回',
                    style:
                        TextStyle(fontSize: 10.5, color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(WardrobeProvider p) {
    final cats = <String?>[null, ...ClothingCategory.names.keys];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, i) {
                final cat = cats[i];
                final on = _category == cat;
                final label =
                    cat == null ? '全部' : ClothingCategory.names[cat] ?? cat;
                final n = cat == null
                    ? p.allClothes.length
                    : p.allClothes.where((c) => c.category == cat).length;
                return GestureDetector(
                  onTap: () => setState(() {
                    _category = cat;
                    _focused = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on
                          ? AppColors.lime
                          : Colors.white.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$label $n',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: on ? AppColors.ink : Colors.white60,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 12, color: Colors.white30),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '环形 3D 陈列基于真实单品图；单件 3D 模型需要美术资源，暂未接入',
                  style: TextStyle(fontSize: 9.5, color: Colors.white30),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _autoSpin = !_autoSpin),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _autoSpin ? '暂停旋转' : '自动旋转',
                    style: const TextStyle(
                        fontSize: 10, color: Colors.white54),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Placed {
  final Clothing item;
  final double theta;
  final double depth;
  final double x;
  final double y;
  final double scale;

  _Placed({
    required this.item,
    required this.theta,
    required this.depth,
    required this.x,
    required this.y,
    required this.scale,
  });
}

class _Card extends StatelessWidget {
  const _Card({
    required this.item,
    required this.tilt,
    required this.active,
    required this.onTap,
  });

  final Clothing item;
  final double tilt;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // #3 修框：抠图 PNG 大多自带透明留白，cover 会把衣身裁掉一截；
    // 改 contain 整件入框，深色渐变底吃掉 letterbox，观感更完整
    final img = fileImageWidget(item.displayImagePath, fit: BoxFit.contain);
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0015)
      ..rotateY(tilt);

    return GestureDetector(
      onTap: onTap,
      child: Transform(
        transform: transform,
        alignment: Alignment.center,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? AppColors.lime.withValues(alpha: .55)
                  : Colors.white.withValues(alpha: .12),
              width: active ? 1.4 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.lime.withValues(alpha: .12),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2B221C), Color(0xFF17120F)],
                  ),
                ),
                alignment: Alignment.center,
                child: img ??
                    Text(
                      ClothingCategory.names[item.category] ?? '单品',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: Colors.white
                            .withValues(alpha: active ? .72 : .42),
                      ),
                    ),
              ),
              // 底部渐变 + 名称，保证在深色底上读得清
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: .78),
                      ],
                    ),
                  ),
                  child: Text(
                    '${item.color} ${ClothingCategory.names[item.category] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
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
