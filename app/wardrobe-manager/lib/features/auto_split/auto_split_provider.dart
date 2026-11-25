import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/clothing_naming.dart';
import '../../models/models.dart';
import '../../services/cutout_service.dart';
import '../../services/duplicate_detector.dart';
import '../../services/exif_cleaner.dart';
import '../../services/file_bytes.dart';
import '../../services/gateway_profile.dart';
import '../../services/wardrobe_backend.dart';
import '../../services/gateway_store.dart';
import '../../services/image_store.dart';
import '../../services/storage_service.dart';
import '../../services/vision_gateway_service.dart';

/// 拆分流程的状态机与队列。
///
/// 设计约束（来自任务书）：
/// - 批量任务里单张失败不影响其他任务继续
/// - 任一环节失败都保留原图与任务，可重试
/// - 确认入库前所有修改都只在内存里，不写 Hive
class AutoSplitProvider extends ChangeNotifier {
  final StorageService storage;
  final GatewayStore gatewayStore;
  final VisionGatewayService vision;
  final CutoutService cutout;
  final DuplicateDetector detector;
  final ImageStore imageStore;
  late final WardrobeBackend backend = WardrobeBackend(storage);
  BackendConfig? _config;

  AutoSplitProvider({
    required this.storage,
    required this.gatewayStore,
    VisionGatewayService? vision,
    CutoutService? cutout,
    DuplicateDetector? detector,
    ImageStore? imageStore,
  })  : vision = vision ?? VisionGatewayService(),
        cutout = cutout ?? const LocalEdgeCutoutService(),
        detector = detector ?? DuplicateDetector(),
        imageStore = imageStore ?? ImageStore.instance {
    this.detector.fileReader = readFileBytes;
  }

  // ---------- 状态 ----------

  List<SplitTask> _tasks = [];
  final Map<String, List<SplitCandidate>> _drafts = {};
  final Set<String> _processingCutouts = {};
  bool _queueRunning = false;
  String? _lastError;
  UploadInfo? _lastUpload;
  bool _disposed = false;

  /// 任务代际令牌：_runTask 每次启动自增。
  /// 180 秒超时把任务标记为 failed 后，底层请求仍在后台跑；
  /// 用户立刻点重试会开启新一轮，旧一轮（僵尸）返回时不许再写
  /// 任务状态/裁片草稿，否则会覆盖新一轮结果、裁片生成两次。
  final Map<String, int> _runTokens = {};

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 页面销毁后队列可能仍在跑，只更新存储，不再通知已销毁的监听者
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// 视觉网关是否可用（未配置时页面直接引导去配置）
  GatewayProfile? _profile;
  bool _profileLoaded = false;

  List<SplitTask> get tasks => _tasks;
  String? get lastError => _lastError;

  /// 最近一次上传的压缩情况（页面上展示「原图 4.2 MB → 上传 380 KB」）
  UploadInfo? get lastUpload => _lastUpload;
  GatewayProfile? get visionProfile => _profile;
  bool get queueRunning => _queueRunning;

  List<SplitTask> get pendingTasks => _tasks
      .where((t) =>
          t.status == SplitStatus.pending || t.status == SplitStatus.running)
      .toList();

  List<SplitCandidate> draftsOf(String taskId) => _drafts[taskId] ?? const [];

  bool isCutoutRunning(String taskId) => _processingCutouts.contains(taskId);

  int get activeCount =>
      _tasks.where((t) => t.status == SplitStatus.success).length;

  Future<void> load() async {
    _tasks = storage.getAllSplitTasks();
    // 上次会话中断的任务会永远卡在 running（UI 显示“识别中”却无法重试），
    // 恢复成 failed 让用户可以点重试
    for (final t in _tasks) {
      if (t.status == SplitStatus.running) {
        t.status = SplitStatus.failed;
        t.errorMessage = '上次识别时应用被中断，点重试即可继续';
        t.finishedAt = DateTime.now();
        await storage.updateSplitTask(t);
      }
    }
    _profile = await gatewayStore.load(GatewayKind.vision);
    _config = await backend.config();
    _profileLoaded = true;
    _notify();
  }

  Future<void> refreshProfile() async {
    _profile = await gatewayStore.load(GatewayKind.vision);
    _config = await backend.refresh();
    _profileLoaded = true;
    _notify();
  }

  BackendConfig? get serviceConfig => _config;

  /// 是否已能发起拆分：以「管理员是否开通视觉模型」为准
  bool get canSplit => _profileLoaded && (_config?.vision ?? false);

  String? get configHint {
    if (!_profileLoaded) return '正在连接 AI 服务…';
    final c = _config;
    if (c == null || !c.online) {
      return 'AI 服务暂时连不上，联网后重试即可；也可以先手工录入衣物。';
    }
    if (!c.aiEnabled) {
      return '管理员暂停了 AI 服务，先手工录入吧。';
    }
    if (!c.vision) {
      return '管理员还没开通「AI 拆衣」，可以先手工录入衣物。';
    }
    return null;
  }

  // ---------- 入队 ----------

  /// 把一批图片加入任务队列。返回成功入队的任务数。
  Future<int> enqueueImages(List<({Uint8List bytes, String name})> images) async {
    if (images.isEmpty) return 0;
    var added = 0;
    for (final img in images) {
      // Web 没有文件系统：直接把字节存在任务里不可行，这里仅在 available 时工作
      final path = await imageStore.saveBytes(img.bytes,
          prefix: 'fullbody', ext: _extOf(img.name));
      if (path == null) continue;

      final task = SplitTask(
        id: const Uuid().v4(),
        sourceImagePath: path,
        status: SplitStatus.pending,
        createdAt: DateTime.now(),
        gatewayProfileId: _profile?.kind.key,
      );
      await storage.addSplitTask(task);
      _tasks.insert(0, task);
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

  /// 串行处理队列（一次一张，避免多个大图请求把网关打挂）
  Future<void> _pump() async {
    if (_queueRunning) return;
    _queueRunning = true;
    _notify();
    try {
      while (true) {
        final next = _tasks
            .where((t) => t.status == SplitStatus.pending)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (next.isEmpty) break;
        try {
          // 单任务硬超时：网关挂住 / 裁片过多时也不会让队列永远卡在 running
          await _runTask(next.first).timeout(const Duration(seconds: 180));
        } catch (e) {
          final t = next.first;
          if (t.status == SplitStatus.running) {
            t.status = SplitStatus.failed;
            t.errorMessage = '处理超时，可点重试继续';
            t.finishedAt = DateTime.now();
            await storage.updateSplitTask(t);
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
  /// 闭包共享同一个 Context 对象——_runTask 里的 mine() 捕获了 task
  /// （SplitTask 是 HiveObject → BoxImpl → StorageBackendVm → SendPort）
  /// 与 this（storage/gatewayStore 等重字段），Isolate.run 闭包若留在
  /// 原作用域，发送时会序列化整个 Context → object is unsendable。
  /// 提取成 static 函数后，闭包 Context 只含参数 data（纯字节）。
  static Future<CleanImage?> _cleanInIsolate(Uint8List data) =>
      Isolate.run(() => ExifCleaner.prepare(data, maxSide: 768, quality: 82));

  Future<void> _runTask(SplitTask task) async {
    // 本轮的代际令牌：只有令牌仍属于自己的那一轮才允许写终态
    final token = (_runTokens[task.id] ?? 0) + 1;
    _runTokens[task.id] = token;
    bool mine() => _runTokens[task.id] == token && !_disposed;
    task.status = SplitStatus.running;
    task.errorMessage = null;
    await storage.updateSplitTask(task);
    _replace(task);
    _notify();

    try {
      final profile = await gatewayStore.load(GatewayKind.vision);
      _profile = profile;
      final key = await gatewayStore.readKey(GatewayKind.vision);
      final bytes = await readFileBytes(task.sourceImagePath);
      if (bytes == null) {
        throw GatewayException(
            GatewayErrorKind.network, '读不到原图，可能已被系统清理');
      }

      // 上传前清理 EXIF（GPS/机型/拍摄时间）并限长边，失败则原文上传，
      // 绝不因为隐私清理失败而阻断识别。重编码放 isolate，避免大图卡 UI。
      // 拆衣是纯识别不生图：768px 足够模型看清单品（省一半上传时间与
      // vision token，识别精度无损——模型内部本来就会缩到 1K 以内）。
      // 注意：Isolate.run 必须经 _cleanInIsolate 独立作用域间接调用，
      // 闭包才不会连带捕获 mine()/task/this（详见该方法注释）。
      final cleaned = await _cleanInIsolate(bytes)
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
      _lastUpload = cleaned == null
          ? null
          : UploadInfo(
              originalBytes: cleaned.originalBytes,
              uploadedBytes: cleaned.bytes.length,
              width: cleaned.width,
              height: cleaned.height,
            );

      final result = await vision.splitOutfit(
        imageBytes: cleaned?.bytes ?? bytes,
        profile: profile,
        apiKey: key,
      );

      // 期间用户已重试/删除：本轮作废，结果丢弃（新一轮正在跑）
      if (!mine()) return;
      _drafts[task.id] = result.items;
      task.status = SplitStatus.success;
      task.resultJson = jsonEncode(result.items.map((e) => e.toJson()).toList());
      task.itemCount = result.items.length;
      task.finishedAt = DateTime.now();
      task.errorMessage = null;
      await storage.updateSplitTask(task);
      _replace(task);
      _notify();

      // 识别完立刻开始生成裁片（用户进不进确认页都先备好）
      unawaited(ensureCutouts(task.id));
    } on GatewayException catch (e) {
      if (!mine()) return;
      task.status = SplitStatus.failed;
      task.errorMessage = e.message;
      task.finishedAt = DateTime.now();
      // 原始响应留着，方便「查看详情」
      if (e.raw != null && e.raw!.isNotEmpty) {
        task.resultJson = e.raw;
      }
      await storage.updateSplitTask(task);
      _replace(task);
      _notify();
    } catch (e) {
      if (!mine()) return;
      task.status = SplitStatus.failed;
      task.errorMessage = '识别失败：$e';
      task.finishedAt = DateTime.now();
      await storage.updateSplitTask(task);
      _replace(task);
      _notify();
    }
  }

  void _replace(SplitTask task) {
    final i = _tasks.indexWhere((t) => t.id == task.id);
    if (i == -1) {
      _tasks.insert(0, task);
    } else {
      _tasks[i] = task;
    }
  }

  // ---------- 重试 ----------

  Future<void> retryTask(String taskId) async {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final task = _tasks[i];
    if (task.status != SplitStatus.failed) return;
    task.status = SplitStatus.pending;
    task.errorMessage = null;
    await storage.updateSplitTask(task);
    _replace(task);
    _notify();
    unawaited(_pump());
  }

  Future<void> deleteTask(String taskId) async {
    // 自增令牌作废在途的识别轮次：僵尸返回时 mine() 为 false，不会复活任务
    _runTokens[taskId] = (_runTokens[taskId] ?? 0) + 1;
    await storage.deleteSplitTask(taskId);
    _tasks.removeWhere((t) => t.id == taskId);
    _drafts.remove(taskId);
    _notify();
  }

  // ---------- 裁片 / 抠图 ----------

  /// 为某个任务的候选单品生成裁片（幂等，可重复调用）
  Future<void> ensureCutouts(String taskId) async {
    if (_processingCutouts.contains(taskId)) return;
    final drafts = _drafts[taskId];
    if (drafts == null || drafts.isEmpty) return;
    final pending = drafts.where((d) => d.imagePath == null).toList();
    if (pending.isEmpty) return;

    _processingCutouts.add(taskId);
    _notify();
    try {
      final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (taskIndex == -1) return;
      final source =
          await readFileBytes(_tasks[taskIndex].sourceImagePath);
      if (source == null) return;
      for (final draft in pending) {
        await _cutOne(draft, source);
        _notify();
      }
    } catch (e) {
      // 后台裁片出错不能把异常甩到 unawaited 里，更不能让任务永远停在生成中
      debugPrint('生成裁片失败：$e');
    } finally {
      _processingCutouts.remove(taskId);
      _notify();
    }
  }

  /// 单件重试抠图（用户调完 bbox 或点「重试」时）
  Future<void> recutCandidate(String taskId, SplitCandidate candidate) async {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final task = _tasks[i];
    final source = await readFileBytes(task.sourceImagePath);
    if (source == null) return;
    candidate.imagePath = null;
    candidate.cutoutStatus = 'pending';
    await _cutOne(candidate, source);
    _notify();
  }

  Future<void> _cutOne(SplitCandidate c, Uint8List source) async {
    try {
      final result = await cutout.process(source, c.bbox);
      final path = await imageStore.saveBytes(
        result.bytes,
        prefix: 'piece',
        ext: result.transparent ? 'png' : 'jpg',
      );
      c.imagePath = path;
      c.transparent = result.transparent;
      c.cutoutStatus = result.transparent ? 'success' : 'failed';
      c.cutoutNote = result.note;
    } catch (e) {
      c.cutoutStatus = 'failed';
      c.cutoutNote = '抠图出错：$e';
      c.imagePath = null;
    }
  }

  // ---------- 编辑 ----------

  void editCandidate(
    String taskId,
    SplitCandidate c, {
    String? category,
    String? subCategory,
    List<String>? colors,
    List<String>? styleTags,
    List<String>? seasons,
    BBox? bbox,
    bool? selected,
  }) {
    if (category != null && category != c.category) {
      c.category = category;
      // 换分类时子分类兜底，避免出现「上衣/牛仔裤」
      final allowed = ClothingSubCategory.subCategories[category] ?? const [];
      if (!allowed.contains(c.subCategory)) {
        c.subCategory = allowed.isEmpty ? 't_shirt' : allowed.first;
      }
    }
    if (subCategory != null) c.subCategory = subCategory;
    if (colors != null) c.colors = colors;
    if (styleTags != null) c.styleTags = styleTags;
    if (seasons != null) c.seasons = seasons;
    if (selected != null) c.selected = selected;
    if (bbox != null) {
      final moved = bbox.x != c.bbox.x ||
          bbox.y != c.bbox.y ||
          bbox.w != c.bbox.w ||
          bbox.h != c.bbox.h;
      c.bbox = bbox;
      if (moved) {
        c.userEdited = true;
        // bbox 变了，裁片作废，等用户点「重新裁剪」
        c.imagePath = null;
        c.cutoutStatus = 'pending';
        c.cutoutNote = '包围盒已改，需要重新裁剪';
      }
    }
    c.userEdited = true;
    _notify();
  }

  /// 删除误识别
  void removeCandidate(String taskId, SplitCandidate c) {
    final list = _drafts[taskId];
    if (list == null) return;
    list.remove(c);
    _notify();
  }

  /// 合并重复：把 source 合并进 target（颜色/标签取并集，bbox 取较大者）
  void mergeCandidates(String taskId, SplitCandidate source, SplitCandidate target) {
    final list = _drafts[taskId];
    if (list == null) return;
    target.colors = {...target.colors, ...source.colors}.toList();
    target.styleTags = {...target.styleTags, ...source.styleTags}.toList();
    target.seasons = {...target.seasons, ...source.seasons}.toList();
    target.extraTags = {...target.extraTags, ...source.extraTags}.toList();
    if (source.bbox.area > target.bbox.area) {
      target.bbox = source.bbox;
      target.imagePath = null;
      target.cutoutStatus = 'pending';
    }
    target.confidence =
        target.confidence > source.confidence ? target.confidence : source.confidence;
    list.remove(source);
    _notify();
  }

  // ---------- 重复检测 ----------

  /// 对某个任务的所有候选跑一遍重复检测（只在确认页提示，不阻止入库）
  Future<void> detectDuplicates(String taskId) async {
    final drafts = _drafts[taskId];
    if (drafts == null) return;
    final existing = storage.getAllClothes();
    for (final c in drafts) {
      final bytes = c.imagePath == null ? null : await readFileBytes(c.imagePath!);
      if (bytes == null) continue;
      final hit = await detector.findBest(
        candidateBytes: bytes,
        existing: existing,
        category: c.category,
        color: c.primaryColor,
      );
      c.duplicateHint = hit?.reason;
    }
    _notify();
  }

  // ---------- 入库 ----------

  /// 把勾选的候选写成 Clothing，返回实际入库数量
  Future<int> importSelected(String taskId, {required List<Clothing> existing}) async {
    final drafts = _drafts[taskId];
    if (drafts == null) return 0;
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return 0;
    final task = _tasks[taskIndex];

    final selected = drafts.where((d) => d.selected && d.imagePath != null).toList();
    if (selected.isEmpty) return 0;

    final now = DateTime.now();
    final clothes = <Clothing>[];
    for (final d in selected) {
      // #1：颜色英文归一；名称按「颜色+品类」中文规范生成，品牌剥离进详情
      final zhColor = normalizeAiColor(d.primaryColor); // #15 AI 自报颜色直存
      final parsed = parseChineseClothingName(d.rawCategory, colorHint: zhColor);
      clothes.add(Clothing(
        id: const Uuid().v4(),
        imageUrl: '',
        category: d.category,
        subCategory: d.subCategory,
        color: zhColor,
        customName: parsed.name.isNotEmpty && parsed.hasCategory
            ? parsed.name
            : null,
        brand: parsed.brand,
        styles: d.styleTags,
        seasons: d.seasons.isEmpty ? const [] : d.seasons,
        tags: d.extraTags,
        material: null,
        thickness: _thicknessFor(d.category),
        occasions: _occasionsFor(d.styleTags),
        createdAt: now,
        originalImagePath: task.sourceImagePath,
        cutoutImagePath: d.transparent ? d.imagePath : null,
        sourceType: 'autoSplit',
        sourcePhotoId: task.id,
        bboxX: d.bbox.x,
        bboxY: d.bbox.y,
        bboxW: d.bbox.w,
        bboxH: d.bbox.h,
        aiCategory: d.rawCategory.isEmpty ? d.category : d.rawCategory,
        aiTags: d.extraTags,
        aiColors: d.colors,
        aiConfidence: d.confidence,
        userEdited: d.userEdited,
        gatewayProfileId: 'vision',
        cutoutStatus: d.cutoutStatus,
      ));
    }

    // 这里负责真正落库，避免任务显示已导入但衣物实际未写入。
    for (final clothing in clothes) {
      await storage.addClothing(clothing);
    }
    task.status = SplitStatus.imported;
    task.importedCount = clothes.length;
    task.itemCount = drafts.length;
    task.finishedAt = DateTime.now();
    await storage.updateSplitTask(task);
    _replace(task);
    _notify();
    return clothes.length;
  }

  /// 生成待写入的 Clothing 列表（与 importSelected 同逻辑，但由页面负责写库）
  List<Clothing> buildClothingFromDrafts(String taskId) {
    final drafts = _drafts[taskId] ?? const [];
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return const [];
    final task = _tasks[taskIndex];
    final now = DateTime.now();
    return drafts.where((d) => d.selected).map((d) {
      // #1：与 importSelected 同款中文命名（颜色归一 + 品牌/颜色+品类）
      final zhColor = normalizeAiColor(d.primaryColor); // #15 AI 自报颜色直存
      final parsed = parseChineseClothingName(d.rawCategory, colorHint: zhColor);
      return Clothing(
        id: const Uuid().v4(),
        imageUrl: '',
        category: d.category,
        subCategory: d.subCategory,
        color: zhColor,
        customName: parsed.name.isNotEmpty && parsed.hasCategory
            ? parsed.name
            : null,
        brand: parsed.brand,
        styles: d.styleTags,
        seasons: d.seasons,
        tags: d.extraTags,
        thickness: _thicknessFor(d.category),
        occasions: _occasionsFor(d.styleTags),
        createdAt: now,
        originalImagePath: task.sourceImagePath,
        cutoutImagePath: d.transparent ? d.imagePath : null,
        sourceType: 'autoSplit',
        sourcePhotoId: task.id,
        bboxX: d.bbox.x,
        bboxY: d.bbox.y,
        bboxW: d.bbox.w,
        bboxH: d.bbox.h,
        aiCategory: d.rawCategory.isEmpty ? d.category : d.rawCategory,
        aiTags: d.extraTags,
        aiColors: d.colors,
        aiConfidence: d.confidence,
        userEdited: d.userEdited,
        gatewayProfileId: 'vision',
        cutoutStatus: d.cutoutStatus,
      );
    }).toList();
  }

  Future<void> markImported(String taskId, int count) async {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final task = _tasks[i];
    task.status = SplitStatus.imported;
    task.importedCount = count;
    task.finishedAt = DateTime.now();
    await storage.updateSplitTask(task);
    _replace(task);
    _notify();
  }

  int _thicknessFor(String category) {
    switch (category) {
      case ClothingCategory.outerwear:
        return 3;
      case ClothingCategory.shoes:
        return 2;
      case ClothingCategory.accessories:
        return 1;
      default:
        return 2;
    }
  }

  List<String> _occasionsFor(List<String> styles) {
    final out = <String>{};
    for (final s in styles) {
      switch (s) {
        case 'business':
        case 'formal':
          out.add(Occasion.work);
          break;
        case 'sporty':
          out.add(Occasion.sport);
          break;
        case 'dating':
          out.add(Occasion.dating);
          break;
        case 'party':
          out.add(Occasion.party);
          break;
        default:
          out.add(Occasion.daily);
      }
    }
    if (out.isEmpty) out.add(Occasion.daily);
    return out.toList();
  }

  /// 打开历史任务时把 resultJson 恢复成草稿
  void hydrateDraft(SplitTask task) {
    if (_drafts.containsKey(task.id)) return;
    final raw = task.resultJson;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['items'] : decoded;
      if (list is! List) return;
      _drafts[task.id] = list
          .whereType<Map>()
          .map((e) => SplitCandidate.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // 恢复的草稿没有裁片，按需重新生成
      for (final d in _drafts[task.id]!) {
        d.imagePath = null;
        d.cutoutStatus = 'pending';
      }
      _notify();
    } catch (_) {}
  }
}

/// 一次上传的体积信息，用于向用户证明「照片被压过、EXIF 被清过」
class UploadInfo {
  final int originalBytes;
  final int uploadedBytes;
  final int width;
  final int height;

  const UploadInfo({
    required this.originalBytes,
    required this.uploadedBytes,
    required this.width,
    required this.height,
  });

  String get originalLabel => _kb(originalBytes);
  String get uploadedLabel => _kb(uploadedBytes);
  String get sizeLabel => '$width×$height';

  /// 省下的比例 0-1
  double get savedRatio => originalBytes <= 0
      ? 0
      : ((originalBytes - uploadedBytes) / originalBytes).clamp(0.0, 1.0);

  static String _kb(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }
}
