/// Firmware update progress information
class PolarFirmwareUpdateProgress {
  /// The device identifier
  final String identifier;

  /// Progress percentage (0-100)
  final int progressPercentage;

  /// Current status message describing the update stage
  final String status;

  /// Whether the update is completed
  final bool isCompleted;

  const PolarFirmwareUpdateProgress({
    required this.identifier,
    required this.progressPercentage,
    required this.status,
    required this.isCompleted,
  });

  /// Creates a [PolarFirmwareUpdateProgress] instance from a JSON map.
  factory PolarFirmwareUpdateProgress.fromJson(Map<String, dynamic> json) {
    return PolarFirmwareUpdateProgress(
      identifier: json['identifier'] as String,
      progressPercentage: json['progressPercentage'] as int,
      status: json['status'] as String,
      isCompleted: json['isCompleted'] as bool,
    );
  }

  /// Converts this [PolarFirmwareUpdateProgress] instance to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'identifier': identifier,
      'progressPercentage': progressPercentage,
      'status': status,
      'isCompleted': isCompleted,
    };
  }
}
