import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'direct_ai_client.dart';
import 'storage_service.dart';

/// App 与「管理后台」之间的唯一通道。
///
/// 设计前提（很重要）：
/// - 用户不需要注册账号、不需要填模型地址、不需要填 API Key；
/// - App 首次启动自动拿一个设备凭据，之后所有 AI 请求都由后台代理；
/// - v1.9：图片类请求（拆衣/试穿/白底）可凭后台下发的直连凭证优先直连厂商
///   （密钥只存 secure storage），无凭证/过期则继续走后台代理，行为不变；
/// - 后台不可达时只降级 AI 功能，绝不影响记账主流程。
class WardrobeBackend {
  /// 可在构建时覆盖：flutter build --dart-define=WM_BACKEND=https://your.domain
  static const String _defaultBase =
      String.fromEnvironment('WM_BACKEND', defaultValue: 'https://ai.slongb.xyz');

  static const String _tokenKey = 'backend_device_token';
  static const String _deviceKey = 'backend_device_id';

  /// v1.9 直连凭证：明文 JSON 只存 secure storage，不落 Hive、不进备份。
  static const String _directCredKey = 'direct_ai_credential';

  final StorageService storage;
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _token;
  String? _deviceId;
  BackendConfig? _config;
  DateTime? _configAt;
  String? _lastError;

  /// v1.9 直连凭证的内存缓存与最近一次取数时间（做失败节流）。
  DirectCredential? _direct;
  DateTime? _directAt;

  WardrobeBackend(this.storage) {
    // v1.9：图片类服务（拆衣/试穿/白底）经 DirectAiClient 取直连凭证。
    // 多实例共享同一 secure storage 与同一后台地址，后注册覆盖前者无副作用。
    DirectAiClient.register(
      fetchCredential: () => directCredential(),
      proxyBase: proxyBaseUrl,
    );
  }

  static String get baseUrl {
    final v = _defaultBase.trim();
    return v.replaceAll(RegExp(r'/+$'), '');
  }

  /// 代理网关根地址：OpenAI 兼容协议，App 侧无需再改任何代码。
  static String get proxyBaseUrl => '$baseUrl/api/app/ai/v1';

  static bool get _secureSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// 复用同一个 Dio：免得每个请求都重建 BaseOptions / 连接池，
  /// 行为与原先逐次新建完全一致（无拦截器、无会话状态）。
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 150),
    validateStatus: (_) => true,
  ));

  String get deviceId {
    final cached = _deviceId;
    if (cached != null && cached.isNotEmpty) return cached;
    final saved = storage.getSetting<String>(_deviceKey);
    if (saved != null && saved.length >= 8) {
      _deviceId = saved;
      return saved;
    }
    final rand = Random.secure();
    final id = List.generate(24, (_) => rand.nextInt(16).toRadixString(16)).join();
    _deviceId = id;
    storage.setSetting<String>(_deviceKey, id);
    return id;
  }

  String get platformName {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  Future<String?> _readCachedToken() async {
    if (_token != null) return _token;
    if (!_secureSupported) return null;
    try {
      final v = await _secure.read(key: _tokenKey);
      if (v != null && v.isNotEmpty) _token = v;
      return v;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToken(String token) async {
    _token = token;
    if (!_secureSupported) return;
    try {
      await _secure.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  Future<void> _clearToken() async {
    _token = null;
    if (!_secureSupported) return;
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {}
  }

  /// 是否已经接入过服务（仅用于界面文案，不代表网络可用）。
  bool get hasToken => _token != null;

  Future<String?> token({bool refresh = false}) async {
    if (!refresh) {
      final cached = await _readCachedToken();
      if (cached != null && cached.isNotEmpty) return cached;
    } else {
      await _clearToken();
    }
    return _registerDevice();
  }

  Future<String?> _registerDevice() async {
    try {
      final r = await _dio.post('/api/app/device', data: {
        'device_id': deviceId,
        'platform': platformName,
        'app_version': await _appVersion(),
        'name': _deviceName(),
      });
      final data = r.data;
      if (r.statusCode == 200 && data is Map && data['token'] is String) {
        final t = data['token'] as String;
        await _saveToken(t);
        _lastError = null;
        if (data['config'] is Map) {
          _config = BackendConfig.fromJson(
              Map<String, dynamic>.from(data['config'] as Map));
          _configAt = DateTime.now();
        }
        return t;
      }
      _lastError = _describe(r);
      return null;
    } on DioException catch (e) {
      _lastError = _describeDio(e);
      return null;
    }
  }

  String _deviceName() {
    final p = platformName;
    if (p == 'android') return '安卓手机';
    if (p == 'ios') return 'iPhone';
    if (p == 'web') return '网页预览';
    return '桌面端';
  }

  Future<String> _appVersion() async {
    final v = storage.getSetting<String>('app_version');
    // 与 pubspec.yaml 的 version 保持一致；后台用它做最低版本拦截
    return (v == null || v.isEmpty) ? '1.9.0' : v;
  }

  /// 拉取「哪些 AI 能力可用」。5 分钟内复用缓存，避免每次开页都请求。
  Future<BackendConfig> config({bool force = false}) async {
    final cached = _config;
    if (!force &&
        cached != null &&
        _configAt != null &&
        DateTime.now().difference(_configAt!) < const Duration(minutes: 5)) {
      return cached;
    }
    var authRejected = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      final t = await token(refresh: attempt > 0);
      if (t == null) break;
      try {
        final r = await _dio.get('/api/app/config',
            options: Options(headers: {'Authorization': 'Bearer $t'}));
        if (r.statusCode == 200 && r.data is Map) {
          _config = BackendConfig.fromJson(
              Map<String, dynamic>.from(r.data as Map));
          _configAt = DateTime.now();
          _lastError = null;
          return _config!;
        }
        if (r.statusCode == 401 || r.statusCode == 403) {
          // 设备被停用/移除：这是"服务明确拒绝"，不能退回旧缓存
          // 显示"已连接"——否则状态芯片最长 5 分钟撒谎。
          authRejected = true;
          _lastError = _describe(r);
          continue;
        }
        _lastError = _describe(r);
        break;
      } on DioException catch (e) {
        _lastError = _describeDio(e);
        break;
      }
    }
    // 网络故障退回旧缓存（显示最近已知状态）；服务明确拒绝则如实报不可用
    final fallback = authRejected
        ? BackendConfig.unavailable(_lastError ?? '设备已被管理员停用')
        : (cached ?? BackendConfig.unavailable(_lastError ?? '连不上服务'));
    _config = fallback;
    _configAt = DateTime.now();
    return fallback;
  }

  Future<BackendConfig> refresh() => config(force: true);

  // ---------- v1.9 直连凭证 ----------

  /// 直连凭证读取：内存有效判断 → secure storage 恢复 → 过期自动重取
  ///（重取做 5 分钟内存节流，仿 config() 缓存节奏，避免后台抖动被连环打）。
  /// 拿不到（未开通 / 过期 / 后台不可达 / 被拒）一律返回 null，调用方静默走代理。
  Future<DirectCredential?> directCredential({bool force = false}) async {
    if (!force) {
      final cached = _direct;
      if (cached != null && cached.validNow) return cached;
      // 设备重启 / 其他实例刚拿到新凭证：先从 secure storage 恢复
      final restored = await _readDirectCredential();
      if (restored != null && restored.validNow) {
        _direct = restored;
        return restored;
      }
    }
    final now = DateTime.now();
    final last = _directAt;
    final throttled = !force &&
        last != null &&
        now.difference(last) < const Duration(minutes: 5);
    if (throttled) return null;
    _directAt = now;
    final fresh = await fetchDirectCredential();
    if (fresh != null && fresh.validNow) {
      _direct = fresh;
      return fresh;
    }
    _direct = null;
    return null;
  }

  /// 凭设备凭据向后台申请直连凭证（POST /api/app/credential）。
  /// 成功：把明文凭证与 expires_at 原样存 secure storage（key [_directCredKey]）。
  /// 401（设备凭据被服务端轮换/失效）→ 先刷新设备凭据重试一次，与
  /// config()/whiteBackground() 同款；仍 401 或 403（未授权直连）→ 清本地缓存。
  /// 其余失败保持缓存不动、返回 null（静默，不写 _lastError、不打日志）。
  Future<DirectCredential?> fetchDirectCredential() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final t = await token(refresh: attempt > 0);
        if (t == null) return null;
        final r = await _dio.post('/api/app/credential',
            options: Options(headers: {'Authorization': 'Bearer $t'}));
        final code = r.statusCode ?? 0;
        if (code == 401 && attempt == 0) continue;
        if (code == 401 || code == 403) {
          await _clearDirectCredential();
          return null;
        }
        if (code == 200 && r.data is Map) {
          final data = Map<String, dynamic>.from(r.data as Map);
          if (data['ok'] == false) {
            // 后台明确说没开通直连 → 同步清缓存
            await _clearDirectCredential();
            return null;
          }
          final cred = DirectCredential.fromJson(data);
          if (cred == null) {
            // 结构不完整（缺 expires_at 或用途全空）按无凭证处理
            return null;
          }
          await _saveDirectCredential(data);
          return cred;
        }
        // 其他状态码（5xx 等）：缓存不动，本轮走代理
        return null;
      } catch (_) {
        return null; // 网络故障等：静默走代理
      }
    }
    return null;
  }

  Future<DirectCredential?> _readDirectCredential() async {
    if (!_secureSupported) return null;
    try {
      final v = await _secure.read(key: _directCredKey);
      if (v == null || v.isEmpty) return null;
      final decoded = jsonDecode(v);
      if (decoded is Map) {
        return DirectCredential.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveDirectCredential(Map<String, dynamic> data) async {
    if (!_secureSupported) return;
    try {
      await _secure.write(key: _directCredKey, value: jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _clearDirectCredential() async {
    _direct = null;
    if (!_secureSupported) return;
    try {
      await _secure.delete(key: _directCredKey);
    } catch (_) {}
  }

  String? get lastError => _lastError;

  /// 后台代跑白底图（仅在管理员把模式设为 server 时调用）。
  /// 单张图片经服务器转发给模型，服务器不保存。
  Future<Uint8List> whiteBackground(Uint8List bytes) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final t = await token(refresh: attempt > 0);
      if (t == null) throw StateError(_lastError ?? '连不上 AI 服务');
      final form = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: 'garment.png'),
      });
      try {
        final r = await _dio.post('/api/app/white-bg',
            data: form,
            options: Options(
              responseType: ResponseType.bytes,
              headers: {'Authorization': 'Bearer $t'},
            ));
        if (r.statusCode == 200) {
          final raw = r.data;
          if (raw is List<int> && raw.length > 200) {
            return Uint8List.fromList(raw);
          }
          throw StateError('服务没有返回有效图片');
        }
        if (r.statusCode == 401 || r.statusCode == 403) continue;
        throw StateError(_describe(r));
      } on DioException catch (e) {
        throw StateError(_describeDio(e));
      }
    }
    throw StateError(_lastError ?? '白底图生成失败，请稍后再试');
  }

  /// 照片数字人：上传本人全身照，返回三视角形象图。
  /// 服务器只在内存里转发，不保存照片、不回传模型名。
  Future<Uint8List> generateAvatar(Uint8List bytes) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final t = await token(refresh: attempt > 0);
      if (t == null) throw StateError(_lastError ?? '连不上 AI 服务');
      final form = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: 'me.jpg'),
      });
      try {
        final r = await _dio.post('/api/app/avatar',
            data: form,
            options: Options(
              responseType: ResponseType.bytes,
              headers: {'Authorization': 'Bearer $t'},
            ));
        if (r.statusCode == 200) {
          final raw = r.data;
          if (raw is List<int> && raw.length > 200) {
            return Uint8List.fromList(raw);
          }
          throw StateError('服务没有返回有效图片');
        }
        if (r.statusCode == 401 || r.statusCode == 403) continue;
        throw StateError(_describe(r));
      } on DioException catch (e) {
        throw StateError(_describeDio(e));
      }
    }
    throw StateError(_lastError ?? '形象生成失败，请稍后再试');
  }

  String _describe(Response<dynamic> r) {
    final data = r.data;
    if (data is Map && data['message'] != null) return data['message'].toString();
    if (data is List<int>) {
      try {
        final decoded = jsonDecode(utf8.decode(data));
        if (decoded is Map && decoded['message'] != null) {
          return decoded['message'].toString();
        }
      } catch (_) {}
    }
    if (r.statusCode == 401) return '设备凭据失效，请重新打开 App';
    if (r.statusCode == 403) return '管理员暂未开放 AI 服务';
    if (r.statusCode == 429) return '请求太频繁，请稍后再试';
    return 'AI 服务返回 HTTP ${r.statusCode ?? 0}';
  }

  String _describeDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接 AI 服务超时，请检查网络';
      case DioExceptionType.receiveTimeout:
        return 'AI 服务响应超时，请稍后再试';
      case DioExceptionType.connectionError:
        return '连不上 AI 服务，请检查网络';
      default:
        return e.message ?? '网络请求失败';
    }
  }
}

/// 后台下发的服务状态（不含任何模型地址或密钥）。
class BackendConfig {
  final bool aiEnabled;
  final bool vision;
  final bool text;
  final bool edit;
  final bool avatarReady;
  final bool whiteBgReady;
  final String whiteBgMode; // local | server | off
  final String notice;
  final String minVersion;
  final String error;

  const BackendConfig({
    required this.aiEnabled,
    required this.vision,
    required this.text,
    required this.edit,
    required this.avatarReady,
    required this.whiteBgReady,
    required this.whiteBgMode,
    required this.notice,
    required this.minVersion,
    required this.error,
  });

  factory BackendConfig.fromJson(Map<String, dynamic> m) {
    final ai = (m['ai'] as Map?) ?? const {};
    final wb = (m['white_bg'] as Map?) ?? const {};
    return BackendConfig(
      aiEnabled: ai['enabled'] == true,
      vision: ai['vision'] == true,
      text: ai['text'] == true,
      edit: ai['edit'] == true,
      avatarReady: ai['avatar'] == true,
      whiteBgReady: ai['white_bg'] == true,
      whiteBgMode: (wb['mode'] as String?) ?? 'local',
      notice: (m['notice'] as String?) ?? '',
      minVersion: (m['min_version'] as String?) ?? '',
      error: '',
    );
  }

  factory BackendConfig.unavailable(String error) => BackendConfig(
        aiEnabled: false,
        vision: false,
        text: false,
        edit: false,
        avatarReady: false,
        whiteBgReady: false,
        whiteBgMode: 'local',
        notice: '',
        minVersion: '',
        error: error,
      );

  bool get online => error.isEmpty;

  bool get anyAi => aiEnabled && (vision || text || edit || avatarReady);

  /// 给界面用的一句话状态。
  String get summary {
    if (!online) return '未连接';
    if (!aiEnabled) return '管理员已关闭';
    if (!anyAi) return '待管理员配置';
    return '已连接';
  }
}
