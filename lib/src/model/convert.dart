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
/// Android: The sensor's clock is set to local time via setLocalTime().
/// The raw nanosecond values represent LOCAL time since Polar epoch.
/// We extract as UTC (to prevent double-conversion) then re-create as local.
///
/// iOS: The raw nanosecond values represent UTC time since Polar epoch.
/// We extract as UTC and keep as UTC, then the caller's .toUtc() is a no-op.
class PolarSampleTimestampConverter extends JsonConverter<DateTime, int> {
  /// Constructor
  const PolarSampleTimestampConverter();

  @override
  DateTime fromJson(int json) {
    final micros = json ~/ 1000;
    // Extract raw value as UTC (no timezone conversion)
    final raw = DateTime.fromMicrosecondsSinceEpoch(
      _polarEpoch + micros,
      isUtc: true,
    );

    if (Platform.isIOS) {
      // iOS: raw value is already UTC — keep as local DateTime
      // so .toUtc() correctly returns the same UTC value
      return DateTime.fromMicrosecondsSinceEpoch(_polarEpoch + micros);
    } else {
      // Android: raw value represents local time — re-create as local DateTime
      // so .toUtc() correctly subtracts the timezone offset
      return DateTime(
        raw.year, raw.month, raw.day,
        raw.hour, raw.minute, raw.second,
        raw.millisecond, raw.microsecond,
      );
    }
  }

  @override
  int toJson(DateTime object) {
    if (Platform.isIOS) {
      final micros = object.microsecondsSinceEpoch - _polarEpoch;
      return micros * 1000;
    } else {
      // Android: convert local DateTime components back to raw value
      final utcView = DateTime.utc(
        object.year, object.month, object.day,
        object.hour, object.minute, object.second,
        object.millisecond, object.microsecond,
      );
      final micros = utcView.microsecondsSinceEpoch - _polarEpoch;
      return micros * 1000;
    }
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
