// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import ChiakiTV

/// Round-trip tests for `SettingsStore` and `RegisteredHostStore`. Both back
/// onto `UserDefaults.standard` — `JSONFileStore.reset()` between tests keeps
/// them isolated.
@MainActor
final class PersistenceTests: XCTestCase {

    override func setUp() async throws {
        JSONFileStore.reset()
    }

    override func tearDown() async throws {
        JSONFileStore.reset()
    }

    // MARK: - SettingsStore

    func testSettingsLoadDefaultsWhenFileMissing() {
        let s = SettingsStore.load()
        XCTAssertEqual(s, AppSettings(),
                       "Missing settings.json must yield struct defaults.")
    }

    func testSettingsRoundTrip() {
        var s = AppSettings()
        s.psnAccountId = "AAAAAAAAAAAAAAAA=="
        s.bitrateKbps  = 25_000
        s.fps          = .fps30
        s.codec        = .h265hdr
        s.audioBufferMs = 120
        s.showStreamStats = false

        SettingsStore.save(s)
        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded, s)
    }

    /// Adding new fields with defaults must NOT break a settings blob written
    /// before that field existed. Simulate by injecting a stripped JSON
    /// payload directly into UserDefaults and verifying decode falls back to
    /// the struct's defaults for missing fields.
    func testSettingsForwardCompatibleDecode() throws {
        // Note: `showStreamStats` is intentionally omitted to exercise the
        // missing-field → default path. The struct default is `true`.
        let legacyJSON = """
        {
          "audioBufferMs": 100,
          "audioVolume": 90,
          "audioVideoMode": "both",
          "actionOnDisconnect": "askConfirm",
          "actionOnSuspend": "disconnect",
          "bitrateKbps": 20000,
          "codec": "h265",
          "fps": 60,
          "packetLossReportedMax": 3,
          "psnAccountId": "",
          "renderPreset": "highQuality",
          "resolution": "res1080p",
          "streamerMode": false,
          "verboseLogs": false,
          "verticalSync": true,
          "weakWifiThresholdPct": 5
        }
        """
        JSONFileStore.defaults.set(Data(legacyJSON.utf8),
                                   forKey: SettingsStore.filename)

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.bitrateKbps, 20_000)
        XCTAssertEqual(loaded.audioBufferMs, 100)
        XCTAssertEqual(loaded.showStreamStats, true,
                       "Field absent from legacy file — struct default (true) must apply.")
    }

    // MARK: - RegisteredHostStore

    func testRegisteredHostsEmptyOnFirstLaunch() {
        XCTAssertEqual(RegisteredHostStore.load(), [])
    }

    func testRegisteredHostsRoundTrip() {
        let a = RegisteredHost(
            nickname: "Living Room PS5", mac: "11:22:33:44:55:66",
            targetVersion: 1_000_100,
            rpKeyBase64: "k1", rpRegistKeyBase64: "r1",
            lastIpAddress: "192.168.1.42", consolePin: "0000")

        let b = RegisteredHost(
            nickname: "Bedroom PS5", mac: "aa:bb:cc:dd:ee:ff",
            targetVersion: 1_000_100,
            rpKeyBase64: "k2", rpRegistKeyBase64: "r2",
            lastIpAddress: "192.168.1.51", consolePin: nil)

        RegisteredHostStore.save([a, b])
        XCTAssertEqual(RegisteredHostStore.load(), [a, b])
    }

    func testRegisteredHostsUpsertReplacesExistingByMac() {
        let original = RegisteredHost(
            nickname: "PS5", mac: "11:22:33:44:55:66",
            targetVersion: 1_000_100,
            rpKeyBase64: "k1", rpRegistKeyBase64: "r1",
            lastIpAddress: "10.0.0.1", consolePin: nil)
        RegisteredHostStore.upsert(original)

        // Same MAC, but the nickname + IP have changed.
        let updated = RegisteredHost(
            nickname: "Renamed PS5", mac: "11:22:33:44:55:66",
            targetVersion: 1_000_100,
            rpKeyBase64: "k1", rpRegistKeyBase64: "r1",
            lastIpAddress: "10.0.0.99", consolePin: nil)
        RegisteredHostStore.upsert(updated)

        let loaded = RegisteredHostStore.load()
        XCTAssertEqual(loaded.count, 1, "Upsert by MAC must not duplicate.")
        XCTAssertEqual(loaded.first?.nickname, "Renamed PS5")
        XCTAssertEqual(loaded.first?.lastIpAddress, "10.0.0.99")
    }

    func testRegisteredHostsRemoveById() {
        let a = RegisteredHost(
            nickname: "A", mac: "aa:aa:aa:aa:aa:aa",
            targetVersion: 1_000_100, rpKeyBase64: "x",
            rpRegistKeyBase64: "y", lastIpAddress: "10.0.0.1",
            consolePin: nil)
        let b = RegisteredHost(
            nickname: "B", mac: "bb:bb:bb:bb:bb:bb",
            targetVersion: 1_000_100, rpKeyBase64: "x",
            rpRegistKeyBase64: "y", lastIpAddress: "10.0.0.2",
            consolePin: nil)

        RegisteredHostStore.save([a, b])
        RegisteredHostStore.remove(id: a.id)

        XCTAssertEqual(RegisteredHostStore.load(), [b])
    }

    // MARK: - AppState integration

    func testAppStateAutoSavesSettingsOnMutation() {
        let state = AppState()
        XCTAssertEqual(state.settings.bitrateKbps, 15_000)

        state.settings.bitrateKbps = 22_500

        // The Combine sink dispatches on the next runloop turn — let it run.
        let exp = expectation(description: "settings persisted")
        DispatchQueue.main.async {
            let reloaded = SettingsStore.load()
            XCTAssertEqual(reloaded.bitrateKbps, 22_500)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testAppStateAutoSavesRegisteredHostsOnMutation() {
        let state = AppState()
        XCTAssertEqual(state.registeredHosts, [])

        let host = RegisteredHost(
            nickname: "P", mac: "00:00:00:00:00:01",
            targetVersion: 1_000_100, rpKeyBase64: "r",
            rpRegistKeyBase64: "k", lastIpAddress: "10.0.0.1",
            consolePin: nil)
        state.registeredHosts.append(host)

        let exp = expectation(description: "hosts persisted")
        DispatchQueue.main.async {
            XCTAssertEqual(RegisteredHostStore.load(), [host])
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testAppStateLoadsHydratedValuesOnInit() {
        // Simulate a previous session having saved state.
        var s = AppSettings()
        s.bitrateKbps = 33_000
        SettingsStore.save(s)

        let host = RegisteredHost(
            nickname: "Persistent", mac: "00:00:00:00:00:02",
            targetVersion: 1_000_100, rpKeyBase64: "r",
            rpRegistKeyBase64: "k", lastIpAddress: "10.0.0.2",
            consolePin: nil)
        RegisteredHostStore.save([host])

        // New AppState constructed after the writes above must rehydrate.
        let state = AppState()
        XCTAssertEqual(state.settings.bitrateKbps, 33_000)
        XCTAssertEqual(state.registeredHosts, [host])
    }
}
