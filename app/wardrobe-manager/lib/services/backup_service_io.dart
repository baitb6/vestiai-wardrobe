import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'image_store_io.dart';
import 'storage_service.dart';

class BackupEntry {
  final String path;
  final String name;
  final int bytes;
  final DateTime createdAt;

  BackupEntry({
    required this.path,
    required this.name,
    required this.bytes,
    required this.createdAt,
  });

  String get sizeLabel => bytes > 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).round()} KB';
}

class BackupResult {
  final bool ok;
  final String message;
  final String? path;
  final int itemCount;
  final int imageCount;

  BackupResult({
    required this.ok,
    required this.message,
    this.path,
    this.itemCount = 0,
    this.imageCount = 0,
  });
}

class RestoreResult {
  final bool ok;
  final String message;
  final int clothes;
  final int outfits;
  final int records;
  final int missingImages;

  RestoreResult({
    required this.ok,
    required this.message,
    this.clothes = 0,
    this.outfits = 0,
    this.records = 0,
    this.missingImages = 0,
  });
}

/// 本地备份：JSON 清单 + 图片打进一个 zip。
///
/// 不加密（用户自己的数据），但导出前页面会提示隐私风险。
class BackupService {
  static final BackupService instance = BackupService._();

  BackupService._();

  StorageService? _storage;

  bool get available => true;

  void bind(StorageService storage) {
    _storage = storage;
  }

  static const int _schema = 1;

  Future<Directory> _backupDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'wardrobe_backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<BackupEntry>> listBackups() async {
    try {
      final dir = await _backupDir();
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.zip'))
          .cast<File>()
          .toList();
      final entries = <BackupEntry>[];
      for (final f in files) {
        final stat = await f.stat();
        entries.add(BackupEntry(
          path: f.path,
          name: p.basename(f.path),
          bytes: stat.size,
          createdAt: stat.modified,
        ));
      }
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } catch (e) {
      // 列不出备份不致命：当没有备份处理，页面给出空列表
      debugPrint('读取备份列表失败：$e');
      return [];
    }
  }

  /// 导出全部衣橱数据 + 图片
  Future<BackupResult> export() async {
    final storage = _storage;
    if (storage == null || !storage.isReady) {
      // isReady 一并检查：init 失败时空衣橱状态下导出会产出"成功"的空 zip
      return BackupResult(ok: false, message: '存储还没就绪，稍后再试');
    }

    File? outFile;
    try {
      final clothes = storage.getAllClothes();
      final outfits = storage.getAllOutfits();
      final records = storage.getAllRecords();

      final archive = Archive();
      final usedNames = <String>{};
      var imageCount = 0;

      /// 把一张本地图片塞进 zip，返回包内路径；读不出来返回 null（按缺失处理）
      Future<String?> addImage(String? path) async {
        if (path == null || path.isEmpty) return null;
        final file = File(path);
        Uint8List? bytes;
        try {
          if (await file.exists()) {
            bytes = await file.readAsBytes();
          }
        } catch (e) {
          // 文件在但读不出来（被占用/损坏）：按缺失处理，不让单张图卡死导出
          debugPrint('备份读取图片失败，按缺失处理：$path ($e)');
        }
        if (bytes == null) return null;
        var name = p.basename(path);
        if (usedNames.contains(name)) {
          name = '${DateTime.now().microsecondsSinceEpoch}_$name';
        }
        usedNames.add(name);
        archive.addFile(ArchiveFile('images/$name', bytes.length, bytes));
        imageCount++;
        return 'images/$name';
      }

      final clothesJson = <Map<String, dynamic>>[];
      for (final c in clothes) {
        final map = _clothingToMap(c);
        for (final field in ['originalImagePath', 'cutoutImagePath']) {
          map[field] = await addImage(map[field] as String?);
        }
        clothesJson.add(map);
      }

      // 愿望清单的参考图也一起带走，否则恢复后只剩文字
      final wishesJson = <Map<String, dynamic>>[];
      for (final w in storage.getAllWishItems()) {
        final map = _wishToMap(w);
        map['imagePath'] = await addImage(w.imagePath);
        wishesJson.add(map);
      }

      // 行李清单：纯数据不挂图片，但丢了整段行程规划就没了
      final packingJson =
          storage.getAllPackingLists().map(_packingToMap).toList();

      // 数字人形象与生成用的本人照片：不带走换手机就真丢了
      Map<String, dynamic>? profileJson;
      final profile = storage.getProfile();
      if (profile != null) {
        profileJson = {
          'avatarSheetPath': await addImage(profile.avatarSheetPath),
          'avatarSourcePath': await addImage(profile.avatarSourcePath),
        };
      }

      final data = {
        'app': 'wardrobe-manager',
        'schema': _schema,
        'exportedAt': DateTime.now().toIso8601String(),
        'clothes': clothesJson,
        'outfits': outfits.map(_outfitToMap).toList(),
        'records': records.map(_recordToMap).toList(),
        'spaces': storage.getAllSpaces().map(_spaceToMap).toList(),
        'wishes': wishesJson,
        'packing_lists': packingJson,
        if (profileJson != null) 'profile': profileJson,
      };
      final dataBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
      archive.addFile(ArchiveFile('data.json', dataBytes.length, dataBytes));

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        return BackupResult(ok: false, message: '打包失败');
      }

      final dir = await _backupDir();
      final stamp = DateTime.now();
      final name =
          'wardrobe_${stamp.year}${_two(stamp.month)}${_two(stamp.day)}_${_two(stamp.hour)}${_two(stamp.minute)}.zip';
      outFile = File(p.join(dir.path, name));
      await outFile.writeAsBytes(zipBytes, flush: true);

      return BackupResult(
        ok: true,
        message: '已导出 ${clothes.length} 件衣物、${outfits.length} 套搭配、'
            '${records.length} 条记录，图片 $imageCount 张',
        path: outFile.path,
        itemCount: clothes.length,
        imageCount: imageCount,
      );
    } catch (e) {
      // 半成品 zip 留在目录里只会骗到用户「有备份」，删掉
      if (outFile != null) {
        try {
          if (await outFile.exists()) await outFile.delete();
        } catch (e2) {
          debugPrint('清理半成品备份文件失败：${outFile.path} ($e2)');
        }
      }
      return BackupResult(ok: false, message: '导出失败：$e');
    }
  }

  /// 从 zip 恢复。图片缺失只计数，不中断。
  Future<RestoreResult> restore(String zipPath) async {
    final storage = _storage;
    if (storage == null || !storage.isReady) {
      // isReady 一并检查：未就绪时写入全是 no-op，会报"恢复完成"的假成功
      return RestoreResult(ok: false, message: '存储还没就绪');
    }

    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      Map<String, dynamic>? data;
      final images = <String, Uint8List>{};
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final content = f.content;
        if (content is! List<int>) continue;
        final name = f.name;
        if (name == 'data.json') {
          try {
            data = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('备份 data.json 解析失败：$e');
            return RestoreResult(
                ok: false, message: '备份里的 data.json 损坏，不是有效的备份文件');
          }
        } else if (name.startsWith('images/')) {
          images[p.basename(name)] = Uint8List.fromList(content);
        }
      }

      if (data == null) {
        return RestoreResult(ok: false, message: '压缩包里没有 data.json，不是有效备份');
      }

      final store = ImageStore.instance;
      final restoredPaths = <String, String>{};
      Future<String?> restoreImage(String? zipName) async {
        if (zipName == null || zipName.isEmpty) return null;
        final base = p.basename(zipName);
        if (restoredPaths.containsKey(base)) return restoredPaths[base];
        final bytes = images[base];
        if (bytes == null) return null;
        final ext = p.extension(base).replaceFirst('.', '');
        final newPath = await store.saveBytes(
          bytes,
          prefix: 'restore',
          ext: ext.isEmpty ? 'jpg' : ext,
        );
        if (newPath != null) restoredPaths[base] = newPath;
        return newPath;
      }

      var missing = 0;
      var clothesCount = 0;

      // 先恢复衣橱空间，衣物才能挂回原来的柜子（老备份没有 spaces，跳过即可）
      var spaceCount = 0;
      for (final raw in (data['spaces'] as List? ?? const [])) {
        if (raw is! Map) continue;
        try {
          final space = _spaceFromMap(Map<String, dynamic>.from(raw));
          if (storage.getAllSpaces().any((s) => s.id == space.id)) continue;
          await storage.saveSpace(space);
          spaceCount++;
        } catch (e) {
          debugPrint('恢复时跳过一条无法解析的衣橱空间：$e');
        }
      }
      final validSpaceIds =
          storage.getAllSpaces().map((s) => s.id).toSet();

      final existingIds = storage.getAllClothes().map((e) => e.id).toSet();

      for (final raw in (data['clothes'] as List? ?? const [])) {
        if (raw is! Map) continue;
        Map<String, dynamic> map;
        try {
          map = Map<String, dynamic>.from(raw);
        } catch (e) {
          debugPrint('恢复时跳过一条格式异常的衣物：$e');
          continue;
        }
        final originalName = map['originalImagePath'] as String?;
        final cutoutName = map['cutoutImagePath'] as String?;
        map['originalImagePath'] = await restoreImage(originalName);
        map['cutoutImagePath'] = await restoreImage(cutoutName);
        if (originalName != null &&
            originalName.isNotEmpty &&
            map['originalImagePath'] == null) {
          missing++;
        }
        if (cutoutName != null &&
            cutoutName.isNotEmpty &&
            map['cutoutImagePath'] == null) {
          missing++;
        }
        // 图片丢了但记录还在：保留原有尺寸信息，界面会走占位
        try {
          final clothing = _clothingFromMap(map);
          // 备份里的空间可能没恢复成功：孤儿空间归回默认衣橱，不丢衣物
          if (clothing.wardrobeId != null &&
              !validSpaceIds.contains(clothing.wardrobeId)) {
            clothing.wardrobeId = null;
          }
          if (existingIds.contains(clothing.id)) {
            await storage.updateClothing(clothing);
          } else {
            await storage.addClothing(clothing);
          }
          clothesCount++;
        } catch (e) {
          // 单条数据坏（字段类型不对等）跳过，不影响其它衣物恢复
          debugPrint('恢复时跳过一条无法解析的衣物：$e');
        }
      }

      var outfitCount = 0;
      final existingOutfits = storage.getAllOutfits().map((e) => e.id).toSet();
      for (final raw in (data['outfits'] as List? ?? const [])) {
        if (raw is! Map) continue;
        try {
          final outfit = _outfitFromMap(Map<String, dynamic>.from(raw));
          if (existingOutfits.contains(outfit.id)) continue;
          await storage.addOutfit(outfit);
          outfitCount++;
        } catch (e) {
          debugPrint('恢复时跳过一条无法解析的搭配：$e');
        }
      }

      var recordCount = 0;
      final existingRecords = storage.getAllRecords().map((e) => e.id).toSet();
      for (final raw in (data['records'] as List? ?? const [])) {
        if (raw is! Map) continue;
        try {
          final record = _recordFromMap(Map<String, dynamic>.from(raw));
          if (existingRecords.contains(record.id)) continue;
          await storage.addRecord(record);
          recordCount++;
        } catch (e) {
          debugPrint('恢复时跳过一条无法解析的记录：$e');
        }
      }

      var wishCount = 0;
      final existingWishes = storage.getAllWishItems().map((w) => w.id).toSet();
      for (final raw in (data['wishes'] as List? ?? const [])) {
        if (raw is! Map) continue;
        try {
          final map = Map<String, dynamic>.from(raw);
          map['imagePath'] = await restoreImage(map['imagePath'] as String?);
          final wish = _wishFromMap(map);
          if (existingWishes.contains(wish.id)) continue;
          await storage.saveWishItem(wish);
          wishCount++;
        } catch (e) {
          debugPrint('恢复时跳过一条无法解析的愿望：$e');
        }
      }

      // 行李清单：老备份没有 packing_lists 键，跳过即可
      var packingCount = 0;
      final existingPacking =
          storage.getAllPackingLists().map((l) => l.id).toSet();
      for (final raw in (data['packing_lists'] as List? ?? const [])) {
        if (raw is! Map) continue;
        try {
          final list = _packingFromMap(Map<String, dynamic>.from(raw));
          if (existingPacking.contains(list.id)) continue;
          await storage.addPackingList(list);
          packingCount++;
        } catch (e) {
          debugPrint('恢复时跳过一条无法解析的行李清单：$e');
        }
      }

      // 恢复数字人形象：只补 avatar 两张图，不动昵称/身材等本机资料。
      // 换机场景（本机 profile 被清空）就新建一个空档案，形象不能丢。
      final profileRaw = data['profile'];
      if (profileRaw is Map) {
        try {
          final sheet =
              await restoreImage(profileRaw['avatarSheetPath'] as String?);
          final source =
              await restoreImage(profileRaw['avatarSourcePath'] as String?);
          if (sheet != null || source != null) {
            var current = storage.getProfile();
            current ??= UserProfile(createdAt: DateTime.now());
            current.avatarSheetPath = sheet ?? current.avatarSheetPath;
            current.avatarSourcePath = source ?? current.avatarSourcePath;
            await storage.saveProfile(current);
          }
        } catch (e) {
          debugPrint('恢复数字人形象失败（忽略，不影响其它数据）：$e');
        }
      }

      final detail = '衣物 $clothesCount 件（同 ID 覆盖）、'
          '搭配新增 $outfitCount、记录新增 $recordCount、'
          '衣橱新增 $spaceCount、愿望新增 $wishCount、行李清单新增 $packingCount';
      return RestoreResult(
        ok: true,
        message: missing == 0
            ? '恢复完成：$detail'
            : '恢复完成：$detail；'
                '有 $missing 张图片在备份里缺失，已保留记录',
        clothes: clothesCount,
        outfits: outfitCount,
        records: recordCount,
        missingImages: missing,
      );
    } catch (e) {
      return RestoreResult(ok: false, message: '恢复失败：$e');
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  // ---------- JSON 编解码 ----------

  static Map<String, dynamic> _clothingToMap(Clothing c) => {
        'id': c.id,
        'imageUrl': c.imageUrl,
        'category': c.category,
        'subCategory': c.subCategory,
        'color': c.color,
        'pattern': c.pattern,
        'styles': c.styles,
        'seasons': c.seasons,
        'brand': c.brand,
        'size': c.size,
        'price': c.price,
        'purchaseDate': c.purchaseDate?.toIso8601String(),
        'locationStatus': c.locationStatus,
        'locationRoom': c.locationRoom,
        'locationFurniture': c.locationFurniture,
        'wearCount': c.wearCount,
        'lastWearDate': c.lastWearDate?.toIso8601String(),
        'createdAt': c.createdAt.toIso8601String(),
        'updatedAt': c.updatedAt?.toIso8601String(),
        'tags': c.tags,
        'isFavorite': c.isFavorite,
        'notes': c.notes,
        'material': c.material,
        'thickness': c.thickness,
        'tempMin': c.tempMin,
        'tempMax': c.tempMax,
        'occasions': c.occasions,
        'originalImagePath': c.originalImagePath,
        'cutoutImagePath': c.cutoutImagePath,
        'maskPath': c.maskPath,
        'sourceType': c.sourceType,
        'sourcePhotoId': c.sourcePhotoId,
        'bboxX': c.bboxX,
        'bboxY': c.bboxY,
        'bboxW': c.bboxW,
        'bboxH': c.bboxH,
        'aiCategory': c.aiCategory,
        'aiTags': c.aiTags,
        'aiColors': c.aiColors,
        'aiConfidence': c.aiConfidence,
        'userEdited': c.userEdited,
        'gatewayProfileId': c.gatewayProfileId,
        'cutoutStatus': c.cutoutStatus,
        'wardrobeId': c.wardrobeId,
        'customName': c.customName,
        'extraAttributes': c.extraAttributes,
      };

  static Clothing _clothingFromMap(Map<String, dynamic> m) {
    List<String> strings(dynamic v) =>
        (v as List?)?.map((e) => e.toString()).toList() ?? const [];
    return Clothing(
      id: m['id'] as String,
      imageUrl: m['imageUrl'] as String? ?? '',
      category: m['category'] as String? ?? 'tops',
      subCategory: m['subCategory'] as String? ?? 't_shirt',
      color: m['color'] as String? ?? '未知',
      pattern: m['pattern'] as String?,
      styles: strings(m['styles']),
      seasons: strings(m['seasons']),
      brand: m['brand'] as String?,
      size: m['size'] as String?,
      price: (m['price'] as num?)?.toDouble(),
      purchaseDate: _date(m['purchaseDate']),
      locationStatus: m['locationStatus'] as String? ?? 'in_wardrobe',
      locationRoom: m['locationRoom'] as String?,
      locationFurniture: m['locationFurniture'] as String?,
      wearCount: (m['wearCount'] as num?)?.toInt() ?? 0,
      lastWearDate: _date(m['lastWearDate']),
      createdAt: _date(m['createdAt']) ?? DateTime.now(),
      updatedAt: _date(m['updatedAt']),
      tags: strings(m['tags']),
      isFavorite: m['isFavorite'] as bool? ?? false,
      notes: m['notes'] as String?,
      material: m['material'] as String?,
      thickness: (m['thickness'] as num?)?.toInt() ?? 2,
      tempMin: (m['tempMin'] as num?)?.toInt(),
      tempMax: (m['tempMax'] as num?)?.toInt(),
      occasions: strings(m['occasions']),
      originalImagePath: m['originalImagePath'] as String?,
      cutoutImagePath: m['cutoutImagePath'] as String?,
      maskPath: m['maskPath'] as String?,
      sourceType: m['sourceType'] as String? ?? 'import',
      sourcePhotoId: m['sourcePhotoId'] as String?,
      bboxX: (m['bboxX'] as num?)?.toDouble(),
      bboxY: (m['bboxY'] as num?)?.toDouble(),
      bboxW: (m['bboxW'] as num?)?.toDouble(),
      bboxH: (m['bboxH'] as num?)?.toDouble(),
      aiCategory: m['aiCategory'] as String?,
      aiTags: (m['aiTags'] as List?)?.map((e) => e.toString()).toList(),
      aiColors: (m['aiColors'] as List?)?.map((e) => e.toString()).toList(),
      aiConfidence: (m['aiConfidence'] as num?)?.toDouble(),
      userEdited: m['userEdited'] as bool?,
      gatewayProfileId: m['gatewayProfileId'] as String?,
      cutoutStatus: m['cutoutStatus'] as String?,
      wardrobeId: m['wardrobeId'] as String?,
      customName: m['customName'] as String?,
      extraAttributes: (m['extraAttributes'] as Map?)?.cast<String, String>(),
    );
  }

  static Map<String, dynamic> _outfitToMap(Outfit o) => {
        'id': o.id,
        'name': o.name,
        'clothingIds': o.clothingIds,
        'occasion': o.occasion,
        'season': o.season,
        'weather': o.weather,
        'description': o.description,
        'isAiGenerated': o.isAiGenerated,
        'wearCount': o.wearCount,
        'lastWearDate': o.lastWearDate?.toIso8601String(),
        'isFavorite': o.isFavorite,
        'createdAt': o.createdAt.toIso8601String(),
        'updatedAt': o.updatedAt?.toIso8601String(),
      };

  static Outfit _outfitFromMap(Map<String, dynamic> m) => Outfit(
        id: m['id'] as String,
        name: m['name'] as String? ?? '恢复的搭配',
        clothingIds: (m['clothingIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        occasion: m['occasion'] as String?,
        season: m['season'] as String?,
        weather: m['weather'] as String?,
        description: m['description'] as String?,
        isAiGenerated: m['isAiGenerated'] as bool? ?? false,
        wearCount: (m['wearCount'] as num?)?.toInt() ?? 0,
        lastWearDate: _date(m['lastWearDate']),
        isFavorite: m['isFavorite'] as bool? ?? false,
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        updatedAt: _date(m['updatedAt']),
      );

  static Map<String, dynamic> _recordToMap(OutfitRecord r) => {
        'id': r.id,
        'outfitId': r.outfitId,
        'clothingIds': r.clothingIds,
        'date': r.date.toIso8601String(),
        'weather': r.weather,
        'temperature': r.temperature,
        'mood': r.mood,
        'occasion': r.occasion,
        'notes': r.notes,
        'createdAt': r.createdAt.toIso8601String(),
      };

  static OutfitRecord _recordFromMap(Map<String, dynamic> m) => OutfitRecord(
        id: m['id'] as String,
        outfitId: m['outfitId'] as String?,
        clothingIds: (m['clothingIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        date: _date(m['date']) ?? DateTime.now(),
        weather: m['weather'] as String?,
        temperature: (m['temperature'] as num?)?.toInt(),
        mood: m['mood'] as String?,
        occasion: m['occasion'] as String?,
        notes: m['notes'] as String?,
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
      );

  static Map<String, dynamic> _spaceToMap(WardrobeSpace s) => {
        'id': s.id,
        'name': s.name,
        'emoji': s.emoji,
        'note': s.note,
        'createdAt': s.createdAt.toIso8601String(),
        'isDefault': s.isDefault,
      };

  static WardrobeSpace _spaceFromMap(Map<String, dynamic> m) => WardrobeSpace(
        id: m['id'] as String,
        name: m['name'] as String? ?? '恢复的衣橱',
        emoji: m['emoji'] as String? ?? '🏠',
        note: m['note'] as String?,
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        isDefault: m['isDefault'] as bool? ?? false,
      );

  static Map<String, dynamic> _packingToMap(PackingList l) => {
        'id': l.id,
        'name': l.name,
        'destination': l.destination,
        'startDate': l.startDate.toIso8601String(),
        'endDate': l.endDate.toIso8601String(),
        'climate': l.climate,
        'occasions': l.occasions,
        'avgTemp': l.avgTemp,
        'items': l.items
            .map((i) => <String, dynamic>{
                  'id': i.id,
                  'name': i.name,
                  'category': i.category,
                  'quantity': i.quantity,
                  'packed': i.packed,
                  'clothingId': i.clothingId,
                  'note': i.note,
                })
            .toList(),
        'createdAt': l.createdAt.toIso8601String(),
      };

  static PackingList _packingFromMap(Map<String, dynamic> m) => PackingList(
        id: m['id'] as String,
        name: m['name'] as String? ?? '恢复的清单',
        destination: m['destination'] as String?,
        startDate: _date(m['startDate']) ?? DateTime.now(),
        endDate: _date(m['endDate']) ?? DateTime.now(),
        climate: m['climate'] as String? ?? 'mild',
        occasions:
            ((m['occasions'] as List?) ?? const []).whereType<String>().toList(),
        avgTemp: (m['avgTemp'] as num?)?.toDouble(),
        items: ((m['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((raw) => PackingItem(
                  id: raw['id'] as String? ?? '',
                  name: raw['name'] as String? ?? '（无名条目）',
                  category: raw['category'] as String? ?? 'other',
                  quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
                  packed: raw['packed'] as bool? ?? false,
                  clothingId: raw['clothingId'] as String?,
                  note: raw['note'] as String?,
                ))
            .toList(),
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
      );

  static Map<String, dynamic> _wishToMap(WishItem w) => {
        'id': w.id,
        'name': w.name,
        'category': w.category,
        'subCategory': w.subCategory,
        'color': w.color,
        'price': w.price,
        'note': w.note,
        'imagePath': w.imagePath,
        'priority': w.priority,
        'createdAt': w.createdAt.toIso8601String(),
        'purchasedAt': w.purchasedAt?.toIso8601String(),
        'clothingId': w.clothingId,
        'cooldownUntil': w.cooldownUntil?.toIso8601String(),
      };

  static WishItem _wishFromMap(Map<String, dynamic> m) => WishItem(
        id: m['id'] as String,
        name: m['name'] as String? ?? '恢复的愿望',
        category: m['category'] as String? ?? ClothingCategory.tops,
        subCategory: m['subCategory'] as String?,
        color: m['color'] as String?,
        price: (m['price'] as num?)?.toDouble(),
        note: m['note'] as String?,
        imagePath: m['imagePath'] as String?,
        priority: (m['priority'] as num?)?.toInt() ?? 1,
        createdAt: _date(m['createdAt']) ?? DateTime.now(),
        purchasedAt: _date(m['purchasedAt']),
        clothingId: m['clothingId'] as String?,
        cooldownUntil: _date(m['cooldownUntil']),
      );

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
