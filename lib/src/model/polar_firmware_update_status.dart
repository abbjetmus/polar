import 'package:json_annotation/json_annotation.dart';

part 'polar_firmware_update_status.g.dart';

/// Status for firmware update check.
@JsonSerializable()
class PolarFirmwareUpdateCheckStatus {
  /// The type of status
  final String type;

  /// Version if available
  final String? version;

  /// Details if not available or failed
  final String? details;

  /// Constructor
  PolarFirmwareUpdateCheckStatus({
    required this.type,
    this.version,
    this.details,
  });

  /// From json
  factory PolarFirmwareUpdateCheckStatus.fromJson(Map<String, dynamic> json) =>
      _$PolarFirmwareUpdateCheckStatusFromJson(json);

  /// To json
  Map<String, dynamic> toJson() => _$PolarFirmwareUpdateCheckStatusToJson(this);
}

/// Status for firmware update process.
@JsonSerializable()
class PolarFirmwareUpdateStatus {
  /// The type of status
  final String type;

  /// Details
  final String? details;

  /// Constructor
  PolarFirmwareUpdateStatus({
    required this.type,
    this.details,
  });

  /// From json
  factory PolarFirmwareUpdateStatus.fromJson(Map<String, dynamic> json) =>
      _$PolarFirmwareUpdateStatusFromJson(json);

  /// To json
  Map<String, dynamic> toJson() => _$PolarFirmwareUpdateStatusToJson(this);
}
