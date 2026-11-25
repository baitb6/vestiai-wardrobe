import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'direct_ai_client.dart';
import 'gateway_profile.dart';
import 'vision_gateway_service.dart';

/// 试穿失败时，用来说明「为什么退回搭配预览」
class TryOnResult {
  final Uint8List bytes;

  /// 实际走通的端点：/images/edits 或 /chat/completions
  final String endpoint;

  /// 模型回传的改写提示词（部分网关会给）
  final String? revisedPrompt;

  TryOnResult({
    required this.bytes,
    required this.endpoint,
    this.revisedPrompt,
  });
}

/// 2D 虚拟试穿：把搭配「穿」到用户的人像照片上。
///
/// 职责边界：
/// - 只负责调用编辑网关、拿回图片字节
/// - 落盘、任务状态、降级由 TryOnProvider / 页面处理
/// - 不做人脸伪造、不做换脸，只做服装替换
class TryOnService {
  final Dio _dio;

  TryOnService([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              validateStatus: (s) => s != null && s < 500,
            ));

  /// 生成试穿图。
  ///
  /// 先试 `/images/edits`（标准 OpenAI 图像编辑），
  /// 返回 404/405 说明网关没这个端点，再退到 `/chat/completions`
  /// 的多模态图生图（Gemini / 部分国内网关走这条）。
  Future<TryOnResult> generate({
    required Uint8List personImage,
    required List<Clothing> items,
    required GatewayProfile profile,
    String? apiKey,
    String? extraNote,
  }) async {
    if (profile.baseUrl.trim().isEmpty || profile.model.trim().isEmpty) {
      throw GatewayException(
        GatewayErrorKind.unsupported,
        'AI 服务还没就绪，联网后稍等片刻再试',
      );
    }
    if (!profile.supportsImageEdit) {
      throw GatewayException(
        GatewayErrorKind.unsupported,
        '管理员还没开通虚拟试穿，暂时用不了这个功能',
      );
    }
    if (items.isEmpty) {
      throw GatewayException(
        GatewayErrorKind.empty,
        '这套搭配里没有单品，先挑几件再试穿',
      );
    }

    // v1.9：直连优先（edit 用途）——只换 baseUrl / 模型 / 密钥 / 端点，
    // 请求逻辑不动；无直连凭证时原样走代理（profile.baseUrl 即代理地址）。
    // 直连失败不在本轮回退代理，避免同一张图重复上传。
    final eff = await _effective(profile, apiKey);
    final prompt = buildPrompt(items, extraNote: extraNote);
    final editEndpoint = eff.profile.editEndpoint.trim().isEmpty
        ? '/images/edits'
        : eff.profile.editEndpoint.trim();

    try {
      return await _viaImageEdit(
        personImage: personImage,
        prompt: prompt,
        profile: eff.profile,
        apiKey: eff.apiKey,
        endpoint: editEndpoint,
      );
    } on GatewayException catch (e) {
      final missingEndpoint = e.statusCode == 404 || e.statusCode == 405;
      if (!missingEndpoint) rethrow;
      // 端点不存在 → 换 chat 多模态路线
      return _viaChat(
        personImage: personImage,
        prompt: prompt,
        profile: eff.profile,
        apiKey: eff.apiKey,
      );
    }
  }

  /// 通用图像编辑入口，供白底商品图等非试穿任务复用。
  Future<TryOnResult> generateEditedImage({
    required Uint8List sourceImage,
    required String prompt,
    required GatewayProfile profile,
    String? apiKey,
  }) async {
    // v1.9：同 generate——直连优先，无凭证走代理；直连失败不回退代理。
    final eff = await _effective(profile, apiKey);
    final endpoint = eff.profile.editEndpoint.trim().isEmpty
        ? '/images/edits'
        : eff.profile.editEndpoint.trim();
    try {
      return await _viaImageEdit(
        personImage: sourceImage,
        prompt: prompt,
        profile: eff.profile,
        apiKey: eff.apiKey,
        endpoint: endpoint,
      );
    } on GatewayException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 405) rethrow;
      return _viaChat(
        personImage: sourceImage,
        prompt: prompt,
        profile: eff.profile,
        apiKey: eff.apiKey,
      );
    }
  }

  /// 生成英文提示词：多数图像编辑模型对英文指令更稳，
  /// 但单品描述保留中文原值以免翻译跑偏。
  String buildPrompt(List<Clothing> items, {String? extraNote}) {
    final parts = <String>[];
    for (final c in items) {
      final cat = ClothingCategory.names[c.category] ?? c.category;
      final sub = ClothingSubCategory.names[c.subCategory] ?? c.subCategory;
      parts.add('$cat($sub, ${c.color})');
    }
    final buf = StringBuffer()
      ..writeln('Virtual try-on. Replace the outfit of the person in the photo '
          'with exactly these garments: ${parts.join(', ')}.')
      ..writeln('Rules:')
      ..writeln('- Keep the same person: same face, hair, body shape, skin tone.')
      ..writeln('- Keep the same pose, camera angle, background and lighting.')
      ..writeln('- Only change the clothing. No text, no watermark, no extra people.')
      ..writeln('- The garments must fit naturally with correct folds and shadows.');
    if (extraNote != null && extraNote.trim().isNotEmpty) {
      buf.writeln('Additional request from user: ${extraNote.trim()}');
    }
    return buf.toString();
  }

  // ---------- 路线一：/images/edits ----------

  Future<TryOnResult> _viaImageEdit({
    required Uint8List personImage,
    required String prompt,
    required GatewayProfile profile,
    String? apiKey,
    required String endpoint,
  }) async {
    final form = FormData.fromMap({
      'model': profile.model,
      'prompt': prompt,
      'size': '1024x1024',
      'n': 1,
      'response_format': 'b64_json',
      'image': MultipartFile.fromBytes(personImage, filename: 'person.png'),
    });

    final resp = await _post(
      '${profile.normalizedBaseUrl}${endpoint.startsWith('/') ? '' : '/'}$endpoint',
      data: form,
      profile: profile,
      apiKey: apiKey,
      multipart: true,
    );

    final data = resp['data'];
    if (data is! List || data.isEmpty) {
      throw GatewayException(
        GatewayErrorKind.parse,
        '网关没有返回图片，检查模型是否支持 /images/edits',
        raw: resp.toString(),
      );
    }
    final first = data.first;
    if (first is! Map) {
      throw GatewayException(GatewayErrorKind.parse, '返回结构不是对象', raw: resp.toString());
    }

    final b64 = first['b64_json'];
    if (b64 is String && b64.isNotEmpty) {
      return TryOnResult(
        bytes: base64Decode(b64),
        endpoint: endpoint,
        revisedPrompt: first['revised_prompt']?.toString(),
      );
    }
    final url = first['url'];
    if (url is String && url.isNotEmpty) {
      final bytes = await _download(url);
      return TryOnResult(
        bytes: bytes,
        endpoint: endpoint,
        revisedPrompt: first['revised_prompt']?.toString(),
      );
    }
    throw GatewayException(
      GatewayErrorKind.parse,
      '返回里既没有 b64_json 也没有 url，把 response_format 设成 b64_json 再试',
      raw: resp.toString(),
    );
  }

  // ---------- 路线二：/chat/completions 多模态 ----------

  Future<TryOnResult> _viaChat({
    required Uint8List personImage,
    required String prompt,
    required GatewayProfile profile,
    String? apiKey,
  }) async {
    final dataUrl = 'data:image/png;base64,${base64Encode(personImage)}';
    final body = <String, dynamic>{
      'model': profile.model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        }
      ],
      'modalities': ['text', 'image'],
      'temperature': profile.temperature,
    };

    final resp = await _post(
      '${profile.normalizedBaseUrl}/chat/completions',
      data: body,
      profile: profile,
      apiKey: apiKey,
      multipart: false,
    );

    final choices = resp['choices'];
    if (choices is! List || choices.isEmpty) {
      throw GatewayException(
        GatewayErrorKind.parse,
        '返回里没有 choices，网关可能不支持图生图',
        raw: resp.toString(),
      );
    }
    final first = choices.first;
    if (first is! Map) {
      throw GatewayException(
        GatewayErrorKind.parse,
        'choices 结构异常，网关可能不支持图生图',
        raw: resp.toString(),
      );
    }
    final message = first['message'];
    if (message is Map) {
      // 常见形态 A：message.images[0].image_url.url
      final images = message['images'];
      if (images is List && images.isNotEmpty) {
        final img = images.first;
        final url = img is Map
            ? (img['image_url'] is Map
                ? (img['image_url'] as Map)['url']
                : img['url'])
            : null;
        final bytes = await _bytesFromAnyUrl(url?.toString());
        if (bytes != null) {
          return TryOnResult(bytes: bytes, endpoint: '/chat/completions');
        }
      }
      // 常见形态 B：content 数组里混着 image_url
      final content = message['content'];
      if (content is List) {
        for (final part in content) {
          if (part is Map && part['type'] == 'image_url') {
            final u = part['image_url'];
            final url = u is Map ? u['url'] : u;
            final bytes = await _bytesFromAnyUrl(url?.toString());
            if (bytes != null) {
              return TryOnResult(bytes: bytes, endpoint: '/chat/completions');
            }
          }
        }
        final text = content
            .whereType<Map>()
            .map((e) => e['text'])
            .whereType<String>()
            .join()
            .trim();
        if (text.isNotEmpty) {
          throw GatewayException(
            GatewayErrorKind.unsupported,
            '这个模型只回文字不回图，换支持图像编辑的模型（如 gpt-image-1 / seedream / gemini-2.5-flash-image）',
            raw: text,
          );
        }
      }
    }
    throw GatewayException(
      GatewayErrorKind.parse,
      '网关没有返回图片',
      raw: resp.toString(),
    );
  }

  // ---------- 内部 ----------

  /// v1.9 直连优先解析（edit 用途）：有直连凭证 → copyWith 换 baseUrl /
  /// 模型 / 编辑端点并换厂商密钥；无凭证 → 原样返回代理的 profile 与 key。
  Future<({GatewayProfile profile, String? apiKey})> _effective(
      GatewayProfile profile, String? apiKey) async {
    final ep = await DirectAiClient.resolveEndpoint(
      kind: 'edit',
      proxyBaseUrl: profile.baseUrl,
      proxyApiKey: apiKey,
    );
    if (!ep.direct) return (profile: profile, apiKey: apiKey);
    final directEndpoint = (ep.endpoint ?? '').trim();
    return (
      profile: profile.copyWith(
        baseUrl: ep.baseUrl,
        model: ep.model ?? profile.model,
        editEndpoint:
            directEndpoint.isEmpty ? profile.editEndpoint : directEndpoint,
      ),
      apiKey: ep.apiKey,
    );
  }

  Future<Map<String, dynamic>> _post(
    String url, {
    required Object data,
    required GatewayProfile profile,
    String? apiKey,
    required bool multipart,
  }) async {
    try {
      final resp = await _dio.post(
        url,
        data: data,
        options: Options(
          headers: {
            if (!multipart) 'Content-Type': 'application/json',
            if (apiKey != null && apiKey.trim().isNotEmpty)
              'Authorization': 'Bearer ${apiKey.trim()}',
          },
          // 图像生成慢，按配置翻倍
          sendTimeout: Duration(seconds: profile.timeoutSeconds),
          receiveTimeout: Duration(seconds: profile.timeoutSeconds + 60),
          validateStatus: (_) => true,
        ),
      );
      final code = resp.statusCode ?? 0;
      if (code == 401 || code == 403) {
        throw GatewayException(GatewayErrorKind.auth, '网关拒绝访问（HTTP $code），检查 API Key',
            statusCode: code);
      }
      if (code == 404 || code == 405) {
        throw GatewayException(
          GatewayErrorKind.unsupported,
          '这个地址没有图像编辑端点（HTTP $code）',
          statusCode: code,
        );
      }
      if (code >= 400) {
        final brief = resp.data?.toString() ?? '';
        throw GatewayException(
          GatewayErrorKind.http,
          '网关返回 HTTP $code：${brief.length > 200 ? '${brief.substring(0, 200)}…' : brief}',
          statusCode: code,
          raw: brief,
        );
      }
      final body = resp.data;
      final map = VisionGatewayService.looseDecode(body);
      if (map != null) return map;
      throw GatewayException(GatewayErrorKind.parse, '网关返回的不是 JSON 对象',
          raw: body?.toString());
    } on GatewayException {
      rethrow;
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
          throw GatewayException(GatewayErrorKind.network, '连接超时，检查网关地址是否可达');
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw GatewayException(
              GatewayErrorKind.network, '生成超时，图像模型通常要 30-90 秒，可在网关配置里调大超时');
        case DioExceptionType.connectionError:
          throw GatewayException(
              GatewayErrorKind.network, '连不上网关：${e.message ?? '网络不可达'}');
        default:
          throw GatewayException(
              GatewayErrorKind.network, '网络错误：${e.message ?? e.type.name}');
      }
    }
  }

  Future<Uint8List> _download(String url) async {
    final bytes = await _bytesFromAnyUrl(url);
    if (bytes == null) {
      throw GatewayException(GatewayErrorKind.network, '结果图下载失败，链接可能已过期');
    }
    return bytes;
  }

  Future<Uint8List?> _bytesFromAnyUrl(String? url) async {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma == -1) return null;
      try {
        return base64Decode(url.substring(comma + 1));
      } catch (e) {
        // 内嵌 base64 坏了 → 走「网关没有返回图片」的错误提示
        debugPrint('结果图 base64 解码失败：$e');
        return null;
      }
    }
    try {
      final resp = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          // 结果图走 CDN 也可能卡住，给个硬超时，避免任务永远「生成中」
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final data = resp.data;
      return data == null ? null : Uint8List.fromList(data);
    } catch (e) {
      // 下载失败返回 null，由调用方给出「结果图下载失败」的提示
      debugPrint('结果图下载失败：$e');
      return null;
    }
  }
}
