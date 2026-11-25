import 'package:flutter/widgets.dart';

/// Web 上没有文件系统，返回 null 由调用方回退到 base64。
Widget? fileImageWidget(
  String? path, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  Alignment alignment = Alignment.center,
}) =>
    null;
