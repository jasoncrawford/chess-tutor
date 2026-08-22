import XCTest
@testable import ChessTutor

final class CoachingGoldenTranscriptTests: XCTestCase {
    func testCorpusContainsEveryApprovedAnchor() {
        XCTAssertEqual(CoachingGoldenPosition.allCases.count, 15)
        XCTAssertEqual(Set(CoachingGoldenPosition.allCases.map(\.rawValue)).count, 15)
        XCTAssertEqual(CoachingGoldenCase.allCases.count, 46)
        XCTAssertEqual(Set(CoachingGoldenCase.allCases.map(\.rawValue)).count, 46)
    }
}
