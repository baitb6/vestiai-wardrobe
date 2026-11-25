import 'package:hive_flutter/hive_flutter.dart';
import '../models/models.dart';

class StorageService {
  static const String clothingBoxName = 'clothes';
  static const String outfitBoxName = 'outfits';
  static const String recordBoxName = 'outfit_records';
  static const String profileBoxName = 'user_profile';
  static const String settingsBoxName = 'settings';
  static const String packingBoxName = 'packing_lists';
  static const String splitTaskBoxName = 'split_tasks';
  static const String tryOnBoxName = 'try_on_tasks';
  static const String wishBoxName = 'wish_items';
  static const String spaceBoxName = 'wardrobe_spaces';

  late Box<Clothing> _clothingBox;
  late Box<Outfit> _outfitBox;
  late Box<OutfitRecord> _recordBox;
  late Box<UserProfile> _profileBox;
  late Box<PackingList> _packingBox;
  late Box<SplitTask> _splitTaskBox;
  late Box<TryOnTask> _tryOnBox;
  late Box<WishItem> _wishBox;
  late Box<WardrobeSpace> _spaceBox;
  late Box<dynamic> _settingsBox;

  /// 存储是否就绪。未就绪时所有读接口返回空，避免 UI 撞上
  /// LateInitializationError 直接红屏（桌面端/权限异常的常见情况）。
  bool _ready = false;
  bool get isReady => _ready;

  Future<void> init() async {
    await Hive.initFlutter();

    // 注册适配器（热重启时会重复注册，忽略即可）
    void reg<T>(TypeAdapter<T> adapter) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) {
        Hive.registerAdapter(adapter);
      }
    }

    reg(ClothingAdapter());
    reg(OutfitAdapter());
    reg(OutfitRecordAdapter());
    reg(UserProfileAdapter());
    reg(PackingListAdapter());
    reg(PackingItemAdapter());
    reg(SplitTaskAdapter());
    reg(TryOnTaskAdapter());
    reg(WishItemAdapter());
    reg(WardrobeSpaceAdapter());

    // 打开盒子
    _clothingBox = await Hive.openBox<Clothing>(clothingBoxName);
    _outfitBox = await Hive.openBox<Outfit>(outfitBoxName);
    _recordBox = await Hive.openBox<OutfitRecord>(recordBoxName);
    _profileBox = await Hive.openBox<UserProfile>(profileBoxName);
    _packingBox = await Hive.openBox<PackingList>(packingBoxName);
    _splitTaskBox = await Hive.openBox<SplitTask>(splitTaskBoxName);
    _tryOnBox = await Hive.openBox<TryOnTask>(tryOnBoxName);
    _wishBox = await Hive.openBox<WishItem>(wishBoxName);
    _spaceBox = await Hive.openBox<WardrobeSpace>(spaceBoxName);
    _settingsBox = await Hive.openBox<dynamic>(settingsBoxName);
    _ready = true;
  }

  // ========== Clothes ==========
  
  List<Clothing> getAllClothes() {
    if (!_ready) return [];
    return _clothingBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Clothing> getClothesByCategory(String category) {
    if (!_ready) return [];
    return _clothingBox.values
        .where((c) => c.category == category)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Clothing> getClothesByLocation(String status) {
    if (!_ready) return [];
    return _clothingBox.values
        .where((c) => c.locationStatus == status)
        .toList();
  }

  List<Clothing> searchClothes(String query) {
    if (!_ready) return [];
    final lowerQuery = query.toLowerCase();
    return _clothingBox.values.where((c) {
      return c.color.toLowerCase().contains(lowerQuery) ||
          c.subCategory.toLowerCase().contains(lowerQuery) ||
          (c.brand?.toLowerCase().contains(lowerQuery) ?? false) ||
          c.tags.any((t) => t.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  Clothing? getClothingById(String id) {
    if (!_ready) return null;
    for (final c in _clothingBox.values) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> addClothing(Clothing clothing) async {
    if (!_ready) return;
    await _clothingBox.put(clothing.id, clothing);
  }

  Future<void> updateClothing(Clothing clothing) async {
    if (!_ready) return;
    clothing.updatedAt = DateTime.now();
    // 用 put 而不是 save()：从备份恢复出来的对象还没挂到 box 上，
    // save() 会抛 "This object is currently not in a box"。
    await _clothingBox.put(clothing.id, clothing);
  }

  Future<void> deleteClothing(String id) async {
    if (!_ready) return;
    await _clothingBox.delete(id);
  }

  Clothing? getClothing(String id) {
    if (!_ready) return null;
    return _clothingBox.get(id);
  }

  // ========== Outfits ==========

  List<Outfit> getAllOutfits() {
    if (!_ready) return [];
    return _outfitBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<Outfit> getFavoriteOutfits() {
    if (!_ready) return [];
    return _outfitBox.values.where((o) => o.isFavorite).toList();
  }

  Future<void> addOutfit(Outfit outfit) async {
    if (!_ready) return;
    await _outfitBox.put(outfit.id, outfit);
  }

  Future<void> deleteOutfit(String id) async {
    if (!_ready) return;
    await _outfitBox.delete(id);
  }

  // ========== Outfit Records ==========

  List<OutfitRecord> getAllRecords() {
    if (!_ready) return [];
    return _recordBox.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<OutfitRecord> getRecordsByDateRange(DateTime start, DateTime end) {
    if (!_ready) return [];
    return _recordBox.values
        .where((r) => r.date.isAfter(start) && r.date.isBefore(end))
        .toList();
  }

  Future<void> addRecord(OutfitRecord record) async {
    if (!_ready) return;
    await _recordBox.put(record.id, record);
  }

  // ========== User Profile ==========

  UserProfile? getProfile() {
    if (!_ready) return null;
    return _profileBox.get('profile');
  }

  Future<void> saveProfile(UserProfile profile) async {
    if (!_ready) return;
    await _profileBox.put('profile', profile);
  }

  // ========== Settings ==========

  T? getSetting<T>(String key) {
    if (!_ready) return null;
    return _settingsBox.get(key) as T?;
  }

  Future<void> setSetting<T>(String key, T value) async {
    if (!_ready) return;
    await _settingsBox.put(key, value);
  }

  // ========== Packing Lists ==========
  
  List<PackingList> getAllPackingLists() {
    if (!_ready) return [];
    return _packingBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<PackingList> getUpcomingPackingLists() {
    if (!_ready) return [];
    return _packingBox.values
        .where((p) => !p.isPast)
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
  }

  Future<void> addPackingList(PackingList list) async {
    if (!_ready) return;
    await _packingBox.put(list.id, list);
  }

  Future<void> deletePackingList(String id) async {
    if (!_ready) return;
    await _packingBox.delete(id);
  }

  PackingList? getPackingList(String id) {
    if (!_ready) return null;
    return _packingBox.get(id);
  }

  // ========== Split tasks ==========

  List<SplitTask> getAllSplitTasks() {
    if (!_ready) return [];
    return _splitTaskBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> addSplitTask(SplitTask task) async {
    if (!_ready) return;
    await _splitTaskBox.put(task.id, task);
  }

  Future<void> updateSplitTask(SplitTask task) async {
    if (!_ready) return;
    await _splitTaskBox.put(task.id, task);
  }

  Future<void> deleteSplitTask(String id) async {
    if (!_ready) return;
    await _splitTaskBox.delete(id);
  }

  /// 清空所有业务数据（保留设置）
  Future<void> clearAll() async {
    if (!_ready) return;
    await _clothingBox.clear();
    await _outfitBox.clear();
    await _recordBox.clear();
    await _packingBox.clear();
    await _splitTaskBox.clear();
    await _tryOnBox.clear();
    await _wishBox.clear();
    await _spaceBox.clear();
    await _profileBox.clear();
  }

  // ========== Statistics ==========

  Map<String, int> getCategoryStats() {
    final stats = <String, int>{};
    if (!_ready) return stats;
    for (final clothing in _clothingBox.values) {
      stats[clothing.category] = (stats[clothing.category] ?? 0) + 1;
    }
    return stats;
  }

  int get totalClothes => _ready ? _clothingBox.length : 0;
  int get totalOutfits => _ready ? _outfitBox.length : 0;
  int get totalRecords => _ready ? _recordBox.length : 0;

  List<Clothing> getLeastWornClothes({int limit = 10}) {
    if (!_ready) return [];
    return (_clothingBox.values.toList()
          ..sort((a, b) => a.wearCount.compareTo(b.wearCount)))
        .take(limit)
        .toList();
  }

  List<Clothing> getMostWornClothes({int limit = 10}) {
    if (!_ready) return [];
    return (_clothingBox.values.toList()
          ..sort((a, b) => b.wearCount.compareTo(a.wearCount)))
        .take(limit)
        .toList();
  }

  /// 闲置衣物（超过 idleDays 天未穿）
  List<Clothing> getIdleClothes({int idleDays = 90}) {
    if (!_ready) return [];
    return _clothingBox.values
        .where((c) => c.idleDays() >= idleDays)
        .toList()
      ..sort((a, b) => b.idleDays().compareTo(a.idleDays()));
  }

  /// 穿过的比例（衣橱利用率）
  double getUtilization() {
    if (!_ready || _clothingBox.isEmpty) return 0;
    final worn = _clothingBox.values.where((c) => c.wearCount > 0).length;
    return worn / _clothingBox.length;
  }

  /// 日历查询：某天的穿搭记录
  List<OutfitRecord> getRecordsForDay(DateTime day) {
    if (!_ready) return [];
    return _recordBox.values.where((r) {
      return r.date.year == day.year &&
          r.date.month == day.month &&
          r.date.day == day.day;
    }).toList();
  }

  /// 某月的所有记录
  Map<int, List<OutfitRecord>> getRecordsForMonth(int year, int month) {
    final map = <int, List<OutfitRecord>>{};
    if (!_ready) return map;
    for (final r in _recordBox.values) {
      if (r.date.year == year && r.date.month == month) {
        map.putIfAbsent(r.date.day, () => []).add(r);
      }
    }
    return map;
  }

  /// 材质分布统计
  Map<String, int> getMaterialStats() {
    final stats = <String, int>{};
    if (!_ready) return stats;
    for (final clothing in _clothingBox.values) {
      final key = clothing.material ?? 'unknown';
      stats[key] = (stats[key] ?? 0) + 1;
    }
    return stats;
  }

  // ========== 虚拟试穿任务 ==========

  List<TryOnTask> getAllTryOnTasks() {
    if (!_ready) return [];
    return _tryOnBox.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveTryOnTask(TryOnTask task) async {
    if (!_ready) return;
    await _tryOnBox.put(task.id, task);
  }

  Future<void> deleteTryOnTask(String id) async {
    if (!_ready) return;
    await _tryOnBox.delete(id);
  }

  // ========== 愿望清单 ==========

  List<WishItem> getAllWishItems() {
    if (!_ready) return [];
    return _wishBox.values.toList()
      ..sort((a, b) {
        // 未购入的排前面，再按优先级、创建时间
        if (a.purchased != b.purchased) return a.purchased ? 1 : -1;
        if (a.priority != b.priority) return b.priority.compareTo(a.priority);
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  Future<void> saveWishItem(WishItem item) async {
    if (!_ready) return;
    await _wishBox.put(item.id, item);
  }

  Future<void> deleteWishItem(String id) async {
    if (!_ready) return;
    await _wishBox.delete(id);
  }

  // ========== 衣橱空间 ==========

  List<WardrobeSpace> getAllSpaces() {
    final list = <WardrobeSpace>[];
    if (_ready) list.addAll(_spaceBox.values);
    if (list.every((s) => !s.isDefault)) {
      list.insert(0, WardrobeSpace.builtin());
    }
    list.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  Future<void> saveSpace(WardrobeSpace space) async {
    if (!_ready) return;
    await _spaceBox.put(space.id, space);
  }

  /// 删除空间：把里面的衣物退回默认衣橱，绝不连带删衣物
  Future<int> deleteSpace(String id) async {
    if (!_ready) return 0;
    var moved = 0;
    for (final c in _clothingBox.values) {
      if (c.wardrobeId == id) {
        c.wardrobeId = null;
        await _clothingBox.put(c.id, c);
        moved++;
      }
    }
    await _spaceBox.delete(id);
    return moved;
  }
}
