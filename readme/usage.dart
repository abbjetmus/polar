import 'package:flutter/foundation.dart';
import 'package:polar/polar.dart';

const identifier = '1C709B20';
final polar = Polar();

void example() {
  polar.connectToDevice(identifier);
  streamWhenReady();
}

void streamWhenReady() async {
  await polar.sdkFeatureReady.firstWhere(
    (e) =>
        e.identifier == identifier &&
        e.feature == PolarSdkFeature.onlineStreaming,
  );
  final availabletypes = await polar.getAvailableOnlineStreamDataTypes(
    identifier,
  );

  debugPrint('available types: $availabletypes');

  if (availabletypes.contains(PolarDataType.hr)) {
    polar
        .startHrStreaming(identifier)
        .listen((e) => debugPrint('HR data received'));
  }
  if (availabletypes.contains(PolarDataType.ecg)) {
    polar
        .startEcgStreaming(identifier)
        .listen((e) => debugPrint('ECG data received'));
  }
  if (availabletypes.contains(PolarDataType.acc)) {
    polar
        .startAccStreaming(identifier)
        .listen((e) => debugPrint('ACC data received'));
  }
}

void firmwareUpdateExample() async {
  // Check if firmware update is available
  final updateInfo = await polar.checkFirmwareUpdate(identifier);
  if (updateInfo.isUpdateAvailable) {
    debugPrint('Update available: ${updateInfo.availableVersion}');
    debugPrint('Current version: ${updateInfo.currentVersion}');

    // Perform firmware update
    // WARNING: This will erase all data on the device
    await polar.updateFirmware(identifier);
    debugPrint('Firmware update completed');
  } else {
    debugPrint('No firmware update available');
  }
}
