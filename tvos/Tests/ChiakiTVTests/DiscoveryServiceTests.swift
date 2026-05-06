// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
import ChiakiBridgeC
@testable import ChiakiTV

/// Tests for the typed Swift wrapper around `chiaki_tv_discovery_service_t`.
///
/// We cover the parts that don't require a real PS5 on the LAN:
///   - Lifecycle: `start()` / `stop()` are idempotent and don't crash.
///   - Bridge → Swift conversion: synthesize a `chiaki_tv_discovery_host_t`
///     and feed it through the same private init the C callback uses.
///   - host_id → MAC normalization (12 hex → xx:xx:xx:xx:xx:xx).
///
/// Real LAN discovery is verified by hardware test in Phase 1 sign-off
/// (see docs/phases.md §"End-to-end hardware verification").
@MainActor
final class DiscoveryServiceTests: XCTestCase {

    // MARK: - Lifecycle

    func testStartStopIsIdempotent() {
        let svc = DiscoveryService()
        XCTAssertFalse(svc.isRunning)

        svc.start()
        XCTAssertTrue(svc.isRunning,
                      "start() must spin up the bridge service")

        svc.start()  // double-start is a no-op
        XCTAssertTrue(svc.isRunning)

        svc.stop()
        XCTAssertFalse(svc.isRunning)
        XCTAssertEqual(svc.hosts, [])

        svc.stop()  // double-stop is a no-op
        XCTAssertFalse(svc.isRunning)
    }

    func testHostsClearedOnStop() {
        let svc = DiscoveryService()
        svc.start()
        // No real hosts on the simulator's LAN, but we can verify the contract.
        XCTAssertEqual(svc.hosts, [])
        svc.stop()
        XCTAssertEqual(svc.hosts, [])
    }

    // MARK: - host_id → MAC normalization

    func testHostIdNormalizesToColonMac() {
        XCTAssertEqual(Host.normalizeHostIdToMac("AABBCCDDEEFF"),
                       "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(Host.normalizeHostIdToMac("aabbccddeeff"),
                       "AA:BB:CC:DD:EE:FF",
                       "lowercase hex must uppercase")
    }

    func testHostIdRejectsNonHex() {
        XCTAssertEqual(Host.normalizeHostIdToMac("XXXXXXXXXXXX"), "")
        XCTAssertEqual(Host.normalizeHostIdToMac("AABB"), "",
                       "Wrong length must yield empty")
        XCTAssertEqual(Host.normalizeHostIdToMac("AA:BB:CC:DD:EE:FF"), "",
                       "Already-formatted MAC isn't 12 chars")
    }

    // MARK: - Bridge POD → Host conversion

    /// Build a synthetic ChiakiDiscoveryHost-equivalent and verify the Host
    /// init pulls all fields out correctly.
    func testHostFromBridgeSnapshotPopulatesAllFields() {
        let hostId = "112233445566"
        let nickname = "Living Room PS5"
        let ip = "192.168.1.42"
        let app = "Astro Bot"
        let titleId = "PPSA01100_00"

        hostId.withCString { hostIdC in
            nickname.withCString { nicknameC in
                ip.withCString { ipC in
                    app.withCString { appC in
                        titleId.withCString { titleIdC in
                            var snap = chiaki_tv_discovery_host_t()
                            snap.state = CHIAKI_TV_DISCOVERY_HOST_STATE_READY
                            snap.host_request_port = 9295
                            snap.ps5 = true
                            snap.host_id = hostIdC
                            snap.host_name = nicknameC
                            snap.host_addr = ipC
                            snap.running_app_name = appC
                            snap.running_app_titleid = titleIdC

                            let host = Host(fromBridge: snap)
                            XCTAssertNotNil(host)
                            guard let host = host else { return }
                            XCTAssertEqual(host.id, "11:22:33:44:55:66")
                            XCTAssertEqual(host.mac, "11:22:33:44:55:66")
                            XCTAssertEqual(host.nickname, nickname)
                            XCTAssertEqual(host.ipAddress, ip)
                            XCTAssertEqual(host.runningApp, app)
                            XCTAssertEqual(host.titleId, titleId)
                            XCTAssertEqual(host.state, .ready)
                            XCTAssertTrue(host.ps5)
                            XCTAssertTrue(host.discovered)
                            XCTAssertFalse(host.registered)
                            XCTAssertFalse(host.manual)
                        }
                    }
                }
            }
        }
    }

    func testHostFromBridgeSnapshotMapsStandbyState() {
        "AABBCCDDEEFF".withCString { idC in
            var snap = chiaki_tv_discovery_host_t()
            snap.state = CHIAKI_TV_DISCOVERY_HOST_STATE_STANDBY
            snap.host_id = idC
            let host = Host(fromBridge: snap)
            XCTAssertEqual(host?.state, .standby)
        }
    }

    func testHostFromBridgeSnapshotReturnsNilWhenIdMissing() {
        var snap = chiaki_tv_discovery_host_t()
        // host_id left NULL — chiaki-lib treats this as a malformed host
        // (see lib/src/discoveryservice.c:312–317).
        XCTAssertNil(Host(fromBridge: snap))
    }

    func testHostFromBridgeSnapshotFallsBackToRawIdWhenNotMacShape() {
        // Some discovery responses arrive with a non-MAC host_id during
        // pre-registration. We still surface them, just without the MAC
        // normalization. Use the raw id as `id` and `mac` is empty.
        "non-mac-id".withCString { idC in
            var snap = chiaki_tv_discovery_host_t()
            snap.host_id = idC
            let host = Host(fromBridge: snap)
            XCTAssertNotNil(host)
            XCTAssertEqual(host?.id, "non-mac-id")
            XCTAssertEqual(host?.mac, "")
        }
    }

    // MARK: - AppState wiring

    func testAppStateMirrorsDiscoveryServiceHosts() async {
        let svc = DiscoveryService()
        let state = AppState(discoveryService: svc)
        XCTAssertEqual(state.hosts, [])

        // Push a host into the service directly (bypass C callback path —
        // we're testing the Observation-driven mirror in AppState, not the
        // bridge). The mirror runs as a `withObservationTracking` recursive
        // re-arm scheduled on the main actor; allow the run loop to spin
        // before reading the mirrored value.
        let mockHost = Host.previewReady
        svc.injectForTest(hosts: [mockHost])

        // Yield until the mirror fires (or fail after a generous timeout).
        let deadline = Date().addingTimeInterval(0.5)
        while state.hosts.first?.id != mockHost.id, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(state.hosts.first?.id, mockHost.id)
    }

    func testToggleDiscoveryEnabledStartsAndStopsService() {
        let svc = DiscoveryService()
        let state = AppState(discoveryService: svc)
        XCTAssertFalse(svc.isRunning,
                       "init must not autostart — bootstrap is explicit")

        // Flip toggle off → no change (was off)
        state.discoveryEnabled = false
        XCTAssertFalse(svc.isRunning)

        // Flip on → start
        state.discoveryEnabled = true
        XCTAssertTrue(svc.isRunning)

        // Flip off → stop
        state.discoveryEnabled = false
        XCTAssertFalse(svc.isRunning)
    }
}
