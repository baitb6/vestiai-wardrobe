import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../prompts/style_analysis_prompt.dart';
import 'gateway_profile.dart';
import 'style_digest.dart';
import 'vision_gateway_service.dart';

/// 文本网关：风格分析、搭配点评。
///
/// 与视觉网关的区别：只发文本、不发图片，因此可以配便宜的小模型；
/// 温度默认给高一点（0.7），点评不至于像模板。
class TextGatewayService {
  final Dio _dio;

  TextGatewayService([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              validateStatus: (s) => s != null && s < 500,
            ));

  /// 分析衣橱风格。未配置网关时调用方应改用 LocalStyleAnalyzer。
  Future<StyleReport> analyzeStyle({
    required WardrobeDigest digest,
    required GatewayProfile profile,
    String? apiKey,
    String? occasion,
    String? goal,
  }) async {
    if (!profile.configured) {
      throw GatewayException(
        GatewayErrorKind.unsupported,
        'AI 服务还没就绪，联网后稍等片刻再试；也可以先用本地分析',
      );
    }
    if (digest.total == 0) {
      throw GatewayException(
        GatewayErrorKind.empty,
        '衣橱里还没有单品，先录入几件再分析',
      );
    }

    final payload = <String, dynamic>{
      'model': profile.model,
      'messages': [
        {
          'role': 'system',
          'content': styleAnalysisPromptFor(occasion: occasion, goal: goal),
        },
        {
          'role': 'user',
          'content':
              '衣橱摘要：\n${jsonEncode(digest.toJson())}\n\n请按要求的 JSON 结构输出。',
        },
      ],
      'temperature': profile.temperature,
      'max_tokens': 1200,
      if (profile.supportsJsonOutput) 'response_format': {'type': 'json_object'},
    };

    final content = await _chat(payload, profile, apiKey);
    return parseReport(content);
  }

  /// 容错解析：围栏、前后废话、字段缺失、ratio 不是数字都兜住
  StyleReport parseReport(String content) {
    final jsonText = VisionGatewayService.extractJson(content);
    if (jsonText == null) {
      throw GatewayException(
        GatewayErrorKind.parse,
        '模型这次没返回 JSON，点「重新分析」再试一次',
        raw: content,
      );
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (e) {
      debugPrint('风格分析 JSON 解析失败：$e');
      throw GatewayException(
        GatewayErrorKind.parse,
        '模型返回的 JSON 不完整，点「重新分析」再试一次',
        raw: content,
      );
    }
    if (decoded is! Map) {
      throw GatewayException(GatewayErrorKind.parse, '返回结构不是对象', raw: content);
    }

    final mix = <StyleMix>[];
    final rawMix = decoded['styleMix'];
    if (rawMix is List) {
      for (final m in rawMix) {
        if (m is! Map) continue;
        final name = (m['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final r = m['ratio'];
        final ratio = r is num ? r.toDouble() : double.tryParse('$r') ?? 0;
        mix.add(StyleMix(name, ratio.clamp(0, 1).toDouble()));
      }
    }

    final gaps = <StyleGap>[];
    final rawGaps = decoded['gaps'];
    if (rawGaps is List) {
      for (final g in rawGaps) {
        if (g is Map) {
          final cat = (g['category'] ?? '').toString().trim();
          if (cat.isEmpty) continue;
          gaps.add(StyleGap(cat, (g['reason'] ?? '').toString()));
        } else if (g is String && g.trim().isNotEmpty) {
          gaps.add(StyleGap(g.trim(), ''));
        }
      }
    }

    final buys = <BuySuggestion>[];
    final rawBuys = decoded['buyNext'];
    if (rawBuys is List) {
      for (final b in rawBuys) {
        if (b is Map) {
          final item = (b['item'] ?? '').toString().trim();
          if (item.isEmpty) continue;
          final p = (b['priority'] ?? 'medium').toString().toLowerCase();
          buys.add(BuySuggestion(
            item,
            (b['why'] ?? '').toString(),
            ['high', 'medium', 'low'].contains(p) ? p : 'medium',
          ));
        } else if (b is String && b.trim().isNotEmpty) {
          buys.add(BuySuggestion(b.trim(), '', 'medium'));
        }
      }
    }

    List<String> strings(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final persona = (decoded['persona'] ?? '').toString().trim();
    if (persona.isEmpty) {
      throw GatewayException(
        GatewayErrorKind.parse,
        '模型没给出风格画像，点「重新分析」再试一次',
        raw: content,
      );
    }

    return StyleReport(
      persona: persona,
      styleMix: mix.take(4).toList(),
      strengths: strings(decoded['strengths']).take(4).toList(),
      gaps: gaps.take(3).toList(),
      colorStory: (decoded['colorStory'] ?? '').toString().trim(),
      buyNext: buys.take(3).toList(),
      avoid: strings(decoded['avoid']).take(3).toList(),
      raw: content,
    );
  }

  Future<String> _chat(
      Map<String, dynamic> payload, GatewayProfile profile, String? apiKey) async {
    try {
      final resp = await _dio.post(
        '${profile.normalizedBaseUrl}/chat/completions',
        data: payload,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (apiKey != null && apiKey.trim().isNotEmpty)
              'Authorization': 'Bearer ${apiKey.trim()}',
          },
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
      if (code == 404) {
        throw GatewayException(
          GatewayErrorKind.unsupported,
          '接口不存在（HTTP 404），地址通常需要以 /v1 结尾',
          statusCode: code,
        );
      }
      if (code >= 400) {
        final brief = resp.data?.toString() ?? '';
        throw GatewayException(
          GatewayErrorKind.http,
          '网关返回 HTTP $code：${brief.length > 160 ? '${brief.substring(0, 160)}…' : brief}',
          statusCode: code,
          raw: brief,
        );
      }
      // 网关可能用 text/plain 回 JSON，甚至带前后废话：容错解码
      final data = VisionGatewayService.looseDecode(resp.data);
      if (data == null) {
        throw GatewayException(
          GatewayErrorKind.parse,
          '网关返回的不是 JSON 对象',
          raw: resp.data?.toString(),
        );
      }
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        throw GatewayException(
          GatewayErrorKind.parse,
          '返回里没有 choices，可能不是 OpenAI 兼容接口',
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
      if (content is String && content.trim().isNotEmpty) return content;
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
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw GatewayException(GatewayErrorKind.network,
              '请求超时，可以把超时调到 60 秒后重试');
        case DioExceptionType.connectionError:
          throw GatewayException(GatewayErrorKind.network,
              '连不上网关：${e.message ?? '网络不可达'}');
        default:
          throw GatewayException(GatewayErrorKind.network,
              '网络错误：${e.message ?? e.type.name}');
      }
    }
  }
}
