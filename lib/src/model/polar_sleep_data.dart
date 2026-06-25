/// Represents the sleep analysis result for a single sleep period, as produced
/// by the Polar device's dedicated sleep algorithm (`PolarSleepApi.getSleep`).
///
/// This is the reliable on-device sleep detection — distinct from, and far more
/// accurate than, the `SLEEP` activity class found in activity sample data.
class PolarSleepData {
  /// The date this sleep result belongs to (typically the wake-up date),
  /// in the device's local time. May be null if the device did not report it.
  final DateTime? date;

  /// Absolute start time of the detected sleep period. Null if unavailable.
  final DateTime? sleepStartTime;

  /// Absolute end time of the detected sleep period. Null if unavailable.
  final DateTime? sleepEndTime;

  /// Creates a new [PolarSleepData] instance.
  PolarSleepData({
    this.date,
    this.sleepStartTime,
    this.sleepEndTime,
  });

  /// Creates a [PolarSleepData] instance from a JSON map.
  factory PolarSleepData.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic value) {
      if (value == null) return null;
      final str = value as String;
      if (str.isEmpty) return null;
      return DateTime.tryParse(str);
    }

    return PolarSleepData(
      date: parse(json['date']),
      sleepStartTime: parse(json['sleepStartTime']),
      sleepEndTime: parse(json['sleepEndTime']),
    );
  }

  /// Converts this [PolarSleepData] instance to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'date': date?.toIso8601String(),
      'sleepStartTime': sleepStartTime?.toIso8601String(),
      'sleepEndTime': sleepEndTime?.toIso8601String(),
    };
  }
}
