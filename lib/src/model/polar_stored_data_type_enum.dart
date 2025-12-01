import 'dart:io';

/// Represents the types of stored data that can be deleted from a Polar device.
/// This corresponds to the iOS StoredDataType enum.
enum PolarStoredDataTypeEnum {
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
}
