import Flutter
import HealthKit

final class HealthKitBridge {
  private let store = HKHealthStore()
  private let workoutType = HKObjectType.workoutType()
  private var channel: FlutterMethodChannel?

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "gymmane/healthkit", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      self.handle(call, result: result)
    }
  }

  private var authorization: String {
    guard HKHealthStore.isHealthDataAvailable() else { return "unsupported" }
    switch store.authorizationStatus(for: workoutType) {
    case .notDetermined: return "notDetermined"
    case .sharingDenied: return "denied"
    case .sharingAuthorized: return "authorized"
    @unknown default: return "unsupported"
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability":
      result(["available": HKHealthStore.isHealthDataAvailable()])
    case "authorization":
      result(["status": authorization])
    case "requestAuthorization":
      guard available(result) else { return }
      // Export-only: do not ask to read any health data.
      store.requestAuthorization(toShare: [workoutType], read: []) { success, error in
        DispatchQueue.main.async {
          if let error { self.fail(error, operation: "authorization", result: result) }
          else if !success {
            result(FlutterError(code: "authorization_failed", message: "Health authorization did not complete.", details: nil))
          } else {
            // Completion does not imply the user granted write access.
            result(["status": self.authorization])
          }
        }
      }
    case "saveWorkout":
      do {
        let input = try HealthKitWorkout(arguments: call.arguments)
        guard writable(result) else { return }
        save(input, result: result)
      } catch { invalid(result) }
    case "deleteWorkout":
      do {
        let (id, revision) = try HealthKitWorkout.identity(call.arguments)
        guard writable(result) else { return }
        delete(id: id, revision: revision, result: result)
      } catch { invalid(result) }
    default: result(FlutterMethodNotImplemented)
    }
  }

  static func makeWorkout(_ input: HealthKitWorkout) -> HKWorkout {
    // Explicit duration preserves pauses; nil energy/distance never invents measurements.
    return HKWorkout(
      activityType: .traditionalStrengthTraining,
      start: input.start, end: input.end, duration: input.duration,
      totalEnergyBurned: nil, totalDistance: nil,
      metadata: [
        HKMetadataKeySyncIdentifier: input.syncIdentifier,
        HKMetadataKeySyncVersion: input.revision,
        HKMetadataKeyWorkoutBrandName: "GymMane",
        "com.gymmane.app.workoutName": input.name,
      ]
    )
  }

  private func save(_ input: HealthKitWorkout, result: @escaping FlutterResult) {
    let workout = Self.makeWorkout(input)
    // HealthKit replaces lower sync versions and ignores already saved versions.
    // Return the stable sync key, not this object's potentially unsaved UUID.
    store.save(workout) { success, error in
      DispatchQueue.main.async {
        if let error { self.fail(error, operation: "save", result: result) }
        else if !success { self.failed("save", result: result) }
        else { result(["syncIdentifier": input.syncIdentifier, "revision": input.revision]) }
      }
    }
  }

  static func deletionPredicate(id: String, revision: Int) -> NSPredicate {
    NSCompoundPredicate(andPredicateWithSubpredicates: [
      HKQuery.predicateForObjects(from: HKSource.default()),
      HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                 allowedValues: [HealthKitWorkout.namespace + id]),
      // A delayed tombstone must not delete a newer revision.
      HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncVersion,
                                 operatorType: .lessThanOrEqualTo, value: revision),
    ])
  }

  private func delete(id: String, revision: Int, result: @escaping FlutterResult) {
    store.deleteObjects(of: workoutType,
                        predicate: Self.deletionPredicate(id: id, revision: revision)) { success, count, error in
      DispatchQueue.main.async {
        if let error { self.fail(error, operation: "delete", result: result) }
        else if !success { self.failed("delete", result: result) }
        else { result(["deletedCount": count]) }
      }
    }
  }

  private func available(_ result: FlutterResult) -> Bool {
    guard HKHealthStore.isHealthDataAvailable() else {
      result(FlutterError(code: "unsupported", message: "HealthKit is unavailable on this device.", details: nil))
      return false
    }
    return true
  }

  private func writable(_ result: FlutterResult) -> Bool {
    guard available(result) else { return false }
    guard authorization == "authorized" else {
      result(FlutterError(code: "permission_denied", message: "Allow GymMane to write workouts in Health.", details: nil))
      return false
    }
    return true
  }

  private func invalid(_ result: FlutterResult) {
    result(FlutterError(code: "invalid_argument", message: "A UUID, positive revision, UTC times, valid duration and workout name are required.", details: nil))
  }

  private func failed(_ operation: String, result: FlutterResult) {
    result(FlutterError(code: operation + "_failed", message: "HealthKit did not complete the operation.", details: nil))
  }

  private func fail(_ error: Error, operation: String, result: FlutterResult) {
    let native = error as NSError
    let denied = native.domain == HKErrorDomain &&
      (native.code == HKError.Code.errorAuthorizationDenied.rawValue ||
       native.code == HKError.Code.errorAuthorizationNotDetermined.rawValue)
    result(FlutterError(code: denied ? "permission_denied" : operation + "_failed",
                        message: denied ? "Health workout access is not authorized." : "HealthKit could not complete the operation.",
                        details: ["domain": native.domain, "code": native.code]))
  }
}
