import XCTest
@testable import MacCleanKit

final class TimeoutTests: XCTestCase {

    func testReturnsValueWhenOperationFinishesInTime() async throws {
        let value = try await withTimeout(.seconds(1)) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testThrowsTimeoutErrorWhenOperationTooSlow() async {
        do {
            _ = try await withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(10))
                return 0
            }
            XCTFail("expected withTimeout to throw before the slow operation finished")
        } catch is TimeoutError {
            // expected
        } catch {
            XCTFail("expected TimeoutError, got \(error)")
        }
    }

    func testPropagatesOperationError() async {
        struct Boom: Error {}
        do {
            _ = try await withTimeout(.seconds(1)) { () async throws -> Int in
                throw Boom()
            }
            XCTFail("expected the operation's own error to propagate")
        } catch is Boom {
            // expected: a fast failure surfaces, not a timeout
        } catch {
            XCTFail("expected Boom, got \(error)")
        }
    }
}
