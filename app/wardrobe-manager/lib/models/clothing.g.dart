// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clothing.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ClothingAdapter extends TypeAdapter<Clothing> {
  @override
  final int typeId = 0;

  @override
  Clothing read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Clothing(
      id: fields[0] as String? ?? '',
      imageUrl: fields[1] as String? ?? '',
      category: fields[2] as String? ?? '',
      subCategory: fields[3] as String? ?? '',
      color: fields[4] as String? ?? '',
      pattern: fields[5] as String?,
      styles: (fields[6] as List?)?.cast<String>() ?? const <String>[],
      seasons: (fields[7] as List?)?.cast<String>() ?? const <String>[],
      brand: fields[8] as String?,
      size: fields[9] as String?,
      price: fields[10] as double?,
      purchaseDate: fields[11] as DateTime?,
      locationStatus: fields[12] as String? ?? 'in_wardrobe',
      locationRoom: fields[13] as String?,
      locationFurniture: fields[14] as String?,
      wearCount: fields[15] as int? ?? 0,
      lastWearDate: fields[16] as DateTime?,
      createdAt: fields[17] as DateTime? ?? DateTime.now(),
      updatedAt: fields[18] as DateTime?,
      tags: (fields[19] as List?)?.cast<String>() ?? const <String>[],
      isFavorite: fields[20] as bool? ?? false,
      notes: fields[21] as String?,
      material: fields[22] as String?,
      thickness: fields[23] as int? ?? 2,
      tempMin: fields[24] as int?,
      tempMax: fields[25] as int?,
      occasions: (fields[26] as List?)?.cast<String>() ?? const <String>[],
      originalImagePath: fields[27] as String?,
      cutoutImagePath: fields[28] as String?,
      maskPath: fields[29] as String?,
      sourceType: fields[30] as String?,
      sourcePhotoId: fields[31] as String?,
      bboxX: fields[32] as double?,
      bboxY: fields[33] as double?,
      bboxW: fields[34] as double?,
      bboxH: fields[35] as double?,
      aiCategory: fields[36] as String?,
      aiTags: (fields[37] as List?)?.cast<String>(),
      aiColors: (fields[38] as List?)?.cast<String>(),
      aiConfidence: fields[39] as double?,
      userEdited: fields[40] as bool?,
      gatewayProfileId: fields[41] as String?,
      cutoutStatus: fields[42] as String?,
      wardrobeId: fields[43] as String?,
      customName: fields[44] as String?,
      extraAttributes: (fields[45] as Map?)?.cast<String, String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Clothing obj) {
    writer
      ..writeByte(46)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.imageUrl)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.subCategory)
      ..writeByte(4)
      ..write(obj.color)
      ..writeByte(5)
      ..write(obj.pattern)
      ..writeByte(6)
      ..write(obj.styles)
      ..writeByte(7)
      ..write(obj.seasons)
      ..writeByte(8)
      ..write(obj.brand)
      ..writeByte(9)
      ..write(obj.size)
      ..writeByte(10)
      ..write(obj.price)
      ..writeByte(11)
      ..write(obj.purchaseDate)
      ..writeByte(12)
      ..write(obj.locationStatus)
      ..writeByte(13)
      ..write(obj.locationRoom)
      ..writeByte(14)
      ..write(obj.locationFurniture)
      ..writeByte(15)
      ..write(obj.wearCount)
      ..writeByte(16)
      ..write(obj.lastWearDate)
      ..writeByte(17)
      ..write(obj.createdAt)
      ..writeByte(18)
      ..write(obj.updatedAt)
      ..writeByte(19)
      ..write(obj.tags)
      ..writeByte(20)
      ..write(obj.isFavorite)
      ..writeByte(21)
      ..write(obj.notes)
      ..writeByte(22)
      ..write(obj.material)
      ..writeByte(23)
      ..write(obj.thickness)
      ..writeByte(24)
      ..write(obj.tempMin)
      ..writeByte(25)
      ..write(obj.tempMax)
      ..writeByte(26)
      ..write(obj.occasions)
      ..writeByte(27)
      ..write(obj.originalImagePath)
      ..writeByte(28)
      ..write(obj.cutoutImagePath)
      ..writeByte(29)
      ..write(obj.maskPath)
      ..writeByte(30)
      ..write(obj.sourceType)
      ..writeByte(31)
      ..write(obj.sourcePhotoId)
      ..writeByte(32)
      ..write(obj.bboxX)
      ..writeByte(33)
      ..write(obj.bboxY)
      ..writeByte(34)
      ..write(obj.bboxW)
      ..writeByte(35)
      ..write(obj.bboxH)
      ..writeByte(36)
      ..write(obj.aiCategory)
      ..writeByte(37)
      ..write(obj.aiTags)
      ..writeByte(38)
      ..write(obj.aiColors)
      ..writeByte(39)
      ..write(obj.aiConfidence)
      ..writeByte(40)
      ..write(obj.userEdited)
      ..writeByte(41)
      ..write(obj.gatewayProfileId)
      ..writeByte(42)
      ..write(obj.cutoutStatus)
      ..writeByte(43)
      ..write(obj.wardrobeId)
      ..writeByte(44)
      ..write(obj.customName)
      ..writeByte(45)
      ..write(obj.extraAttributes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClothingAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
