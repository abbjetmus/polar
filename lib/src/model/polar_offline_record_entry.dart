import 'package:json_annotation/json_annotation.dart';
import 'package:polar/polar.dart';
import 'package:polar/src/model/convert.dart';

part 'polar_offline_record_entry.g.dart';

DateTime _parseDateField(dynamic value) {
  if (value is num) {
    // Android: unix timestamp in milliseconds
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  } else if (value is String) {
    // iOS: iso8601 string
    return DateTime.parse(value);
  } else if (value is Map) {
    // Fallback: map format
    return const MapToDateTimeConverter()
        .fromJson(Map<String, dynamic>.from(value));
  }
  throw ArgumentError('Unexpected date format: $value (${value.runtimeType})');
}

String _dateToJson(DateTime date) => date.toIso8601String();

/// A class representing an offline recording entry from a Polar device.
@JsonSerializable()
class PolarOfflineRecordingEntry {
  /// The file path of the recording.
  final String path;

  /// The size of the recording file in bytes.
  final int size;

  /// The date and time when the recording was made.
  /// On Android this comes as a unix timestamp (milliseconds).
  /// On iOS this comes as an ISO 8601 string.
  @JsonKey(fromJson: _parseDateField, toJson: _dateToJson)
  final DateTime date;

  /// The type of data recorded by the Polar device.
  @PolarDataTypeConverter()
  final PolarDataType type;

  /// Constructs a [PolarOfflineRecordingEntry] with the given parameters.
  PolarOfflineRecordingEntry({
    required this.path,
    required this.size,
    required this.date,
    required this.type,
  });

  /// Creates a new instance from a JSON object.
  factory PolarOfflineRecordingEntry.fromJson(Map<String, dynamic> json) =>
      _$PolarOfflineRecordingEntryFromJson(json);

  /// Converts the instance to a JSON object.
  Map<String, dynamic> toJson() => _$PolarOfflineRecordingEntryToJson(this);
}
