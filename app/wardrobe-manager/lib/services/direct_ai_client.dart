// 本文件会被 wardrobe_backend.dart 引用来注册取凭证入口，
// 因此这里刻意不 import 任何工程内文件，避免循环依赖。

/// 单个用途的直连配置（由后台 POST /api/app/credential 下发）。
/// 字段缺失或为空 → 视为该用途不可直连，调用方继续走代理。
class DirectModel {
  final String baseUrl;
  final String model;
  final String apiKey;

  /// 该用途的请求端点（如 /chat/completions、/images/edits）；可为空，由调用方按默认拼接。
  final String endpoint;

  const DirectModel({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.endpoint = '',
  });

  /// 是否够格直连：地址、模型名、密钥缺一不可。
  bool get usable =>
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;

  /// 容错解析：非对象或缺关键字段返回 null（跳过该用途）。
  static DirectModel? fromJson(dynamic v) {
    if (v is! Map) return null;
    final base = v['base_url'];
    final model = v['model'];
    final key = v['api_key'];
    final endpoint = v['endpoint'];
    if (base is! String || model is! String || key is! String) return null;
    return DirectModel(
      baseUrl: base.trim(),
      model: model.trim(),
      apiKey: key.trim(),
      endpoint: endpoint is String ? endpoint.trim() : '',
    );
  }
}

/// 一份直连凭证：到期时间 + 按用途（vision/text/edit/avatar/white_bg）的模型配置。
/// 纪律：明文密钥只允许存在于内存与 secure storage，不落 Hive、不进日志、不进备份。
class DirectCredential {
  final DateTime expiresAt;
  final Map<String, DirectModel> models;

  const DirectCredential({required this.expiresAt, required this.models});

  /// 提前 60 秒视为过期，避免上传途中凭证失效。
  bool get validNow =>
      DateTime.now().add(const Duration(seconds: 60)).isBefore(expiresAt);

  /// expires_at 兼容三种形态：秒级时间戳、毫秒级时间戳、ISO 8601 字符串。
  static DateTime? _parseExpires(dynamic v) {
    if (v == null) return null;
    int? epoch;
    if (v is int) {
      epoch = v;
    } else if (v is num) {
      epoch = v.toInt();
    } else if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) {
        epoch = parsed;
      } else {
        return DateTime.tryParse(v);
      }
    }
    if (epoch == null) return null;
    // 大于 1e10 认为已是毫秒
    final ms = epoch > 9999999999 ? epoch : epoch * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 容错解析：无到期时间或没有任何可用用途 → null（调用方按无凭证处理）。
  static DirectCredential? fromJson(Map<String, dynamic> m) {
    final expires = _parseExpires(m['expires_at']);
    if (expires == null) return null;
    final rawModels = m['models'];
    final models = <String, DirectModel>{};
    if (rawModels is Map) {
      for (final entry in rawModels.entries) {
        final dm = DirectModel.fromJson(entry.value);
        if (dm != null) models[entry.key.toString()] = dm;
      }
    }
    if (models.isEmpty) return null;
    return DirectCredential(expiresAt: expires, models: models);
  }
}

/// 直连/代理解析结果。direct=false 时 baseUrl/apiKey 原样来自调用方（代理路径）。
class ResolvedAiEndpoint {
  /// 实际请求的网关根地址（直连=厂商 base_url，代理=后台代理地址）。
  final String baseUrl;

  /// 鉴权密钥（直连=厂商 api_key，代理=设备 token）。
  final String? apiKey;

  /// 直连模型名（代理路径为 null，沿用调用方 profile 的模型）。
  final String? model;

  /// 直连端点（如 /chat/completions、/images/edits）；为 null 时用调用方默认。
  final String? endpoint;

  final bool direct;

  const ResolvedAiEndpoint({
    required this.baseUrl,
    required this.direct,
    this.apiKey,
    this.model,
    this.endpoint,
  });
}

/// 直连客户端：图片类 AI 请求「直连优先、代理回退」的统一入口。
///
/// 凭证来源由 [WardrobeBackend] 构造时通过 [register] 注册（内存 + secure storage
/// 缓存都留在 backend 侧），服务层无需持有 backend 实例即可解析。
/// 取不到凭证（未开通/过期/后台不可达）时一律返回代理值，行为与 v1.8 完全一致。
class DirectAiClient {
  static Future<DirectCredential?> Function()? _fetchCredential;
  static String? _proxyBase;

  /// 由 [WardrobeBackend] 构造时注册；重复注册以后一次为准
  ///（所有实例指向同一后台与同一 secure storage，覆盖无副作用）。
  static void register({
    required Future<DirectCredential?> Function() fetchCredential,
    required String proxyBase,
  }) {
    _fetchCredential = fetchCredential;
    _proxyBase = proxyBase;
  }

  /// 取某用途的完整直连配置。
  static DirectModel? configFor(DirectCredential? cred, String kind) =>
      cred?.models[kind];

  /// 按用途取直连地址；无可用配置返回 null（调用方走代理）。
  static String? baseUrlFor(DirectCredential? cred, String kind) {
    final m = configFor(cred, kind);
    return m == null || !m.usable ? null : m.baseUrl;
  }

  /// 按用途取直连密钥；无可用配置返回 null。
  static String? apiKeyFor(DirectCredential? cred, String kind) {
    final m = configFor(cred, kind);
    return m == null || !m.usable ? null : m.apiKey;
  }

  /// 按用途取直连模型名；无可用配置返回 null。
  static String? modelFor(DirectCredential? cred, String kind) {
    final m = configFor(cred, kind);
    return m == null || !m.usable ? null : m.model;
  }

  /// 发请求前统一解析端点：三个图片服务（拆衣视觉 / 试穿 / 白底）共用这一份逻辑。
  ///
  /// - [kind] 用途键：vision / edit / white_bg；
  /// - [proxyBaseUrl] 当前代理路径的 baseUrl（即服务里 profile.baseUrl）；
  /// - [proxyApiKey] 代理路径的鉴权（设备 token）。
  ///
  /// 有该用途的可用直连凭证 → 返回厂商 base/key/model/endpoint（direct=true）；
  /// 无凭证 / 过期 / 取凭证失败 → 原样返回代理值（direct=false），静默回退。
  ///
  /// 特殊守卫：传入的 [proxyBaseUrl] 已不是后台代理地址（说明上层已经解析过、
  /// 例如白底直连复用图像编辑入口）→ 直接透传，避免二次改写成别的用途。
  static Future<ResolvedAiEndpoint> resolveEndpoint({
    required String kind,
    required String proxyBaseUrl,
    String? proxyApiKey,
  }) async {
    final base = _proxyBase;
    if (base != null && proxyBaseUrl.trim() != base) {
      return ResolvedAiEndpoint(
          baseUrl: proxyBaseUrl, apiKey: proxyApiKey, direct: false);
    }
    final fetcher = _fetchCredential;
    if (fetcher != null) {
      try {
        final cred = await fetcher();
        final m = cred == null ? null : configFor(cred, kind);
        if (m != null && m.usable) {
          return ResolvedAiEndpoint(
            baseUrl: _normalize(m.baseUrl),
            apiKey: m.apiKey,
            model: m.model,
            endpoint: m.endpoint.isEmpty ? null : m.endpoint,
            direct: true,
          );
        }
      } catch (_) {
        // 取凭证失败按无凭证处理走代理；静默，不带任何 URL / Key 细节
      }
    }
    return ResolvedAiEndpoint(
        baseUrl: proxyBaseUrl, apiKey: proxyApiKey, direct: false);
  }

  static String _normalize(String u) {
    var s = u.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}
