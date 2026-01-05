/// Represents the types of data that can be stored on a Polar device.
enum PolarStoredDataType {
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

  /// Skin contact changes data
  skinContactChanges,

  /// Skin temperature data
  skintemp,

  /// Sleep data
  sleep,

  /// Sleep score data
  sleepScore;

  /// Converts this enum to a JSON string.
  String toJson() => name;

  /// Creates a [PolarStoredDataType] from a JSON string.
  static PolarStoredDataType fromJson(String json) {
    return PolarStoredDataType.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw Exception('Unknown PolarStoredDataType: $json'),
    );
  }
}
