import 'package:hive/hive.dart';

part 'try_on_task.g.dart';

/// 虚拟试穿任务状态机：
/// pending → running → success / failed（可重试）
class TryOnStatus {
  static const String pending = 'pending';
  static const String running = 'running';
  static const String success = 'success';
  static const String failed = 'failed';

  static const Map<String, String> names = {
    pending: '排队中',
    running: '生成中',
    success: '已完成',
    failed: '失败',
  };

  static String name(String status) => names[status] ?? status;
}

/// 一次 2D 虚拟试穿任务。
///
/// 设计要点：
/// - 独立表，不污染衣物/搭配数据
/// - 人像原图与结果图都落本地文件系统，Hive 只存路径
/// - 失败保留原图与 prompt，允许换网关重试
@HiveType(typeId: 7)
class TryOnTask extends HiveObject {
  @HiveField(0)
  String id;

  /// 人像照片本地路径
  @HiveField(1)
  String personImagePath;

  /// 参与试穿的单品 id 列表
  @HiveField(2)
  List<String> itemIds;

  /// pending / running / success / failed
  @HiveField(3)
  String status;

  /// 成功后的结果图路径
  @HiveField(4)
  String? resultImagePath;

  /// 实际发给模型的提示词（便于复现）
  @HiveField(5)
  String? prompt;

  /// 失败原因（中文可读）
  @HiveField(6)
  String? errorMessage;

  /// 使用哪个编辑网关
  @HiveField(7)
  String? gatewayProfileId;

  @HiveField(8)
  DateTime createdAt;

  @HiveField(9)
  DateTime? finishedAt;

  /// 是否已降级为搭配预览（网关不可用时）
  @HiveField(10)
  bool degraded;

  /// 搭配名称（可编辑，为空时显示「未命名试穿」）
  @HiveField(11)
  String? outfitName;

  /// 分类：通勤 / 约会 / 休闲 / 度假 / 运动 …
  @HiveField(12)
  String? outfitCategory;

  /// 自定义标签
  @HiveField(13)
  List<String>? outfitTags;

  TryOnTask({
    required this.id,
    required this.personImagePath,
    this.itemIds = const [],
    this.status = TryOnStatus.pending,
    this.resultImagePath,
    this.prompt,
    this.errorMessage,
    this.gatewayProfileId,
    required this.createdAt,
    this.finishedAt,
    this.degraded = false,
    this.outfitName,
    this.outfitCategory,
    this.outfitTags,
  });

  String get displayName {
    final n = outfitName?.trim();
    return (n != null && n.isNotEmpty) ? n : '未命名试穿';
  }

  bool get isRunning => status == TryOnStatus.running;
  bool get isSuccess => status == TryOnStatus.success;

  /// 一套搭配是否包含这几件（用于首页入口判断）
  bool coversItems(List<String> ids) {
    if (ids.isEmpty || itemIds.isEmpty) return false;
    return ids.every(itemIds.contains);
  }
}
