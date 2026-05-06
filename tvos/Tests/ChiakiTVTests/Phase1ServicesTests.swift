// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
import ChiakiBridgeC
@testable import ChiakiTV

/// Coverage for the Phase 1 service layer above the C bridge — registration
/// helpers, host-lookup, manual-host wiring. Anything that requires a live
/// chiaki session (i.e. an actual PS5) is verified manually on hardware.
@MainActor
final class Phase1ServicesTests: XCTestCase {

    // MARK: - PSN account ID decoding

    func testDecodesPrefilledPsnAccountId() {
        // The default ships Stephano's account; must always decode to 8 bytes.
        let bytes = RegistrationService.decodePsnAccountId("TyiIo99CmXI=")
        XCTAssertNotNil(bytes)
        XCTAssertEqual(bytes?.count, 8)
    }

    func testRejectsTooShortPsnAccountId() {
        XCTAssertNil(RegistrationService.decodePsnAccountId(""))
        // 4 bytes after base64 → too short.
        XCTAssertNil(RegistrationService.decodePsnAccountId("AAAA"))
    }

    func testRejectsTooLongPsnAccountId() {
        // 16 bytes after decode — wrong size.
        XCTAssertNil(RegistrationService.decodePsnAccountId("AAAAAAAAAAAAAAAAAAAAAA=="))
    }

    func testAppSettingsDefaultPsnAccountIdMatches() {
        XCTAssertEqual(AppSettings().psnAccountId, "TyiIo99CmXI=",
                       "Default PSN account ID must remain Stephano's prefilled value")
    }

    // MARK: - registeredHost(for:) lookup

    func testRegisteredHostFoundByMac() async {
        let state = AppState.preview()
        state.registeredHosts = [
            RegisteredHost(
                nickname: "PS5-Living-Room", mac: "AA:BB:CC:DD:EE:FF",
                targetVersion: 1_000_100,
                rpKeyBase64: "x", rpRegistKeyBase64: "y",
                lastIpAddress: "10.0.0.1", consolePin: nil)
        ]
        let host = Host(id: "id", nickname: "Discovered",
                        ipAddress: "10.0.0.99",
                        mac: "aa:bb:cc:dd:ee:ff",  // case-insensitive
                        ps5: true, registered: false, manual: false,
                        discovered: true, state: .ready)
        XCTAssertNotNil(state.registeredHost(for: host))
    }

    func testRegisteredHostFoundByIpWhenMacMissing() async {
        let state = AppState.preview()
        state.registeredHosts = [
            RegisteredHost(
                nickname: "PS5", mac: "11:22:33:44:55:66",
                targetVersion: 1_000_100,
                rpKeyBase64: "x", rpRegistKeyBase64: "y",
                lastIpAddress: "192.168.1.42", consolePin: nil)
        ]
        let host = Host(id: "manual", nickname: "Manual",
                        ipAddress: "192.168.1.42", mac: "",
                        ps5: true, registered: false, manual: true,
                        discovered: false, state: .unknown)
        XCTAssertNotNil(state.registeredHost(for: host))
    }

    func testRegisteredHostMissForUnknownHost() async {
        let state = AppState.preview()
        let host = Host(id: "x", nickname: "X", ipAddress: "10.99.99.99",
                        mac: "00:00:00:00:00:00")
        XCTAssertNil(state.registeredHost(for: host))
    }

    // MARK: - matchesRegistered(host:in:) — drives the discovered/registered
    // reconciliation in observeDiscoveryHosts(). Without this, a paired host
    // that was just discovered would render as "(unregistered)" and hide its
    // Wake Up / Update Pin inline actions until the next app launch.

    func testMatchesRegisteredByMacIsCaseInsensitive() {
        let regs = [
            RegisteredHost(nickname: "PS5", mac: "AA:BB:CC:DD:EE:FF",
                           targetVersion: 1_000_100,
                           rpKeyBase64: "x", rpRegistKeyBase64: "y",
                           lastIpAddress: "10.0.0.1", consolePin: nil)
        ]
        let host = Host(id: "id", nickname: "Discovered",
                        ipAddress: "10.0.0.99",
                        mac: "aa:bb:cc:dd:ee:ff",
                        ps5: true, registered: false, manual: false,
                        discovered: true, state: .ready)
        XCTAssertTrue(AppState.matchesRegistered(host: host, in: regs))
    }

    func testMatchesRegisteredByIpWhenMacMissing() {
        let regs = [
            RegisteredHost(nickname: "PS5", mac: "11:22:33:44:55:66",
                           targetVersion: 1_000_100,
                           rpKeyBase64: "x", rpRegistKeyBase64: "y",
                           lastIpAddress: "192.168.1.42", consolePin: nil)
        ]
        let host = Host(id: "manual", nickname: "Manual",
                        ipAddress: "192.168.1.42", mac: "")
        XCTAssertTrue(AppState.matchesRegistered(host: host, in: regs))
    }

    func testMatchesRegisteredFalseForUnpairedHost() {
        let regs = [
            RegisteredHost(nickname: "Other", mac: "AA:AA:AA:AA:AA:AA",
                           targetVersion: 1_000_100,
                           rpKeyBase64: "x", rpRegistKeyBase64: "y",
                           lastIpAddress: "10.0.0.1", consolePin: nil)
        ]
        let host = Host(id: "id", nickname: "Stranger",
                        ipAddress: "10.99.99.99",
                        mac: "BB:BB:BB:BB:BB:BB")
        XCTAssertFalse(AppState.matchesRegistered(host: host, in: regs))
    }

    func testMatchesRegisteredFalseForEmptyMacAndIp() {
        let regs = [
            RegisteredHost(nickname: "PS5", mac: "AA:BB:CC:DD:EE:FF",
                           targetVersion: 1_000_100,
                           rpKeyBase64: "x", rpRegistKeyBase64: "y",
                           lastIpAddress: "10.0.0.1", consolePin: nil)
        ]
        let host = Host(id: "blank", nickname: "Blank", ipAddress: "", mac: "")
        XCTAssertFalse(AppState.matchesRegistered(host: host, in: regs))
    }

    // MARK: - ChiakiBridgeC visibility from Swift

    func testBridgeCodecConstantsAreImported() {
        // Smoke test: the chiaki_tv_codec_t enum case must exist and import
        // as a Swift type. If this stops compiling we'll know quickly.
        XCTAssertEqual(CHIAKI_TV_CODEC_H265.rawValue, 1)
        XCTAssertEqual(CHIAKI_TV_CODEC_H265_HDR.rawValue, 2)
    }

    func testTargetPS5HelpersReturnExpectedValues() {
        // ChiakiTarget value 1_000_100 = PS5_1.
        XCTAssertEqual(chiaki_tv_target_ps5_1(), 1_000_100)
        XCTAssertEqual(chiaki_tv_target_ps5_unknown(), 1_000_000)
    }
}
