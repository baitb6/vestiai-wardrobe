import 'dart:typed_data';

import '../models/bbox.dart';
import 'cutout_service.dart';
import 'gateway_profile.dart';
import 'local_white_bg.dart';
import 'wardrobe_backend.dart';
import 'white_background_service.dart';

/// 白底图第二步（生成模型美化）的提示词意图常量：
/// 保持款式、纹理、印花不变，纯白背景，规整的商品平铺图。
/// server 模式由后台实现同义提示词；直连网关模式由
/// [WhiteBackgroundService.buildPrompt] 落成模型提示词（其内容与本常量一致）。
const String kWhiteBgBeautifyPrompt =
    '保持款式、纹理、印花不变，纯白背景，规整的商品平铺图';

/// 两步开关：分割（本地抠图）与美化（生成模型）各自可关。
class WhiteBgSteps {
  /// 第一步：本地分割抠图，产出「透明底衣服图」。
  final bool segment;

  /// 第二步：生成模型美化，产出白底商品图。
  final bool beautify;

  const WhiteBgSteps({this.segment = true, this.beautify = true});
}

/// 流水线结果。每一步独立降级，绝不抛异常阻断主流程。
class WhiteBgResult {
  /// 最终图片字节（可能是模型白底图 / 透明底分割图 / 原图）
  final Uint8List bytes;

  /// true = 第一步成功产出透明底衣服图
  final bool segmented;

  /// true = 第二步生成模型成功
  final bool beautified;

  /// 降级说明（中文，多段用「；」连接），全部成功时为 null
  final String? note;

  const WhiteBgResult({
    required this.bytes,
    required this.segmented,
    required this.beautified,
    this.note,
  });

  /// 按文件头判断真实格式，避免把 JPEG 存成 .png。
  String get extension => isPng ? 'png' : 'jpg';

  bool get isPng =>
      bytes.length > 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
}

/// #10 白底图两步流程：
/// - 第一步（分割抠图）：[LocalEdgeCutoutService]，输出透明底衣服图；
/// - 第二步（生成模型美化）：server 模式调 [WardrobeBackend.whiteBackground]；
///   直连网关注入 [imageEditor]（现有 [WhiteBackgroundService] 公开 API）；
///   都未配置时退回本地合成（[LocalWhiteBackground]，即现有本地白底实现）。
///
/// 降级矩阵（任何一步失败都不抛异常）：
/// - 分割失败 → 保留原图继续第二步（或直接返回原图 + note）；
/// - 美化失败 → 返回第一步的透明底图（或原图）+ note；
/// - 都失败 → 原图。
class WhiteBgPipeline {
  /// server 模式：后台代跑白底图。
  final WardrobeBackend? backend;

  /// 直连模式：图像编辑网关（由调用方注入现有 WhiteBackgroundService）。
  final WhiteBackgroundService? imageEditor;

  /// 直连模式配套的网关配置与密钥。
  final GatewayProfile? profile;
  final String? apiKey;

  /// 分割实现，测试可注入。
  final CutoutService? cutout;

  const WhiteBgPipeline({
    this.backend,
    this.imageEditor,
    this.profile,
    this.apiKey,
    this.cutout,
  });

  Future<WhiteBgResult> process(
    Uint8List source, {
    required WhiteBgSteps steps,
  }) async {
    var current = source;
    var segmented = false;
    final notes = <String>[];

    // ---------- 第一步：分割抠图（透明底衣服图） ----------
    if (steps.segment) {
      try {
        final cut =
            await (cutout ?? const LocalEdgeCutoutService()).process(source, BBox.empty);
        current = cut.bytes;
        segmented = cut.transparent;
        if (!cut.transparent) {
          notes.add(cut.note ?? '分割未成功，已保留原图');
        }
      } catch (e) {
        // 分割失败：保留原图继续第二步
        notes.add('分割出错，已保留原图');
      }
    }

    // ---------- 第二步：生成模型美化 ----------
    if (steps.beautify) {
      try {
        final Uint8List out;
        if (backend != null) {
          out = await backend!.whiteBackground(current);
        } else if (imageEditor != null && profile != null) {
          out = (await imageEditor!.generate(
            source: current,
            profile: profile!,
            apiKey: apiKey,
          ))
              .bytes;
        } else {
          // 未配置模型通道：本地合成白底（现有 local_white_bg 实现）
          out = await const LocalWhiteBackground().build(source);
        }
        if (!_looksLikeImage(out)) {
          throw StateError('白底服务没有返回有效图片');
        }
        return WhiteBgResult(
          bytes: out,
          segmented: segmented,
          beautified: true,
          note: _joinNotes(notes),
        );
      } catch (e) {
        // 美化失败：返回第一步的透明底图（或原图）
        notes.add('白底美化失败，已保留${segmented ? '分割结果' : '原图'}');
      }
    }

    return WhiteBgResult(
      bytes: current,
      segmented: segmented,
      beautified: false,
      note: _joinNotes(notes),
    );
  }

  static String? _joinNotes(List<String> notes) =>
      notes.isEmpty ? null : notes.join('；');

  /// 轻量图片校验：PNG / JPEG 文件头（不做完整解码）。
  static bool _looksLikeImage(Uint8List b) {
    if (b.length < 200) return false;
    final isPng = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final isJpg = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
    return isPng || isJpg;
  }
}
