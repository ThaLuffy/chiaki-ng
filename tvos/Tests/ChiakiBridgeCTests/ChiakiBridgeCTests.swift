// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import ChiakiBridgeC

final class ChiakiBridgeCTests: XCTestCase {

    /// Phase 0 smoke test: confirms ChiakiBridgeC was linked into the test
    /// binary and its public symbols are reachable from Swift via the
    /// module map. Phase 1 will replace this with real C-bridge tests
    /// (callback adapters, log routing, packet feed paths).
    func testBridgeVersionStringIsReachable() throws {
        guard let cString = chiaki_tv_bridge_version() else {
            XCTFail("chiaki_tv_bridge_version() returned NULL")
            return
        }
        let s = String(cString: cString)
        XCTAssertTrue(s.contains("ChiakiBridgeC"), "got: \(s)")
        XCTAssertTrue(s.contains("Phase 0"), "got: \(s)")
    }
}
