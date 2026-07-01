#if DEBUG
import CloudKit
import XCTest
@testable import ChessTutor

final class CloudKitShareSpikeTests: XCTestCase {
    @MainActor
    func testModelReportsMissingCloudKitEntitlementWithoutCreatingClient() {
        var didCreateClient = false

        let model = CloudKitShareSpikeModel(
            capabilities: CloudKitShareSpikeCapabilities(isCloudKitEnabled: false),
            makeClient: {
                didCreateClient = true
                return CloudKitShareSpikeClient()
            }
        )

        XCTAssertFalse(model.canUseCloudKit)
        XCTAssertEqual(
            model.setupMessage,
            "CloudKit is not enabled for this launch. Add iCloud container entitlements, then launch with --cloudkit-share-spike-use-cloudkit."
        )
        XCTAssertFalse(didCreateClient)
    }

    func testCapabilitiesRequireExplicitCloudKitArgument() {
        XCTAssertFalse(
            CloudKitShareSpikeCapabilities.current(arguments: ["ChessTutor", "--cloudkit-share-spike"])
                .canUseCloudKit
        )
        XCTAssertTrue(
            CloudKitShareSpikeCapabilities.current(
                arguments: ["ChessTutor", "--cloudkit-share-spike", "--cloudkit-share-spike-use-cloudkit"]
            )
            .canUseCloudKit
        )
    }

    func testLaunchConfigurationRequiresExplicitArgument() {
        XCTAssertFalse(CloudKitShareSpikeLaunchConfiguration.isEnabled(arguments: ["ChessTutor"]))
        XCTAssertTrue(
            CloudKitShareSpikeLaunchConfiguration.isEnabled(
                arguments: ["ChessTutor", "--cloudkit-share-spike"]
            )
        )
    }

    func testRecordPointerRoundTripsThroughCodable() throws {
        let recordID = CKRecord.ID(
            recordName: "game-123",
            zoneID: CKRecordZone.ID(zoneName: "RemoteGameZone", ownerName: "owner-456")
        )

        let pointer = CloudKitShareSpikeRecordPointer(recordID: recordID)
        let data = try JSONEncoder().encode(pointer)
        let decoded = try JSONDecoder().decode(CloudKitShareSpikeRecordPointer.self, from: data)

        XCTAssertEqual(decoded, pointer)
        XCTAssertEqual(decoded.recordID.recordName, "game-123")
        XCTAssertEqual(decoded.recordID.zoneID.zoneName, "RemoteGameZone")
        XCTAssertEqual(decoded.recordID.zoneID.ownerName, "owner-456")
    }
}
#endif
