import 'dart:io';

import 'package:flutter/widgets.dart';

/// 本地文件图片。文件被删/损坏时回退成空白，不抛异常。
Widget? fileImageWidget(
  String? path, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  Alignment alignment = Alignment.center,
}) {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  return Image.file(
    file,
    fit: fit,
    width: width,
    height: height,
    alignment: alignment,
    gaplessPlayback: true,
    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
}
