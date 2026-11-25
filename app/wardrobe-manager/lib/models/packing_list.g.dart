// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'packing_list.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PackingListAdapter extends TypeAdapter<PackingList> {
  @override
  final int typeId = 4;

  @override
  PackingList read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PackingList(
      id: fields[0] as String? ?? '',
      name: fields[1] as String? ?? '',
      destination: fields[2] as String?,
      startDate: fields[3] as DateTime? ?? DateTime.now(),
      endDate: fields[4] as DateTime? ?? DateTime.now(),
      climate: fields[5] as String? ?? 'mild',
      occasions: (fields[6] as List?)?.cast<String>() ?? const <String>[],
      avgTemp: fields[7] as double?,
      items: (fields[8] as List?)?.cast<PackingItem>() ?? const <PackingItem>[],
      createdAt: fields[9] as DateTime? ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, PackingList obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.destination)
      ..writeByte(3)
      ..write(obj.startDate)
      ..writeByte(4)
      ..write(obj.endDate)
      ..writeByte(5)
      ..write(obj.climate)
      ..writeByte(6)
      ..write(obj.occasions)
      ..writeByte(7)
      ..write(obj.avgTemp)
      ..writeByte(8)
      ..write(obj.items)
      ..writeByte(9)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackingListAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class PackingItemAdapter extends TypeAdapter<PackingItem> {
  @override
  final int typeId = 5;

  @override
  PackingItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PackingItem(
      id: fields[0] as String? ?? '',
      name: fields[1] as String? ?? '',
      category: fields[2] as String? ?? '',
      quantity: fields[3] as int? ?? 1,
      packed: fields[4] as bool? ?? false,
      clothingId: fields[5] as String?,
      note: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PackingItem obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.category)
      ..writeByte(3)
      ..write(obj.quantity)
      ..writeByte(4)
      ..write(obj.packed)
      ..writeByte(5)
      ..write(obj.clothingId)
      ..writeByte(6)
      ..write(obj.note);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackingItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
