import Foundation
import CoreFoundation

/// Validates the untrusted platform-channel boundary before touching HealthKit.
struct HealthKitWorkout {
  static let namespace = "com.gymmane.app.workout."
  let id: String
  let revision: Int
  let start: Date
  let end: Date
  let duration: TimeInterval
  let name: String

  var syncIdentifier: String { Self.namespace + id }

  static func identity(_ arguments: Any?) throws -> (String, Int) {
    guard let values = arguments as? [String: Any],
          let rawID = values["id"] as? String,
          let uuid = UUID(uuidString: rawID),
          let number = values["revision"] as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite,
          number.doubleValue >= 1,
          number.doubleValue <= 9007199254740991,
          number.doubleValue.rounded(.down) == number.doubleValue else {
      throw ValidationError.invalidIdentity
    }
    return (uuid.uuidString.lowercased(), number.intValue)
  }

  init(arguments: Any?) throws {
    let (id, revision) = try Self.identity(arguments)
    guard let values = arguments as? [String: Any],
          let startText = values["startTime"] as? String,
          let endText = values["endTime"] as? String,
          let start = Self.utcDate(startText), let end = Self.utcDate(endText),
          end > start,
          let seconds = values["durationSeconds"] as? NSNumber,
          CFGetTypeID(seconds) != CFBooleanGetTypeID(),
          seconds.doubleValue.isFinite, seconds.doubleValue > 0,
          seconds.doubleValue <= end.timeIntervalSince(start) + 0.001,
          let name = values["name"] as? String,
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          name.utf16.count <= 256 else {
      throw ValidationError.invalidWorkout
    }
    self.id = id
    self.revision = revision
    self.start = start
    self.end = end
    self.duration = seconds.doubleValue
    self.name = name
  }

  private static func utcDate(_ value: String) -> Date? {
    guard value.hasSuffix("Z") else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  enum ValidationError: Error {
    case invalidIdentity, invalidWorkout
  }
}
