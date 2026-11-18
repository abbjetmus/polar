import Foundation
import PolarBleSdk

/// Android names for the PMD control-point response codes, so a rejection
/// reads the same on both platforms (`ERROR_DISK_FULL`, `ERROR_INVALID_STATE`).
private let pmdResponseCodeNames: [Int: String] = [
  1: "ERROR_INVALID_OP_CODE",
  2: "ERROR_INVALID_MEASUREMENT_TYPE",
  3: "ERROR_NOT_SUPPORTED",
  4: "ERROR_INVALID_LENGTH",
  5: "ERROR_INVALID_PARAMETER",
  6: "ERROR_ALREADY_IN_STATE",
  7: "ERROR_INVALID_RESOLUTION",
  8: "ERROR_INVALID_SAMPLE_RATE",
  9: "ERROR_INVALID_RANGE",
  10: "ERROR_INVALID_MTU",
  11: "ERROR_INVALID_NUMBER_OF_CHANNELS",
  12: "ERROR_INVALID_STATE",
  13: "ERROR_DEVICE_IN_CHARGER",
  14: "ERROR_DISK_FULL",
  15: "ERROR_INVALID_SOURCE_MEASUREMENT_TYPE",
  16: "ERROR_INVALID_SOURCE_MEASUREMENT_RATE",
  17: "ERROR_INVALID_DERIVED_MEASUREMENT_SETTINGS_GROUP",
  18: "ERROR_INVALID_DERIVED_MEASUREMENT_METHOD",
]

/// The message to send over the channel for `error`.
///
/// `localizedDescription` on a Swift enum error only gives the case index
/// ("PolarBleSdk.BlePmdError error 0"), which drops the response code the band
/// sent. For PMD errors, spell the code out instead, e.g.
/// `ERROR_INVALID_STATE (12): Invalid state`.
func errorMessage(_ error: Error) -> String {
  guard let pmdError = error as? BlePmdError else {
    return error.localizedDescription
  }
  switch pmdError {
  case let .controlPointRequestFailed(errorCode, description):
    let name = pmdResponseCodeNames[errorCode] ?? "ERROR_UNKNOWN"
    return "\(name) (\(errorCode)): \(description)"
  default:
    return String(describing: pmdError)
  }
}
