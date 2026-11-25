// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'try_on_task.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TryOnTaskAdapter extends TypeAdapter<TryOnTask> {
  @override
  final int typeId = 7;

  @override
  TryOnTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TryOnTask(
      id: fields[0] as String? ?? '',
      personImagePath: fields[1] as String? ?? '',
      itemIds: (fields[2] as List?)?.cast<String>() ?? const [],
      status: fields[3] as String? ?? 'pending',
      resultImagePath: fields[4] as String?,
      prompt: fields[5] as String?,
      errorMessage: fields[6] as String?,
      gatewayProfileId: fields[7] as String?,
      createdAt: fields[8] as DateTime? ?? DateTime.now(),
      finishedAt: fields[9] as DateTime?,
      degraded: fields[10] as bool? ?? false,
      outfitName: fields[11] as String?,
      outfitCategory: fields[12] as String?,
      outfitTags: (fields[13] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, TryOnTask obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.personImagePath)
      ..writeByte(2)
      ..write(obj.itemIds)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.resultImagePath)
      ..writeByte(5)
      ..write(obj.prompt)
      ..writeByte(6)
      ..write(obj.errorMessage)
      ..writeByte(7)
      ..write(obj.gatewayProfileId)
      ..writeByte(8)
      ..write(obj.createdAt)
      ..writeByte(9)
      ..write(obj.finishedAt)
      ..writeByte(10)
      ..write(obj.degraded)
      ..writeByte(11)
      ..write(obj.outfitName)
      ..writeByte(12)
      ..write(obj.outfitCategory)
      ..writeByte(13)
      ..write(obj.outfitTags);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TryOnTaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
