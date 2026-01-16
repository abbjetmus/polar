import 'dart:io';

/// Represents the types of data that can be stored on a Polar device.
/// Order must match iOS PolarStoredDataType.StoredDataType enum
enum PolarStoredDataType {
  /// Undefined data type
  undefined,

  /// Activity data
  activity,

  /// Auto sample data
  autoSample,

  /// Daily summary data
  dailySummary,

  /// Nightly recovery data
  nightlyRecovery,

  /// SD logs data
  sdlogs,

  /// Sleep data
  sleep,

  /// Sleep score data
  sleepScore,

  /// Skin contact changes data
  skinContactChanges,

  /// Skin temperature data
  skintemp;

  /// Converts this enum to JSON format for use with the native API.
  /// - iOS: Returns the enum index as an integer
  /// - Android: Returns the enum name as a string
  dynamic toJson() {
    if (Platform.isIOS) {
      return index;
    } else {
      return name;
    }
  }

  /// Creates a [PolarStoredDataType] from a JSON string.
  static PolarStoredDataType fromJson(String json) {
    return PolarStoredDataType.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw Exception('Unknown PolarStoredDataType: $json'),
    );
  }
}
