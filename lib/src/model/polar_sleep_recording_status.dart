/// Sleep recording status reported by the device (polar-ble-sdk 8.4.0+).
enum PolarSleepRecordingStatus {
  /// Sleep recording is on.
  enabled,

  /// Sleep recording is off.
  disabled,

  /// The device answered but did not report the state. Not the same as
  /// [disabled]: before 8.4.0 the SDK mapped this to "off", so callers could
  /// not tell an explicit off from a missing value.
  unknown;

  /// Both platforms send the lowercase case name.
  static PolarSleepRecordingStatus fromJson(dynamic json) =>
      PolarSleepRecordingStatus.values.asNameMap()[json as String] ?? unknown;
}
