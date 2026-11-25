import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/clothing_naming.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../services/weather_service.dart';
import '../services/recommendation_engine.dart';
import '../services/ai_service.dart';
import '../services/insights_service.dart';
import '../services/image_store.dart';
import '../services/wardrobe_backend.dart';

class WardrobeProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final WeatherService _weatherService = WeatherService();
  final RecommendationEngine _engine = RecommendationEngine();
  final InsightsService _insightsService = InsightsService();

  /// 当前城市（持久化在 settings）
  String _city = '武汉';
  WeatherInfo? _weather;
  bool _weatherLoading = false;
  String? _weatherError;
  String _weatherSource = '实时';
  List<String> _customStyles = [];

  // AI 服务状态（模型与密钥全部来自管理后台，App 内不保存任何用户配置）
  late final WardrobeBackend _backend = WardrobeBackend(_storage);
  late final AIService _aiService = AIService(tokenProvider: _backend.token);
  BackendConfig? _aiStatus;

  // 状态
  List<Clothing> _clothes = [];
  List<Outfit> _outfits = [];
  List<OutfitRecord> _records = [];
  List<PackingList> _packingLists = [];
  UserProfile? _profile;

  bool _isLoading = false;
  String? _error;

  // 筛选状态
  String? _selectedCategory;
  String? _selectedLocation;
  String? _selectedMaterial;
  String? _selectedColor;
  String? _selectedSeason;
  String? _selectedOccasion;
  String? _selectedTag;
  String _searchQuery = '';
  WardrobeSort _sort = WardrobeSort.newest;

  // 拆分任务（AI 全身照拆单品）
  List<SplitTask> _splitTasks = [];

  // 多衣橱空间
  List<WardrobeSpace> _spaces = [];
  String? _currentSpaceId;

  // 愿望清单
  List<WishItem> _wishItems = [];

  // Getters
  List<Clothing> get clothes => _filterClothes();
  List<Outfit> get outfits => _outfits;
  List<OutfitRecord> get records => _records;
  List<PackingList> get packingLists => _packingLists;
  List<PackingList> get upcomingPackingLists =>
      _packingLists.where((p) => !p.isPast).toList();
  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get totalClothes => _clothes.length;

  /// 未经过筛选的全部衣物（图片管家、备份等需要全量）
  List<Clothing> get allClothes => List.unmodifiable(_clothes);
  List<SplitTask> get splitTasks => _splitTasks;

  // ===== 多衣橱 =====

  List<WardrobeSpace> get spaces => List.unmodifiable(_spaces);

  /// 当前浏览的空间；null 表示默认衣橱（老数据都在这里）
  String? get currentSpaceId => _currentSpaceId;

  WardrobeSpace get currentSpace {
    // Hive 未就绪 / 空间表为空时给内置兜底，避免 _spaces.first 抛 StateError
    if (_spaces.isEmpty) return WardrobeSpace.builtin();
    return _spaces.firstWhere(
      (s) => s.id == _currentSpaceId,
      orElse: () => _spaces.first,
    );
  }

  /// 某个空间里的衣物件数
  int countInSpace(String? spaceId) =>
      _clothes.where((c) => c.belongsTo(spaceId)).length;

  // ===== 愿望清单 =====

  List<WishItem> get wishItems => List.unmodifiable(_wishItems);
  List<WishItem> get activeWishes =>
      _wishItems.where((w) => !w.purchased).toList();
  List<WishItem> get purchasedWishes =>
      _wishItems.where((w) => w.purchased).toList();
  int get wishCount => activeWishes.length;

  /// 所有被 Hive 引用的图片绝对路径：用于判断图片仓库里哪些是孤儿
  Set<String> get referencedImagePaths {
    final set = <String>{};
    void add(String? path) {
      if (path != null && path.isNotEmpty) set.add(path);
    }

    for (final c in _clothes) {
      add(c.originalImagePath);
      add(c.cutoutImagePath);
      add(c.maskPath);
      // 手动录入的照片可能以 data: 开头，也可能是文件路径
      if (!c.imageUrl.startsWith('data:')) add(c.imageUrl);
    }
    for (final t in _splitTasks) {
      add(t.sourceImagePath);
    }
    add(_profile?.avatarSheetPath);
    add(_profile?.avatarSourcePath);
    return set;
  }

  WardrobeSort get sort => _sort;
  String? get selectedColor => _selectedColor;
  String? get selectedSeason => _selectedSeason;
  String? get selectedOccasion => _selectedOccasion;
  String? get selectedTag => _selectedTag;

  /// 是否有任何筛选（用于显示「清除」）
  bool get hasActiveFilter =>
      _selectedCategory != null ||
      _selectedLocation != null ||
      _selectedMaterial != null ||
      _selectedColor != null ||
      _selectedSeason != null ||
      _selectedOccasion != null ||
      _selectedTag != null ||
      _searchQuery.isNotEmpty;

  /// 衣橱里出现过的颜色（筛选用）
  List<String> get availableColors {
    final set = <String>{};
    for (final c in _clothes) {
      if (c.color.trim().isEmpty) continue;
      set.add(c.color.trim());
    }
    return set.toList()..sort();
  }

  /// 衣橱里出现过的自由标签
  List<String> get availableTags {
    final set = <String>{};
    for (final c in _clothes) {
      set.addAll(c.tags);
      set.addAll(c.aiTags ?? const []);
    }
    return set.toList()..sort();
  }

  /// 存储服务（备份页需要直接读写）
  StorageService get storage => _storage;
  int get totalOutfits => _outfits.length;

  String get city => _city;
  WeatherInfo? get weather => _weather;
  bool get weatherLoading => _weatherLoading;
  String? get weatherError => _weatherError;
  String get weatherSource => _weatherSource;
  List<String> get customStyles => List.unmodifiable(_customStyles);

  Future<void> setCustomStyles(List<String> values) async {
    _customStyles = values
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    await _storage.setSetting<String>(
        'custom_styles', jsonEncode(_customStyles));
    notifyListeners();
  }
  RecommendationEngine get engine => _engine;

  /// 当前 AI 服务状态（只读，界面用）
  BackendConfig? get aiService => _aiStatus;

  /// 复用同一个设备凭据的 App 后台通道（数字人生成等直接调用）。
  WardrobeBackend get backend => _backend;

  /// 当前温度（无天气数据时按季节估计）
  double get currentTemperature =>
      _weather?.temperature ?? _seasonalFallbackTemp();

  double _seasonalFallbackTemp() {
    final m = DateTime.now().month;
    // 粗略的季节温度兜底（武汉基准）
    if (m <= 2 || m == 12) return 5;
    if (m <= 4) return 16;
    if (m <= 6) return 24;
    if (m <= 9) return 30;
    return 18;
  }

  // 初始化
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _storage.init();
      _city = _storage.getSetting<String>('city') ?? '武汉';
      _purgeLegacyAiSettings();
      _loadData();
      refreshWeather();       // 后台刷新，不阻塞启动
      primeAiService();       // 静默接入 AI 服务，失败不影响使用
    } catch (e) {
      _error = e.toString();
    }
    
    _isLoading = false;
    notifyListeners();
  }

  void _loadData() {
    _splitTasks = _storage.getAllSplitTasks();
    _spaces = _storage.getAllSpaces();
    _wishItems = _storage.getAllWishItems();
    final savedSpace = _storage.getSetting<String>('current_space_id');
    _currentSpaceId = _spaces.any((s) => s.id == savedSpace) ? savedSpace : null;
    _clothes = _storage.getAllClothes();
    _outfits = _storage.getAllOutfits();
    _records = _storage.getAllRecords();
    _packingLists = _storage.getAllPackingLists();
    _profile = _storage.getProfile();
    try {
      final raw = _storage.getSetting<String>('custom_styles');
      _customStyles = raw == null || raw.isEmpty
          ? []
          : (jsonDecode(raw) as List).map((e) => e.toString()).toList();
    } catch (_) {
      _customStyles = [];
    }
    
    // 如果没有用户配置，创建默认的
    if (_profile == null) {
      _profile = UserProfile(createdAt: DateTime.now());
      _storage.saveProfile(_profile!);
    }
  }

  // ========== 天气 ==========

  Future<void> refreshWeather() async {
    _weatherLoading = true;
    _weatherError = null;
    notifyListeners();
    try {
      final w = await _weatherService.getByCity(_city);
      _weather = w;
      _weatherSource = '实时';
      await _storage.setSetting<String>('weather_cache', jsonEncode({
        'city': w.city,
        'temperature': w.temperature,
        'tempMin': w.tempMin,
        'tempMax': w.tempMax,
        'weatherCode': w.weatherCode,
        'windSpeed': w.windSpeed,
        'humidity': w.humidity,
        'precipProb': w.precipProb,
      }));
    } catch (e) {
      // 天气拿不到不能让首页空着：优先用上次成功记录，其次给离线默认值
      _weatherError = e.toString();
      _weather = _cachedWeather() ?? _offlineWeather();
      _weatherSource = _cachedWeather() != null ? '上次记录' : '离线默认';
    }
    _weatherLoading = false;
    notifyListeners();
  }

  WeatherInfo? _cachedWeather() {
    final raw = _storage.getSetting<String>('weather_cache');
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return WeatherInfo(
        city: m['city'] as String? ?? _city,
        temperature: (m['temperature'] as num?)?.toDouble() ?? 20,
        tempMin: (m['tempMin'] as num?)?.toDouble() ?? 15,
        tempMax: (m['tempMax'] as num?)?.toDouble() ?? 25,
        weatherCode: (m['weatherCode'] as num?)?.toInt() ?? 1,
        windSpeed: (m['windSpeed'] as num?)?.toDouble() ?? 3,
        humidity: (m['humidity'] as num?)?.toInt() ?? 50,
        precipProb: (m['precipProb'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  WeatherInfo _offlineWeather() => WeatherInfo(
        city: _city,
        temperature: 20,
        tempMin: 15,
        tempMax: 25,
        weatherCode: 1,
        windSpeed: 3,
        humidity: 50,
        precipProb: 0,
      );

  /// 网络定位（不需要系统定位权限）；失败返回中文提示，引导手动选城市
  Future<String?> locateByIp() async {
    try {
      final city = await _weatherService.locateCityByIp();
      if (city == null || city.trim().isEmpty) {
        _weatherError = '没能自动定位到城市，请手动选择城市；'
            '如需精确定位，请在系统设置里授予位置权限';
        notifyListeners();
        return null;
      }
      await setCity(city.trim());
      return city.trim();
    } catch (e) {
      _weatherError = '自动定位失败，请手动选择城市；'
          '如需精确定位，请在系统设置里授予位置权限';
      notifyListeners();
      return null;
    }
  }

  Future<void> setCity(String newCity) async {
    _city = newCity;
    await _storage.setSetting<String>('city', newCity);
    notifyListeners();
    await refreshWeather();
  }

  // ========== AI 服务（由管理后台统一配置） ==========

  /// 清掉历史版本可能留在本机的明文密钥，避免旧配置继续生效。
  void _purgeLegacyAiSettings() {
    for (final key in [
      'ai_api_key', 'ai_key', 'ai_base_url',
      'ai_vision_model', 'ai_text_model',
      'ai_vision_key', 'ai_text_key', 'ai_edit_key',
    ]) {
      if ((_storage.getSetting<String>(key) ?? '').isNotEmpty) {
        _storage.setSetting<String>(key, '');
      }
    }
  }

  /// 静默接入：首次启动自动拿设备凭据，之后由后台下发可用能力。
  Future<void> primeAiService({bool force = false}) async {
    try {
      final cfg = force ? await _backend.refresh() : await _backend.config();
      _aiStatus = cfg;
      notifyListeners();
    } catch (_) {
      // 连不上就保持未知状态，AI 入口会显示「暂时连不上」
    }
  }

  // ========== 衣橱洞察 / 一周计划 ==========

  /// 连续打卡天数（今天没记则从昨天起算）
  int get streakDays {
    if (_records.isEmpty) return 0;
    final days = _records
        .map((r) => DateTime(r.date.year, r.date.month, r.date.day))
        .toSet();
    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var n = 0;
    while (days.contains(cursor)) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// 衣橱体检：利用率、健康度、CPW、配色分布、建议
  WardrobeInsights get insights => _insightsService.analyze(_clothes);

  /// 未来七天穿搭计划（尽量不重复上衣）
  List<DayPlan> get weekPlan => _insightsService.weekPlan(
        clothes: _clothes,
        temperature: currentTemperature,
        engine: _engine,
      );

  // ========== 规则推荐（本地引擎） ==========

  /// 最近一次「今日推荐」的旁路结果（含理由/性别提示）。
  /// OutfitPlan 与 Hive 侧模型互不相干，理由经 [OutfitRecommendation] 供给界面。
  OutfitRecommendation? _lastRecommendation;
  String? _lastOccasion;

  /// 性别未填（null/空）时提示补充；'other'（不愿说）视为已表态，不提示。
  bool get needsGenderHint {
    final g = _profile?.gender;
    return g == null || g.isEmpty;
  }

  /// 今日推荐穿搭（温度 + 场合 + 性别规则引擎）。
  /// 理由与性别提示挂 [OutfitRecommendation] 旁路，OutfitPlan 本体不变。
  /// #12：按「年月日」做种子——同一天内推荐稳定，跨天自动换一套。
  OutfitPlan? recommendToday({String? occasion}) {
    if (_clothes.isEmpty) {
      _lastRecommendation = null;
      return null;
    }
    _lastOccasion = occasion;
    final now = DateTime.now();
    final daySeed = now.year * 100000 + now.month * 1000 + now.day;
    final r = _engine.recommendWithReasons(
      clothes: _clothes,
      temperature: currentTemperature,
      occasion: occasion,
      gender: _profile?.gender,
      seed: daySeed,
    );
    _lastRecommendation = r;
    return r.plan;
  }

  /// 推荐理由（#8 展示旁路）：最近一次推荐直接用缓存；
  /// 「换一套」等未缓存方案按当前温度/场合即时重算（纯函数，无副作用）。
  List<String> reasonsOf(OutfitPlan? plan) {
    if (plan == null || plan.pieces.isEmpty) return const [];
    if (identical(_lastRecommendation?.plan, plan)) {
      return _lastRecommendation?.reasons ?? const [];
    }
    return OutfitRules.buildReasons(
      pieces: plan.pieces,
      temperature: currentTemperature,
      occasion: _lastOccasion,
    );
  }

  /// 户外方案（穿搭+装备），同样带上性别过滤。
  OutdoorPlan? recommendOutdoor(String scenario) {
    if (_clothes.isEmpty) return null;
    return _engine.recommendOutdoor(
      clothes: _clothes,
      temperature: currentTemperature,
      scenario: scenario,
      precipProb: _weather?.precipProb ?? 0,
      windSpeed: _weather?.windSpeed ?? 0,
      gender: _profile?.gender,
    );
  }

  // ========== 行李清单 ==========

  Future<PackingList> generatePackingList({
    required String name,
    String? destination,
    required DateTime startDate,
    required DateTime endDate,
    required String climate,
    List<String> occasions = const [],
    double? avgTemp,
  }) async {
    final days = endDate.difference(startDate).inDays + 1;
    final items = _engine.buildPackingItems(
      clothes: _clothes,
      days: days,
      climate: climate,
      occasions: occasions,
      avgTemp: avgTemp,
    );
    final list = PackingList(
      id: 'packing_${const Uuid().v4()}',
      name: name,
      destination: destination,
      startDate: startDate,
      endDate: endDate,
      climate: climate,
      occasions: occasions,
      avgTemp: avgTemp,
      items: items,
      createdAt: DateTime.now(),
    );
    await _storage.addPackingList(list);
    _packingLists.insert(0, list);
    notifyListeners();
    return list;
  }

  Future<void> togglePacked(String listId, String itemId) async {
    final index = _packingLists.indexWhere((p) => p.id == listId);
    if (index == -1) return;
    _packingLists[index].togglePacked(itemId);
    await _storage.addPackingList(_packingLists[index]);
    notifyListeners();
  }

  Future<void> deletePackingList(String id) async {
    await _storage.deletePackingList(id);
    _packingLists.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  // ========== 统计 ==========

  Map<String, int> getCategoryStats() => _storage.getCategoryStats();

  Map<String, int> getMaterialStats() => _storage.getMaterialStats();

  List<Clothing> getLeastWornClothes({int limit = 10}) {
    return _storage.getLeastWornClothes(limit: limit);
  }

  List<Clothing> getMostWornClothes({int limit = 10}) {
    return _storage.getMostWornClothes(limit: limit);
  }

  /// 闲置衣物（默认 90 天未穿）
  List<Clothing> getIdleClothes({int idleDays = 90}) {
    return _storage.getIdleClothes(idleDays: idleDays);
  }

  /// 衣橱利用率（穿过比例）
  double getUtilization() => _storage.getUtilization();

  /// 穿搭日历：某月 {日: 记录列表}
  Map<int, List<OutfitRecord>> getRecordsForMonth(int year, int month) {
    return _storage.getRecordsForMonth(year, month);
  }

  List<OutfitRecord> getRecordsForDay(DateTime day) {
    return _storage.getRecordsForDay(day);
  }
  
  // ========== 筛选 ==========
  
  List<Clothing> _filterClothes() {
    // 多衣橱只影响浏览范围；推荐与统计仍按全部单品算，
    // 避免「换了空间就推荐不出来」这种反直觉行为
    var filtered =
        _clothes.where((c) => c.belongsTo(_currentSpaceId)).toList();
    
    if (_selectedCategory != null) {
      filtered = filtered.where((c) => c.category == _selectedCategory).toList();
    }
    
    if (_selectedLocation != null) {
      filtered = filtered.where((c) => c.locationStatus == _selectedLocation).toList();
    }

    if (_selectedMaterial != null) {
      filtered = filtered.where((c) => c.material == _selectedMaterial).toList();
    }
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((c) {
        return c.color.toLowerCase().contains(query) ||
            c.subCategory.toLowerCase().contains(query) ||
            (c.brand?.toLowerCase().contains(query) ?? false) ||
            (c.material ?? '').toLowerCase().contains(query) ||
            (c.notes ?? '').toLowerCase().contains(query) ||
            c.tags.any((t) => t.toLowerCase().contains(query)) ||
            (c.aiTags ?? const []).any((t) => t.toLowerCase().contains(query));
      }).toList();
    }

    if (_selectedColor != null) {
      filtered = filtered
          .where((c) =>
              c.color.contains(_selectedColor!) ||
              _selectedColor!.contains(c.color))
          .toList();
    }

    if (_selectedSeason != null) {
      filtered = filtered
          .where((c) => c.seasons.contains(_selectedSeason))
          .toList();
    }

    if (_selectedOccasion != null) {
      filtered = filtered
          .where((c) => c.occasions.contains(_selectedOccasion))
          .toList();
    }

    if (_selectedTag != null) {
      filtered = filtered
          .where((c) =>
              c.tags.contains(_selectedTag) ||
              (c.aiTags ?? const []).contains(_selectedTag))
          .toList();
    }

    final sorted = [...filtered];
    switch (_sort) {
      case WardrobeSort.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case WardrobeSort.oldest:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case WardrobeSort.mostWorn:
        sorted.sort((a, b) => b.wearCount.compareTo(a.wearCount));
        break;
      case WardrobeSort.idle:
        sorted.sort((a, b) => b.idleDays().compareTo(a.idleDays()));
        break;
      case WardrobeSort.cpw:
        sorted.sort((a, b) => (a.cpw ?? double.infinity)
            .compareTo(b.cpw ?? double.infinity));
        break;
      case WardrobeSort.lowestWear:
        sorted.sort((a, b) => a.wearCount.compareTo(b.wearCount));
        break;
    }
    return sorted;
  }

  void setSort(WardrobeSort sort) {
    _sort = sort;
    notifyListeners();
  }

  void setColorFilter(String? color) {
    _selectedColor = color;
    notifyListeners();
  }

  void setSeasonFilter(String? season) {
    _selectedSeason = season;
    notifyListeners();
  }

  void setOccasionFilter(String? occasion) {
    _selectedOccasion = occasion;
    notifyListeners();
  }

  void setTagFilter(String? tag) {
    _selectedTag = tag;
    notifyListeners();
  }

  void clearAllFilters() {
    _selectedCategory = null;
    _selectedLocation = null;
    _selectedMaterial = null;
    _selectedColor = null;
    _selectedSeason = null;
    _selectedOccasion = null;
    _selectedTag = null;
    _searchQuery = '';
    notifyListeners();
  }

  void setCategoryFilter(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setLocationFilter(String? location) {
    _selectedLocation = location;
    notifyListeners();
  }

  void setMaterialFilter(String? material) {
    _selectedMaterial = material;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
  
  // ========== 衣服管理 ==========
  
  Future<void> addClothing(Clothing clothing) async {
    // 存储未就绪时底层写入是 no-op：跳过内存镜像更新，
    // 避免 UI 报"已保存"而重启后全丢
    if (!_storage.isReady) return;
    await _storage.addClothing(clothing);
    _clothes.insert(0, clothing);
    
    // 更新统计
    _profile?.totalClothes = _clothes.length;
    _profile?.addPoints(10); // 添加衣服奖励积分
    if (_profile != null) await _storage.saveProfile(_profile!);
    
    notifyListeners();
  }
  
  Future<void> updateClothing(Clothing clothing) async {
    if (!_storage.isReady) return;
    await _storage.updateClothing(clothing);
    final index = _clothes.indexWhere((c) => c.id == clothing.id);
    if (index != -1) {
      _clothes[index] = clothing;
    }
    notifyListeners();
  }
  
  Future<void> deleteClothing(String id) async {
    if (!_storage.isReady) return;
    await _storage.deleteClothing(id);
    _clothes.removeWhere((c) => c.id == id);

    _profile?.totalClothes = _clothes.length;
    if (_profile != null) await _storage.saveProfile(_profile!);
    
    notifyListeners();
  }
  
  /// 从 base64 图像识别（纯识别预填，不入库；确认入库由调用方 addClothing）
  Future<Clothing?> recognizeClothingFromBase64(String base64Image) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final result = await _aiService.recognizeClothingFromBase64(base64Image);
      
      final clothing = Clothing(
        id: 'c_${const Uuid().v4()}',
        imageUrl: 'data:image/jpeg;base64,$base64Image',
        category: result.category,
        subCategory: result.subCategory,
        color: normalizeAiColor(result.color), // #15 AI 自报颜色直存
        pattern: result.pattern,
        styles: result.styles,
        seasons: result.seasons,
        brand: result.brand,
        material: result.material,
        thickness: result.thickness,
        tempMin: result.tempMin,
        tempMax: result.tempMax,
        occasions: result.occasions,
        createdAt: DateTime.now(),
      );
      return clothing;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// 更新位置/洗护状态（在衣柜 / 在洗 / 正在穿 / 收纳中）
  Future<void> setLocationStatus(String id, String status) async {
    final index = _clothes.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _clothes[index].locationStatus = status;
    // 记录状态变更时间，「送洗几天了」用它算
    _clothes[index].updatedAt = DateTime.now();
    await _storage.updateClothing(_clothes[index]);
    notifyListeners();
  }

  // ========== 洗护 ==========

  /// 正在洗 / 干洗中的单品
  List<Clothing> get laundryItems => _clothes
      .where((c) =>
          c.locationStatus == LocationStatus.washing ||
          c.locationStatus == LocationStatus.dryCleaning)
      .toList()
    ..sort((a, b) => b.updatedAt
        ?.compareTo(a.updatedAt ?? a.createdAt) ??
        0);

  /// 超过 3 天没收回的件数（首页提醒用）
  int get laundryOverdueCount =>
      laundryItems.where((c) => laundryDays(c) >= 3).length;

  /// 这次送洗已经几天
  int laundryDays(Clothing c) {
    final since = c.updatedAt ?? c.createdAt;
    final days = DateTime.now().difference(since).inDays;
    return days < 0 ? 0 : days;
  }

  /// 送洗
  Future<void> sendToLaundry(String id, {bool dryClean = false}) =>
      setLocationStatus(
          id, dryClean ? LocationStatus.dryCleaning : LocationStatus.washing);

  /// 洗好收回衣柜
  Future<void> collectFromLaundry(String id) =>
      setLocationStatus(id, LocationStatus.inWardrobe);


  /// 设置购入价（用于 CPW 单次穿着成本）
  Future<void> setPrice(String id, double? price) async {
    final index = _clothes.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _clothes[index].price = price;
    await _storage.updateClothing(_clothes[index]);
    notifyListeners();
  }

  /// 手动记一次穿着
  Future<void> logWear(String id) async {
    final index = _clothes.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _clothes[index].incrementWearCount();
    await _storage.updateClothing(_clothes[index]);
    _profile?.addPoints(2);
    if (_profile != null) await _storage.saveProfile(_profile!);
    notifyListeners();
  }

  // ========== 穿搭管理 ==========
  
  Future<void> addOutfit(Outfit outfit) async {
    await _storage.addOutfit(outfit);
    _outfits.insert(0, outfit);
    
    _profile?.totalOutfits = _outfits.length;
    _profile?.addPoints(15);
    if (_profile != null) await _storage.saveProfile(_profile!);
    
    notifyListeners();
  }
  
  Future<void> deleteOutfit(String id) async {
    await _storage.deleteOutfit(id);
    _outfits.removeWhere((o) => o.id == id);
    notifyListeners();
  }
  
  Future<OutfitSuggestion?> generateOutfitSuggestion({
    required String prompt,
    String? occasion,
    String? season,
  }) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final clothingIds = _clothes.map((c) => c.id).toList();
      final suggestion = await _aiService.generateOutfitSuggestion(
        prompt: prompt,
        occasion: occasion,
        season: season,
        temperature: _weather?.temperature,
        availableClothingIds: clothingIds,
        availableClothes: _clothes,
      );
      return suggestion;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // ========== 穿搭记录 ==========
  
  /// 记录穿搭：未填天气时自动带上当前天气
  Future<void> addOutfitRecord(OutfitRecord record) async {
    if (record.weather == null && _weather != null) {
      record.weather = _weather!.conditionText;
      record.temperature = _weather!.temperature.round();
    }
    await _storage.addRecord(record);
    _records.insert(0, record);
    
    // 更新衣服穿着次数
    for (final id in record.clothingIds) {
      final index = _clothes.indexWhere((c) => c.id == id);
      if (index != -1) {
        _clothes[index].incrementWearCount();
        await _storage.updateClothing(_clothes[index]);
      }
    }
    
    _profile?.totalWearDays++;
    _profile?.addPoints(5);
    if (_profile != null) await _storage.saveProfile(_profile!);
    
    notifyListeners();
  }
  
  // ========== 用户配置 ==========
  
  Future<void> updateProfile({
    String? nickname,
    String? avatarUrl,
    String? gender,
    int? height,
    int? weight,
    List<String>? stylePreferences,
    String? avatarSheetPath,
    String? avatarSourcePath,
  }) async {
    if (_profile == null) return;

    if (nickname != null) _profile!.nickname = nickname;
    if (avatarUrl != null) _profile!.avatarUrl = avatarUrl;
    if (gender != null) _profile!.gender = gender;
    if (height != null) _profile!.height = height;
    if (weight != null) _profile!.weight = weight;
    if (stylePreferences != null) _profile!.stylePreferences = stylePreferences;
    if (avatarSheetPath != null) _profile!.avatarSheetPath = avatarSheetPath;
    if (avatarSourcePath != null) _profile!.avatarSourcePath = avatarSourcePath;

    await _storage.saveProfile(_profile!);
    notifyListeners();
  }

  /// 保存照片数字人形象（先清掉旧文件，避免堆积孤儿图）。
  Future<bool> saveDigitalAvatar(
      {required String sheetPath, required String sourcePath}) async {
    if (_profile == null) return false;
    final oldSheet = _profile!.avatarSheetPath;
    final oldSource = _profile!.avatarSourcePath;
    _profile!.avatarSheetPath = sheetPath;
    _profile!.avatarSourcePath = sourcePath;
    await _storage.saveProfile(_profile!);
    notifyListeners();
    if (oldSheet != null && oldSheet != sheetPath) {
      await ImageStore.instance.deleteQuietly(oldSheet);
    }
    if (oldSource != null && oldSource != sourcePath) {
      await ImageStore.instance.deleteQuietly(oldSource);
    }
    return true;
  }

  /// 删除数字人形象：同时清掉本地图片，不留孤儿文件。
  Future<void> clearDigitalAvatar() async {
    if (_profile == null) return;
    final sheet = _profile!.avatarSheetPath;
    final source = _profile!.avatarSourcePath;
    _profile!.avatarSheetPath = null;
    _profile!.avatarSourcePath = null;
    await _storage.saveProfile(_profile!);
    notifyListeners();
    await ImageStore.instance.deleteQuietly(sheet);
    await ImageStore.instance.deleteQuietly(source);
  }
  
  // ========== 演示数据 ==========

  /// 载入一套示例衣橱：用于第一次打开时快速看效果，可一键清空。
  Future<void> seedDemoData() async {
    if (_clothes.isNotEmpty) return;
    final now = DateTime.now();
    Clothing make(
      String id,
      String cat,
      String sub,
      String color,
      String material, {
      String? brand,
      double? price,
      int thickness = 2,
      int? tMin,
      int? tMax,
      List<String> styles = const [],
      List<String> seasons = const [],
      List<String> occasions = const [],
      int wear = 0,
      int daysAgo = 10,
      String status = 'in_wardrobe',
    }) {
      final c = Clothing(
        id: id,
        imageUrl: '',
        category: cat,
        subCategory: sub,
        color: color,
        material: material,
        brand: brand,
        price: price,
        thickness: thickness,
        tempMin: tMin,
        tempMax: tMax,
        styles: styles,
        seasons: seasons,
        occasions: occasions,
        locationStatus: status,
        wearCount: wear,
        lastWearDate:
            wear > 0 ? now.subtract(Duration(days: daysAgo)) : null,
        createdAt: now.subtract(Duration(days: 120 - daysAgo)),
      );
      return c;
    }

    final demo = <Clothing>[
      make('d01', ClothingCategory.tops, 't_shirt', '白色', MaterialType.cotton,
          brand: 'Uniqlo', price: 99, tMin: 16, tMax: 30,
          styles: ['casual', 'minimalist'], seasons: ['spring', 'summer'],
          occasions: ['daily', 'work'], wear: 26, daysAgo: 3),
      make('d02', ClothingCategory.tops, 'sweater', '灰色', MaterialType.wool,
          brand: 'COS', price: 599, thickness: 3, tMin: 4, tMax: 18,
          styles: ['minimalist', 'formal'], seasons: ['autumn', 'winter'],
          occasions: ['work', 'daily'], wear: 8, daysAgo: 12),
      make('d03', ClothingCategory.tops, 'hoodie', '墨绿', MaterialType.polyester,
          brand: 'Stussy', price: 899, thickness: 3, tMin: 2, tMax: 16,
          styles: ['streetwear', 'sporty'], seasons: ['autumn', 'winter'],
          occasions: ['daily', 'sport'], wear: 14, daysAgo: 6),
      make('d04', ClothingCategory.bottoms, 'jeans', '藏青', MaterialType.denim,
          brand: "Levi's", price: 799, tMin: 5, tMax: 24,
          styles: ['casual', 'streetwear'], seasons: ['spring', 'autumn', 'winter'],
          occasions: ['daily'], wear: 31, daysAgo: 1),
      make('d05', ClothingCategory.bottoms, 'trousers', '米色', MaterialType.blended,
          brand: 'Massimo Dutti', price: 690, tMin: 12, tMax: 26,
          styles: ['formal', 'minimalist'], seasons: ['spring', 'autumn'],
          occasions: ['work', 'interview'], wear: 6, daysAgo: 20),
      make('d06', ClothingCategory.outerwear, 'jacket', '黑色', MaterialType.leather,
          brand: 'Zara', price: 1299, thickness: 3, tMin: 6, tMax: 20,
          styles: ['streetwear', 'vintage'], seasons: ['autumn', 'winter'],
          occasions: ['daily', 'dating'], wear: 11, daysAgo: 9),
      make('d07', ClothingCategory.outerwear, 'coat', '驼色', MaterialType.wool,
          brand: 'Max Mara', price: 3999, thickness: 4, tMin: -2, tMax: 12,
          styles: ['minimalist', 'formal'], seasons: ['winter'],
          occasions: ['work', 'dating'], wear: 2, daysAgo: 45),
      make('d08', ClothingCategory.shoes, 'sneakers', '白色', MaterialType.leather,
          brand: 'New Balance', price: 899, tMin: 0, tMax: 40,
          styles: ['casual', 'sporty'], seasons: ['spring', 'summer', 'autumn'],
          occasions: ['daily', 'sport'], wear: 48, daysAgo: 1),
      make('d09', ClothingCategory.shoes, 'loafers', '黑色', MaterialType.leather,
          brand: 'Clarks', price: 1099, tMin: 5, tMax: 26,
          styles: ['formal'], seasons: ['spring', 'autumn'],
          occasions: ['work', 'interview'], wear: 3, daysAgo: 60),
      make('d10', ClothingCategory.accessories, 'bag', '黑色', MaterialType.leather,
          brand: 'Coach', price: 2600, tMin: -10, tMax: 40,
          styles: ['formal', 'minimalist'], occasions: ['work', 'daily'],
          wear: 22, daysAgo: 2),
      make('d11', ClothingCategory.dress, 'midi_dress', '奶油白', MaterialType.silk,
          brand: '& Other Stories', price: 899, tMin: 18, tMax: 30,
          styles: ['dating', 'minimalist'], seasons: ['summer'],
          occasions: ['dating', 'party'], wear: 1, daysAgo: 120 - 1,
          status: 'in_wardrobe'),
      make('d12', ClothingCategory.tops, 'shirt', '条纹', MaterialType.linen,
          brand: 'Muji', price: 269, tMin: 18, tMax: 32,
          styles: ['casual', 'vintage'], seasons: ['summer'],
          occasions: ['daily', 'travel'], wear: 0, status: 'washing'),
    ];

    for (final c in demo) {
      await _storage.addClothing(c);
    }
    _clothes = _storage.getAllClothes();

    // 几条历史穿搭记录，让日历和统计有内容
    for (var i = 0; i < 4; i++) {
      final r = OutfitRecord(
        id: 'demo_record_$i',
        date: now.subtract(Duration(days: i * 3 + 1)),
        clothingIds: ['d01', 'd04', 'd08'],
        occasion: 'daily',
        weather: '晴',
        temperature: 18 + i,
        createdAt: now.subtract(Duration(days: i * 3 + 1)),
      );
      await _storage.addRecord(r);
    }
    _records = _storage.getAllRecords();

    _profile?.totalClothes = _clothes.length;
    _profile?.addPoints(30);
    if (_profile != null) await _storage.saveProfile(_profile!);
    await _storage.setSetting<bool>('demo_seeded', true);
    notifyListeners();
  }

  /// 清空全部本地数据（演示 / 重置用）
  Future<void> resetAll() async {
    await _storage.clearAll();
    _clothes = [];
    _outfits = [];
    _records = [];
    _packingLists = [];
    _splitTasks = [];
    _wishItems = [];
    // 清空后至少要有内置默认衣橱，否则「我的衣橱」页会空到下次重启
    _spaces = _storage.getAllSpaces();
    _currentSpaceId = null;
    _profile = UserProfile(createdAt: DateTime.now());
    await _storage.saveProfile(_profile!);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// 恢复备份后把 Hive 里的数据重新读进内存，页面无需重启即可看到。
  Future<void> reloadFromStorage() async {
    if (!_storage.isReady) return;
    _loadData();
    notifyListeners();
  }

  // ========== AI 拆分：批量入库 / 任务 ==========

  /// 一次写入多件（拆分确认后调用），只重建一次列表
  Future<int> addClothingBatch(List<Clothing> items) async {
    if (items.isEmpty) return 0;
    if (!_storage.isReady) return 0;
    for (final c in items) {
      await _storage.addClothing(c);
    }
    _clothes = _storage.getAllClothes();
    _profile?.totalClothes = _clothes.length;
    _profile?.addPoints(10 * items.length);
    if (_profile != null) await _storage.saveProfile(_profile!);
    notifyListeners();
    return items.length;
  }

  Future<void> saveSplitTask(SplitTask task) async {
    await _storage.addSplitTask(task);
    final i = _splitTasks.indexWhere((t) => t.id == task.id);
    if (i == -1) {
      _splitTasks.insert(0, task);
    } else {
      _splitTasks[i] = task;
    }
    notifyListeners();
  }

  Future<void> deleteSplitTask(String id) async {
    await _storage.deleteSplitTask(id);
    _splitTasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  Future<void> reloadSplitTasks() async {
    _splitTasks = _storage.getAllSplitTasks();
    notifyListeners();
  }

  /// 手动补录后刷新列表（不走 addClothing 的积分逻辑）
  void refreshClothes() {
    _clothes = _storage.getAllClothes();
    notifyListeners();
  }

  // ========== 多衣橱空间 ==========

  Future<void> setCurrentSpace(String? spaceId) async {
    final valid = spaceId == null || _spaces.any((s) => s.id == spaceId);
    _currentSpaceId = valid ? spaceId : null;
    await _storage.setSetting('current_space_id', _currentSpaceId ?? '');
    notifyListeners();
  }

  Future<void> addSpace(String name, {String emoji = '🏠', String? note}) async {
    final space = WardrobeSpace(
      id: 'space_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      emoji: emoji,
      note: note,
      createdAt: DateTime.now(),
    );
    await _storage.saveSpace(space);
    _spaces = _storage.getAllSpaces();
    _currentSpaceId = space.id;
    await _storage.setSetting('current_space_id', space.id);
    notifyListeners();
  }

  /// 删除空间：里面的衣物退回默认衣橱，返回被移动的件数
  Future<int> deleteSpace(String id) async {
    final moved = await _storage.deleteSpace(id);
    _spaces = _storage.getAllSpaces();
    _clothes = _storage.getAllClothes();
    if (_currentSpaceId == id) {
      _currentSpaceId = null;
      await _storage.setSetting('current_space_id', '');
    }
    notifyListeners();
    return moved;
  }

  /// 把衣物移到某个空间（null = 默认衣橱）
  Future<void> moveToSpace(String clothingId, String? spaceId) async {
    final i = _clothes.indexWhere((c) => c.id == clothingId);
    if (i == -1) return;
    _clothes[i].wardrobeId = spaceId;
    await _storage.updateClothing(_clothes[i]);
    notifyListeners();
  }

  // ========== 愿望清单 ==========

  Future<void> addWish(WishItem item) async {
    await _storage.saveWishItem(item);
    _wishItems = _storage.getAllWishItems();
    notifyListeners();
  }

  Future<void> updateWish(WishItem item) async {
    await _storage.saveWishItem(item);
    _wishItems = _storage.getAllWishItems();
    notifyListeners();
  }

  /// 删除愿望（#5 连带数据）：DB 记录 + 参考图文件一起清。
  /// 已购入的愿望参考图被衣橱单品直接引用（purchaseWish 建的 clothing
  /// 用同一个路径），这类图片不动，只删未购入愿望自己的参考图，避免孤儿文件。
  Future<void> deleteWish(String id) async {
    final target = _wishItems.where((w) => w.id == id).toList();
    await _storage.deleteWishItem(id);
    _wishItems = _storage.getAllWishItems();
    for (final w in target) {
      if (!w.purchased) {
        await ImageStore.instance.deleteQuietly(w.imagePath);
      }
    }
    notifyListeners();
  }

  /// 冷静期：新建愿望默认 7 天内只提醒不催买
  static const int wishCooldownDays = 7;

  /// 标记已购入：同时生成一条衣物记录，图片沿用愿望清单的参考图；
  /// 找不到该愿望（已被删除）时返回 null，不抛 StateError
  Future<Clothing?> purchaseWish(String id, {double? price}) async {
    final i = _wishItems.indexWhere((w) => w.id == id);
    if (i == -1) return null;
    final item = _wishItems[i];
    if (item.purchased || item.clothingId != null) {
      for (final clothing in _clothes) {
        if (clothing.id == item.clothingId) return clothing;
      }
      return null;
    }
    final now = DateTime.now();
    final clothing = Clothing(
      id: 'c_${const Uuid().v4()}',
      imageUrl: item.imagePath ?? '',
      originalImagePath: item.imagePath,
      category: item.category,
      subCategory: item.subCategory ?? '',
      color: item.color ?? '未标注',
      price: price ?? item.price,
      purchaseDate: now,
      createdAt: now,
      tags: const ['wishlist'],
      notes: item.note,
      sourceType: 'wishlist',
      wardrobeId: _currentSpaceId,
    );
    await _storage.addClothing(clothing);
    _clothes.insert(0, clothing);

    item.purchasedAt = now;
    item.clothingId = clothing.id;
    if (price != null) item.price = price;
    await _storage.saveWishItem(item);
    _wishItems = _storage.getAllWishItems();
    notifyListeners();
    return clothing;
  }
}

/// 衣橱排序方式
enum WardrobeSort {
  newest,
  oldest,
  mostWorn,
  lowestWear,
  idle,
  cpw;

  String get label {
    switch (this) {
      case WardrobeSort.newest:
        return '最近添加';
      case WardrobeSort.oldest:
        return '最早添加';
      case WardrobeSort.mostWorn:
        return '穿得最多';
      case WardrobeSort.lowestWear:
        return '穿得最少';
      case WardrobeSort.idle:
        return '闲置最久';
      case WardrobeSort.cpw:
        return '单次成本最低';
    }
  }
}
