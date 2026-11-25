import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../services/file_bytes.dart';
import '../../services/gateway_profile.dart';
import '../../services/gateway_store.dart';
import '../../services/image_store.dart';
import '../../services/storage_service.dart';
import '../../services/try_on_service.dart';
import '../../services/wardrobe_backend.dart';
import '../../services/vision_gateway_service.dart';

/// 虚拟试穿的状态与队列。
///
/// 只放一个任务在跑：图像生成很贵，并发排队只会让用户等更久，
/// 而且失败时更难定位是哪一张出的问题。
class TryOnProvider extends ChangeNotifier {
  TryOnProvider(this._storage, {TryOnService? service})
      : _service = service ?? TryOnService();

  final StorageService _storage;
  final TryOnService _service;
  GatewayStore? _store;
  late final WardrobeBackend _backend = WardrobeBackend(_storage);
  BackendConfig? _config;

  List<TryOnTask> _tasks = [];
  String? _runningId;
  String? _error;
  bool _degraded = false;
  GatewayProfile? _profile;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 页面退出后 generate 仍会跑完并落库，只是不再通知已销毁的监听者
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  List<TryOnTask> get tasks => List.unmodifiable(_tasks);
  String? get runningId => _runningId;
  String? get error => _error;

  /// 网关不可用时为 true：页面应直接展示搭配预览而不是报错
  bool get degraded => _degraded;
  bool get busy => _runningId != null;
  GatewayProfile? get profile => _profile;

  Future<void> load() async {
    _tasks = _storage.getAllTryOnTasks();
    _store ??= GatewayStore(_storage);
    _profile = await _store!.load(GatewayKind.edit);
    _config = await _backend.config();
    _degraded = !(_config?.edit ?? false);
    _notify();
  }

  BackendConfig? get serviceConfig => _config;

  Future<void> refreshGateway() async {
    _store ??= GatewayStore(_storage);
    _profile = await _store!.load(GatewayKind.edit);
    _config = await _backend.refresh();
    _degraded = !(_config?.edit ?? false);
    _notify();
  }

  /// 跑一次试穿。返回的任务对象里带成功/失败原因，页面据此决定渲染。
  Future<TryOnTask> generate({
    required String personImagePath,
    required List<Clothing> items,
    String? extraNote,
  }) async {
    if (_runningId != null) {
      _error = '上一张还在生成，等它出来再试';
      _notify();
      for (final t in _tasks) {
        if (t.id == _runningId) return t;
      }
      return _placeholder(personImagePath, items);
    }

    final now = DateTime.now();
    final task = TryOnTask(
      id: 'tryon_${now.millisecondsSinceEpoch}',
      personImagePath: personImagePath,
      itemIds: items.map((c) => c.id).toList(),
      status: TryOnStatus.pending,
      createdAt: now,
    );
    _tasks.insert(0, task);
    await _storage.saveTryOnTask(task);
    _error = null;
    _runningId = task.id;
    _notify();

    _store ??= GatewayStore(_storage);
    final profile = _profile ?? await _store!.load(GatewayKind.edit);
    _profile = profile;

    // 未配置或明确不支持 → 直接降级，不把它当成错误
    if (!profile.configured || !profile.supportsImageEdit) {
      task
        ..status = TryOnStatus.failed
        ..degraded = true
        ..errorMessage = !profile.configured
            ? '管理员还没开通试穿，先看搭配预览吧'
            : '当前模型不支持图像编辑，先看搭配预览吧'
        ..finishedAt = DateTime.now();
      await _storage.saveTryOnTask(task);
      _degraded = true;
      _runningId = null;
      _notify();
      return task;
    }

    task.status = TryOnStatus.running;
    await _storage.saveTryOnTask(task);
    _notify();

    try {
      final bytes = await readFileBytes(personImagePath);
      if (bytes == null) {
        throw GatewayException(
            GatewayErrorKind.network, '读不到人像原图，可能已被系统清理');
      }
      final key = await _store!.readKey(GatewayKind.edit);
      final result = await _service.generate(
        personImage: bytes,
        items: items,
        profile: profile,
        apiKey: key,
        extraNote: extraNote,
      );

      final saved = await ImageStore.instance
          .saveBytes(result.bytes, prefix: 'tryon', ext: 'png');
      if (saved == null) {
        throw GatewayException(
            GatewayErrorKind.network, '结果图保存失败，检查存储空间');
      }

      task
        ..status = TryOnStatus.success
        ..resultImagePath = saved
        ..prompt = _service.buildPrompt(items, extraNote: extraNote)
        ..gatewayProfileId = profile.kind.key
        ..degraded = false
        ..finishedAt = DateTime.now();
      _degraded = false;
    } catch (e) {
      task
        ..status = TryOnStatus.failed
        ..errorMessage = e.toString()
        ..finishedAt = DateTime.now();
      _error = e.toString();
      _degraded = true;
    }

    await _storage.saveTryOnTask(task);
    _runningId = null;
    _tasks = _storage.getAllTryOnTasks();
    _notify();
    return task;
  }

  Future<TryOnTask> retry(TryOnTask task, List<Clothing> items) async {
    await _storage.deleteTryOnTask(task.id);
    _tasks.removeWhere((t) => t.id == task.id);
    _notify();
    return generate(
      personImagePath: task.personImagePath,
      items: items,
    );
  }

  Future<void> deleteTask(String id) async {
    String? resultPath;
    for (final t in _tasks) {
      if (t.id == id) resultPath = t.resultImagePath;
    }
    await ImageStore.instance.deleteQuietly(resultPath);
    await _storage.deleteTryOnTask(id);
    _tasks = _storage.getAllTryOnTasks();
    _notify();
  }

  /// 编辑搭配的名称 / 分类 / 标签，立即落库
  Future<void> updateMeta(
    TryOnTask task, {
    String? name,
    String? category,
    List<String>? tags,
  }) async {
    task.outfitName = name?.trim().isEmpty ?? true ? null : name!.trim();
    task.outfitCategory =
        category?.trim().isEmpty ?? true ? null : category!.trim();
    task.outfitTags = (tags == null || tags.isEmpty) ? null : tags;
    await _storage.saveTryOnTask(task);
    _tasks = _storage.getAllTryOnTasks();
    _notify();
  }

  TryOnTask _placeholder(String path, List<Clothing> items) => TryOnTask(
        id: 'busy',
        personImagePath: path,
        itemIds: items.map((c) => c.id).toList(),
        createdAt: DateTime.now(),
      );

  /// 结果图的字节（分享用）
  Future<Uint8List?> resultBytes(TryOnTask task) =>
      readFileBytes(task.resultImagePath ?? '');
}
