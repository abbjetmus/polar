import CoreBluetooth
import Flutter
import PolarBleSdk
import UIKit

private let encoder = JSONEncoder()
private let decoder = JSONDecoder()

private func jsonEncode(_ value: Encodable) -> String? {
  guard let data = try? encoder.encode(value),
    let data = String(data: data, encoding: .utf8)
  else {
    return nil
  }

  return data
}

/// Invoke a FlutterResult / FlutterEventSink payload on the main thread.
/// The Polar BLE SDK 8.x delivers values on the cooperative thread pool,
/// while Flutter platform channel callbacks must run on the main thread.
private func onMain(_ block: @escaping () -> Void) {
  if Thread.isMainThread {
    block()
  } else {
    DispatchQueue.main.async(execute: block)
  }
}

public class SwiftPolarPlugin:
  NSObject,
  FlutterPlugin,
  FlutterStreamHandler,
  PolarBleApiObserver,
  PolarBleApiPowerStateObserver,
  PolarBleApiDeviceFeaturesObserver,
  PolarBleApiDeviceInfoObserver
{
  /// Binary messenger for dynamic EventChannel registration
  let messenger: FlutterBinaryMessenger

  /// Method channel
  let methodChannel: FlutterMethodChannel

  /// Event channel
  let eventChannel: FlutterEventChannel

  /// Search channel
  let searchChannel: FlutterEventChannel

  /// Streaming channels
  var streamingChannels = [String: StreamingChannel]()

  var api: PolarBleApi!
  var events: FlutterEventSink?

  init(
    messenger: FlutterBinaryMessenger,
    methodChannel: FlutterMethodChannel,
    eventChannel: FlutterEventChannel,
    searchChannel: FlutterEventChannel
  ) {
    self.messenger = messenger
    self.methodChannel = methodChannel
    self.eventChannel = eventChannel
    self.searchChannel = searchChannel
  }

  private func initApi() {
    guard api == nil else { return }
    api = PolarBleApiDefaultImpl.polarImplementation(
      DispatchQueue.main, features: Set(PolarBleSdkFeature.allCases))

    api.observer = self
    api.powerStateObserver = self
    api.deviceFeaturesObserver = self
    api.deviceInfoObserver = self
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "polar/methods", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(
      name: "polar/events", binaryMessenger: registrar.messenger())
    let searchChannel = FlutterEventChannel(
      name: "polar/search", binaryMessenger: registrar.messenger())

    let instance = SwiftPolarPlugin(
      messenger: registrar.messenger(),
      methodChannel: methodChannel,
      eventChannel: eventChannel,
      searchChannel: searchChannel
    )

    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
    searchChannel.setStreamHandler(instance.searchHandler)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    initApi()

    do {
      switch call.method {
      case "connectToDevice":
        try api.connectToDevice(call.arguments as! String)
        result(nil)
      case "disconnectFromDevice":
        try api.disconnectFromDevice(call.arguments as! String)
        result(nil)
      case "getAvailableOnlineStreamDataTypes":
        getAvailableOnlineStreamDataTypes(call, result)
      case "requestStreamSettings":
        requestStreamSettings(call, result)
      case "createStreamingChannel":
        createStreamingChannel(call, result)
      case "startRecording":
        startRecording(call, result)
      case "stopRecording":
        stopRecording(call, result)
      case "requestRecordingStatus":
        requestRecordingStatus(call, result)
      case "listExercises":
        listExercises(call, result)
      case "fetchExercise":
        fetchExercise(call, result)
      case "removeExercise":
        removeExercise(call, result)
      case "setLedConfig":
        setLedConfig(call, result)
      case "doFactoryReset":
        doFactoryReset(call, result)
      case "doRestart":
        doRestart(call, result)
      case "enableSdkMode":
        enableSdkMode(call, result)
      case "disableSdkMode":
        disableSdkMode(call, result)
      case "setAutomaticOHRMeasurementEnabled":
        setAutomaticOHRMeasurementEnabled(call, result)
      case "isSdkModeEnabled":
        isSdkModeEnabled(call, result)
      case "getAvailableOfflineRecordingDataTypes":
        getAvailableOfflineRecordingDataTypes(call, result)
      case "requestOfflineRecordingSettings":
        requestOfflineRecordingSettings(call, result)
      case "startOfflineRecording":
        startOfflineRecording(call, result)
      case "stopOfflineRecording":
        stopOfflineRecording(call, result)
      case "getOfflineRecordingStatus":
        getOfflineRecordingStatus(call, result)
      case "setOfflineRecordingTrigger":
        setOfflineRecordingTrigger(call, result)
      case "listOfflineRecordings":
        listOfflineRecordings(call, result)
      case "getOfflineRecord":
        getOfflineRecord(call, result)
      case "removeOfflineRecord":
        removeOfflineRecord(call, result)
      case "getChargerState":
        getChargerState(call, result)
      case "getDiskSpace":
        getDiskSpace(call, result)
      case "getLocalTime":
        getLocalTime(call, result)
      case "setLocalTime":
        setLocalTime(call, result)
      case "doFirstTimeUse":
        doFirstTimeUse(call, result)
      case "isFtuDone":
        isFtuDone(call, result)
      case "deleteStoredDeviceData":
        deleteStoredDeviceData(call, result)
      case "deleteDeviceDateFolders":
        deleteDeviceDateFolders(call, result)
      case "getSteps":
        getSteps(call, result)
      case "getSleep":
        getSleep(call, result)
      case "getSleepRecordingState":
        getSleepRecordingState(call, result)
      case "stopSleepRecording":
        stopSleepRecording(call, result)
      case "getDistance":
        getDistance(call, result)
      case "getActiveTime":
        getActiveTime(call, result)
      case "getActivitySampleData":
        getActivitySampleData(call, result)
      case "sendInitializationAndStartSyncNotifications":
        sendInitializationAndStartSyncNotifications(call, result)
      case "sendTerminateAndStopSyncNotifications":
        sendTerminateAndStopSyncNotifications(call, result)
      case "checkFirmwareUpdate":
        checkFirmwareUpdate(call, result)
      case "updateFirmware":
        updateFirmware(call, result)
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      result(
        FlutterError(
          code: "Error in Polar plugin", message: error.localizedDescription, details: nil))
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    initApi()
    self.events = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    return nil
  }

  var searchTask: Task<Void, Never>?
  lazy var searchHandler = StreamHandler(
    onListen: { _, events in
      self.initApi()

      self.searchTask = Task {
        do {
          for try await data in self.api.searchForDevice() {
            guard let data = jsonEncode(PolarDeviceInfoCodable(data))
            else { continue }
            onMain {
              events(data)
            }
          }
          if !Task.isCancelled {
            onMain {
              events(FlutterEndOfEventStream)
            }
          }
        } catch {
          if !Task.isCancelled {
            onMain {
              events(
                FlutterError(
                  code: "Error in searchForDevice", message: error.localizedDescription,
                  details: nil)
              )
            }
          }
        }
      }
      return nil
    },
    onCancel: { _ in
      self.searchTask?.cancel()
      self.searchTask = nil
      return nil
    })

  private func createStreamingChannel(_ call: FlutterMethodCall, _ result: @escaping FlutterResult)
  {
    let arguments = call.arguments as! [Any]
    let name = arguments[0] as! String
    let identifier = arguments[1] as! String
    let feature = PolarDeviceDataType.allCases[arguments[2] as! Int]

    if streamingChannels[name] == nil {
      streamingChannels[name] = StreamingChannel(messenger, name, api, identifier, feature)
    }

    result(nil)
  }

  func getAvailableOnlineStreamDataTypes(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    let identifier = call.arguments as! String

    Task {
      do {
        let dataTypes = try await api.getAvailableOnlineStreamDataTypes(identifier)
        guard
          let data = jsonEncode(dataTypes.map { PolarDeviceDataType.allCases.firstIndex(of: $0)! })
        else {
          onMain {
            result(
              FlutterError(
                code: "Unable to get available online stream data types", message: nil, details: nil
              ))
          }
          return
        }
        onMain {
          result(data)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Unable to get available online stream data types",
              message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func requestStreamSettings(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let feature = PolarDeviceDataType.allCases[arguments[1] as! Int]

    Task {
      do {
        let settings = try await api.requestStreamSettings(identifier, feature: feature)
        guard let data = jsonEncode(PolarSensorSettingCodable(settings))
        else { return }
        onMain {
          result(data)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Unable to request stream settings", message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func startRecording(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let exerciseId = arguments[1] as! String
    let interval = RecordingInterval(rawValue: arguments[2] as! Int)!
    let sampleType = SampleType(rawValue: arguments[3] as! Int)!

    Task {
      do {
        try await api.startRecording(
          identifier,
          exerciseId: exerciseId,
          interval: interval,
          sampleType: sampleType
        )
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error starting recording", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func stopRecording(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        try await api.stopRecording(identifier)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error stopping recording", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func requestRecordingStatus(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        let data = try await api.requestRecordingStatus(identifier)
        onMain {
          result([data.ongoing, data.entryId])
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error stopping recording", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func listExercises(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        var exercises = [String]()
        for try await data in api.fetchStoredExerciseList(identifier) {
          guard let data = jsonEncode(PolarExerciseEntryCodable(data))
          else {
            continue
          }
          exercises.append(data)
        }
        onMain {
          result(exercises)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error listing exercises", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func fetchExercise(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let entry = try! decoder.decode(
      PolarExerciseEntryCodable.self,
      from: (arguments[1] as! String)
        .data(using: .utf8)!
    ).data

    Task {
      do {
        let data = try await api.fetchExercise(identifier, entry: entry)
        guard let data = jsonEncode(PolarExerciseDataCodable(data))
        else {
          return
        }
        onMain {
          result(data)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error  fetching exercise", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func removeExercise(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let entry = try! decoder.decode(
      PolarExerciseEntryCodable.self,
      from: (arguments[1] as! String)
        .data(using: .utf8)!
    ).data

    Task {
      do {
        try await api.removeExercise(identifier, entry: entry)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error removing exercise", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func setLedConfig(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let config = try! decoder.decode(
      LedConfigCodable.self,
      from: (arguments[1] as! String)
        .data(using: .utf8)!
    ).data

    Task {
      do {
        try await api.setLedConfig(identifier, ledConfig: config)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error setting led config", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func doFactoryReset(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        try await api.doFactoryReset(identifier)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error doing factory reset", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func doRestart(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        try await api.doRestart(identifier, preservePairingInformation: false)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error doing restart", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func enableSdkMode(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        try await api.enableSDKMode(identifier)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error enabling SDK mode", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func disableSdkMode(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        try await api.disableSDKMode(identifier)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error disabling SDK mode", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func setAutomaticOHRMeasurementEnabled(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    let args = call.arguments as! [Any]
    let identifier = args[0] as! String
    let enabled = args[1] as! Bool

    Task {
      do {
        try await api.setAutomaticOHRMeasurementEnabled(identifier, enabled: enabled)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error setting automatic OHR measurement", message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func isSdkModeEnabled(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        let isEnabled = try await api.isSDKModeEnabled(identifier)
        onMain {
          result(isEnabled)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error checking SDK mode status", message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  private func success(_ event: String, data: Any? = nil) {
    DispatchQueue.main.async {
      self.events?(["event": event, "data": data])
    }
  }

  public func deviceConnecting(_ polarDeviceInfo: PolarDeviceInfo) {
    guard let data = jsonEncode(PolarDeviceInfoCodable(polarDeviceInfo))
    else {
      return
    }
    success("deviceConnecting", data: data)
  }

  public func deviceConnected(_ polarDeviceInfo: PolarDeviceInfo) {
    guard let data = jsonEncode(PolarDeviceInfoCodable(polarDeviceInfo))
    else {
      return
    }
    success("deviceConnected", data: data)
  }

  public func deviceDisconnected(_ polarDeviceInfo: PolarDeviceInfo, pairingError: Bool) {
    guard let data = jsonEncode(PolarDeviceInfoCodable(polarDeviceInfo))
    else {
      return
    }
    success("deviceDisconnected", data: [data, pairingError])
  }

  public func batteryLevelReceived(_ identifier: String, batteryLevel: UInt) {
    success("batteryLevelReceived", data: [identifier, batteryLevel])
  }

  public func batteryChargingStatusReceived(
    _ identifier: String, chargingStatus: BleBasClient.ChargeState
  ) {
    success(
      "batteryChargingStatusReceived", data: [identifier, String(describing: chargingStatus)])
  }

  public func blePowerOn() {
    success("blePowerStateChanged", data: true)
  }

  public func blePowerOff() {
    success("blePowerStateChanged", data: true)
  }

  public func bleSdkFeatureReady(_ identifier: String, feature: PolarBleSdkFeature) {
    success(
      "sdkFeatureReady",
      data: [
        identifier,
        PolarBleSdkFeature.allCases.firstIndex(of: feature)!,
      ])
  }

  public func bleSdkFeaturesReadiness(
    _ identifier: String, ready: [PolarBleSdkFeature], unavailable: [PolarBleSdkFeature]
  ) {
    success(
      "sdkFeaturesReadiness",
      data: [
        identifier,
        ready.map { PolarBleSdkFeature.allCases.firstIndex(of: $0)! },
        unavailable.map { PolarBleSdkFeature.allCases.firstIndex(of: $0)! },
      ])
  }

  public func disInformationReceived(_ identifier: String, uuid: CBUUID, value: String) {
    success(
      "disInformationReceived", data: [identifier, uuid.uuidString, value])
  }

  public func disInformationReceivedWithKeysAsStrings(
    _ identifier: String, key: String, value: String
  ) {
    success("disInformationReceived", data: [identifier, key, value])
  }

  // MARK: Deprecated functions

  public func streamingFeaturesReady(
    _ identifier: String, streamingFeatures: Set<PolarBleSdk.PolarDeviceDataType>
  ) {
    // Do nothing
  }

  public func hrFeatureReady(_ identifier: String) {
    // Do nothing
  }

  public func ftpFeatureReady(_ identifier: String) {
    // Do nothing
  }

  func getAvailableOfflineRecordingDataTypes(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    guard let identifier = call.arguments as? String else {
      result(
        FlutterError(code: "INVALID_ARGUMENT", message: "Identifier is not a string", details: nil))
      return
    }

    // Use the api to get available offline recording data types
    Task {
      do {
        let dataTypes = try await api.getAvailableOfflineRecordingDataTypes(identifier)
        // Map data types to their respective indices
        let dataTypesIds = dataTypes.compactMap { PolarDeviceDataType.allCases.firstIndex(of: $0) }
        // Safely convert indices to description strings and return
        let dataTypesDescriptions = dataTypesIds.map { "\($0)" }
        onMain {
          result(dataTypesDescriptions)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "ERROR_GETTING_DATA_TYPES",
              message: error.localizedDescription,
              details: nil
            ))
        }
      }
    }
  }

  func requestOfflineRecordingSettings(_ call: FlutterMethodCall, _ result: @escaping FlutterResult)
  {
    guard let arguments = call.arguments as? [Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENT", message: "Arguments are not in expected format", details: nil))
      return
    }
    guard let identifier = arguments[0] as? String else {
      result(
        FlutterError(
          code: "INVALID_IDENTIFIER", message: "Identifier is not a string", details: nil))
      return
    }
    guard let index = arguments[1] as? Int, index < PolarDeviceDataType.allCases.count else {
      result(
        FlutterError(
          code: "INVALID_FEATURE", message: "Feature index is out of bounds", details: nil))
      return
    }
    let feature = PolarDeviceDataType.allCases[index]

    Task {
      do {
        let settings = try await api.requestOfflineRecordingSettings(identifier, feature: feature)
        if let encodedData = jsonEncode(PolarSensorSettingCodable(settings)) {
          onMain {
            result(encodedData)
          }
        } else {
          onMain {
            result(
              FlutterError(
                code: "ENCODING_ERROR", message: "Failed to encode offline recording settings",
                details: nil))
          }
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "REQUEST_ERROR",
              message: "Error requesting offline recording settings: \(error.localizedDescription)",
              details: nil))
        }
      }
    }
  }

  func startOfflineRecording(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let feature = PolarDeviceDataType.allCases[arguments[1] as! Int]
    // Attempt to decode the sensor settings
    let settingsData = arguments[2] as? String
    let settings =
      settingsData != nil
      ? try? decoder.decode(
        PolarSensorSettingCodable.self,
        from: settingsData!.data(using: .utf8)!
      ).data : nil

    Task {
      do {
        try await api.startOfflineRecording(
          identifier, feature: feature, settings: settings, secret: nil)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error starting offline recording", message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func stopOfflineRecording(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let feature = PolarDeviceDataType.allCases[arguments[1] as! Int]

    Task {
      do {
        try await api.stopOfflineRecording(identifier, feature: feature)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error stopping offline recording",
              message: error.localizedDescription.description, details: nil))
        }
      }
    }
  }

  func getOfflineRecordingStatus(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String

    Task {
      do {
        let statusDict = try await api.getOfflineRecordingStatus(identifier)
        // Filter and map keys where the value is true
        let keysWithTrueValues = statusDict.compactMap { key, value -> Int? in
          value ? PolarDeviceDataType.allCases.firstIndex(of: key) : nil
        }
        onMain {
          result(keysWithTrueValues)  // Return only the filtered list of keys
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error getting offline recording status", message: error.localizedDescription,
              details: nil)
          )
        }
      }
    }
  }

  func setOfflineRecordingTrigger(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let modeIndex = arguments[1] as! Int
    let featuresList = arguments[2] as! [[Any?]]

    let triggerModes: [PolarOfflineRecordingTriggerMode] = [
      .triggerDisabled,
      .triggerSystemStart,
      .triggerExerciseStart,
    ]
    let mode = triggerModes[modeIndex]

    var triggerFeatures: [PolarDeviceDataType: PolarSensorSetting?] = [:]
    for entry in featuresList {
      let featureIndex = entry[0] as! Int
      let feature = PolarDeviceDataType.allCases[featureIndex]
      let settingsJson = entry[1] as? String
      let settings: PolarSensorSetting? =
        settingsJson != nil
        ? try? decoder.decode(
          PolarSensorSettingCodable.self,
          from: settingsJson!.data(using: .utf8)!
        ).data : nil
      triggerFeatures[feature] = settings
    }

    let trigger = PolarOfflineRecordingTrigger(
      triggerMode: mode, triggerFeatures: triggerFeatures)

    Task {
      do {
        try await api.setOfflineRecordingTrigger(identifier, trigger: trigger, secret: nil)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error setting offline recording trigger",
              message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func listOfflineRecordings(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let identifier = call.arguments as? String else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS", message: "Expected a string identifier as argument",
          details: nil))
      return
    }

    Task {
      do {
        var entries: [PolarOfflineRecordingEntry] = []
        for try await entry in api.listOfflineRecordings(identifier) {
          entries.append(entry)
        }

        var jsonStringList: [String] = []

        do {
          let encoder = JSONEncoder()
          encoder.dateEncodingStrategy = .iso8601
          for entry in entries {
            // Use PolarOfflineRecordingEntryCodable for encoding
            let entryCodable = PolarOfflineRecordingEntryCodable(entry)
            let data = try encoder.encode(entryCodable)
            if let jsonString = String(data: data, encoding: .utf8) {
              jsonStringList.append(jsonString)
            }
          }
          onMain {
            result(jsonStringList)  // Return the array of JSON strings
          }
        } catch {
          onMain {
            result(
              FlutterError(
                code: "ENCODE_ERROR", message: "Failed to encode entries to JSON", details: nil))
          }
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "ERROR",
              message: "Offline recording listing error: \(error.localizedDescription)",
              details: nil))
        }
      }
    }
  }

  func getOfflineRecord(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let entryJsonString = arguments[1] as! String

    guard let entryData = entryJsonString.data(using: .utf8) else {
      result(
        FlutterError(code: "INVALID_ARGUMENT", message: "Invalid entry JSON string", details: nil))
      return
    }

    do {
      let entry = try JSONDecoder().decode(PolarOfflineRecordingEntryCodable.self, from: entryData)
        .data

      Task {
        do {
          let recordingData = try await api.getOfflineRecord(identifier, entry: entry, secret: nil)
          do {
            // Use the PolarOfflineRecordingDataCodable to encode the data to JSON
            let dataCodable = PolarOfflineRecordingDataCodable(recordingData)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(dataCodable)
            if let jsonString = String(data: data, encoding: .utf8) {
              onMain {
                result(jsonString)
              }
            } else {
              onMain {
                result(
                  FlutterError(
                    code: "ENCODE_ERROR", message: "Failed to encode recording data to JSON string",
                    details: nil))
              }
            }
          } catch {
            onMain {
              result(
                FlutterError(
                  code: "ENCODE_ERROR", message: "Failed to encode recording data to JSON",
                  details: nil))
            }
          }
        } catch {
          onMain {
            result(
              FlutterError(
                code: "FETCH_ERROR",
                message: "Failed to fetch recording: \(error.localizedDescription)", details: nil))
          }
        }
      }
    } catch {
      result(
        FlutterError(code: "DECODE_ERROR", message: "Failed to decode entry JSON", details: nil))
    }
  }

  func removeOfflineRecord(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let arguments = call.arguments as! [Any]
    let identifier = arguments[0] as! String
    let entryJsonString = arguments[1] as! String

    guard let entryData = entryJsonString.data(using: .utf8) else {
      result(
        FlutterError(code: "INVALID_ARGUMENT", message: "Invalid entry JSON string", details: nil))
      return
    }

    let entry = try! JSONDecoder().decode(PolarOfflineRecordingEntryCodable.self, from: entryData)
      .data

    Task {
      do {
        try await api.removeOfflineRecord(identifier, entry: entry)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error removing exercise", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func getChargerState(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String
    do {
      let chargeState = try api.getChargerState(identifier: identifier)
      // Return as string matching the Swift enum case names
      let stateString: String
      switch chargeState {
      case .charging: stateString = "charging"
      case .dischargingActive: stateString = "dischargingActive"
      case .dischargingInactive: stateString = "dischargingInactive"
      default: stateString = "unknown"
      }
      result(stateString)
    } catch {
      result(
        FlutterError(
          code: "GET_CHARGER_STATE_ERROR",
          message: error.localizedDescription,
          details: nil))
    }
  }

  func getDiskSpace(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        let diskSpaceData = try await api.getDiskSpace(identifier)
        let freeSpace = diskSpaceData.freeSpace  // Corrected from 'availableSpace'
        let totalSpace = diskSpaceData.totalSpace
        onMain {
          result([freeSpace, totalSpace])  // Return as a list
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error getting disk space", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func getLocalTime(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let identifier = call.arguments as? String else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS", message: "Expected a device identifier as a String",
          details: nil))
      return
    }

    Task {
      do {
        let time = try await api.getLocalTime(identifier)
        let dateFormatter = ISO8601DateFormatter()
        let timeString = dateFormatter.string(from: time)

        onMain {
          result(timeString)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "GET_LOCAL_TIME_ERROR",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  func setLocalTime(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [Any],
      args.count == 2,
      let identifier = args[0] as? String,
      let timestamp = args[1] as? Double
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS", message: "Expected [identifier, timestamp] as arguments",
          details: nil))
      return
    }

    let time = Date(timeIntervalSince1970: timestamp)

    let timeZone = TimeZone.current

    Task {
      do {
        try await api.setLocalTime(identifier, time: time, zone: timeZone)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "SET_LOCAL_TIME_ERROR",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  func doFirstTimeUse(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let identifier = args["identifier"] as? String,
      let configDict = args["config"] as? [String: Any]
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Expected identifier and config dictionary",
          details: nil))
      return
    }

    // Convert the dictionary to PolarFirstTimeUseConfig
    guard let gender = configDict["gender"] as? String,
      let birthDateString = configDict["birthDate"] as? String,
      let height = configDict["height"] as? Int,
      let weight = configDict["weight"] as? Int,
      let maxHeartRate = configDict["maxHeartRate"] as? Int,
      let vo2Max = configDict["vo2Max"] as? Int,
      let restingHeartRate = configDict["restingHeartRate"] as? Int,
      let trainingBackground = configDict["trainingBackground"] as? Int,
      let deviceTime = configDict["deviceTime"] as? String,
      let typicalDay = configDict["typicalDay"] as? Int,
      let sleepGoalMinutes = configDict["sleepGoalMinutes"] as? Int
    else {
      result(
        FlutterError(
          code: "INVALID_CONFIG",
          message: "Invalid configuration parameters",
          details: nil))
      return
    }

    // Convert string date to Date object
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    guard let birthDate = dateFormatter.date(from: birthDateString) else {
      result(
        FlutterError(
          code: "INVALID_DATE",
          message: "Invalid birth date format",
          details: nil))
      return
    }

    // Convert training background value to appropriate enum case
    let trainingBackgroundLevel: PolarFirstTimeUseConfig.TrainingBackground
    switch trainingBackground {
    case 10: trainingBackgroundLevel = .occasional
    case 20: trainingBackgroundLevel = .regular
    case 30: trainingBackgroundLevel = .frequent
    case 40: trainingBackgroundLevel = .heavy
    case 50: trainingBackgroundLevel = .semiPro
    case 60: trainingBackgroundLevel = .pro
    default: trainingBackgroundLevel = .occasional  // default fallback
    }

    // Convert typical day to enum
    let typicalDayEnum: PolarFirstTimeUseConfig.TypicalDay
    switch typicalDay {
    case 1: typicalDayEnum = .mostlyMoving
    case 2: typicalDayEnum = .mostlySitting
    case 3: typicalDayEnum = .mostlyStanding
    default: typicalDayEnum = .mostlySitting
    }

    // Create config object with validation
    let config = PolarBleSdk.PolarFirstTimeUseConfig(
      gender: gender == "Male" ? .male : .female,
      birthDate: birthDate,
      height: Float(height),
      weight: Float(weight),
      maxHeartRate: maxHeartRate,
      vo2Max: vo2Max,
      restingHeartRate: restingHeartRate,
      trainingBackground: trainingBackgroundLevel,
      deviceTime: deviceTime,
      typicalDay: typicalDayEnum,
      sleepGoalMinutes: sleepGoalMinutes
    )

    Task {
      do {
        // 8.x API: doFirstTimeUse is a plain async throws call (no stream to iterate)
        try await api.doFirstTimeUse(identifier, ftuConfig: config)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "FTU_ERROR",
              message: error.localizedDescription,
              details: nil
            ))
        }
      }
    }
  }

  func isFtuDone(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let identifier = call.arguments as? String else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Expected a device identifier as a String",
          details: nil
        ))
      return
    }

    Task {
      do {
        let isFtuDone = try await api.isFtuDone(identifier)
        onMain {
          result(isFtuDone)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "FTU_CHECK_ERROR",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  func deleteStoredDeviceData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [Any],
      arguments.count == 3,
      let identifier = arguments[0] as? String,
      let dataTypeIndex = arguments[1] as? Int,
      let untilDateString = arguments[2] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Expected [identifier, dataType, untilDate]",
          details: nil))
      return
    }

    // Convert dataType index to PolarStoredDataType
    guard dataTypeIndex < PolarBleSdk.PolarStoredDataType.StoredDataType.allCases.count else {
      result(
        FlutterError(
          code: "INVALID_DATA_TYPE",
          message: "Invalid data type index",
          details: nil))
      return
    }
    let dataType = PolarBleSdk.PolarStoredDataType.StoredDataType.allCases[dataTypeIndex]

    // Parse the until date
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    guard let untilDate = dateFormatter.date(from: untilDateString) else {
      result(
        FlutterError(
          code: "INVALID_DATE_FORMAT",
          message: "Date must be in yyyy-MM-dd format",
          details: nil))
      return
    }

    Task {
      do {
        try await api.deleteStoredDeviceData(identifier, dataType: dataType, until: untilDate)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "ERROR_DELETING_DATA",
              message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func deleteDeviceDateFolders(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [Any],
      arguments.count == 3,
      let identifier = arguments[0] as? String,
      let fromDateString = arguments[1] as? String,
      let toDateString = arguments[2] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Expected [identifier, fromDate, toDate]",
          details: nil))
      return
    }

    // Parse the dates
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    guard let fromDate = dateFormatter.date(from: fromDateString),
      let toDate = dateFormatter.date(from: toDateString)
    else {
      result(
        FlutterError(
          code: "INVALID_DATE_FORMAT",
          message: "Dates must be in yyyy-MM-dd format",
          details: nil))
      return
    }

    Task {
      do {
        try await api.deleteDeviceDateFolders(identifier, fromDate: fromDate, toDate: toDate)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "ERROR_DELETING_FOLDERS",
              message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func getSteps(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [Any],
      arguments.count == 3,
      let identifier = arguments[0] as? String,
      let fromDateString = arguments[1] as? String,
      let toDateString = arguments[2] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Expected [identifier, fromDate, toDate]",
          details: nil))
      return
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    guard let fromDate = dateFormatter.date(from: fromDateString),
      let toDate = dateFormatter.date(from: toDateString)
    else {
      result(
        FlutterError(
          code: "INVALID_DATE_FORMAT",
          message: "Dates must be in yyyy-MM-dd format",
          details: nil))
      return
    }

    Task {
      do {
        let stepsData = try await api.getSteps(
          identifier: identifier, fromDate: fromDate, toDate: toDate)
        do {
          let encoder = JSONEncoder()
          encoder.dateEncodingStrategy = .iso8601
          let jsonData = try encoder.encode(stepsData)
          if let jsonString = String(data: jsonData, encoding: .utf8) {
            onMain {
              result(jsonString)
            }
          } else {
            onMain {
              result(
                FlutterError(
                  code: "ENCODING_ERROR",
                  message: "Failed to convert JSON data to string",
                  details: nil))
            }
          }
        } catch {
          onMain {
            result(
              FlutterError(
                code: "ENCODING_ERROR",
                message: "Failed to encode steps data: \(error.localizedDescription)",
                details: nil))
          }
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "ERROR_GETTING_STEPS",
              message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func getSleepRecordingState(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        let state = try await api.getSleepRecordingState(identifier: identifier)
        onMain {
          result(state)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error getting sleep recording state",
              message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func stopSleepRecording(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier = call.arguments as! String

    Task {
      do {
        try await api.stopSleepRecording(identifier: identifier)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "Error stopping sleep recording",
              message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func getSleep(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [Any],
      arguments.count == 3,
      let identifier = arguments[0] as? String,
      let fromDateString = arguments[1] as? String,
      let toDateString = arguments[2] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Expected [identifier, fromDate, toDate]",
          details: nil))
      return
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    guard let fromDate = dateFormatter.date(from: fromDateString),
      let toDate = dateFormatter.date(from: toDateString)
    else {
      result(
        FlutterError(
          code: "INVALID_DATE_FORMAT",
          message: "Dates must be in yyyy-MM-dd format",
          details: nil))
      return
    }

    Task {
      do {
        let sleepData = try await api.getSleep(
          identifier: identifier, fromDate: fromDate, toDate: toDate)

        let isoFormatter = ISO8601DateFormatter()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"

        // The device returns one entry per day in the requested range, most
        // with no actual sleep (nil start/end). Keep only entries with a real
        // sleep period so the payload carries real sleep only.
        let mapped: [[String: Any]] = sleepData.compactMap { analysis in
          guard let start = analysis.sleepStartTime,
            let end = analysis.sleepEndTime
          else {
            return nil
          }
          // Prefer the device-provided result date; fall back to the wake date.
          let dateString: String
          if let comps = analysis.sleepResultDate,
            let resultDate = Calendar.current.date(from: comps)
          {
            dateString = dayFormatter.string(from: resultDate)
          } else {
            dateString = dayFormatter.string(from: end)
          }
          let phases: [[String: Any]] = (analysis.sleepWakePhases ?? []).map { phase in
            [
              "offsetSeconds": Int(phase.secondsFromSleepStart),
              "state": phase.state.rawValue,
            ]
          }
          let cycles: [[String: Any]] = (analysis.sleepCycles ?? []).map { cycle in
            [
              "offsetSeconds": Int(cycle.secondsFromSleepStart),
              "sleepDepthStart": cycle.sleepDepthStart,
            ]
          }
          var entry: [String: Any] = [
            "date": dateString,
            "sleepStartTime": isoFormatter.string(from: start),
            "sleepEndTime": isoFormatter.string(from: end),
            "sleepWakePhases": phases,
            "sleepCycles": cycles,
          ]
          if let goal = analysis.sleepGoalMinutes {
            entry["sleepGoalMinutes"] = Int(goal)
          }
          if let rating = analysis.userSleepRating {
            entry["userSleepRating"] = rating.rawValue
          }
          return entry
        }

        do {
          let jsonData = try JSONSerialization.data(withJSONObject: mapped, options: [])
          if let jsonString = String(data: jsonData, encoding: .utf8) {
            onMain {
              result(jsonString)
            }
          } else {
            onMain {
              result(
                FlutterError(
                  code: "ENCODING_ERROR",
                  message: "Failed to convert JSON data to string",
                  details: nil))
            }
          }
        } catch {
          onMain {
            result(
              FlutterError(
                code: "ENCODING_ERROR",
                message: "Failed to encode sleep data: \(error.localizedDescription)",
                details: nil))
          }
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "ERROR_GETTING_SLEEP",
              message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func getDistance(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [Any],
      arguments.count == 3,
      let identifier = arguments[0] as? String,
      let fromDateString = arguments[1] as? String,
      let toDateString = arguments[2] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Expected [identifier, fromDate, toDate]",
          details: nil))
      return
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    guard let fromDate = dateFormatter.date(from: fromDateString),
      let toDate = dateFormatter.date(from: toDateString)
    else {
      result(
        FlutterError(
          code: "INVALID_DATE_FORMAT",
          message: "Dates must be in yyyy-MM-dd format",
          details: nil))
      return
    }

    Task {
      do {
        let distanceData = try await api.getDistance(
          identifier: identifier, fromDate: fromDate, toDate: toDate)
        do {
          let encoder = JSONEncoder()
          encoder.dateEncodingStrategy = .iso8601
          let codables = distanceData.map(PolarDistanceDataCodable.init)
          let jsonData = try encoder.encode(codables)
          if let jsonString = String(data: jsonData, encoding: .utf8) {
            onMain {
              result(jsonString)
            }
          } else {
            onMain {
              result(
                FlutterError(
                  code: "ENCODING_ERROR",
                  message: "Failed to convert JSON data to string",
                  details: nil))
            }
          }
        } catch {
          onMain {
            result(
              FlutterError(
                code: "ENCODING_ERROR",
                message: "Failed to encode distance data: \(error.localizedDescription)",
                details: nil))
          }
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "ERROR_GETTING_DISTANCE",
              message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func getActiveTime(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [Any],
      arguments.count == 3,
      let identifier = arguments[0] as? String,
      let fromDateString = arguments[1] as? String,
      let toDateString = arguments[2] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Expected [identifier, fromDate, toDate]",
          details: nil))
      return
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    guard let fromDate = dateFormatter.date(from: fromDateString),
      let toDate = dateFormatter.date(from: toDateString)
    else {
      result(
        FlutterError(
          code: "INVALID_DATE_FORMAT",
          message: "Dates must be in yyyy-MM-dd format",
          details: nil))
      return
    }

    Task {
      do {
        let activeTimeData = try await api.getActiveTime(
          identifier: identifier, fromDate: fromDate, toDate: toDate)
        do {
          let encoder = JSONEncoder()
          encoder.dateEncodingStrategy = .iso8601
          let codables = activeTimeData.map(PolarActiveTimeDataCodable.init)
          let jsonData = try encoder.encode(codables)
          if let jsonString = String(data: jsonData, encoding: .utf8) {
            onMain {
              result(jsonString)
            }
          } else {
            onMain {
              result(
                FlutterError(
                  code: "ENCODING_ERROR",
                  message: "Failed to convert JSON data to string",
                  details: nil))
            }
          }
        } catch {
          onMain {
            result(
              FlutterError(
                code: "ENCODING_ERROR",
                message: "Failed to encode active time data: \(error.localizedDescription)",
                details: nil))
          }
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "ERROR_GETTING_ACTIVE_TIME",
              message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func getActivitySampleData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [Any],
      arguments.count == 3,
      let identifier = arguments[0] as? String,
      let fromDateString = arguments[1] as? String,
      let toDateString = arguments[2] as? String
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Expected [identifier, fromDate, toDate]",
          details: nil))
      return
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"

    guard let fromDate = dateFormatter.date(from: fromDateString),
      let toDate = dateFormatter.date(from: toDateString)
    else {
      result(
        FlutterError(
          code: "INVALID_DATE_FORMAT",
          message: "Dates must be in yyyy-MM-dd format",
          details: nil))
      return
    }

    Task {
      do {
        let activityDayDataList = try await api.getActivitySampleData(
          identifier: identifier, fromDate: fromDate, toDate: toDate)
        do {
          // Convert the data directly from the native structures
          let response = activityDayDataList.map { dayData -> [String: Any] in
            let samplesDataList = dayData.polarActivityDataList.compactMap {
              activityData -> [String: Any]? in
              // Access the samples directly from the activityData
              guard let samples = activityData.samples else { return nil }

              // Convert startTime to ISO8601 string
              let formatter = ISO8601DateFormatter()
              let startTimeString = formatter.string(from: samples.startTime)

              // Convert activityInfoList
              let activityInfoList = samples.activityInfoList.map { activityInfo in
                [
                  "timeStamp": formatter.string(from: activityInfo.timeStamp),
                  "activityClass": activityInfo.activityClass.rawValue,
                  "factor": activityInfo.factor,
                ]
              }

              return [
                "startTime": startTimeString,
                "metRecordingInterval": samples.metRecordingInterval,
                "metSamples": samples.metSamples ?? [],
                "stepRecordingInterval": samples.stepRecordingInterval,
                "stepSamples": samples.stepSamples ?? [],
                "activityInfoList": activityInfoList,
              ]
            }

            // Extract date from first sample's startTime (sensor-local calendar date)
            let dateString: String
            if let firstSample = samplesDataList.first,
              let startTime = firstSample["startTime"] as? String,
              !startTime.isEmpty
            {
              // Extract date part from ISO8601 string (YYYY-MM-DD)
              if let dateRange = startTime.range(of: "T") {
                dateString = String(startTime[..<dateRange.lowerBound])
              } else {
                dateString = startTime
              }
            } else {
              dateString = ""
            }

            return [
              "date": dateString,
              "samplesDataList": samplesDataList,
            ]
          }

          let jsonData = try JSONSerialization.data(withJSONObject: response, options: [])
          if let jsonString = String(data: jsonData, encoding: .utf8) {
            onMain {
              result(jsonString)
            }
          } else {
            onMain {
              result(
                FlutterError(
                  code: "ENCODING_ERROR",
                  message: "Failed to convert JSON data to string",
                  details: nil))
            }
          }
        } catch {
          onMain {
            result(
              FlutterError(
                code: "ENCODING_ERROR",
                message: "Failed to encode activity sample data: \(error.localizedDescription)",
                details: nil))
          }
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: "ERROR_GETTING_ACTIVITY_SAMPLE_DATA",
              message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func sendInitializationAndStartSyncNotifications(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    guard let identifier = call.arguments as? String else {
      result(
        FlutterError(
          code: "ERROR_INVALID_ARGUMENT",
          message: "Expected a single String argument",
          details: nil))
      return
    }

    Task {
      do {
        try await api.sendInitializationAndStartSyncNotifications(identifier: identifier)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: error.localizedDescription,
              message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func sendTerminateAndStopSyncNotifications(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    guard let identifier = call.arguments as? String else {
      result(
        FlutterError(
          code: "ERROR_INVALID_ARGUMENT",
          message: "Expected a single String argument",
          details: nil))
      return
    }

    Task {
      do {
        try await api.sendTerminateAndStopSyncNotifications(identifier: identifier)
        onMain {
          result(nil)
        }
      } catch {
        onMain {
          result(
            FlutterError(
              code: error.localizedDescription,
              message: error.localizedDescription,
              details: nil))
        }
      }
    }
  }

  func checkFirmwareUpdate(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let identifier = call.arguments as? String else {
      result(
        FlutterError(
          code: "ERROR_INVALID_ARGUMENT",
          message: "Expected a single String argument",
          details: nil))
      return
    }

    Task {
      do {
        for try await status in api.checkFirmwareUpdate(identifier) {
          var jsonStatus: [String: Any] = [:]
          switch status {
          case .checkFwUpdateAvailable(let version):
            jsonStatus = ["type": "available", "version": version]
          case .checkFwUpdateNotAvailable(let details):
            jsonStatus = ["type": "notAvailable", "details": details]
          case .checkFwUpdateFailed(let details):
            jsonStatus = ["type": "failed", "details": details]
          }

          self.success("firmwareUpdateCheckStatusReceived", data: [identifier, jsonStatus])
        }
      } catch {
        let jsonStatus: [String: Any] = ["type": "failed", "details": error.localizedDescription]
        self.success("firmwareUpdateCheckStatusReceived", data: [identifier, jsonStatus])
      }
    }

    result(nil)
  }

  func updateFirmware(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let identifier: String
    let firmwareUrl: String?

    if let args = call.arguments as? [Any], args.count == 2,
      let id = args[0] as? String, let url = args[1] as? String
    {
      identifier = id
      firmwareUrl = url
    } else if let id = call.arguments as? String {
      identifier = id
      firmwareUrl = nil
    } else {
      result(
        FlutterError(
          code: "ERROR_INVALID_ARGUMENT",
          message: "Expected [String, String] or String",
          details: nil))
      return
    }

    let stream =
      firmwareUrl != nil
      ? api.updateFirmware(identifier, fromFirmwareURL: URL(string: firmwareUrl!)!)
      : api.updateFirmware(identifier)

    Task {
      do {
        for try await status in stream {
          var jsonStatus: [String: Any] = [:]
          switch status {
          case .fetchingFwUpdatePackage(let details):
            jsonStatus = ["type": "fetchingPackage", "details": details]
          case .preparingDeviceForFwUpdate(let details):
            jsonStatus = ["type": "preparingDevice", "details": details]
          case .writingFwUpdatePackage(let details):
            jsonStatus = ["type": "writingPackage", "details": details]
          case .finalizingFwUpdate(let details):
            jsonStatus = ["type": "finalizing", "details": details]
          case .fwUpdateCompletedSuccessfully(let details):
            jsonStatus = ["type": "completed", "details": details]
          case .fwUpdateNotAvailable(let details):
            jsonStatus = ["type": "notAvailable", "details": details]
          case .fwUpdateFailed(let details):
            jsonStatus = ["type": "failed", "details": details]
          }

          self.success("firmwareUpdateStatusReceived", data: [identifier, jsonStatus])
        }
      } catch {
        let jsonStatus: [String: Any] = ["type": "failed", "details": error.localizedDescription]
        self.success("firmwareUpdateStatusReceived", data: [identifier, jsonStatus])
      }
    }

    result(nil)
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  let onListen: (Any?, @escaping FlutterEventSink) -> FlutterError?
  let onCancel: (Any?) -> FlutterError?

  init(
    onListen: @escaping (Any?, @escaping FlutterEventSink) -> FlutterError?,
    onCancel: @escaping (Any?) -> FlutterError?
  ) {
    self.onListen = onListen
    self.onCancel = onCancel
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    return onListen(arguments, events)
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    return onCancel(arguments)
  }
}

class StreamingChannel: NSObject, FlutterStreamHandler {
  let api: PolarBleApi
  let identifier: String
  let feature: PolarDeviceDataType
  let channel: FlutterEventChannel

  var streamTask: Task<Void, Never>?

  init(
    _ messenger: FlutterBinaryMessenger, _ name: String, _ api: PolarBleApi, _ identifier: String,
    _ feature: PolarDeviceDataType
  ) {
    self.api = api
    self.identifier = identifier
    self.feature = feature
    self.channel = FlutterEventChannel(name: name, binaryMessenger: messenger)

    super.init()

    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    // Will be null for some features
    let settings = try? decoder.decode(
      PolarSensorSettingCodable.self,
      from: (arguments as! String)
        .data(using: .utf8)!
    ).data

    switch feature {
    case .ecg:
      streamTask = consume(api.startEcgStreaming(identifier, settings: settings!), events)
    case .acc:
      streamTask = consume(api.startAccStreaming(identifier, settings: settings!), events)
    case .ppg:
      streamTask = consume(api.startPpgStreaming(identifier, settings: settings!), events)
    case .ppi:
      streamTask = consume(api.startPpiStreaming(identifier), events)
    case .gyro:
      streamTask = consume(api.startGyroStreaming(identifier, settings: settings!), events)
    case .magnetometer:
      streamTask = consume(api.startMagnetometerStreaming(identifier, settings: settings!), events)
    case .hr:
      streamTask = consume(api.startHrStreaming(identifier), events)
    case .temperature:
      streamTask = consume(api.startTemperatureStreaming(identifier, settings: settings!), events)
    case .pressure:
      streamTask = consume(api.startPressureStreaming(identifier, settings: settings!), events)
    case .skinTemperature:
      streamTask = consume(
        api.startSkinTemperatureStreaming(identifier, settings: settings!), events)
    }

    return nil
  }

  /// Iterate an SDK data stream and forward each sample batch to Flutter.
  /// Values arrive on the cooperative thread pool, so every sink invocation
  /// is dispatched onto the main thread.
  private func consume<T>(
    _ stream: AsyncThrowingStream<T, Error>, _ events: @escaping FlutterEventSink
  ) -> Task<Void, Never> {
    Task {
      do {
        for try await data in stream {
          guard let data = jsonEncode(PolarDataCodable(data)) else {
            continue
          }
          onMain {
            events(data)
          }
        }
        if !Task.isCancelled {
          onMain {
            events(FlutterEndOfEventStream)
          }
        }
      } catch {
        if !Task.isCancelled {
          onMain {
            events(
              FlutterError(
                code: "Error while streaming", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    streamTask?.cancel()
    streamTask = nil
    return nil
  }

  func dispose() {
    streamTask?.cancel()
    streamTask = nil
    channel.setStreamHandler(nil)
  }
}
