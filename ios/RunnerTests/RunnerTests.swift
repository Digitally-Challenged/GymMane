import XCTest
import HealthKit
@testable import Runner

final class RunnerTests: XCTestCase {
  private let id = "0f68869c-e8f2-4a01-bab9-1710be636176"
  private var payload: [String: Any] {
    ["id": id, "revision": 2, "startTime": "2026-10-01T12:00:00.000Z",
     "endTime": "2026-10-01T12:30:00Z", "durationSeconds": 1200, "name": "Strength"]
  }

  func testValidWorkoutPreservesActiveDurationAndStableIdentity() throws {
    var value = payload
    value["id"] = id.uppercased()
    let workout = try HealthKitWorkout(arguments: value)
    XCTAssertEqual(workout.id, id)
    XCTAssertEqual(workout.syncIdentifier, "com.gymmane.app.workout." + id)
    XCTAssertEqual(workout.duration, 1200)
    XCTAssertEqual(workout.end.timeIntervalSince(workout.start), 1800)
  }

  func testHealthKitSampleHasNoFabricatedMeasurements() throws {
    let sample = HealthKitBridge.makeWorkout(try HealthKitWorkout(arguments: payload))
    XCTAssertEqual(sample.workoutActivityType, .traditionalStrengthTraining)
    XCTAssertEqual(sample.duration, 1200)
    XCTAssertNil(sample.totalEnergyBurned)
    XCTAssertNil(sample.totalDistance)
    XCTAssertEqual(sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                   HealthKitWorkout.namespace + id)
    XCTAssertEqual(sample.metadata?[HKMetadataKeySyncVersion] as? Int, 2)
  }

  func testRejectsUntrustedInvalidArguments() {
    let invalid: [(String, Any)] = [
      ("id", "*"), ("revision", true), ("revision", 0), ("revision", 1.5),
      ("revision", 9007199254740992 as Int64), ("durationSeconds", true),
      ("durationSeconds", Double.nan), ("durationSeconds", Double.infinity),
      ("durationSeconds", 0), ("durationSeconds", 1801), ("name", "  "),
      ("name", String(repeating: "a", count: 257)),
      ("startTime", "2026-10-01T12:00:00"),
      ("endTime", "2026-10-01T11:00:00Z"),
    ]
    for (key, badValue) in invalid {
      var value = payload
      value[key] = badValue
      XCTAssertThrowsError(try HealthKitWorkout(arguments: value), key)
    }
  }

  func testDeletionRequiresSourceSyncKeyAndRevisionFence() {
    let predicate = HealthKitBridge.deletionPredicate(id: id, revision: 2)
    let compound = predicate as? NSCompoundPredicate
    XCTAssertEqual(compound?.compoundPredicateType, .and)
    XCTAssertEqual(compound?.subpredicates.count, 3)
    XCTAssertTrue(predicate.predicateFormat.contains("com.gymmane.app.workout." + id))
    XCTAssertTrue(predicate.predicateFormat.contains("<="))
  }
}
