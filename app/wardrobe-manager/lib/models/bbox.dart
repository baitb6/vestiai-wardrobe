/// 归一化包围盒（0-1 相对坐标），视觉模型返回的 bbox 统一用它承载。
///
/// 纯 Dart 实现，不依赖 dart:ui，方便在 isolate / 单元测试里用。
class BBox {
  /// 左上角 x（0-1）
  final double x;

  /// 左上角 y（0-1）
  final double y;

  /// 宽（0-1）
  final double w;

  /// 高（0-1）
  final double h;

  const BBox({required this.x, required this.y, required this.w, required this.h});

  static const BBox empty = BBox(x: 0, y: 0, w: 1, h: 1);

  /// 从模型返回的 JSON 解析，容忍 {x,y,w,h} / [x,y,w,h] / 百分比写法
  factory BBox.fromJson(dynamic raw) {
    if (raw is List && raw.length >= 4) {
      return BBox(
        x: _toUnit(raw[0]),
        y: _toUnit(raw[1]),
        w: _toUnit(raw[2]),
        h: _toUnit(raw[3]),
      ).clamped;
    }
    if (raw is Map) {
      double pick(List<String> keys) {
        for (final k in keys) {
          final v = raw[k];
          if (v is num) return v.toDouble();
          if (v is String) {
            final parsed = double.tryParse(v.replaceAll('%', ''));
            if (parsed != null) return parsed;
          }
        }
        return 0;
      }

      var x = pick(['x', 'left', 'x1']);
      var y = pick(['y', 'top', 'y1']);
      var w = pick(['w', 'width']);
      var h = pick(['h', 'height']);
      // 有些模型给 x1/y1/x2/y2
      final x2 = raw['x2'], y2 = raw['y2'];
      if (w == 0 && x2 is num) w = x2.toDouble() - x;
      if (h == 0 && y2 is num) h = y2.toDouble() - y;
      // 百分比（>1）自动归一
      if (x > 1 || y > 1 || w > 1 || h > 1) {
        x /= 100;
        y /= 100;
        w /= 100;
        h /= 100;
      }
      return BBox(x: x, y: y, w: w, h: h).clamped;
    }
    return empty;
  }

  static double _toUnit(dynamic v) {
    if (v is num) {
      final d = v.toDouble();
      return d > 1 ? d / 100 : d;
    }
    if (v is String) {
      final d = double.tryParse(v.replaceAll('%', '')) ?? 0;
      return d > 1 ? d / 100 : d;
    }
    return 0;
  }

  /// 夹到 0-1 内，并保证有最小面积
  BBox get clamped {
    var nx = x.clamp(0.0, 1.0);
    var ny = y.clamp(0.0, 1.0);
    var nw = w.clamp(0.02, 1.0);
    var nh = h.clamp(0.02, 1.0);
    if (nx + nw > 1) nw = (1 - nx).clamp(0.02, 1.0);
    if (ny + nh > 1) nh = (1 - ny).clamp(0.02, 1.0);
    return BBox(x: nx, y: ny, w: nw, h: nh);
  }

  BBox copyWith({double? x, double? y, double? w, double? h}) =>
      BBox(x: x ?? this.x, y: y ?? this.y, w: w ?? this.w, h: h ?? this.h)
          .clamped;

  double get area => w * h;

  double get right => x + w;

  double get bottom => y + h;

  /// 交集占比（用于判断两个框是否指向同一件衣物）
  double iou(BBox o) {
    final ix = (x > o.x ? x : o.x);
    final iy = (y > o.y ? y : o.y);
    final ir = (right < o.right ? right : o.right);
    final ib = (bottom < o.bottom ? bottom : o.bottom);
    if (ir <= ix || ib <= iy) return 0;
    final inter = (ir - ix) * (ib - iy);
    final union = area + o.area - inter;
    return union <= 0 ? 0 : inter / union;
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  @override
  String toString() =>
      'BBox(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, '
      '${w.toStringAsFixed(3)}, ${h.toStringAsFixed(3)})';
}
