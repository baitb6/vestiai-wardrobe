import 'package:flutter/foundation.dart';

import 'gateway_profile.dart';
import 'storage_service.dart';
import 'wardrobe_backend.dart';

/// 模型配置入口（已统一收归管理后台）。
///
/// 这里不再读写任何用户可编辑的模型地址 / 模型 ID / API Key：
/// - 地址固定指向后台代理 `…/api/app/ai/v1`
/// - 「密钥」换成设备凭据，由 [WardrobeBackend] 自动换取
/// - 方法签名保持不变，业务代码无需重写
class GatewayStore {
  final StorageService _storage;
  late final WardrobeBackend backend = WardrobeBackend(_storage);

  GatewayStore(this._storage, {Object? secure});

  /// 历史遗留字段，仅用于让旧代码继续编译；界面已不再展示。
  bool get isSecure => true;
  String? get secureError => null;

  Future<GatewayProfile> load(GatewayKind kind) async {
    final cfg = await backend.config();
    return GatewayProfile(
      kind: kind,
      baseUrl: WardrobeBackend.proxyBaseUrl,
      model: 'auto',
      editEndpoint: '/images/edits',
      supportsImageInput: cfg.vision || cfg.edit,
      supportsImageEdit: cfg.edit || cfg.whiteBgReady,
    );
  }

  Future<Map<GatewayKind, GatewayProfile>> loadAll() async {
    final result = <GatewayKind, GatewayProfile>{};
    for (final kind in GatewayKind.values) {
      result[kind] = await load(kind);
    }
    return result;
  }

  /// 配置已由后台统一下发，前台保存是空操作（保留签名兼容旧调用）。
  Future<void> save(GatewayProfile profile, {String? apiKey}) async {
    if (kDebugMode) {
      debugPrint('模型配置已统一由管理后台管理，忽略本地保存（${profile.kind.label}）');
    }
  }

  /// 「密钥」= 设备凭据。后台校验后才会真正调用模型，模型 Key 不出服务器。
  Future<String?> readKey(GatewayKind kind) => backend.token();

  Future<void> writeKey(GatewayKind kind, String? value) async {
    // 不再接受前台写入的模型密钥
  }

  Future<void> clearKey(GatewayKind kind) async {}

  /// 重新向后台注册设备（凭据失效时调用）。
  Future<String?> refreshDevice() => backend.token(refresh: true);

  /// 清理历史版本存在 Hive 里的明文密钥（一次性迁移）。
  Future<void> purgeLegacyKeys() async {
    for (final key in [
      'ai_api_key',
      'ai_key',
      ...GatewayKind.values.map((k) => 'ai_${k.key}_key'),
    ]) {
      final legacy = _storage.getSetting<String>(key);
      if (legacy != null && legacy.isNotEmpty) {
        await _storage.setSetting<String>(key, '');
      }
    }
  }
}
