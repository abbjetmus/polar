# polar

Plugin wrapper for the [Polar SDK](https://github.com/polarofficial/polar-ble-sdk)

## Note

This is an unofficial wrapper for the Polar SDK. For any questions regarding the underlying SDKs or Polar devices in general, please see the [official repository](https://github.com/polarofficial/polar-ble-sdk).

## Getting Started

### Android

android/app/src/main/AndroidManifest.xml:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
```

If you use `BLUETOOTH_SCAN` to determine location, remove `android:usesPermissionFlags="neverForLocation"`

If you use location services in your app, remove `android:maxSdkVersion="30"` from the location permission tags

### iOS

Change the deployment target in Xcode to iOS 14+

Podfile:

```ruby
platform :ios, '14.0'
```

Info.plist:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Used to connect to Polar devices</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Used to connect to Polar devices</string>
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
</array>
```

## Usage

<!-- embedme readme/usage.dart -->

## Firmware Updates

You can check if there is a firmware update available for your Polar device and perform the update directly through the plugin.

### Checking for Updates

Use the `checkFirmwareUpdate()` method to check if an update is available:

```dart
final updateInfo = await polar.checkFirmwareUpdate(identifier);
if (updateInfo.isUpdateAvailable) {
  debugPrint('Update available: ${updateInfo.availableVersion}');
  debugPrint('Current version: ${updateInfo.currentVersion}');
}
```

### Performing Firmware Update

To update the firmware, simply call the `updateFirmware()` method. This will update the device with the latest available firmware using the [Polar Firmware Management API](https://firmware-management.polar.com/docs/).

You can monitor the update progress by listening to the `firmwareUpdateProgress` stream:

```dart
// Subscribe to firmware update progress
final progressSubscription = polar.firmwareUpdateProgress
    .where((event) => event.identifier == identifier)
    .listen((progress) {
  debugPrint('Firmware update progress: ${progress.progressPercentage}%');
  debugPrint('Status: ${progress.status}');
  
  if (progress.isCompleted) {
    debugPrint('Firmware update completed!');
  }
});

// Start the firmware update
await polar.updateFirmware(identifier);

// Don't forget to cancel the subscription when done
await progressSubscription.cancel();
```

### ⚠️ Important Notes

- **Performing firmware update with Polar devices will erase all data inside the device**, including SDK offline recordings. Please make sure to sync any data you wish to retrieve before doing it.
- `doFirstTimeUse()` is **not** necessary to do after firmware update, as there is automatic backup to send user settings back to the device as the last step of the firmware update process.

<!-- embedme readme/usage.dart -->
```dart
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
  final availabletypes =
      await polar.getAvailableOnlineStreamDataTypes(identifier);

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

```