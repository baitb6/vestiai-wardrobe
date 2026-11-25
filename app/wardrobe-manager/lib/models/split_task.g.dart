// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'split_task.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SplitTaskAdapter extends TypeAdapter<SplitTask> {
  @override
  final int typeId = 6;

  @override
  SplitTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SplitTask(
      id: fields[0] as String? ?? '',
      sourceImagePath: fields[1] as String? ?? '',
      status: fields[2] as String? ?? 'pending',
      resultJson: fields[3] as String?,
      errorMessage: fields[4] as String?,
      createdAt: fields[5] as DateTime? ?? DateTime.now(),
      finishedAt: fields[6] as DateTime?,
      itemCount: fields[7] as int?,
      importedCount: fields[8] as int?,
      gatewayProfileId: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SplitTask obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.sourceImagePath)
      ..writeByte(2)
      ..write(obj.status)
      ..writeByte(3)
      ..write(obj.resultJson)
      ..writeByte(4)
      ..write(obj.errorMessage)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.finishedAt)
      ..writeByte(7)
      ..write(obj.itemCount)
      ..writeByte(8)
      ..write(obj.importedCount)
      ..writeByte(9)
      ..write(obj.gatewayProfileId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SplitTaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
