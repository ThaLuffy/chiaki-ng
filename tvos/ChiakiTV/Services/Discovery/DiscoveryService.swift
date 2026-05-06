// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ChiakiBridgeC

/// Drives the C bridge's `chiaki_tv_discovery_service_t` and surfaces the
/// host snapshots as a `@Published [Host]` so views can bind directly.
///
/// The bridge runs the upstream `ChiakiDiscoveryService` on its own thread and
/// fires callbacks from inside chiaki-lib's state mutex. We copy the C-string
/// fields into Swift `String` synchronously inside the callback (the pointers
/// die when the callback returns), then hop to MainActor to publish.
///
/// Lifecycle:
///   - `start()` creates the bridge handle. Idempotent.
///   - `stop()` destroys the bridge handle (joins the thread). Idempotent.
///   - `deinit` calls `stop()` to guarantee no callback fires after Swift releases.
///
/// References:
///   - `tvos/ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_discovery.h`
///   - `lib/include/chiaki/discoveryservice.h`
///   - `gui/src/discoverymanager.cpp` (desktop reference)
@MainActor
@Observable
final class DiscoveryService {

    /// Live, deduplicated host list. Each entry's `id` is the chiaki host_id
    /// (12-char hex MAC, normalized to `xx:xx:xx:xx:xx:xx`).
    private(set) var hosts: [Host] = []

    /// `true` while the bridge service is running.
    private(set) var isRunning: Bool = false

    // C-bridge plumbing — not view-observable. `@ObservationIgnored` keeps
    // these out of `@Observable` tracking so `deinit` (nonisolated) can read
    // them during teardown.
    @ObservationIgnored private var handle: OpaquePointer?

    /// Strong reference passed to the C bridge as `cb_user`. We hold the
    /// matching Unmanaged so we can balance retain/release across start/stop.
    @ObservationIgnored private var selfRetainedForCallback: Unmanaged<DiscoveryService>?

    init() {}

    deinit {
        // deinit is `nonisolated` — call the synchronous teardown directly.
        if let h = handle {
            chiaki_tv_discovery_service_destroy(h)
        }
        selfRetainedForCallback?.release()
    }

    func start() {
        guard handle == nil else { return }

        let retained = Unmanaged.passRetained(self)
        selfRetainedForCallback = retained

        let cb: @convention(c) (
            UnsafePointer<chiaki_tv_discovery_host_t>?,
            Int,
            UnsafeMutableRawPointer?
        ) -> Void = DiscoveryService.cCallback

        guard let svc = chiaki_tv_discovery_service_create(cb, retained.toOpaque()) else {
            chiakiLog("DiscoveryService: chiaki_tv_discovery_service_create failed",
                      category: .network, type: .error)
            retained.release()
            selfRetainedForCallback = nil
            return
        }

        handle = svc
        isRunning = true
        chiakiLog("DiscoveryService: started", category: .network, type: .info)
    }

    func stop() {
        guard let h = handle else { return }
        chiaki_tv_discovery_service_destroy(h)
        handle = nil
        selfRetainedForCallback?.release()
        selfRetainedForCallback = nil
        isRunning = false
        hosts = []
        chiakiLog("DiscoveryService: stopped", category: .network, type: .info)
    }

    /// Send a wakeup packet to the standby host. `regist_key_hex` is the
    /// 8-char (or shorter) hex string of the registration key; for a paired
    /// `RegisteredHost` the consumer is expected to derive it from
    /// `rpRegistKeyBase64`.
    func sendWakeup(hostIp: String, registKeyHex: String, ps5: Bool = true) -> Bool {
        return registKeyHex.withCString { keyCStr in
            hostIp.withCString { ipCStr in
                chiaki_tv_discovery_service_send_wakeup(ipCStr, keyCStr, ps5)
            }
        }
    }

    // MARK: - Callback plumbing

    /// `@convention(c)` callback. Runs on chiaki's discovery thread inside the
    /// state mutex. Copies snapshots into Swift values and hops to MainActor.
    private static let cCallback: @convention(c) (
        UnsafePointer<chiaki_tv_discovery_host_t>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void = { hostsPtr, count, userPtr in
        guard let userPtr = userPtr else { return }
        let me = Unmanaged<DiscoveryService>.fromOpaque(userPtr).takeUnretainedValue()

        var snapshot: [Host] = []
        snapshot.reserveCapacity(count)
        if let base = hostsPtr, count > 0 {
            let buf = UnsafeBufferPointer(start: base, count: count)
            for i in 0..<count {
                if let host = Host(fromBridge: buf[i]) {
                    snapshot.append(host)
                }
            }
        }

        // Hop to MainActor — `me` is MainActor-isolated, so we can't touch
        // its @Published properties on the discovery thread.
        Task { @MainActor [snapshot] in
            me.applyDiscoveredHosts(snapshot)
        }
    }

    private func applyDiscoveredHosts(_ discovered: [Host]) {
        guard isRunning else { return }
        // Diagnostic: confirm what chiaki-lib reported per host. Empty/0.0.0.0
        // here means the discovery socket received a packet whose source addr
        // didn't resolve — usually a freshly-woken PS5 mid-handshake.
        if hosts != discovered {
            for h in discovered {
                chiakiLog("DiscoveryService: host id=\(h.id) state=\(h.state) ip='\(h.ipAddress)' nick='\(h.nickname)'",
                          category: .network, type: .debug)
            }
        }
        hosts = discovered
    }

    // MARK: - Test seam

    /// Bypass the C bridge and push a host list directly through the
    /// MainActor-mirroring path. Used by unit tests so they can verify
    /// AppState mirroring without a real PS5.
    func injectForTest(hosts: [Host]) {
        isRunning = true
        self.hosts = hosts
    }
}

// MARK: - Bridge → Host conversion

extension Host {

    /// Build a Host from a bridge POD snapshot. Returns nil if `host_id` is
    /// missing — without it the host has no stable identity, so we skip it
    /// (matches chiaki-lib's own behavior in `discovery_service_host_received`).
    init?(fromBridge snap: chiaki_tv_discovery_host_t) {
        guard let hostIdCStr = snap.host_id else { return nil }
        let hostIdRaw = String(cString: hostIdCStr)
        let mac = Self.normalizeHostIdToMac(hostIdRaw)
        let nickname: String = {
            if let p = snap.host_name { return String(cString: p) }
            return mac.isEmpty ? hostIdRaw : mac
        }()
        let ipAddress: String = {
            if let p = snap.host_addr { return String(cString: p) }
            return ""
        }()
        let runningApp: String? = snap.running_app_name.map { String(cString: $0) }
        let titleId: String? = snap.running_app_titleid.map { String(cString: $0) }

        let state: Host.State = {
            switch snap.state {
            case CHIAKI_TV_DISCOVERY_HOST_STATE_READY:   return .ready
            case CHIAKI_TV_DISCOVERY_HOST_STATE_STANDBY: return .standby
            default:                                     return .unknown
            }
        }()

        self.init(
            id: mac.isEmpty ? hostIdRaw : mac,
            nickname: nickname,
            ipAddress: ipAddress,
            mac: mac,
            ps5: snap.ps5,
            registered: false,
            manual: false,
            discovered: true,
            state: state,
            runningApp: runningApp,
            titleId: titleId
        )
    }

    /// chiaki ships host_id as 12 hex chars without separators. Convert to
    /// the canonical `xx:xx:xx:xx:xx:xx` format we use everywhere else.
    /// Returns "" if the input isn't a 12-char hex string.
    static func normalizeHostIdToMac(_ raw: String) -> String {
        let cleaned = raw.uppercased()
        guard cleaned.count == 12, cleaned.allSatisfy({ $0.isHexDigit }) else {
            return ""
        }
        var out = ""
        out.reserveCapacity(17)
        for (i, ch) in cleaned.enumerated() {
            if i > 0, i % 2 == 0 { out.append(":") }
            out.append(ch)
        }
        return out
    }
}
