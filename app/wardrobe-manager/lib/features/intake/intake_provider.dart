import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/ai_mapping.dart';
import '../../data/clothing_naming.dart';
import '../../models/models.dart';
import '../../providers/wardrobe_provider.dart';
import '../../services/ai_service.dart';
import '../../services/cutout_service.dart';
import '../../services/direct_ai_client.dart';
import '../../services/exif_cleaner.dart';
import '../../services/file_bytes.dart';
import '../../services/gateway_profile.dart';
import '../../services/image_store.dart';
import '../../services/wardrobe_backend.dart';
import '../../services/white_bg_pipeline.dart';
import '../../services/white_background_service.dart';

/// #2 后台入库任务状态。
class IntakeStatus {
  static const String pending = 'pending';
  static const String running = 'running';
  static const String completed = 'completed';
  static const String failed = 'failed';

  static const Map<String, String> names = {
    pending: '排队中',
    running: '处理中',
    completed: '已完成',
    failed: '失败',
  };
}

/// 一条「单件快速入库」任务：识别 → 命名 → 抠图 → 白底 → 保存。
///
/// 内存队列：不进 Hive，重启 App 后清空（已入库的衣物不受影响）。
/// Hive 持久化留给下轮；真要做必须手写 TypeAdapter 且可空追加。
class IntakeTask {
  final String id;

  /// 原图在本机文件系统中的路径
  final String sourceImagePath;

  String status;
  String stepLabel;

  /// 失败原因（中文，供「重试 / 自定义保存」两条出口展示）
  String? errorMessage;

  /// 降级说明（分割/白底失败但任务仍完成时保留）
  String? note;

  final DateTime createdAt;
  DateTime? finishedAt;

  /// 识别成功后的草稿（失败任务点「自定义保存」时预填 add_clothing_sheet）
  Clothing? draft;

  String? cutoutImagePath;
  bool cutoutTransparent = false;
  String? whiteBgImagePath;
  String? savedClothingId;

  IntakeTask({
    required this.id,
    required this.sourceImagePath,
    required this.createdAt,
    this.status = IntakeStatus.pending,
    this.stepLabel = '排队中',
  });
}

/// 应用内后台任务队列：上传后立即返回，串行处理
/// （一次一张，避免多个大图请求把网关打挂）。
///
/// 骨架复刻 auto_split_provider：串行 _pump + _runTokens 代际令牌 +
/// 单任务 180 秒超时 + 失败可重试。与 auto_split 并存不冲突：
/// Intake 是「单件快速入库」路径，auto_split 是「全身照拆多件」路径。
class IntakeProvider extends ChangeNotifier {
  final WardrobeProvider wardrobe;
  final CutoutService cutout;

  late final WardrobeBackend backend = WardrobeBackend(wardrobe.storage);
  late final AIService ai = AIService(tokenProvider: backend.token);

  IntakeProvider({required this.wardrobe, CutoutService? cutout})
      : cutout = cutout ?? const LocalEdgeCutoutService();

  final List<IntakeTask> _tasks = [];
  bool _queueRunning = false;
  bool _disposed = false;

  /// 任务代际令牌：重试/删除会作废在途轮次，旧一轮返回时
  /// 不再写任务状态，避免覆盖新一轮结果（与 auto_split 同款）。
  final Map<String, int> _runTokens = {};

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 页面销毁后队列可能仍在跑，只更新内存，不再通知已销毁的监听者
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  List<IntakeTask> get tasks => _tasks;
  bool get queueRunning => _queueRunning;

  /// 进行中（排队 + 处理）任务数，徽标用
  List<IntakeTask> get activeTasks => _tasks
      .where((t) => t.status == IntakeStatus.pending || t.status == IntakeStatus.running)
      .toList();

  int get activeCount => activeTasks.length;

  // ---------- 入队 ----------

  /// 把一批单件照片加入队列，返回成功入队数。
  /// 只做存图 + 建任务，不等待整条处理链（上传后即可继续操作）。
  Future<int> enqueue(List<({Uint8List bytes, String name})> images) async {
    if (images.isEmpty) return 0;
    if (!ImageStore.instance.available) return 0; // Web 没有本地文件系统
    var added = 0;
    for (final img in images) {
      final path = await ImageStore.instance.saveBytes(
        img.bytes,
        prefix: 'intake',
        ext: _extOf(img.name),
      );
      if (path == null) continue;
      _tasks.insert(0, IntakeTask(
        id: const Uuid().v4(),
        sourceImagePath: path,
        createdAt: DateTime.now(),
      ));
      added++;
    }
    if (added > 0) {
      _notify();
      unawaited(_pump());
    }
    return added;
  }

  String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return 'jpg';
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.length > 4 ? 'jpg' : ext;
  }

  // ---------- 队列 ----------

  Future<void> _pump() async {
    if (_queueRunning) return;
    _queueRunning = true;
    _notify();
    try {
      while (true) {
        final next = _tasks
            .where((t) => t.status == IntakeStatus.pending)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (next.isEmpty) break;
        try {
          // 单任务硬超时：网关挂住时不会让队列永远卡在「处理中」
          await _runTask(next.first).timeout(const Duration(seconds: 180));
        } catch (e) {
          final t = next.first;
          if (t.status == IntakeStatus.running) {
            if (t.savedClothingId != null) {
              // 180 秒超时但任务其实已入库（保存正好卡在超时窗口内）：
              // 按完成处理，避免界面误报失败后用户点重试造成重复入库
              t.status = IntakeStatus.completed;
              t.stepLabel = '已完成';
              t.finishedAt = DateTime.now();
            } else {
              t.status = IntakeStatus.failed;
              t.errorMessage = '处理超时，可点重试继续';
              t.finishedAt = DateTime.now();
            }
            _replace(t);
            _notify();
          }
        }
      }
    } finally {
      _queueRunning = false;
      _notify();
    }
  }

  /// EXIF 清理放独立 isolate 跑：必须独立函数/独立作用域。
  ///
  /// 原理：Dart 闭包捕获的是变量槽（Context），同一函数作用域里的所有
  /// 闭包共享同一个 Context 对象——只要 _runTask 里还有 mine() 这类局部
  /// 函数捕获了 task/this（→ Hive Box → StorageBackendVm → SendPort），
  /// 留在原作用域的 Isolate.run 闭包被发送时就会把整个 Context 序列化
  /// 进 isolate，真机抛 object is unsendable（重试永远无效）。
  /// 提取成 static 函数后，闭包 Context 只含自己的参数 data（纯字节），
  /// 与 _runTask 的局部函数彻底隔离。
  static Future<CleanImage?> _cleanInIsolate(Uint8List data) =>
      Isolate.run(() => ExifCleaner.prepare(data, maxSide: 768, quality: 82));

  Future<void> _runTask(IntakeTask task) async {
    // 本轮的代际令牌：只有令牌仍属于自己的那一轮才允许写终态
    final token = (_runTokens[task.id] ?? 0) + 1;
    _runTokens[task.id] = token;
    bool mine() => _runTokens[task.id] == token && !_disposed;

    task.status = IntakeStatus.running;
    task.errorMessage = null;
    task.stepLabel = '识别中';
    _replace(task);
    _notify();

    try {
      final bytes = await readFileBytes(task.sourceImagePath);
      if (bytes == null) {
        throw StateError('读不到原图，可能已被系统清理');
      }

      // 上传前清理 EXIF（GPS/机型/拍摄时间）并限长边；失败则原文上传。
      // 重编码放 isolate，避免大图卡 UI（与 auto_split 同款）。
      // 纯识别不生图：768px 足够（省上传时间与 vision token）。
      // 注意：Isolate.run 必须经 _cleanInIsolate 独立作用域间接调用，
      // 闭包才不会连带捕获 mine()/task/this（详见该方法注释）。
      final cleaned = await _cleanInIsolate(bytes)
          .timeout(const Duration(seconds: 20), onTimeout: () => null);

      final result = await ai
          .recognizeClothingFromBase64(base64Encode(cleaned?.bytes ?? bytes));
      if (result.isFallback) {
        throw StateError('AI 识别暂时不可用（连不上服务或未开通），可点重试，或选「自定义保存」手动填写');
      }
      if (!mine()) return;

      // ---------- 识别 → 中文命名 ----------
      final category = AiMapping.category(result.category);
      final subCategory = AiMapping.subCategory(result.subCategory, category);
      // #15：AI 自报颜色直存（词典优先、原文保留、首字母大写），不再锁预设
      final colorZh = normalizeAiColor(result.color);
      final zhPattern = result.pattern == null || result.pattern!.trim().isEmpty
          ? null
          : toChinesePattern(result.pattern!.trim());
      final rawLabel = [
        result.brand ?? '',
        result.subCategory,
        result.category,
      ].where((s) => s.trim().isNotEmpty).join(' ');
      final parsed =
          parseChineseClothingName(rawLabel, colorHint: colorZh);
      final brandZh = parsed.brand ??
          (result.brand != null && result.brand!.trim().isNotEmpty
              ? result.brand!.trim()
              : null);
      final thickness = result.thickness < 0
          ? 0
          : (result.thickness > 4 ? 4 : result.thickness);
      final material = result.material != null &&
              MaterialType.names.containsKey(result.material)
          ? result.material
          : null;

      final draft = Clothing(
        id: 'c_${const Uuid().v4()}',
        imageUrl: '',
        category: category,
        subCategory: subCategory,
        color: colorZh,
        pattern: zhPattern,
        styles: AiMapping.styles(result.styles),
        seasons: AiMapping.seasons(result.seasons),
        occasions: result.occasions
            .where(Occasion.names.containsKey)
            .toList(growable: false),
        brand: brandZh,
        material: material,
        thickness: thickness,
        tempMin: result.tempMin,
        tempMax: result.tempMax,
        createdAt: DateTime.now(),
        customName:
            parsed.name.isNotEmpty && parsed.hasCategory ? parsed.name : null,
        aiCategory: rawLabel,
        aiConfidence: result.confidence,
      );
      task.draft = draft;
      if (!mine()) return;

      // ---------- 抠图 ----------
      task.stepLabel = '抠图中';
      _replace(task);
      _notify();
      CutoutResult cut;
      try {
        cut = await cutout.process(bytes, BBox.empty);
      } catch (e) {
        cut = CutoutResult(
          bytes: bytes,
          transparent: false,
          note: '抠图出错，已保留原图',
        );
      }
      if (!mine()) return;
      if (cut.transparent) {
        final path = await ImageStore.instance.saveBytes(
          cut.bytes,
          prefix: 'intake_piece',
          ext: 'png',
        );
        task.cutoutImagePath = path;
        task.cutoutTransparent = path != null;
        if (path == null) {
          task.note = '抠图结果保存失败，已使用原图';
        }
      } else {
        task.note = cut.note ?? '背景不纯，未生成透明底';
      }

      // ---------- 白底（两步流水线，按设置降级） ----------
      task.stepLabel = '白底处理中';
      _replace(task);
      _notify();
      var mode = 'local';
      try {
        final cfg = await backend.config();
        mode = cfg.whiteBgMode; // local | server | off
      } catch (_) {
        // 配置拉不到就按本地处理，不阻断
      }
      if (mode != 'off') {
        // server 模式直连优先（white_bg 用途，与 add_clothing_sheet 同款）：
        // 有凭证 → 直发厂商图像编辑端点，无凭证/解析失败 → 后台代理；
        // local 模式本地合成白底。
        final pipeline = mode == 'server'
            ? await _serverWhiteBgPipeline()
            : const WhiteBgPipeline();
        // 抠图结果直接复用：分割步上方已经跑过，这里不再让流水线重跑一遍
        //（省一倍 CPU，且美化输入与已保存的透明底保持一致）；
        // 抠图失败时传原图，与旧行为（流水线自己分割同样失败）一致。
        final res = await pipeline.process(
          cut.transparent ? cut.bytes : bytes,
          steps: const WhiteBgSteps(segment: false),
        );
        if (!mine()) return;
        if (res.beautified) {
          final path = await ImageStore.instance.saveBytes(
            res.bytes,
            prefix: 'intake_whitebg',
            ext: res.extension,
          );
          task.whiteBgImagePath = path;
          if (path == null) {
            task.note = '白底图保存失败，已使用抠图/原图';
          }
        }
        if (res.note != null && res.note!.isNotEmpty) {
          task.note = task.note == null || task.note!.isEmpty
              ? res.note
              : '${task.note}；${res.note}';
        }
      } else {
        task.note = task.note == null || task.note!.isEmpty
            ? '已按设置跳过白底图'
            : task.note;
      }

      // ---------- 保存入库 ----------
      task.stepLabel = '保存中';
      _replace(task);
      _notify();
      if (!mine()) return;
      draft.imageUrl = task.whiteBgImagePath ?? '';
      draft.originalImagePath = task.sourceImagePath;
      draft.cutoutImagePath = task.cutoutTransparent ? task.cutoutImagePath : null;
      draft.sourceType = 'intake';
      draft.sourcePhotoId = task.id;
      draft.cutoutStatus = task.cutoutTransparent ? 'success' : 'failed';

      final saved = await wardrobe.addClothingBatch([draft]);
      if (saved == 0) {
        throw StateError('入库失败：本地存储未就绪，可点重试或自定义保存');
      }
      // 先记录已入库再判令牌：即使本作废/超时，savedClothingId 也已落上，
      // _pump 超时兜底与 retryTask 守卫据此避免重复入库
      task.savedClothingId = draft.id;
      if (!mine()) return;
      task.status = IntakeStatus.completed;
      task.stepLabel = '已完成';
      task.finishedAt = DateTime.now();
      _replace(task);
      _notify();
    } catch (e) {
      if (!mine()) return;
      task.status = IntakeStatus.failed;
      task.stepLabel = '失败';
      task.errorMessage = _zhError(e);
      task.finishedAt = DateTime.now();
      _replace(task);
      _notify();
    }
  }

  String _zhError(Object e) {
    // StateError 的 toString 前缀是 "Bad state: "，Exception 是 "Exception: "
    final s = e
        .toString()
        .replaceFirst(RegExp(r'^(Bad state|StateError|Exception): '), '')
        .trim();
    return s.isEmpty ? '处理失败，请点重试' : s;
  }

  /// server 模式白底流水线：有 white_bg 直连凭证 → 直连厂商图像编辑端点
  ///（直连失败不回退代理，落到流水线自身的分割/原图降级）；
  /// 无凭证 / 过期 / 解析失败 → 后台代理（行为与旧版一致）。
  Future<WhiteBgPipeline> _serverWhiteBgPipeline() async {
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

  void _replace(IntakeTask task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i == -1) {
      _tasks.insert(0, task);
    } else {
      _tasks[i] = task;
    }
  }

  // ---------- 失败出口 ----------

  /// 出口一：重试（整条链重跑）
  Future<void> retryTask(String taskId) async {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final task = _tasks[i];
    if (task.status != IntakeStatus.failed) return;
    if (task.savedClothingId != null) {
      // 上一轮其实已入库（超时误报）：改判完成，不再重跑，避免重复入库
      task.status = IntakeStatus.completed;
      task.stepLabel = '已完成';
      task.errorMessage = null;
      task.finishedAt = DateTime.now();
      _replace(task);
      _notify();
      return;
    }
    task.status = IntakeStatus.pending;
    task.stepLabel = '排队中';
    task.errorMessage = null;
    _replace(task);
    _notify();
    unawaited(_pump());
  }

  Future<void> deleteTask(String taskId) async {
    // 删除令牌条目即作废在途轮次：僵尸返回时 mine() 为 false（null != token），
    // 不会复活任务；顺带清掉 _runTokens 里的条目，不随任务数增长
    _runTokens.remove(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    _notify();
  }
}
