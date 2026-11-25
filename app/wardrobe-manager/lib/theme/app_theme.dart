import 'package:flutter/material.dart';

/// 衣橱管家 · 「Editorial Pop」设计系统
///
/// 面向 18–30 岁用户：奶油纸感底色 + 高对比墨黑 + 番茄红主色 + 酸性柠檬点缀。
/// 设计原则：
/// - 大字号、紧字距的标题像时尚杂志封面，正文克制
/// - 卡片一律白底大圆角（24）+ 1px 暖色描边，不用重阴影
/// - 强调色只出现在「行动」与「数据」上，底色保持安静
/// - 药丸标签、超大数字、细线分隔，构成年轻但不幼稚的语汇
class AppColors {
  // ---- 底色 ----
  static const canvas = Color(0xFFFAF6F1); // 奶油纸
  static const canvasTop = Color(0xFFFFFBF6);
  static const canvasBottom = Color(0xFFF5EEE4);

  // ---- 卡片 ----
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF4EEE6); // 次级填充 / 输入框
  static const hairline = Color(0xFFECE2D5);

  // ---- 文字 ----
  static const ink = Color(0xFF15110E); // 近黑
  static const inkMuted = Color(0xFF6F655A); // 暖灰
  static const inkSubtle = Color(0xFFA2968A); // 弱化

  // ---- 主色 ----
  static const primary = Color(0xFFFF3B2F); // 番茄红
  static const primarySoft = Color(0xFFFFE7E3);
  static const accent = Color(0xFF5B4BE8); // 电紫
  static const accentSoft = Color(0xFFEAE7FF);
  static const lime = Color(0xFFD8F651); // 酸性柠檬（仅用于墨黑底）
  static const limeSoft = Color(0xFFF2FCC0);

  // ---- 语义 ----
  static const ok = Color(0xFF1E9E6A);
  static const warn = Color(0xFFC8811A);
  static const bad = Color(0xFFD93B2B);

  // ---- 材质 / 标签底色（低饱和暖色系）----
  static const tagWarm = Color(0xFFFFEDE4);
  static const tagCool = Color(0xFFE6F1FB);
  static const tagNeutral = Color(0xFFF0ECE5);
  static const tagSport = Color(0xFFEDE9FF);

  /// 卡片阴影：极轻，只做分界
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0F15110E),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  /// 悬浮导航阴影
  static const List<BoxShadow> navShadow = [
    BoxShadow(
      color: Color(0x1F15110E),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// 页面背景渐变
  static const LinearGradient pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [canvasTop, canvasBottom],
  );

  /// 墨黑底上的渐变（英雄卡片）
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF221C16), Color(0xFF15110E)],
  );
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.canvas,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        onPrimary: Colors.white,
        error: AppColors.bad,
      ),
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme
          .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
          .copyWith(
            displaySmall: const TextStyle(
              fontSize: 32,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
              color: AppColors.ink,
            ),
            titleLarge: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.ink,
            ),
            titleMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: AppColors.ink,
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.ink,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: AppColors.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.hairline, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.ink,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? Colors.white : AppColors.inkSubtle,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.ink : AppColors.inkSubtle,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        hintStyle: const TextStyle(color: AppColors.inkSubtle, fontSize: 13.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(0, 46),
          side: const BorderSide(color: AppColors.hairline, width: 1.2),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.hairline),
        labelStyle: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600),
        selectedColor: AppColors.ink,
        secondarySelectedColor: AppColors.ink,
        showCheckmark: false,
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.inkMuted,
        textColor: AppColors.ink,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}

/// 主力卡片：白底大圆角 + 暖色 hairline
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
    this.radius = 24,
    this.onTap,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.hairline, width: 1),
        boxShadow: shadow ? AppColors.cardShadow : null,
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: body,
      ),
    );
  }
}

/// 药丸标签
class TagPill extends StatelessWidget {
  const TagPill({
    super.key,
    required this.label,
    this.background = AppColors.surfaceAlt,
    this.foreground = AppColors.inkMuted,
    this.icon,
    this.iconEmoji,
    this.border = false,
    this.dense = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final String? iconEmoji;
  final bool border;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 9 : 11, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
        border: border
            ? Border.all(color: foreground.withValues(alpha: .18), width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconEmoji != null) ...[
            Text(iconEmoji!, style: TextStyle(fontSize: dense ? 10 : 11)),
            const SizedBox(width: 4),
          ],
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 12.5, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// 段落标题：中文粗体 + 可选英文小标
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.eyebrow});

  final String text;
  final Widget? trailing;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (eyebrow != null) ...[
              Text(
                eyebrow!.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  color: AppColors.inkSubtle,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              text,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
