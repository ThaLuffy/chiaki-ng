// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
import ChiakiBridgeC
@testable import ChiakiTV

/// Phase 0 round-trip tests for the three Codable model types. They guard
/// against accidental field renames / removals that would break Phase 1's
/// on-disk persistence (settings.json, registered_hosts.json).
final class ModelCodableTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    // MARK: - Host

    func testHostRoundTrip() throws {
        let host = Host.previewReady
        let data = try encoder.encode(host)
        let decoded = try decoder.decode(Host.self, from: data)
        XCTAssertEqual(host, decoded)
    }

    func testHostManualEncoding() throws {
        let manual = Host.previewManual
        let data = try encoder.encode(manual)
        let decoded = try decoder.decode(Host.self, from: data)
        XCTAssertEqual(decoded.manual, true)
        XCTAssertEqual(decoded.registered, false)
        XCTAssertEqual(decoded.state, .unknown)
    }

    // MARK: - RegisteredHost

    func testRegisteredHostRoundTrip() throws {
        let rh = RegisteredHost(
            nickname: "Living Room PS5",
            mac: "11:22:33:44:55:66",
            targetVersion: 1_000_100,
            rpKeyBase64: "AAAAAAAAAAAAAAAAAAAAAA==",
            rpRegistKeyBase64: "BBBBBBBBBBBBBBBBBBBBBB==",
            lastIpAddress: "192.168.1.42",
            consolePin: "0000"
        )
        let data = try encoder.encode(rh)
        let decoded = try decoder.decode(RegisteredHost.self, from: data)
        XCTAssertEqual(rh, decoded)
        XCTAssertEqual(decoded.id, "11:22:33:44:55:66",
                       "RegisteredHost.id is derived from .mac")
    }

    func testRegisteredHostNilConsolePin() throws {
        let rh = RegisteredHost(
            nickname: "Bedroom PS5",
            mac: "aa:bb:cc:dd:ee:ff",
            targetVersion: 1_000_100,
            rpKeyBase64: "x",
            rpRegistKeyBase64: "y",
            lastIpAddress: "10.0.0.1",
            consolePin: nil
        )
        let data = try encoder.encode(rh)
        let decoded = try decoder.decode(RegisteredHost.self, from: data)
        XCTAssertNil(decoded.consolePin)
    }

    // MARK: - AppSettings

    func testAppSettingsDefaultsRoundTrip() throws {
        let s = AppSettings()
        let data = try encoder.encode(s)
        let decoded = try decoder.decode(AppSettings.self, from: data)
        XCTAssertEqual(s, decoded)
    }

    func testAppSettingsKnownDefaults() {
        // Anchor a few documented defaults so accidental changes are flagged.
        let s = AppSettings()
        XCTAssertEqual(s.audioBufferMs, 80,
                       "Audio buffer default is 80ms — see docs/architecture/audio-pipeline.md")
        XCTAssertEqual(s.bitrateKbps, 15_000)
        XCTAssertEqual(s.fps, .fps60)
        XCTAssertEqual(s.resolution, .res1080p)
        XCTAssertEqual(s.codec, .h265)
        XCTAssertEqual(s.renderPreset, .highQuality)
        XCTAssertEqual(s.audioVolume, 100)
        XCTAssertTrue(s.verticalSync)
        XCTAssertTrue(s.showStreamStats,
                      "In-stream telemetry HUD defaults to on.")
    }

    // MARK: - Bridge → chiaki-lib link smoke test

    /// `chiaki_tv_lib_version_packed()` calls `chiaki_log_level_char(INFO)`
    /// from upstream chiaki-lib. If the link is broken, the test won't
    /// compile or the runtime returns 0. The expected packed value is
    /// (0xCA << 24) | (1 << 16) | 'I' = 0xCA01_0049.
    func testChiakiLibIsLinked() {
        let packed = chiaki_tv_lib_version_packed()
        XCTAssertEqual(packed >> 24, 0xCA, "tag byte")
        XCTAssertEqual((packed >> 16) & 0xFF, 1,
                       "CHIAKI_LIB_ENABLE_OPUS expected to be 1")
        XCTAssertEqual(packed & 0xFF, UInt32(Character("I").asciiValue!),
                       "chiaki_log_level_char(INFO) returns 'I'")
    }
}
