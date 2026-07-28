import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:polar/polar.dart';
import 'package:recase/recase.dart';

/// Read a value from a JSON object keyed based on the platform
Object? readPlatformValue(Map json, Map<TargetPlatform, String> keys) {
  final key = keys[defaultTargetPlatform];
  if (key == null) {
    throw UnsupportedError('Unsupported platform: $defaultTargetPlatform');
  }
  return json[key];
}

/// Converts platform values to booleans
/// - The iOS SDK uses `0` and `1` for booleans
/// - The Android SDK uses `true` and `false` for booleans
class PlatformBooleanConverter extends JsonConverter<bool, dynamic> {
  /// Constructor
  const PlatformBooleanConverter();

  @override
  bool fromJson(dynamic json) {
    if (Platform.isIOS) {
      return json != 0;
    } else {
      return json;
    }
  }

  @override
  dynamic toJson(bool object) {
    if (Platform.isIOS) {
      return object ? 1 : 0;
    } else {
      return object;
    }
  }
}

/// Converter for [PpgDataType]
class PpgDataTypeConverter extends JsonConverter<PpgDataType, dynamic> {
  /// Constructor
  const PpgDataTypeConverter();

  @override
  PpgDataType fromJson(dynamic json) {
    if (Platform.isIOS) {
      switch (json as int) {
        case 4:
          return PpgDataType.ppg3_ambient1;
        default: // 18
          return PpgDataType.unknown;
      }
    } else {
      // This is android
      return PpgDataType.values.byName((json as String).toLowerCase());
    }
  }

  @override
  dynamic toJson(PpgDataType object) {
    if (Platform.isIOS) {
      switch (object) {
        case PpgDataType.ppg3_ambient1:
          return 4;
        default: // PpgDataType.unknown
          return 18;
      }
    } else {
      // This is android
      return object.name.snakeCase.toUpperCase();
    }
  }
}

/// Converter for unix time
class UnixTimeConverter extends JsonConverter<DateTime, int> {
  /// Constructor
  const UnixTimeConverter();

  @override
  DateTime fromJson(int json) => DateTime.fromMillisecondsSinceEpoch(json);

  @override
  int toJson(DateTime object) => object.millisecondsSinceEpoch;
}

/// Converter for [PolarSettingType]
class PolarSettingTypeConverter
    extends JsonConverter<PolarSettingType, String> {
  /// Constructor
  const PolarSettingTypeConverter();

  @override
  PolarSettingType fromJson(String json) {
    if (Platform.isIOS) {
      return PolarSettingType.values[int.parse(json)];
    } else {
      // This is android
      return PolarSettingType.values.byName(json.camelCase);
    }
  }

  @override
  String toJson(PolarSettingType object) {
    if (Platform.isIOS) {
      return object.index.toString();
    } else {
      // This is android
      return object.name.snakeCase.toUpperCase();
    }
  }
}

final _polarEpoch = DateTime.utc(2000).microsecondsSinceEpoch;

/// Convert polar sample timestamps to [DateTime]
///
/// The raw nanosecond values represent UTC time since the Polar epoch
/// (1.1.2000) on both platforms. Polar 360 firmware 5.0.55 stamped offline
/// samples with device-local time on Android, which is why this converter
/// used to re-interpret the raw value as local there; firmware 6.1.19+
/// stamps in UTC, matching iOS.
class PolarSampleTimestampConverter extends JsonConverter<DateTime, int> {
  /// Constructor
  const PolarSampleTimestampConverter();

  @override
  DateTime fromJson(int json) {
    final micros = json ~/ 1000;
    // Raw value is UTC — return as a local-zone DateTime pointing at the
    // same instant, so the caller's .toUtc() yields the raw value unchanged.
    return DateTime.fromMicrosecondsSinceEpoch(_polarEpoch + micros);
  }

  @override
  int toJson(DateTime object) {
    final micros = object.microsecondsSinceEpoch - _polarEpoch;
    return micros * 1000;
  }
}

/// Converts [PolarDataType] to and from JSON strings.
class PolarDataTypeConverter implements JsonConverter<PolarDataType, dynamic> {
  /// Constant constructor for [PolarDataTypeConverter].
  const PolarDataTypeConverter();

  /// Converts JSON to [PolarDataType].
  @override
  PolarDataType fromJson(dynamic json) {
    return PolarDataType.fromJson(json);
  }

  /// Converts [PolarDataType] to JSON.
  @override
  dynamic toJson(PolarDataType object) {
    return object.toJson();
  }
}

/// Converts a map with time components to and from [DateTime].
class MapToDateTimeConverter
    implements JsonConverter<DateTime, Map<String, dynamic>> {
  /// Constant constructor for [MapToDateTimeConverter].
  const MapToDateTimeConverter();

  @override
  DateTime fromJson(Map<String, dynamic> json) {
    return DateTime.utc(
      json['year'] as int,
      (json['month'] as int) + 1,
      json['dayOfMonth'] as int,
      json['hourOfDay'] as int,
      json['minute'] as int,
      json['second'] as int,
    );
  }

  @override
  Map<String, dynamic> toJson(DateTime date) => {
        'year': date.toUtc().year,
        'month': date.toUtc().month - 1,
        'dayOfMonth': date.toUtc().day,
        'hourOfDay': date.toUtc().hour,
        'minute': date.toUtc().minute,
        'second': date.toUtc().second,
      };
}
