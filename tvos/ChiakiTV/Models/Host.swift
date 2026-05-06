// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Visible state of a PS5 on the LAN. Mirrors the desktop's
/// gui/include/host.h `HostMAC + RegisteredHost + DiscoveryHost` projection
/// onto the `Chiaki.hosts` model the QML consumes.
struct Host: Identifiable, Codable, Equatable, Hashable {

    enum State: String, Codable {
        case ready          // PS5 powered on, accepting connections
        case standby        // PS5 in rest mode (Wake-on-LAN target)
        case unknown
    }

    /// Stable identifier (host_id from discovery, or a deterministic UUID for
    /// manual hosts).
    let id: String

    /// User-facing label (PS5's serverNickname).
    var nickname: String

    /// Last-known IP address.
    var ipAddress: String

    /// MAC address (xx:xx:xx:xx:xx:xx). Empty for manual-only hosts pre-discovery.
    var mac: String

    /// PS5 = true; PS4 is dropped from this port (see decisions.md).
    var ps5: Bool

    /// Has this host been paired (have we run registration with a PIN)?
    var registered: Bool

    /// Was this host added manually (vs. discovered)?
    var manual: Bool

    /// Was this host discovered on the LAN this run?
    var discovered: Bool

    /// Current power state.
    var state: State

    /// Currently-running app on the PS5 (when discovered & ready).
    var runningApp: String?

    /// Title ID of the currently-running app.
    var titleId: String?

    init(id: String,
         nickname: String,
         ipAddress: String,
         mac: String = "",
         ps5: Bool = true,
         registered: Bool = false,
         manual: Bool = false,
         discovered: Bool = false,
         state: State = .unknown,
         runningApp: String? = nil,
         titleId: String? = nil) {
        self.id = id
        self.nickname = nickname
        self.ipAddress = ipAddress
        self.mac = mac
        self.ps5 = ps5
        self.registered = registered
        self.manual = manual
        self.discovered = discovered
        self.state = state
        self.runningApp = runningApp
        self.titleId = titleId
    }
}

// MARK: - Mock factories (Phase 0 only — replaced by chiaki-lib in Phase 1)

extension Host {

    static let previewReady = Host(
        id: "mock-ready",
        nickname: "Living Room PS5",
        ipAddress: "192.168.1.42",
        mac: "11:22:33:44:55:66",
        ps5: true,
        registered: true,
        manual: false,
        discovered: true,
        state: .ready,
        runningApp: "Astro Bot",
        titleId: "PPSA01100_00")

    static let previewStandby = Host(
        id: "mock-standby",
        nickname: "Bedroom PS5",
        ipAddress: "192.168.1.51",
        mac: "11:22:33:44:55:77",
        ps5: true,
        registered: true,
        manual: false,
        discovered: false,
        state: .standby)

    static let previewManual = Host(
        id: "mock-manual",
        nickname: "Manual Host",
        ipAddress: "192.168.1.60",
        mac: "",
        ps5: true,
        registered: false,
        manual: true,
        discovered: false,
        state: .unknown)

    static let previewSet: [Host] = [previewReady, previewStandby, previewManual]
}
