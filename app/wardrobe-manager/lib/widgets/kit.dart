import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 英文小标（Eyebrow）
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text,
      {super.key, this.color = AppColors.inkSubtle, this.size = 10});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.2,
          color: color,
        ),
      );
}

/// 药丸按钮（主行动 / 次行动 / 亮色）
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.variant = PillVariant.dark,
    this.expand = false,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final PillVariant variant;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    late Color bg, fg;
    Border? border;
    switch (variant) {
      case PillVariant.dark:
        bg = AppColors.ink;
        fg = Colors.white;
        break;
      case PillVariant.primary:
        bg = AppColors.primary;
        fg = Colors.white;
        break;
      case PillVariant.lime:
        bg = AppColors.lime;
        fg = AppColors.ink;
        break;
      case PillVariant.ghost:
        bg = Colors.transparent;
        fg = AppColors.ink;
        border = Border.all(color: AppColors.hairline, width: 1.2);
        break;
    }
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 17, color: fg),
          const SizedBox(width: 7),
        ],
        Text(label,
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
      ],
    );
    // #9 按钮互动反馈：禁用（loading/连点保护）时降透明度，
    // 点得出来才看得见状态变化，不再「毫无反应」
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: onTap == null ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: expand ? 18 : 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(99),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

enum PillVariant { dark, primary, lime, ghost }

/// 数据小格：大数字 + 小标签
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.color = AppColors.ink,
    this.align = CrossAxisAlignment.start,
  });

  final String value;
  final String label;
  final String? unit;
  final Color color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 24,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: color)),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(unit!,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color.withValues(alpha: .6))),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.inkSubtle,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// 空状态插画位（用排版代替插画，避免引入图片资源）
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.desc,
    this.action,
    this.icon = Icons.checkroom,
  });

  final String title;
  final String? desc;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
                color: AppColors.surfaceAlt, shape: BoxShape.circle),
            child: Icon(icon, size: 28, color: AppColors.inkSubtle),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
          if (desc != null) ...[
            const SizedBox(height: 6),
            Text(desc!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.6, color: AppColors.inkMuted)),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 悬浮药丸导航栏
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.wb_sunny_outlined, Icons.wb_sunny, '今天'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, '衣橱'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, '搭配'),
    (Icons.calendar_today_outlined, Icons.calendar_today, '日历'),
    (Icons.person_outline, Icons.person, '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(99),
        boxShadow: AppColors.navShadow,
      ),
      child: Row(
        children: List.generate(_items.length, (i) {
          final active = i == index;
          final item = _items[i];
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: 46,
                decoration: BoxDecoration(
                  color: active ? AppColors.lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(active ? item.$2 : item.$1,
                        size: 19,
                        color: active ? AppColors.ink : Colors.white70),
                    const SizedBox(height: 2),
                    Text(item.$3,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                          color: active ? AppColors.ink : Colors.white70,
                        )),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 分节细线 + 小标题（用于卡片内部）
class MicroLabel extends StatelessWidget {
  const MicroLabel(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.inkSubtle)),
        ],
      );
}

/// 顶部固定 Header（大标题 + 可选的英文眉标 + 右侧动作）
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Eyebrow(eyebrow!),
                  const SizedBox(height: 6),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.1,
                          color: AppColors.ink,
                        )),
                    if (subtitle != null) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.inkSubtle),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 圆形图标按钮
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.dark = false,
    this.badge,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: dark ? AppColors.ink : AppColors.surface,
          shape: BoxShape.circle,
          border: dark ? null : Border.all(color: AppColors.hairline),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 19, color: dark ? Colors.white : AppColors.ink),
            if (badge != null)
              Positioned(
                right: 9,
                top: 9,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
