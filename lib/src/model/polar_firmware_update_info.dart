/// Information about available firmware update
class PolarFirmwareUpdateInfo {
  /// Whether a firmware update is available
  final bool isUpdateAvailable;

  /// Current firmware version
  final String currentVersion;

  /// Available firmware version (if update is available)
  final String? availableVersion;

  const PolarFirmwareUpdateInfo({
    required this.isUpdateAvailable,
    required this.currentVersion,
    this.availableVersion,
  });

  /// Creates a [PolarFirmwareUpdateInfo] instance from a JSON map.
  factory PolarFirmwareUpdateInfo.fromJson(Map<String, dynamic> json) {
    return PolarFirmwareUpdateInfo(
      isUpdateAvailable: json['isUpdateAvailable'] as bool,
      currentVersion: json['currentVersion'] as String,
      availableVersion: json['availableVersion'] as String?,
    );
  }

  /// Converts this [PolarFirmwareUpdateInfo] instance to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'isUpdateAvailable': isUpdateAvailable,
      'currentVersion': currentVersion,
      'availableVersion': availableVersion,
    };
  }
}
