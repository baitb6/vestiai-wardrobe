// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wish_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WishItemAdapter extends TypeAdapter<WishItem> {
  @override
  final int typeId = 8;

  @override
  WishItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WishItem(
      id: fields[0] as String? ?? '',
      name: fields[1] as String? ?? '',
      category: fields[2] as String? ?? '',
      subCategory: fields[3] as String?,
      color: fields[4] as String?,
      price: fields[5] as double?,
      note: fields[6] as String?,
      imagePath: fields[7] as String?,
      priority: fields[8] as int? ?? 1,
      createdAt: fields[9] as DateTime? ?? DateTime.now(),
      purchasedAt: fields[10] as DateTime?,
      clothingId: fields[11] as String?,
      cooldownUntil: fields[12] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, WishItem obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.subCategory)
      ..writeByte(4)
      ..write(obj.color)
      ..writeByte(5)
      ..write(obj.price)
      ..writeByte(6)
      ..write(obj.note)
      ..writeByte(7)
      ..write(obj.imagePath)
      ..writeByte(8)
      ..write(obj.priority)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.purchasedAt)
      ..writeByte(11)
      ..write(obj.clothingId)
      ..writeByte(12)
      ..write(obj.cooldownUntil);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WishItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
