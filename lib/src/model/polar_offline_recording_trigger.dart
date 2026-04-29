import 'package:polar/src/model/polar_device_data_type.dart';
import 'package:polar/src/model/polar_sensor_setting.dart';

/// Trigger mode that decides when the device automatically starts an
/// offline recording. The trigger is persisted on the device and takes
/// effect on the next device startup (on Polar 360, "device startup"
/// includes unplugging from the charger).
enum PolarOfflineRecordingTriggerMode {
  /// Automatic offline recording is disabled.
  triggerDisabled,

  /// Triggers the offline recording when the device is powered on.
  /// On Polar 360 this fires when the device is unplugged from the charger.
  triggerSystemStart,

  /// Triggers the offline recording when an exercise is started on the device.
  /// Not supported on Polar 360 (no exercise start UI).
  triggerExerciseStart,
}

/// Polar offline recording trigger configuration.
class PolarOfflineRecordingTrigger {
  /// Constructor
  const PolarOfflineRecordingTrigger({
    required this.triggerMode,
    required this.triggerFeatures,
  });

  /// The trigger mode.
  final PolarOfflineRecordingTriggerMode triggerMode;

  /// The data types to record when the trigger fires. For [PolarDataType.ppi]
  /// and [PolarDataType.hr] the settings must be null. The map is empty when
  /// the mode is [PolarOfflineRecordingTriggerMode.triggerDisabled].
  final Map<PolarDataType, PolarSensorSetting?> triggerFeatures;
}
