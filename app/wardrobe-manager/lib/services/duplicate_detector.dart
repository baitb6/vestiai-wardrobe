import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// 重复命中
class DuplicateHit {
  final Clothing clothing;

  /// 0-1，越大越像
  final double similarity;

  /// 给用户看的一句话
  final String reason;

  DuplicateHit(this.clothing, this.similarity, this.reason);
}

/// 重复单品检测：感知哈希（aHash）为主，分类+颜色为兜底。
///
/// 只用于「提示可能已存在」，绝不阻止入库 —— 用户想加就加。
class DuplicateDetector {
  final Map<String, int?> _hashCache = {};

  /// 感知哈希缓存命中率低时也没关系，单次 40 件以内解码很快。
  static const int _maxCompare = 40;

  /// 汉明距离 <= 该值视为视觉相似
  static const int _similarDistance = 12;

  Future<DuplicateHit?> findBest({
    required Uint8List candidateBytes,
    required List<Clothing> existing,
    String? category,
    String? color,
  }) async {
    if (existing.isEmpty) return null;

    final candidateHash = _averageHash(candidateBytes);

    // 同分类优先，最多比 40 件
    final pool = [...existing]
      ..sort((a, b) {
        final sa = a.category == category ? 0 : 1;
        final sb = b.category == category ? 0 : 1;
        if (sa != sb) return sa - sb;
        return b.wearCount.compareTo(a.wearCount);
      });
    final limited = pool.take(_maxCompare).toList();

    DuplicateHit? best;
    if (candidateHash != null) {
      for (final c in limited) {
        final other = await _hashOf(c);
        if (other == null) continue;
        final dist = _hamming(candidateHash, other);
        if (dist > _similarDistance) continue;
        final sim = 1 - dist / 64;
        final sameCategory = c.category == category;
        final score = sim * (sameCategory ? 1.0 : 0.82);
        if (best == null || score > best.similarity) {
          best = DuplicateHit(
            c,
            score,
            sameCategory
                ? '图片和「${c.displayName}」很像（${(score * 100).round()}%）'
                : '图片轮廓和「${c.displayName}」相近（${(score * 100).round()}%）',
          );
        }
      }
    }

    if (best != null && best.similarity >= 0.78) return best;

    // 兜底：同分类 + 同颜色
    if (category != null && color != null && color.isNotEmpty) {
      for (final c in limited) {
        if (c.category != category) continue;
        if (!c.color.contains(color) && !color.contains(c.color)) continue;
        return DuplicateHit(
          c,
          0.62,
          '衣橱里已有同色同类的「${c.displayName}」，确认下是不是重复了',
        );
      }
    }
    return best != null && best.similarity >= 0.7 ? best : null;
  }

  // ---------- aHash ----------

  Future<int?> _hashOf(Clothing c) async {
    final key = c.displayImagePath ?? 'id:${c.id}';
    if (_hashCache.containsKey(key)) return _hashCache[key];

    Uint8List? bytes;
    final path = c.displayImagePath;
    if (path != null && path.isNotEmpty) {
      bytes = await _readFile(path);
    }
    if (bytes == null && c.imageUrl.isNotEmpty) {
      bytes = _tryBase64(c.imageUrl);
    }
    final hash = bytes == null ? null : _averageHash(bytes);
    _hashCache[key] = hash;
    return hash;
  }

  /// 文件读取交给调用方注入，避免这里 import dart:io（Web 也要能编译）
  Future<Uint8List?> Function(String path)? fileReader;

  Future<Uint8List?> _readFile(String path) async {
    final reader = fileReader;
    if (reader == null) return null;
    try {
      return await reader(path);
    } catch (e) {
      // 读不到就当没有本地图片，落到 base64 / 分类颜色兜底
      debugPrint('重复检测读取图片失败：$path ($e)');
      return null;
    }
  }

  Uint8List? _tryBase64(String data) {
    try {
      final raw = data.contains(',') ? data.split(',').last : data;
      return base64Decode(raw);
    } catch (e) {
      // imageUrl 不是合法 base64（可能是网络 URL）：只影响哈希比对，无碍
      debugPrint('重复检测 base64 解析失败，跳过该图：$e');
      return null;
    }
  }

  /// 8x8 灰度均值哈希，返回 64 位整数
  int? _averageHash(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final small = img.copyResize(decoded,
          width: 8, height: 8, interpolation: img.Interpolation.average);
      final values = <int>[];
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          final p = small.getPixel(x, y);
          values.add((p.r * 0.299 + p.g * 0.587 + p.b * 0.114).round());
        }
      }
      final mean = values.reduce((a, b) => a + b) / values.length;
      var hash = 0;
      for (var i = 0; i < 64; i++) {
        if (values[i] >= mean) hash |= (1 << i);
      }
      return hash;
    } catch (e) {
      // 解码/缩放失败：这张图算不出哈希，落到「同分类+同颜色」兜底提示
      debugPrint('重复检测计算哈希失败，跳过该图：$e');
      return null;
    }
  }

  int _hamming(int a, int b) {
    var x = a ^ b;
    var count = 0;
    while (x != 0) {
      count += x & 1;
      x >>= 1;
    }
    return count;
  }
}
