/// 网关类型：视觉（拆分/识图）、文本（点评/推荐）、图像编辑（试穿，迭代1）
enum GatewayKind { vision, text, edit }

extension GatewayKindX on GatewayKind {
  String get key {
    switch (this) {
      case GatewayKind.vision:
        return 'vision';
      case GatewayKind.text:
        return 'text';
      case GatewayKind.edit:
        return 'edit';
    }
  }

  String get label {
    switch (this) {
      case GatewayKind.vision:
        return '视觉模型';
      case GatewayKind.text:
        return '文本模型';
      case GatewayKind.edit:
        return '图像编辑模型';
    }
  }

  String get hint {
    switch (this) {
      case GatewayKind.vision:
        return '用来识别全身照、拆出单品，必须支持图片输入';
      case GatewayKind.text:
        return '用来写搭配点评、风格建议';
      case GatewayKind.edit:
        return '虚拟试穿用，必须支持图像编辑（迭代 1）';
    }
  }

  static GatewayKind fromKey(String key) {
    switch (key) {
      case 'text':
        return GatewayKind.text;
      case 'edit':
        return GatewayKind.edit;
      default:
        return GatewayKind.vision;
    }
  }
}

/// 一份网关配置。API Key 不在这里，单独进安全存储。
class GatewayProfile {
  final GatewayKind kind;
  String baseUrl;
  String model;
  int timeoutSeconds;
  double temperature;

  /// 网关是否支持图片输入（vision 必须为 true）
  bool supportsImageInput;

  /// 网关是否支持 JSON 模式（不支持也能用，靠提示词 + 容错解析）
  bool supportsJsonOutput;

  /// 图像编辑端点（edit 用），默认为空时走 /images/edits
  String editEndpoint;

  /// 图像编辑能力
  bool supportsImageEdit;

  GatewayProfile({
    required this.kind,
    this.baseUrl = '',
    this.model = '',
    this.timeoutSeconds = 90,
    this.temperature = 0.3,
    this.supportsImageInput = true,
    this.supportsJsonOutput = false,
    this.editEndpoint = '/images/edits',
    this.supportsImageEdit = false,
  });

  /// 够不够用来发起请求
  bool get configured =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 规范化 baseUrl（去掉尾部斜杠，补 /v1 交给调用方判断）
  String get normalizedBaseUrl {
    var u = baseUrl.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  GatewayProfile copyWith({
    String? baseUrl,
    String? model,
    int? timeoutSeconds,
    double? temperature,
    bool? supportsImageInput,
    bool? supportsJsonOutput,
    String? editEndpoint,
    bool? supportsImageEdit,
  }) {
    return GatewayProfile(
      kind: kind,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      temperature: temperature ?? this.temperature,
      supportsImageInput: supportsImageInput ?? this.supportsImageInput,
      supportsJsonOutput: supportsJsonOutput ?? this.supportsJsonOutput,
      editEndpoint: editEndpoint ?? this.editEndpoint,
      supportsImageEdit: supportsImageEdit ?? this.supportsImageEdit,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.key,
        'baseUrl': baseUrl,
        'model': model,
        'timeoutSeconds': timeoutSeconds,
        'temperature': temperature,
        'supportsImageInput': supportsImageInput,
        'supportsJsonOutput': supportsJsonOutput,
        'editEndpoint': editEndpoint,
        'supportsImageEdit': supportsImageEdit,
      };

  factory GatewayProfile.fromJson(Map<String, dynamic> json) {
    return GatewayProfile(
      kind: GatewayKindX.fromKey(json['kind'] as String? ?? 'vision'),
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 90,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.3,
      supportsImageInput: json['supportsImageInput'] as bool? ?? true,
      supportsJsonOutput: json['supportsJsonOutput'] as bool? ?? false,
      editEndpoint: json['editEndpoint'] as String? ?? '/images/edits',
      supportsImageEdit: json['supportsImageEdit'] as bool? ?? false,
    );
  }
}
