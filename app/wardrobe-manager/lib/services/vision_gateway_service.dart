import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../data/ai_mapping.dart';
import '../models/bbox.dart';
import '../models/split_candidate.dart';
import '../prompts/split_outfit_prompt.dart';
import 'direct_ai_client.dart';
import 'gateway_profile.dart';

enum GatewayErrorKind { unsupported, network, auth, http, parse, empty }

/// 网关调用失败。message 直接给用户看，raw 供「查看原始响应」用。
class GatewayException implements Exception {
  final GatewayErrorKind kind;
  final String message;
  final String? raw;
  final int? statusCode;

  GatewayException(this.kind, this.message,
      {this.raw, this.statusCode});

  /// 是否值得让用户点「重试」
  bool get retryable =>
      kind == GatewayErrorKind.network || kind == GatewayErrorKind.http;

  @override
  String toString() => message;
}

/// 连通性测试结果
class GatewayTestResult {
  final bool ok;
  final String message;
  final List<String> models;
  final Duration elapsed;

  GatewayTestResult({
    required this.ok,
    required this.message,
    this.models = const [],
    this.elapsed = Duration.zero,
  });
}

/// 一次拆分的返回
class SplitOutfitResult {
  final List<SplitCandidate> items;

  /// 模型原始文本（落库到 SplitTask.resultJson 便于排查）
  final String raw;

  SplitOutfitResult({required this.items, required this.raw});
}

/// 视觉网关：只负责「图片 → 严格 JSON → 候选单品」。
/// 不做抠图（交给 CutoutService），不做入库（交给页面确认）。
class VisionGatewayService {
  final Dio _dio;

  VisionGatewayService([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              validateStatus: (s) => s != null && s < 500,
            ));

  /// 拆分全身照
  Future<SplitOutfitResult> splitOutfit({
    required Uint8List imageBytes,
    required GatewayProfile profile,
    String? apiKey,
    String? mimeType,
  }) async {
    if (!profile.configured) {
      throw GatewayException(
        GatewayErrorKind.unsupported,
        'AI 服务还没就绪，联网后稍等片刻再试；也可以先手工录入衣物',
      );
    }
    if (!profile.supportsImageInput) {
      throw GatewayException(
        GatewayErrorKind.unsupported,
        '管理员还没开通视觉识别，暂时无法拆分照片，先手工录入吧',
      );
    }

    final dataUrl = _toDataUrl(imageBytes, mimeType);
    final payload = <String, dynamic>{
      'model': profile.model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': kSplitOutfitPrompt},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        }
      ],
      'temperature': profile.temperature,
      'max_tokens': 1800,
      if (profile.supportsJsonOutput) 'response_format': {'type': 'json_object'},
    };

    final content = await _chat(payload, profile, apiKey);
    return SplitOutfitResult(
      items: parseItems(content),
      raw: content,
    );
  }

  /// 把模型文本解析成候选单品。脏 JSON 先提取 {...} 再解析。
  List<SplitCandidate> parseItems(String content) {
    final jsonText = extractJson(content);
    if (jsonText == null) {
      throw GatewayException(
        GatewayErrorKind.parse,
        '模型没有返回 JSON。可以把该网关的「支持 JSON 输出」打开，或换个更听话的模型',
        raw: content,
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (e) {
      throw GatewayException(
        GatewayErrorKind.parse,
        'JSON 解析失败：$e',
        raw: content,
      );
    }

    final rawItems = decoded is Map ? decoded['items'] : decoded;
    if (rawItems is! List || rawItems.isEmpty) {
      throw GatewayException(
        GatewayErrorKind.empty,
        '没识别到可入库的单品，换张更清晰的全身照试试',
        raw: content,
      );
    }

    final items = <SplitCandidate>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final category = AiMapping.category(raw['category'] as String?);
      final sub = AiMapping.subCategory(raw['subCategory'] as String?, category);
      final bbox = BBox.fromJson(raw['bbox']);
      // 面积过小多半是误识别（纽扣、logo）
      if (bbox.area < 0.004) continue;

      items.add(SplitCandidate(
        category: category,
        subCategory: sub,
        bbox: bbox,
        colors: AiMapping.colors(
            (raw['colors'] as List?)?.map((e) => e.toString()).toList()),
        styleTags: AiMapping.styles(
            (raw['styleTags'] as List?)?.map((e) => e.toString()).toList()),
        seasons: AiMapping.seasons(
            (raw['season'] as List? ?? raw['seasons'] as List?)
                ?.map((e) => e.toString())
                .toList()),
        confidence: ((raw['confidence'] as num?)?.toDouble() ?? 0.5)
            .clamp(0.0, 1.0),
        rawCategory: raw['category'] as String? ?? '',
        extraTags: AiMapping.extraTags(
            (raw['styleTags'] as List?)?.map((e) => e.toString()).toList()),
      ));
    }

    if (items.isEmpty) {
      throw GatewayException(
        GatewayErrorKind.empty,
        '识别结果里没有合格单品（包围盒太小或格式不对）',
        raw: content,
      );
    }
    // 配饰最多 5 件，多的按置信度砍掉
    final accessories = items.where((e) => e.category == 'accessories').toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    if (accessories.length > 5) {
      for (final extra in accessories.skip(5)) {
        items.remove(extra);
      }
    }
    items.sort((a, b) => b.bbox.area.compareTo(a.bbox.area));
    return items;
  }

  /// 从任意文本里抽出第一个完整的 JSON 对象（跳过字符串内的括号）
  static String? extractJson(String content) {
    var text = content.trim();
    // 去掉 ```json ``` 包裹
    final fence = RegExp(r'```(?:json)?', caseSensitive: false);
    if (text.contains('```')) {
      text = text.replaceAll(fence, '');
    }
    final start = text.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  /// 响应体容错解码：有的网关用 text/plain 回 JSON，甚至混着前后废话。
  /// 先直接 jsonDecode，失败再提取 {...} 解析；都失败返回 null。
  static Map<String, dynamic>? looseDecode(dynamic body) {
    if (body is Map) {
      try {
        return Map<String, dynamic>.from(body);
      } catch (_) {
        return null;
      }
    }
    final text = body is String ? body : body?.toString();
    if (text == null || text.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 落到下面的 {...} 提取
    }
    final extracted = extractJson(text);
    if (extracted == null) return null;
    try {
      final decoded = jsonDecode(extracted);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// 连通性测试：GET /models，失败时给出可读原因
  Future<GatewayTestResult> testConnection(
    GatewayProfile profile,
    String? apiKey,
  ) async {
    final started = DateTime.now();
    if (profile.baseUrl.trim().isEmpty) {
      return GatewayTestResult(ok: false, message: '还没填网关地址');
    }
    try {
      final resp = await _dio.get(
        '${profile.normalizedBaseUrl}/models',
        options: Options(
          headers: _headers(apiKey),
          receiveTimeout: Duration(seconds: profile.timeoutSeconds),
          validateStatus: (_) => true,
        ),
      );
      final elapsed = DateTime.now().difference(started);
      final code = resp.statusCode ?? 0;
      if (code == 401 || code == 403) {
        return GatewayTestResult(
            ok: false, message: '密钥无效或没有权限（HTTP $code）', elapsed: elapsed);
      }
      if (code >= 400) {
        return GatewayTestResult(
            ok: false,
            message: '网关返回 HTTP $code，检查地址是否缺 /v1',
            elapsed: elapsed);
      }
      final data = resp.data;
      final list = <String>[];
      if (data is Map && data['data'] is List) {
        for (final m in data['data']) {
          if (m is Map && m['id'] != null) list.add(m['id'].toString());
        }
      }
      final hit = list.where((m) => m == profile.model).toList();
      final msg = list.isEmpty
          ? '连上了，但没返回模型列表'
          : hit.isNotEmpty
              ? '连通正常，模型 ${profile.model} 可用（共 ${list.length} 个）'
              : '连上了，但列表里没有 ${profile.model}（共 ${list.length} 个）';
      return GatewayTestResult(
          ok: true, message: msg, models: list, elapsed: elapsed);
    } on DioException catch (e) {
      return GatewayTestResult(
        ok: false,
        message: _describeDio(e),
        elapsed: DateTime.now().difference(started),
      );
    } catch (e) {
      return GatewayTestResult(
          ok: false,
          message: '测试失败：$e',
          elapsed: DateTime.now().difference(started));
    }
  }

  // ---------- 内部 ----------

  Future<String> _chat(
      Map<String, dynamic> payload, GatewayProfile profile, String? apiKey) async {
    // v1.9：直连优先——有 vision 直连凭证就换厂商地址/密钥/模型/端点，
    // 没有则原样走代理路径（行为与 v1.8 完全一致）。请求逻辑不动。
    final ep = await DirectAiClient.resolveEndpoint(
      kind: 'vision',
      proxyBaseUrl: profile.baseUrl,
      proxyApiKey: apiKey,
    );
    final directModel = ep.model;
    if (directModel != null && directModel.trim().isNotEmpty) {
      payload['model'] = directModel;
    }
    final base = ep.direct ? ep.baseUrl : profile.normalizedBaseUrl;
    var chatPath = '/chat/completions';
    final directPath = ep.direct ? (ep.endpoint ?? '').trim() : '';
    if (directPath.isNotEmpty) {
      chatPath = directPath.startsWith('/') ? directPath : '/$directPath';
    }
    try {
      final resp = await _dio.post(
        '$base$chatPath',
        data: payload,
        options: Options(
          headers: _headers(ep.apiKey),
          sendTimeout: Duration(seconds: profile.timeoutSeconds),
          receiveTimeout: Duration(seconds: profile.timeoutSeconds),
          validateStatus: (_) => true,
        ),
      );
      final code = resp.statusCode ?? 0;
      if (code == 401 || code == 403) {
        throw GatewayException(GatewayErrorKind.auth, '网关拒绝访问（HTTP $code），检查 API Key',
            statusCode: code);
      }
      if (code >= 400) {
        throw GatewayException(
          GatewayErrorKind.http,
          '网关返回 HTTP $code：${_brief(resp.data)}',
          statusCode: code,
          raw: resp.data?.toString(),
        );
      }
      // 网关可能用 text/plain 回 JSON，甚至带前后废话：容错解码
      final data = looseDecode(resp.data);
      if (data == null) {
        throw GatewayException(GatewayErrorKind.parse, '网关返回的不是 JSON 对象',
            raw: resp.data?.toString());
      }
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        throw GatewayException(
          GatewayErrorKind.parse,
          '网关返回里没有 choices，可能不是 OpenAI 兼容接口',
          raw: data.toString(),
        );
      }
      final first = choices.first;
      if (first is! Map) {
        throw GatewayException(GatewayErrorKind.parse, 'choices 结构异常，可能不是 OpenAI 兼容接口',
            raw: data.toString());
      }
      final message = first['message'];
      final content = message is Map ? message['content'] : null;
      if (content is String) return content;
      // 部分网关返回 content 数组
      if (content is List) {
        final buf = StringBuffer();
        for (final part in content) {
          if (part is Map && part['text'] != null) buf.write(part['text']);
        }
        if (buf.isNotEmpty) return buf.toString();
      }
      throw GatewayException(GatewayErrorKind.parse, '返回内容为空',
          raw: data.toString());
    } on GatewayException {
      rethrow;
    } on DioException catch (e) {
      throw GatewayException(GatewayErrorKind.network, _describeDio(e));
    }
  }

  Map<String, String> _headers(String? apiKey) => {
        'Content-Type': 'application/json',
        if (apiKey != null && apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${apiKey.trim()}',
      };

  String _toDataUrl(Uint8List bytes, String? mime) {
    final m = mime ?? 'image/jpeg';
    return 'data:$m;base64,${base64Encode(bytes)}';
  }

  String _brief(dynamic data) {
    final s = data?.toString() ?? '';
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  String _describeDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，检查地址是否可达（手机端注意 localhost 指的是手机自己）';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '请求超时，视觉模型处理大图较慢，可以把超时调到 120 秒';
      case DioExceptionType.connectionError:
        return '连不上网关：${e.message ?? '网络不可达'}';
      case DioExceptionType.badCertificate:
        return '证书校验失败，网关可能用了自签名证书';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        return '网络错误：${e.message ?? e.type.name}';
    }
  }
}
