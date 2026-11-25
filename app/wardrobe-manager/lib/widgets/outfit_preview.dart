import 'dart:math' as math;
import 'package:flutter/material.dart' hide MaterialType;
import '../models/models.dart';
import '../services/insights_service.dart';
import '../theme/app_theme.dart';
import 'clothing_card.dart';

/// 一套穿搭的单品行：四个小方块 + 品类名
class OutfitPiecesRow extends StatelessWidget {
  const OutfitPiecesRow({
    super.key,
    required this.items,
    this.size = 74,
    this.onTap,
    this.fit = false,
  });

  final List<Clothing> items;
  final double size;
  final void Function(Clothing)? onTap;

  /// true = 一行铺满（最多 5 件等比压缩），适合卡片内的整套展示
  final bool fit;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (fit) {
      return SizedBox(
        height: size + 22,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: i == items.length - 1 ? 0 : 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: size,
                        width: double.infinity,
                        child: ClothingThumb(clothing: items[i], radius: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ClothingSubCategory.names[items[i].subCategory] ??
                            items[i].subCategory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return SizedBox(
      height: size + 22,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = items[i];
          return GestureDetector(
            onTap: onTap == null ? null : () => onTap!(c),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: size,
                  height: size,
                  child: ClothingThumb(clothing: c, radius: 16),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: size,
                  child: Text(
                    ClothingSubCategory.names[c.subCategory] ?? c.subCategory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 适配度 / 健康度圆环
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.value,
    this.size = 84,
    this.stroke = 8,
    this.color = AppColors.primary,
    this.label = '适配度',
    this.trackColor = AppColors.surfaceAlt,
    this.textColor = AppColors.ink,
    this.subColor = AppColors.inkSubtle,
  });

  /// 0–100
  final double value;
  final double size;
  final double stroke;
  final Color color;
  final String label;
  final Color trackColor;
  final Color textColor;
  final Color subColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
            value: value.clamp(0, 100) / 100,
            stroke: stroke,
            color: color,
            track: trackColor),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.round()}',
                  style: TextStyle(
                      fontSize: size * .28,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: textColor)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: size * .11,
                      fontWeight: FontWeight.w600,
                      color: subColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.color,
    required this.track,
  });

  final double value;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - stroke) / 2;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

/// 一周计划里的单日卡片
class DayPlanCard extends StatelessWidget {
  const DayPlanCard({super.key, required this.day, this.onTap});

  final DayPlan day;
  final VoidCallback? onTap;

  static const _week = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final d = day.date;
    final pieces = day.plan?.pieces ?? const <Clothing>[];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 92,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: day.isToday ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: day.isToday ? AppColors.ink : AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              day.isToday ? '今天' : '周${_week[(d.weekday - 1) % 7]}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: day.isToday ? AppColors.lime : AppColors.ink,
              ),
            ),
            const SizedBox(height: 1),
            Text('${d.month}/${d.day}',
                style: TextStyle(
                    fontSize: 9.5,
                    color: day.isToday
                        ? Colors.white54
                        : AppColors.inkSubtle)),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: pieces.isEmpty
                  ? Center(
                      child: Text('—',
                          style: TextStyle(
                              fontSize: 16,
                              color: day.isToday
                                  ? Colors.white30
                                  : AppColors.inkSubtle)),
                    )
                  : Row(
                      children: [
                        for (final c in pieces.take(3))
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: ClothingThumb(
                                  clothing: c,
                                  radius: 7,
                                  showStatus: false),
                            ),
                          ),
                        if (pieces.length < 3)
                          Expanded(child: const SizedBox()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
