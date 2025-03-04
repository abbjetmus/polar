import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:polar/polar.dart';
import 'package:polar/src/model/convert.dart';
import 'package:polar/src/model/polar_offline_recording_data.dart';

/// Flutter implementation of the [PolarBleSdk]
class Polar {
  static const _channel = MethodChannel('polar');
  static const _searchChannel = EventChannel('polar/search');

  static Polar? _instance;

  // Other data
  final _blePowerState = StreamController<bool>.broadcast();
  final _sdkFeatureReady =
      StreamController<PolarSdkFeatureReadyEvent>.broadcast();
  final _deviceConnected = StreamController<PolarDeviceInfo>.broadcast();
  final _deviceConnecting = StreamController<PolarDeviceInfo>.broadcast();
  final _deviceDisconnected =
      StreamController<PolarDeviceDisconnectedEvent>.broadcast();
  final _disInformation =
      StreamController<PolarDisInformationEvent>.broadcast();
  final _batteryLevel = StreamController<PolarBatteryLevelEvent>.broadcast();

  /// helper to ask ble power state
  Stream<bool> get blePowerState => _blePowerState.stream;

  /// feature ready callback
  Stream<PolarSdkFeatureReadyEvent> get sdkFeatureReady =>
      _sdkFeatureReady.stream;

  /// Device connection has been established.
  ///
  /// - Parameter identifier: Polar device info
  Stream<PolarDeviceInfo> get deviceConnected => _deviceConnected.stream;

  /// Callback when connection attempt is started to device
  ///
  /// - Parameter identifier: Polar device info
  Stream<PolarDeviceInfo> get deviceConnecting => _deviceConnecting.stream;

  /// Connection lost to device.
  /// If PolarBleApi#disconnectFromPolarDevice is not called, a new connection attempt is dispatched automatically.
  ///
  /// - Parameter identifier: Polar device info
  Stream<PolarDeviceDisconnectedEvent> get deviceDisconnected =>
      _deviceDisconnected.stream;

  ///  Received DIS info.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id
  ///   - fwVersion: firmware version in format major.minor.patch
  Stream<PolarDisInformationEvent> get disInformation => _disInformation.stream;

  /// Battery level received from device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id
  ///   - batteryLevel: battery level in precentage 0-100%
  Stream<PolarBatteryLevelEvent> get batteryLevel => _batteryLevel.stream;

  /// Will request location permission on Android S+ if false
  final bool _bluetoothScanNeverForLocation;

  Polar._(this._bluetoothScanNeverForLocation) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Initialize the Polar API. Returns a singleton.
  ///
  /// DartDocs are copied from the iOS version of the SDK and are only included for reference
  ///
  /// The plugin will request location permission on Android S+ if [bluetoothScanNeverForLocation] is false
  factory Polar({bool bluetoothScanNeverForLocation = true}) =>
      _instance ??= Polar._(bluetoothScanNeverForLocation);

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'blePowerStateChanged':
        _blePowerState.add(call.arguments);
        return;
      case 'sdkFeatureReady':
        _sdkFeatureReady.add(
          PolarSdkFeatureReadyEvent(
            call.arguments[0],
            PolarSdkFeature.fromJson(call.arguments[1]),
          ),
        );
        return;
      case 'deviceConnected':
        _deviceConnected
            .add(PolarDeviceInfo.fromJson(jsonDecode(call.arguments)));
        return;
      case 'deviceConnecting':
        _deviceConnecting
            .add(PolarDeviceInfo.fromJson(jsonDecode(call.arguments)));
        return;
      case 'deviceDisconnected':
        _deviceDisconnected.add(
          PolarDeviceDisconnectedEvent(
            PolarDeviceInfo.fromJson(jsonDecode(call.arguments[0])),
            call.arguments[1],
          ),
        );
        return;
      case 'disInformationReceived':
        _disInformation.add(
          PolarDisInformationEvent(
            call.arguments[0],
            call.arguments[1],
            call.arguments[2],
          ),
        );
        return;
      case 'batteryLevelReceived':
        _batteryLevel.add(
          PolarBatteryLevelEvent(
            call.arguments[0],
            call.arguments[1],
          ),
        );
        return;
      default:
        throw UnimplementedError(call.method);
    }
  }

  /// Start searching for Polar device(s)
  ///
  /// - Parameter onNext: Invoked once for each device
  /// - Returns: Observable stream
  ///  - onNext: for every new polar device found
  Stream<PolarDeviceInfo> searchForDevice() {
    return _searchChannel.receiveBroadcastStream().map(
          (event) => PolarDeviceInfo.fromJson(jsonDecode(event)),
        );
  }

  /// Request a connection to a Polar device. Invokes `PolarBleApiObservers` polarDeviceConnected.
  /// - Parameter identifier: Polar device id printed on the sensor/device or UUID.
  /// - Throws: InvalidArgument if identifier is invalid polar device id or invalid uuid
  ///
  /// Will request the necessary permissions if [requestPermissions] is true
  Future<void> connectToDevice(
    String identifier, {
    bool requestPermissions = true,
  }) async {
    if (requestPermissions) {
      await this.requestPermissions();
    }

    unawaited(_channel.invokeMethod('connectToDevice', identifier));
  }

  /// Request the necessary permissions on Android
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidDeviceInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidDeviceInfo.version.sdkInt;

      // If we are on Android M+
      if (sdkInt >= 23) {
        // If we are on an Android version before S or bluetooth scan is used to derive location
        if (sdkInt < 31 || !_bluetoothScanNeverForLocation) {
          await Permission.location.request();
        }
        // If we are on Android S+
        if (sdkInt >= 31) {
          await Permission.bluetoothScan.request();
          await Permission.bluetoothConnect.request();
        }
      }
    }
  }

  /// Disconnect from the current Polar device.
  ///
  /// - Parameter identifier: Polar device id
  /// - Throws: InvalidArgument if identifier is invalid polar device id or invalid uuid
  Future<void> disconnectFromDevice(String identifier) {
    return _channel.invokeMethod('disconnectFromDevice', identifier);
  }

  ///  Get the data types available in this device for online streaming
  ///
  /// - Parameters:
  ///   - identifier: polar device id
  /// - Returns: Single stream
  ///   - success: set of available online streaming data types in this device
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<Set<PolarDataType>> getAvailableOnlineStreamDataTypes(
    String identifier,
  ) async {
    final response = await _channel.invokeMethod(
      'getAvailableOnlineStreamDataTypes',
      identifier,
    );
    if (response == null) return {};
    return (jsonDecode(response) as List).map(PolarDataType.fromJson).toSet();
  }

  ///  Request the stream settings available in current operation mode. This request shall be used before the stream is started
  ///  to decide currently available settings. The available settings depend on the state of the device. For example, if any stream(s)
  ///  or optical heart rate measurement is already enabled, then the device may limit the offer of possible settings for other stream feature.
  ///  Requires `polarSensorStreaming` feature.
  ///
  /// - Parameters:
  ///   - identifier: polar device id
  ///   - feature: selected feature from`PolarDeviceDataType`
  /// - Returns: Single stream
  ///   - success: once after settings received from device
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<PolarSensorSetting> requestStreamSettings(
    String identifier,
    PolarDataType feature,
  ) async {
    final response = await _channel.invokeMethod(
      'requestStreamSettings',
      [identifier, feature.toJson()],
    );
    return PolarSensorSetting.fromJson(jsonDecode(response));
  }

  Stream<Map<String, dynamic>> _startStreaming(
    PolarDataType feature,
    String identifier, {
    PolarSensorSetting? settings,
  }) async* {
    assert(settings == null || settings.isSelection);

    final channelName = 'polar/streaming/$identifier/${feature.name}';

    await _channel.invokeMethod('createStreamingChannel', [
      channelName,
      identifier,
      feature.toJson(),
    ]);

    if (settings == null && feature.supportsStreamSettings) {
      final availableSettings = await requestStreamSettings(
        identifier,
        feature,
      );
      settings = availableSettings.maxSettings();
    }

    yield* EventChannel(channelName)
        .receiveBroadcastStream(jsonEncode(settings))
        .cast<String>()
        .map(jsonDecode)
        .cast<Map<String, dynamic>>();
  }

  /// Start heart rate stream. Heart rate stream is stopped if the connection is closed,
  /// error occurs or stream is disposed.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  /// - Returns: Observable stream
  ///   - onNext: for every air packet received. see `PolarHrData`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Stream<PolarHrData> startHrStreaming(String identifier) {
    return _startStreaming(PolarDataType.hr, identifier)
        .map(PolarHrData.fromJson);
  }

  /// Start the ECG (Electrocardiography) stream. ECG stream is stopped if the connection is closed, error occurs or stream is disposed.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  ///   - settings: selected settings to start the stream
  /// - Returns: Observable stream
  ///   - onNext: for every air packet received. see `PolarEcgData`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Stream<PolarEcgData> startEcgStreaming(
    String identifier, {
    PolarSensorSetting? settings,
  }) {
    return _startStreaming(
      PolarDataType.ecg,
      identifier,
      settings: settings,
    ).map(PolarEcgData.fromJson);
  }

  ///  Start ACC (Accelerometer) stream. ACC stream is stopped if the connection is closed, error occurs or stream is disposed.
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  ///   - settings: selected settings to start the stream
  /// - Returns: Observable stream
  ///   - onNext: for every air packet received. see `PolarAccData`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Stream<PolarAccData> startAccStreaming(
    String identifier, {
    PolarSensorSetting? settings,
  }) {
    return _startStreaming(
      PolarDataType.acc,
      identifier,
      settings: settings,
    ).map(PolarAccData.fromJson);
  }

  /// Start Gyro stream. Gyro stream is stopped if the connection is closed, error occurs during start or stream is disposed.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  ///   - settings: selected settings to start the stream
  Stream<PolarGyroData> startGyroStreaming(
    String identifier, {
    PolarSensorSetting? settings,
  }) {
    return _startStreaming(
      PolarDataType.gyro,
      identifier,
      settings: settings,
    ).map(PolarGyroData.fromJson);
  }

  /// Start magnetometer stream. Magnetometer stream is stopped if the connection is closed, error occurs or stream is disposed.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  ///   - settings: selected settings to start the stream
  Stream<PolarMagnetometerData> startMagnetometerStreaming(
    String identifier, {
    PolarSensorSetting? settings,
  }) {
    return _startStreaming(
      PolarDataType.magnetometer,
      identifier,
      settings: settings,
    ).map(PolarMagnetometerData.fromJson);
  }

  /// Start optical sensor PPG (Photoplethysmography) stream. PPG stream is stopped if the connection is closed, error occurs or stream is disposed.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  ///   - settings: selected settings to start the stream
  /// - Returns: Observable stream
  ///   - onNext: for every air packet received. see `PolarPpgData`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Stream<PolarPpgData> startPpgStreaming(
    String identifier, {
    PolarSensorSetting? settings,
  }) {
    return _startStreaming(
      PolarDataType.ppg,
      identifier,
      settings: settings,
    ).map(PolarPpgData.fromJson);
  }

  /// Start PPI (Pulse to Pulse interval) stream.
  /// PPI stream is stopped if the connection is closed, error occurs or stream is disposed.
  /// Notice that there is a delay before PPI data stream starts.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  /// - Returns: Observable stream
  ///   - onNext: for every air packet received. see `PolarPpiData`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Stream<PolarPpiData> startPpiStreaming(String identifier) {
    return _startStreaming(PolarDataType.ppi, identifier)
        .map(PolarPpiData.fromJson);
  }

  /// Start temperature stream. Temperature stream is stopped if the connection is closed,
  /// error occurs or stream is disposed.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  ///   - settings: selected settings to start the stream
  /// - Returns: Observable stream
  ///   - onNext: for every air packet received. see `PolarTemperatureData`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Stream<PolarTemperatureData> startTemperatureStreaming(
    String identifier, {
    PolarSensorSetting? settings,
  }) {
    return _startStreaming(
      PolarDataType.temperature,
      identifier,
      settings: settings,
    ).map(PolarTemperatureData.fromJson);
  }

  /// Start pressure stream. Pressure stream is stopped if the connection is closed,
  /// error occurs or stream is disposed.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  ///   - settings: selected settings to start the stream
  /// - Returns: Observable stream
  ///   - onNext: for every air packet received. see `PolarPressureData`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Stream<PolarPressureData> startPressureStreaming(
    String identifier, {
    PolarSensorSetting? settings,
  }) {
    return _startStreaming(
      PolarDataType.pressure,
      identifier,
      settings: settings,
    ).map(PolarPressureData.fromJson);
  }

  /// Request start recording. Supported only by Polar H10. Requires `polarFileTransfer` feature.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or UUID
  ///   - exerciseId: unique identifier for for exercise entry length from 1-64 bytes
  ///   - interval: recording interval to be used. Has no effect if `sampleType` is `SampleType.rr`
  ///   - sampleType: sample type to be used.
  /// - Returns: Completable stream
  ///   - success: recording started
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<void> startRecording(
    String identifier, {
    required String exerciseId,
    required RecordingInterval interval,
    required SampleType sampleType,
  }) {
    return _channel.invokeMethod(
      'startRecording',
      [identifier, exerciseId, interval.toJson(), sampleType.toJson()],
    );
  }

  /// Request stop for current recording. Supported only by Polar H10. Requires `polarFileTransfer` feature.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or UUID
  /// - Returns: Completable stream
  ///   - success: recording stopped
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<void> stopRecording(String identifier) {
    return _channel.invokeMethod('stopRecording', identifier);
  }

  /// Request current recording status. Supported only by Polar H10. Requires `polarFileTransfer` feature.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id
  /// - Returns: Single stream
  ///   - success: see `PolarRecordingStatus`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<PolarRecordingStatus> requestRecordingStatus(String identifier) async {
    final result =
        await _channel.invokeListMethod('requestRecordingStatus', identifier);

    return PolarRecordingStatus(ongoing: result![0], entryId: result[1]);
  }

  /// Api for fetching stored exercises list from Polar H10 device. Requires `polarFileTransfer` feature. This API is working for Polar OH1 and Polar Verity Sense devices too, however in those devices recording of exercise requires that sensor is registered to Polar Flow account.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  /// - Returns: Observable stream
  ///   - onNext: see `PolarExerciseEntry`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<List<PolarExerciseEntry>> listExercises(String identifier) async {
    final result = await _channel.invokeListMethod('listExercises', identifier);
    if (result == null) {
      return [];
    }
    return result
        .cast<String>()
        .map((e) => PolarExerciseEntry.fromJson(jsonDecode(e)))
        .toList();
  }

  /// Api for fetching a single exercise from Polar H10 device. Requires `polarFileTransfer` feature. This API is working for Polar OH1 and Polar Verity Sense devices too, however in those devices recording of exercise requires that sensor is registered to Polar Flow account.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  ///   - entry: single exercise entry to be fetched
  /// - Returns: Single stream
  ///   - success: invoked after exercise data has been fetched from the device. see `PolarExerciseEntry`
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<PolarExerciseData> fetchExercise(
    String identifier,
    PolarExerciseEntry entry,
  ) async {
    final result = await _channel
        .invokeMethod('fetchExercise', [identifier, jsonEncode(entry)]);
    return PolarExerciseData.fromJson(jsonDecode(result));
  }

  /// Api for removing single exercise from Polar H10 device. Requires `polarFileTransfer` feature. This API is working for Polar OH1 and Polar Verity Sense devices too, however in those devices recording of exercise requires that sensor is registered to Polar Flow account.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or device address
  ///   - entry: single exercise entry to be removed
  /// - Returns: Completable stream
  ///   - complete: entry successfully removed
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<void> removeExercise(String identifier, PolarExerciseEntry entry) {
    return _channel
        .invokeMethod('removeExercise', [identifier, jsonEncode(entry)]);
  }

  /// Set [LedConfig] to enable or disable blinking LEDs (Verity Sense 2.2.1+).
  ///
  /// - Parameters:
  ///   - identifier: polar device id or UUID
  ///   - ledConfig: to enable or disable LEDs blinking
  /// - Returns: Completable stream
  ///   - success: when enable or disable sent to device
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<void> setLedConfig(String identifier, LedConfig config) {
    return _channel
        .invokeMethod('setLedConfig', [identifier, jsonEncode(config)]);
  }

  /// Perform factory reset to given device.
  ///
  /// - Parameters:
  ///   - identifier: polar device id or UUID
  ///   - preservePairingInformation: preserve pairing information during factory reset
  /// - Returns: Completable stream
  ///   - success: when factory reset notification sent to device
  ///   - onError: see `PolarErrors` for possible errors invoked
  Future<void> doFactoryReset(
    String identifier,
    bool preservePairingInformation,
  ) {
    return _channel.invokeMethod(
      'doFactoryReset',
      [identifier, preservePairingInformation],
    );
  }

  ///  Enables SDK mode.
  Future<void> enableSdkMode(String identifier) {
    return _channel.invokeMethod('enableSdkMode', identifier);
  }

  /// Disables SDK mode.
  Future<void> disableSdkMode(String identifier) {
    return _channel.invokeMethod('disableSdkMode', identifier);
  }

  /// Check if SDK mode currently enabled.
  ///
  /// Note, SDK status check is supported by VeritySense starting from firmware 2.1.0
  Future<bool> isSdkModeEnabled(String identifier) async {
    final result =
        await _channel.invokeMethod<bool>('isSdkModeEnabled', identifier);
    return result!;
  }

  /// Fetches the available offline recording data types for a given Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  /// - Returns: A list of available offline recording data types in JSON format.
  ///   - success: Returns a set of PolarDataType representing available data types.
  ///   - onError: Possible errors are returned as exceptions.
  Future<Set<PolarDataType>> getAvailableOfflineRecordingDataTypes(
    String identifier,
  ) async {
    final response = await _channel.invokeMethod(
      'getAvailableOfflineRecordingDataTypes',
      identifier,
    );

    if (response == null) return {};
    return (jsonDecode(response) as List).map(PolarDataType.fromJson).toSet();
  }

  /// Requests the offline recording settings for a specific data type.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - feature: The data type for which settings are requested.
  /// - Returns: Offline recording settings in JSON format.
  ///   - success: Returns a map of settings.
  ///   - onError: Possible errors are returned as exceptions.
  Future<PolarSensorSetting?> requestOfflineRecordingSettings(
    String identifier,
    PolarDataType feature,
  ) async {
    final response = await _channel.invokeMethod<String>(
      'requestOfflineRecordingSettings',
      [identifier, feature.toJson()],
    );

    return response != null
        ? PolarSensorSetting.fromJson(jsonDecode(response))
        : null;
  }

  /// Starts offline recording on a Polar device with the given settings.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - feature: The data type to be recorded.
  ///   - settings: Recording settings in JSON format.
  ///   - encryptionKey: Optional encryption key for the recording.
  /// - Returns: Void.
  ///   - success: Invoked when recording starts successfully.
  ///   - onError: Possible errors are returned as exceptions.
  Future<void> startOfflineRecording(
    String identifier,
    PolarDataType feature, {
    PolarSensorSetting? settings,
  }) async {
    await _channel.invokeMethod(
      'startOfflineRecording',
      [
        identifier,
        feature.toJson(),
        settings != null ? jsonEncode(settings) : null,
      ],
    );
  }

  /// Stops offline recording for a specific data type on a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - feature: The data type to stop recording.
  /// - Returns: Void.
  ///   - success: Invoked when recording stops successfully.
  ///   - onError: Possible errors are returned as exceptions.
  Future<void> stopOfflineRecording(
    String identifier,
    PolarDataType feature,
  ) async {
    await _channel.invokeMethod(
      'stopOfflineRecording',
      [identifier, feature.toJson()],
    );
  }

  /// Checks the status of offline recording for a specific data type.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - feature: The data type to check the status for.
  /// - Returns: Recording status.
  ///   - success: Returns the recording status.
  ///   - onError: Possible errors are returned as exceptions.
  Future<List<PolarDataType>> getOfflineRecordingStatus(
    String identifier,
  ) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'getOfflineRecordingStatus',
      [identifier],
    );

    if (result != null) {
      return result
          .map((e) => const PolarDataTypeConverter().fromJson(e))
          .toList();
    }

    throw Exception('Unexpected null result from getOfflineRecordingStatus');
  }

  /// Lists all offline recordings available on a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  /// - Returns: A list of recordings in JSON format.
  ///   - success: Returns a list of strings representing recording entries.
  ///   - onError: Possible errors are returned as exceptions.
  Future<List<PolarOfflineRecordingEntry>> listOfflineRecordings(
    String identifier,
  ) async {
    final result = await _channel.invokeListMethod(
      'listOfflineRecordings',
      identifier,
    );

    if (result == null) return [];

    return result
        .cast<String>()
        .map((e) => PolarOfflineRecordingEntry.fromJson(jsonDecode(e)))
        .toList();
  }

  /// Fetches a specific offline recording from a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - entry: The entry representing the offline recording to fetch.
  /// - Returns: Recording data in JSON format.
  ///   - success: Returns the fetched recording data.
  ///   - onError: Possible errors are returned as exceptions.
  Future<AccOfflineRecording?> getOfflineAccRecord(
    String identifier,
    PolarOfflineRecordingEntry entry,
  ) async {
    final result = await _channel.invokeMethod<String>(
      'getOfflineRecord',
      [identifier, jsonEncode(entry.toJson())],
    );

    if (result == null) return null;
    final data = jsonDecode(result);
    return AccOfflineRecording.fromJson(data);
  }

  /// Fetches a specific offline recording from a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - entry: The entry representing the offline recording to fetch.
  /// - Returns: Recording data in JSON format.
  ///   - success: Returns the fetched recording data.
  ///   - onError: Possible errors are returned as exceptions.
  Future<PpiOfflineRecording?> getOfflinePpiRecord(
    String identifier,
    PolarOfflineRecordingEntry entry,
  ) async {
    final result = await _channel.invokeMethod<String>(
      'getOfflineRecord',
      [identifier, jsonEncode(entry.toJson())],
    );
    if (result == null) return null;
    final data = jsonDecode(result);
    return PpiOfflineRecording.fromJson(data);
  }

  /// Fetches a specific offline recording from a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - entry: The entry representing the offline recording to fetch.
  /// - Returns: Recording data in JSON format.
  ///   - success: Returns the fetched recording data.
  ///   - onError: Possible errors are returned as exceptions.
  Future<PpgOfflineRecording?> getOfflinePpgRecord(
    String identifier,
    PolarOfflineRecordingEntry entry,
  ) async {
    final result = await _channel.invokeMethod<String>(
      'getOfflineRecord',
      [identifier, jsonEncode(entry.toJson())],
    );
    if (result == null) return null;
    final data = jsonDecode(result);
    return PpgOfflineRecording.fromJson(data);
  }

  /// Removes a specific offline recording from a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - entry: The entry representing the offline recording to remove.
  /// - Returns: Void.
  ///   - success: Invoked when the recording is removed successfully.
  ///   - onError: Possible errors are returned as exceptions.
  Future<void> removeOfflineRecord(
    String identifier,
    PolarOfflineRecordingEntry entry,
  ) async {
    await _channel.invokeMethod(
      'removeOfflineRecord',
      [identifier, jsonEncode(entry.toJson())],
    );
  }

  /// Fetches the available and used disk space on a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  /// - Returns: A list with two integers: available space and total space (in bytes).
  ///   - success: Returns a list containing the available and total space.
  ///   - onError: Possible errors are returned as exceptions.
  Future<List<int>> getDiskSpace(String identifier) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'getDiskSpace',
      identifier,
    );
    return result?.map((e) => e as int).toList() ?? [];
  }

  /// Fetches the local time from a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  /// - Returns: The local time of the Polar device as a DateTime object.
  ///   - success: Returns the local time.
  ///   - onError: Possible errors are returned as exceptions.
  Future<DateTime?> getLocalTime(String identifier) async {
    // Call the native method to get the local time from the Polar device
    final result =
        await _channel.invokeMethod<String>('getLocalTime', identifier);

    // If the result is null, return null
    if (result == null) return null;

    // Convert the string result to a DateTime object
    final time = DateTime.parse(result);

    return time;
  }

  /// Sets the local time on a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - time: The DateTime object representing the time to set on the device.
  /// - Returns: Void.
  ///   - success: Invoked when the time is set successfully.
  ///   - onError: Possible errors are returned as exceptions.
  Future<void> setLocalTime(String identifier, DateTime time) async {
    // Convert the DateTime object to a timestamp (in seconds)
    final timestamp = time.millisecondsSinceEpoch / 1000;

    // Call the native method to set the local time on the Polar device
    await _channel.invokeMethod('setLocalTime', [identifier, timestamp]);
  }

  /// Performs the First Time Use setup for a Polar 360 device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  ///   - config: Configuration data for the first-time use.
  /// - Returns: Future<void>.
  ///   - success: Completes when the configuration is sent to device.
  ///   - onError: Possible errors are returned as exceptions.
  Future<void> doFirstTimeUse(
    String identifier,
    PolarFirstTimeUseConfig config,
  ) async {
    await _channel.invokeMethod('doFirstTimeUse', {
      'identifier': identifier,
      'config': config.toMap(),
    });
  }

  /// Checks if First Time Use setup has been completed for a Polar device.
  ///
  /// - Parameters:
  ///   - identifier: Polar device id or address.
  /// - Returns: A boolean indicating if FTU is completed.
  ///   - success: Returns true if FTU is done, false otherwise.
  ///   - onError: Possible errors are returned as exceptions.
  Future<bool> isFtuDone(String identifier) async {
    // Call the native method to check FTU status
    final result = await _channel.invokeMethod<bool>('isFtuDone', identifier);

    // If the result is null, default to false for safety
    return result ?? false;
  }

  /// Get sleep data for a specific date range
  Future<List<PolarSleepData>> getSleep(
    String identifier,
    DateTime fromDate,
    DateTime toDate,
  ) async {
    final result = await _channel.invokeMethod('getSleep', [
      identifier,
      fromDate.toIso8601String().split('T')[0],
      toDate.toIso8601String().split('T')[0],
    ]);
    
    final List<dynamic> jsonList = json.decode(result);
    return jsonList.map((json) => PolarSleepData.fromJson(json)).toList();
  }
}
