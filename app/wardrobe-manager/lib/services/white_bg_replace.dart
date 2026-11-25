import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../providers/wardrobe_provider.dart';
import 'direct_ai_client.dart';
import 'file_bytes.dart';
import 'gateway_profile.dart';
import 'image_store.dart';
import 'wardrobe_backend.dart';
import 'white_bg_pipeline.dart';
import 'white_background_service.dart';

/// #13 「换白底图」任务阶段（只存内存，与 Intake 队列同一纪律）。
class WhiteBgReplacePhase {
  static const String running = 'running';
  static const String failed = 'failed';
}

/// 单件衣物「换白底图」后台控制器。
///
/// 入口 fire-and-forget（调用方 unawaited 即可），处理全程不阻塞前台：
/// 卡片上用 [isRunning] 显示小圆进度 +「白底处理中…」，成功后经
/// [WardrobeProvider.updateClothing] 落库并自动刷新衣橱；失败不改任何
/// 字段（原图字段原样保留，界面自动落回原图），可随时重试。
///
/// 通道与 intake / add_clothing 的白底分支同款（v1.9 设施全复用）：
/// server 模式先 [DirectAiClient.resolveEndpoint]（kind: white_bg）
/// 直连厂商图像编辑端点，无凭证/解析失败 → 后台代理；local 模式本地合成。
class WhiteBgReplaceController extends ChangeNotifier {
  WhiteBgReplaceController._();

  static final WhiteBgReplaceController instance = WhiteBgReplaceController._();

  final Map<String, String> _phase = {}; // clothingId → running / failed
  final Map<String, String> _errors = {}; // clothingId → 中文失败原因

  bool isRunning(String clothingId) =>
      _phase[clothingId] == WhiteBgReplacePhase.running;

  bool hasFailed(String clothingId) =>
      _phase[clothingId] == WhiteBgReplacePhase.failed;

  String? errorOf(String clothingId) => _errors[clothingId];

  void _set(String clothingId, String phase, {String? error}) {
    _phase[clothingId] = phase;
    if (error == null) {
      _errors.remove(clothingId);
    } else {
      _errors[clothingId] = error;
    }
    notifyListeners();
  }

  /// 清掉失败标记（下一次 replace 会自动覆盖，这里供 UI 主动忽略用）
  void clearFailure(String clothingId) {
    if (_phase[clothingId] != WhiteBgReplacePhase.failed) return;
    _phase.remove(clothingId);
    _errors.remove(clothingId);
    notifyListeners();
  }

  /// 找进流水线的源图：抠图透明底优先（跳过分割省一遍 CPU），
  /// 其次原图，最后 data:/本地文件形态的 imageUrl（手动补录老数据）。
  /// [fromCutout] 告诉调用方拿到的是不是透明底（决定分割步开关）。
  /// bytes 为 null = 一张可用的图都没有。
  Future<({Uint8List? bytes, bool fromCutout})> _sourceBytes(
      Clothing c) async {
    final cutout = c.cutoutImagePath;
    if (cutout != null && cutout.isNotEmpty) {
      final b = await readFileBytes(cutout);
      if (b != null) return (bytes: b, fromCutout: true);
    }
    final original = c.originalImagePath;
    if (original != null && original.isNotEmpty) {
      final b = await readFileBytes(original);
      if (b != null) return (bytes: b, fromCutout: false);
    }
    final url = c.imageUrl;
    if (url.startsWith('data:image')) {
      final comma = url.indexOf(',');
      if (comma != -1) {
        try {
          final b = base64Decode(url.substring(comma + 1));
          if (b.isNotEmpty) return (bytes: b, fromCutout: false);
        } catch (_) {
          // base64 损坏按缺失处理，走下面的本地文件尝试
        }
      }
    }
    if (url.isNotEmpty && !url.startsWith('http')) {
      final b = await readFileBytes(url);
      if (b != null) return (bytes: b, fromCutout: false);
    }
    return (bytes: null, fromCutout: false);
  }

  /// 后台替换某件衣物的展示图为白底图。永不抛异常：所有失败都写进
  /// 状态（[errorOf]），由入口 UI 展示 + 重试。
  Future<void> replace(Clothing clothing, WardrobeProvider wardrobe) async {
    final id = clothing.id;
    if (isRunning(id)) return;
    _set(id, WhiteBgReplacePhase.running);

    try {
      // 弹层里拿到的可能是旧引用：先从 Provider 取最新对象
      final current = wardrobe.allClothes.firstWhere(
        (c) => c.id == id,
        orElse: () => clothing,
      );

      var mode = 'local';
      try {
        mode = (await wardrobe.backend.config()).whiteBgMode;
      } catch (_) {
        // 配置拉不到就按本地处理，不阻断
      }
      if (mode == 'off') {
        throw StateError('白底图功能当前已关闭，暂时不能更换');
      }

      final src = await _sourceBytes(current);
      if (src.bytes == null) {
        throw StateError('找不到可用的原图，无法生成白底图');
      }

      final pipeline =
          mode == 'server' ? await _serverPipeline(wardrobe) : const WhiteBgPipeline();
      // 抠图透明底直接复用（跳过分割步）；否则流水线自己分割
      final res = await pipeline.process(
        src.bytes!,
        steps: WhiteBgSteps(segment: !src.fromCutout),
      );
      if (!res.beautified) {
        throw StateError(res.note ?? '白底图生成失败，请稍后重试');
      }
      final path = await ImageStore.instance.saveBytes(
        res.bytes,
        prefix: 'whitebg_replace',
        ext: res.extension,
      );
      if (path == null) {
        throw StateError('白底图保存失败，请检查存储空间');
      }

      // 落库前再取一次最新对象（处理期间用户可能改过其它字段）
      final fresh = wardrobe.allClothes.firstWhere(
        (c) => c.id == id,
        orElse: () => current,
      );
      // 只换展示图：原图/抠图字段一律不动 → 万一后续出问题仍有兜底
      fresh.imageUrl = path;
      await wardrobe.updateClothing(fresh);

      _phase.remove(id);
      _errors.remove(id);
      notifyListeners();
    } catch (e) {
      // 失败：衣物任何字段都没动，卡片自动落回原图；入口可重试
      final msg = e
          .toString()
          .replaceFirst(RegExp(r'^(Bad state|StateError|Exception): '), '')
          .trim();
      _set(id, WhiteBgReplacePhase.failed,
          error: msg.isEmpty ? '白底图生成失败，请重试' : msg);
    }
  }

  /// server 模式白底流水线：有 white_bg 直连凭证 → 直发厂商图像编辑端点
  /// （直连失败不回退代理，落到流水线自身的分割/原图降级）；
  /// 无凭证 / 过期 / 解析失败 → 后台代理。与 intake_provider 同款。
  Future<WhiteBgPipeline> _serverPipeline(WardrobeProvider wardrobe) async {
    final backend = wardrobe.backend;
    try {
      final ep = await DirectAiClient.resolveEndpoint(
        kind: 'white_bg',
        proxyBaseUrl: WardrobeBackend.proxyBaseUrl,
      );
      if (ep.direct) {
        final directEndpoint = (ep.endpoint ?? '').trim();
        return WhiteBgPipeline(
          imageEditor: WhiteBackgroundService(),
          profile: GatewayProfile(
            kind: GatewayKind.edit,
            baseUrl: ep.baseUrl,
            model: ep.model ?? '',
            editEndpoint:
                directEndpoint.isEmpty ? '/images/edits' : directEndpoint,
            supportsImageEdit: true,
          ),
          apiKey: ep.apiKey,
        );
      }
    } catch (_) {
      // 凭证解析失败按无凭证处理，走代理
    }
    return WhiteBgPipeline(backend: backend);
  }
}
