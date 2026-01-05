// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: document_ignores, unnecessary_cast, require_trailing_commas

part of 'polar_firmware_update_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PolarFirmwareUpdateCheckStatus _$PolarFirmwareUpdateCheckStatusFromJson(
        Map<String, dynamic> json) =>
    PolarFirmwareUpdateCheckStatus(
      type: json['type'] as String,
      version: json['version'] as String?,
      details: json['details'] as String?,
    );

Map<String, dynamic> _$PolarFirmwareUpdateCheckStatusToJson(
        PolarFirmwareUpdateCheckStatus instance) =>
    <String, dynamic>{
      'type': instance.type,
      'version': instance.version,
      'details': instance.details,
    };

PolarFirmwareUpdateStatus _$PolarFirmwareUpdateStatusFromJson(
        Map<String, dynamic> json) =>
    PolarFirmwareUpdateStatus(
      type: json['type'] as String,
      details: json['details'] as String?,
    );

Map<String, dynamic> _$PolarFirmwareUpdateStatusToJson(
        PolarFirmwareUpdateStatus instance) =>
    <String, dynamic>{
      'type': instance.type,
      'details': instance.details,
    };
