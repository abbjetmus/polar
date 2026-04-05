import 'dart:io';

/// Features available in Polar BLE SDK library.
/// Order must match the iOS SDK's PolarBleSdkFeature enum for index-based mapping.
enum PolarSdkFeature {
  /// Hr feature to receive hr and rr data from Polar or any other BLE device
  /// via standard HR BLE service
  hr,

  /// Device information feature to receive sw information from Polar or any
  /// other BLE device
  deviceInfo,

  /// Feature to receive battery level info from Polar or any other BLE device
  batteryInfo,

  /// Polar sensor streaming feature to stream live online data. For example
  /// hr, ecg, acc, ppg, ppi, etc...
  onlineStreaming,

  /// Polar offline recording feature to record offline data to Polar device
  /// without continuous BLE connection.
  offlineRecording,

  /// H10 exercise recording feature to record exercise data to Polar H10
  /// device without continuous BLE connection.
  h10ExerciseRecording,

  /// Offline exercise V2 recording feature.
  offlineExerciseV2,

  /// Feature to read and set device time in Polar device
  deviceTimeSetup,

  /// In SDK mode the wider range of capabilities are available for the online
  /// stream or offline recoding than in normal operation mode.
  sdkMode,

  /// Feature to enable or disable SDK mode blinking LED animation.
  ledAnimation,

  /// Feature to update firmware on Polar device.
  firmwareUpdate,

  /// Feature to read activity data from Polar device.
  activityData,

  /// Feature to read training data from Polar device.
  trainingData,

  /// Feature to read sleep data from Polar device.
  sleepData,

  /// Feature to control Polar device.
  deviceControl,

  /// Feature to enable or disable file transfer.
  fileTransfer,

  /// Health Thermometer Service feature.
  hts,

  /// Feature to read temperature data from Polar device.
  temperatureData,

  /// Feature for features configuration service.
  featuresConfigurationService;

  static const _featureStringMap = {
    hr: 'FEATURE_HR',
    deviceInfo: 'FEATURE_DEVICE_INFO',
    batteryInfo: 'FEATURE_BATTERY_INFO',
    onlineStreaming: 'FEATURE_POLAR_ONLINE_STREAMING',
    offlineRecording: 'FEATURE_POLAR_OFFLINE_RECORDING',
    h10ExerciseRecording: 'FEATURE_POLAR_H10_EXERCISE_RECORDING',
    offlineExerciseV2: 'FEATURE_POLAR_OFFLINE_EXERCISE_V2',
    deviceTimeSetup: 'FEATURE_POLAR_DEVICE_TIME_SETUP',
    sdkMode: 'FEATURE_POLAR_SDK_MODE',
    ledAnimation: 'FEATURE_POLAR_LED_ANIMATION',
    firmwareUpdate: 'FEATURE_POLAR_FIRMWARE_UPDATE',
    activityData: 'FEATURE_POLAR_ACTIVITY_DATA',
    trainingData: 'FEATURE_POLAR_TRAINING_DATA',
    sleepData: 'FEATURE_POLAR_SLEEP_DATA',
    deviceControl: 'FEATURE_POLAR_DEVICE_CONTROL',
    fileTransfer: 'FEATURE_POLAR_FILE_TRANSFER',
    hts: 'FEATURE_HTS',
    temperatureData: 'FEATURE_POLAR_TEMPERATURE_DATA',
    featuresConfigurationService: 'FEATURE_POLAR_FEATURES_CONFIGURATION_SERVICE',
  };

  static final _stringFeatureMap =
      _featureStringMap.map((k, v) => MapEntry(v, k));

  /// Create a [PolarSdkFeature] from json
  static PolarSdkFeature? fromJson(dynamic json) {
    if (Platform.isIOS) {
      final index = json as int;
      if (index >= 0 && index < PolarSdkFeature.values.length) {
        return PolarSdkFeature.values[index];
      }
      return null; // Unknown feature from newer SDK version
    } else {
      // This is Android
      if (json is String && _stringFeatureMap.containsKey(json)) {
        return _stringFeatureMap[json]!;
      } else {
        // Handle the case where json is not a valid key
        return PolarSdkFeature
            .offlineRecording; // Default to hr or another appropriate default
      }
    }
  }

  /// Convert a [PolarSdkFeature] to json
  dynamic toJson() {
    if (Platform.isIOS) {
      return PolarSdkFeature.values.indexOf(this);
    } else {
      // This is Android
      if (_featureStringMap.containsKey(this)) {
        return _featureStringMap[this];
      } else {
        return 'FEATURE_POLAR_OFFLINE_RECORDING'; // Default value if the key is not found
      }
    }
  }
}
