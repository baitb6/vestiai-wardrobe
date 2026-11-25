import 'package:hive/hive.dart';

part 'split_task.g.dart';

/// 拆分任务状态
class SplitStatus {
  static const String pending = 'pending';
  static const String running = 'running';
  static const String success = 'success';
  static const String failed = 'failed';
  static const String imported = 'imported';

  static const Map<String, String> names = {
    pending: '排队中',
    running: '识别中',
    success: '待确认',
    failed: '失败',
    imported: '已入库',
  };
}

/// 一次「全身照拆单品」任务。批量上传时一张照片一条任务。
@HiveType(typeId: 6)
class SplitTask extends HiveObject {
  @HiveField(0)
  String id;

  /// 整身照在文件系统中的路径
  @HiveField(1)
  String sourceImagePath;

  @HiveField(2)
  String status;

  /// 模型返回的原始结果（JSON 字符串），失败时也保留，便于排查
  @HiveField(3)
  String? resultJson;

  @HiveField(4)
  String? errorMessage;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  DateTime? finishedAt;

  /// 识别出的单品数 / 已入库数（冗余字段，列表页直接显示）
  @HiveField(7)
  int? itemCount;

  @HiveField(8)
  int? importedCount;

  /// 产生这条结果的网关配置 ID
  @HiveField(9)
  String? gatewayProfileId;

  SplitTask({
    required this.id,
    required this.sourceImagePath,
    this.status = SplitStatus.pending,
    this.resultJson,
    this.errorMessage,
    required this.createdAt,
    this.finishedAt,
    this.itemCount,
    this.importedCount,
    this.gatewayProfileId,
  });

  bool get isRunning => status == SplitStatus.running;

  bool get isFailed => status == SplitStatus.failed;

  bool get isDone => status == SplitStatus.imported;
}
