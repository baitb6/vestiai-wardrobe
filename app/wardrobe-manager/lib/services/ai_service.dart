import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'wardrobe_backend.dart';

/// AI 服务（视觉识别 / 搭配建议）。
///
/// 地址与密钥不在客户端保存：所有请求都走管理后台代理，
/// 由后台按用途选择模型并注入密钥。App 端只带设备凭据。
class AIService {
  AIService({Future<String?> Function()? tokenProvider})
      : _tokenProvider = tokenProvider {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.baseUrl = WardrobeBackend.proxyBaseUrl;
        final token = await _tokenProvider?.call();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        options.headers['Content-Type'] = 'application/json';
        handler.next(options);
      },
    ));
  }

  final Future<String?> Function()? _tokenProvider;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 120),
  ));

  /// 后台统一下发，客户端不再提供模型名
  String get visionModel => 'auto';
  String get textModel => 'auto';

  /// 连通性检测：能拉到 /api/app/config 就算连上。
  Future<List<String>> testConnection() async {
    try {
      final token = await _tokenProvider?.call();
      if (token == null || token.isEmpty) {
        throw Exception('还没连上 AI 服务，请检查网络后重试');
      }
      final resp = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
      )).get('${WardrobeBackend.baseUrl}/api/app/config',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      final data = resp.data;
      if (data is Map && data['ok'] == true) {
        final ai = data['ai'] as Map? ?? const {};
        return [
          if (ai['vision'] == true) '视觉识别',
          if (ai['text'] == true) '文本分析',
          if (ai['edit'] == true) '图像编辑',
          if (ai['white_bg'] == true) '白底商品图',
        ];
      }
      return const [];
    } on DioException catch (e) {
      throw Exception(_describeDio(e));
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// 批量识别衣服（逐张走 base64 通道）
  Future<List<ClothingRecognitionResult>> recognizeMultipleClothes(
      List<String> base64Images) async {
    final results = <ClothingRecognitionResult>[];
    for (final b64 in base64Images) {
      results.add(await recognizeClothingFromBase64(b64));
    }
    return results;
  }
  
  /// 分析衣柜照片（整柜识别）：入参是 base64，Web / 移动端通用
  Future<WardrobeAnalysisResult> analyzeWardrobe(String base64Image) async {
    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': visionModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': _getWardrobeAnalysisPrompt(),
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image',
                },
              },
            ],
          },
        ],
        'max_tokens': 2048,
        'temperature': 0.3,
      });
      
      final content = response.data['choices'][0]['message']['content'] as String;
      return _parseWardrobeAnalysis(content);
    } catch (e) {
      debugPrint('整柜识别失败，已返回离线兜底结果：${_briefError(e)}');
      return _getMockWardrobeAnalysis();
    }
  }
  
  /// 生成穿搭建议
  Future<OutfitSuggestion> generateOutfitSuggestion({
    required String prompt,
    String? occasion,
    String? season,
    double? temperature,
    List<String>? availableClothingIds,
    List<Clothing>? availableClothes,
  }) async {
    try {
      final systemPrompt = _getOutfitSuggestionSystemPrompt();
      final userPrompt = _buildOutfitUserPrompt(
        prompt: prompt,
        occasion: occasion,
        season: season,
        temperature: temperature,
        availableClothes: availableClothes,
      );
      
      final response = await _dio.post('/chat/completions', data: {
        'model': textModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'max_tokens': 2048,
        'temperature': 0.7,
      });
      
      final content = response.data['choices'][0]['message']['content'] as String;
      return _parseOutfitSuggestion(content, availableClothingIds);
    } catch (e) {
      debugPrint('穿搭建议生成失败，已返回离线兜底结果：${_briefError(e)}');
      return _getMockOutfitSuggestion(availableClothingIds);
    }
  }
  
  /// 语音转文字：尚未接入（见 README「已知限制」）
  /// 保留接口，接入系统 ASR / Whisper 时在这里实现。
  Future<String> speechToText(String audioPath) async {
    throw UnimplementedError('语音输入尚未接入');
  }
  
  // ============ 私有方法 ============

  /// 把 Dio 异常翻译成用户能看懂的中文一句话
  String _describeDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接 AI 服务超时，请检查网络';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'AI 服务响应超时，请稍后重试';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        // v1.8 全部走后台代理：错误信封 {ok:false,message:"中文"}优先透传，
        // 用户能直接看到「管理员还没有配置可用的模型」这类可行动提示，
        // 而不是让他去检查自己根本没有的 API Key。
        final data = e.response?.data;
        if (data is Map &&
            data['message'] is String &&
            (data['message'] as String).isNotEmpty) {
          return data['message'] as String;
        }
        if (code == 401 || code == 403) return 'AI 服务拒绝了这次请求（HTTP $code），请稍后重试';
        if (code >= 500) return 'AI 服务异常（HTTP $code），稍后再试';
        return 'AI 服务返回 HTTP $code';
      case DioExceptionType.connectionError:
        return '连不上 AI 服务：${e.message ?? '网络不可达'}';
      case DioExceptionType.badCertificate:
        return '证书校验失败，网关可能用了自签名证书';
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        return '网络错误：${e.message ?? e.type.name}';
    }
  }

  /// 日志用：异常压成一句话，Dio 异常走中文分类
  String _briefError(Object e) {
    if (e is DioException) return _describeDio(e);
    return e.toString();
  }
  
  /// 从 base64 识别衣服
  Future<ClothingRecognitionResult> recognizeClothingFromBase64(String base64Image) async {
    try {
      final response = await _dio.post('/chat/completions', data: {
        'model': visionModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': _getClothingRecognitionPrompt(),
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image',
                },
              },
            ],
          },
        ],
        'max_tokens': 1024,
        'temperature': 0.3,
      });
      
      final content = response.data['choices'][0]['message']['content'] as String;
      return _parseClothingResult(content);
    } catch (e) {
      debugPrint('AI 识别失败，已返回离线兜底结果：${_briefError(e)}');
      return _getMockClothingResult();
    }
  }
  
  String _getClothingRecognitionPrompt() {
    return '''请识别这张图片中的衣服，并以 JSON 格式返回以下信息：
{
  "category": "衣服类别（tops/bottoms/outerwear/dress/shoes/accessories/underwear）",
  "subCategory": "具体类别（如 t_shirt, jeans, jacket, sneakers 等）",
  "color": "主要颜色（中文，如 白色/黑色/藏青）",
  "pattern": "图案（纯色/条纹/格子/印花等）",
  "styles": ["风格标签（casual/formal/sporty/minimalist/streetwear/vintage）"],
  "seasons": ["适合季节（spring/summer/autumn/winter）"],
  "material": "材质，从这些里选：cotton(纯棉)/wool(羊毛)/cashmere(羊绒)/linen(亚麻)/silk(真丝)/quick_dry(速干)/denim(牛仔)/polyester(聚酯纤维)/nylon(锦纶)/down(羽绒)/leather(皮革)/blended(混纺)/other",
  "thickness": "厚度0-4（0极薄~4特厚）",
  "tempMin": "适合温度下限摄氏度整数",
  "tempMax": "适合温度上限摄氏度整数",
  "occasions": ["适合场合（daily/work/dating/party/interview/travel/sport/home）"],
  "brand": "品牌名（识别不出为null）",
  "confidence": 0.95
}

只返回 JSON，不要其他说明文字。''';
  }
  
  String _getWardrobeAnalysisPrompt() {
    return '''请分析这张衣柜照片，识别所有可见的衣服，并以 JSON 格式返回：
{
  "zones": [
    {
      "name": "区域名称",
      "items": [
        {
          "category": "衣服类别",
          "subCategory": "具体类别",
          "color": "颜色",
          "confidence": 0.9
        }
      ]
    }
  ],
  "totalCount": 5
}

只返回 JSON，不要其他说明文字。''';
  }
  
  String _getOutfitSuggestionSystemPrompt() {
    return '''你是一位专业的时尚搭配顾问。你的任务是根据用户的衣柜内容和需求，提供个性化的穿搭建议。

回答格式（JSON）：
{
  "name": "搭配名称",
  "description": "搭配说明（为什么这样搭配，适合什么场合）",
  "styleTips": "穿搭小技巧",
  "confidence": 0.9
}

要求：
1. 结合用户已有的衣服进行搭配（上衣+下装+外套+鞋+配饰）
2. 考虑场合、天气、温度、季节等因素
3. 优先考虑材质的保暖性/透气性：低温选羊毛/羽绒/抓绒，高温选亚麻/速干/真丝
4. 给出专业的搭配理由
5. 只返回 JSON，不要其他文字''';
  }
  
  String _buildOutfitUserPrompt({
    required String prompt,
    String? occasion,
    String? season,
    double? temperature,
    List<Clothing>? availableClothes,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('用户需求：$prompt');
    
    if (occasion != null) buffer.writeln('场合：$occasion');
    if (season != null) buffer.writeln('季节：$season');
    if (temperature != null) {
      buffer.writeln('当前温度：${temperature.toStringAsFixed(0)}°C');
    }
    
    if (availableClothes != null && availableClothes.isNotEmpty) {
      buffer.writeln('\n用户衣柜中的衣服（含材质与适穿温度）：');
      for (final cloth in availableClothes.take(30)) {
        final material = cloth.material != null
            ? ' 材质:${cloth.material}'
            : '';
        final tempRange = cloth.tempMin != null && cloth.tempMax != null
            ? ' 适穿:${cloth.tempMin}-${cloth.tempMax}°C'
            : '';
        buffer.writeln(
            '- ${cloth.displayName}: ${cloth.category}/${cloth.subCategory}, ${cloth.color}$material$tempRange');
      }
    }
    
    return buffer.toString();
  }
  
  ClothingRecognitionResult _parseClothingResult(String content) {
    try {
      // 提取 JSON 部分
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch != null) {
        final json = jsonDecode(jsonMatch.group(0)!);
        return ClothingRecognitionResult(
          category: json['category'] ?? 'tops',
          subCategory: json['subCategory'] ?? 't_shirt',
          color: json['color'] ?? '白色',
          pattern: json['pattern'],
          styles: List<String>.from(json['styles'] ?? ['casual']),
          seasons: List<String>.from(json['seasons'] ?? ['spring', 'summer']),
          material: json['material'],
          thickness: (json['thickness'] as num?)?.toInt() ?? 2,
          tempMin: (json['tempMin'] as num?)?.toInt(),
          tempMax: (json['tempMax'] as num?)?.toInt(),
          occasions: List<String>.from(json['occasions'] ?? const []),
          confidence: (json['confidence'] ?? 0.9).toDouble(),
          brand: json['brand'],
        );
      }
    } catch (e) {
      debugPrint('识别结果 JSON 解析失败，使用兜底值：$e');
    }
    return _getMockClothingResult();
  }
  
  WardrobeAnalysisResult _parseWardrobeAnalysis(String content) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch != null) {
        final json = jsonDecode(jsonMatch.group(0)!);
        final zones = (json['zones'] as List).map((zone) {
          return WardrobeZone(
            name: zone['name'],
            items: (zone['items'] as List).map((item) {
              return WardrobeItem(
                boundingBox: [0, 0, 100, 100],
                category: item['category'] ?? 'tops',
                subCategory: item['subCategory'] ?? 'unknown',
                color: item['color'] ?? '未知',
                confidence: (item['confidence'] ?? 0.8).toDouble(),
              );
            }).toList(),
          );
        }).toList();
        
        return WardrobeAnalysisResult(
          zones: zones,
          totalCount: json['totalCount'] ?? zones.fold(0, (sum, z) => sum + z.items.length),
        );
      }
    } catch (e) {
      debugPrint('衣柜分析 JSON 解析失败，使用兜底值：$e');
    }
    return _getMockWardrobeAnalysis();
  }
  
  OutfitSuggestion _parseOutfitSuggestion(String content, List<String>? clothingIds) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch != null) {
        final json = jsonDecode(jsonMatch.group(0)!);
        return OutfitSuggestion(
          name: json['name'] ?? 'AI 推荐搭配',
          description: json['description'] ?? '',
          styleTips: json['styleTips'],
          clothingIds: clothingIds?.take(3).toList() ?? [],
          occasion: 'daily',
          season: 'spring',
          confidence: (json['confidence'] ?? 0.85).toDouble(),
        );
      }
    } catch (e) {
      debugPrint('穿搭建议 JSON 解析失败，使用兜底值：$e');
    }
    return _getMockOutfitSuggestion(clothingIds);
  }
  
  // ============ Mock 数据（降级方案）============
  
  ClothingRecognitionResult _getMockClothingResult() {
    return ClothingRecognitionResult(
      category: 'tops',
      subCategory: 't_shirt',
      color: '白色',
      pattern: '纯色',
      styles: ['casual', 'minimalist'],
      seasons: ['spring', 'summer'],
      material: 'cotton',
      thickness: 1,
      tempMin: 15,
      tempMax: 28,
      occasions: ['daily'],
      confidence: 0,
      isFallback: true,
    );
  }
  
  WardrobeAnalysisResult _getMockWardrobeAnalysis() {
    return WardrobeAnalysisResult(
      zones: [
        WardrobeZone(
          name: '上层',
          items: [
            WardrobeItem(
              boundingBox: [100, 50, 200, 150],
              category: 'outerwear',
              subCategory: 'jacket',
              color: '黑色',
              confidence: 0.92,
            ),
          ],
        ),
        WardrobeZone(
          name: '中层',
          items: [
            WardrobeItem(
              boundingBox: [100, 200, 200, 300],
              category: 'tops',
              subCategory: 't_shirt',
              color: '白色',
              confidence: 0.95,
            ),
          ],
        ),
      ],
      totalCount: 2,
      isFallback: true,
    );
  }
  
  OutfitSuggestion _getMockOutfitSuggestion(List<String>? clothingIds) {
    return OutfitSuggestion(
      name: '离线建议',
      description: 'AI 服务暂时没连上，这段是本地规则引擎兜底生成的说明。'
          '联网后稍等片刻再试，即可获得真正的搭配点评。',
      clothingIds: clothingIds?.take(3).toList() ?? [],
      occasion: 'daily',
      season: 'spring',
      confidence: 0,
      isFallback: true,
    );
  }
}

/// 衣服识别结果
class ClothingRecognitionResult {
  final String category;
  final String subCategory;
  final String color;
  final String? pattern;
  final List<String> styles;
  final List<String> seasons;
  final String? material;
  final int thickness;
  final int? tempMin;
  final int? tempMax;
  final List<String> occasions;
  final double confidence;
  final String? brand;

  /// true = 接口失败后的离线默认值，需要用户手工核对
  final bool isFallback;
  
  ClothingRecognitionResult({
    required this.category,
    required this.subCategory,
    required this.color,
    this.pattern,
    required this.styles,
    required this.seasons,
    this.material,
    this.thickness = 2,
    this.tempMin,
    this.tempMax,
    this.occasions = const [],
    required this.confidence,
    this.brand,
    this.isFallback = false,
  });
}

/// 衣柜分析结果
class WardrobeAnalysisResult {
  final List<WardrobeZone> zones;
  final int totalCount;

  /// true = 接口失败后的离线兜底数据，需要用户手工核对
  final bool isFallback;

  WardrobeAnalysisResult({
    required this.zones,
    required this.totalCount,
    this.isFallback = false,
  });
}

/// 衣柜区域
class WardrobeZone {
  final String name;
  final List<WardrobeItem> items;
  
  WardrobeZone({
    required this.name,
    required this.items,
  });
}

/// 衣柜中的衣服项
class WardrobeItem {
  final List<double> boundingBox;
  final String category;
  final String subCategory;
  final String color;
  final double confidence;
  
  WardrobeItem({
    required this.boundingBox,
    required this.category,
    required this.subCategory,
    required this.color,
    required this.confidence,
  });
}

/// 穿搭建议
class OutfitSuggestion {
  final String name;
  final String description;
  final String? styleTips;
  final List<String> clothingIds;
  final String occasion;
  final String season;
  final double confidence;

  /// true = 接口失败后的离线兜底文案，不是真实模型输出
  final bool isFallback;

  OutfitSuggestion({
    required this.name,
    required this.description,
    this.styleTips,
    required this.clothingIds,
    required this.occasion,
    required this.season,
    required this.confidence,
    this.isFallback = false,
  });
}
