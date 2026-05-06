// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ChiakiBridgeC

/// Drives `chiaki_tv_regist_*`. One registration attempt at a time; on
/// success persists a `RegisteredHost` via `RegisteredHostStore` and exposes
/// the result via `state`.
///
/// PSN account ID comes from `AppSettings.psnAccountId` (base64). The PIN is
/// what the PS5 displays on screen during pairing setup.
///
/// References:
///   - C bridge: `ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_regist.h`
///   - Desktop reference: `gui/src/qmlregist.cpp`, `gui/src/registdialog.cpp`
@MainActor
@Observable
final class RegistrationService {

    enum State: Equatable {
        case idle
        case running
        case succeeded(RegisteredHost)
        case failed(String)
        case canceled
    }

    private(set) var state: State = .idle

    // C-bridge plumbing — not observable. `@ObservationIgnored` keeps these
    // out of the `@Observable` tracking machinery so `deinit` (nonisolated)
    // can read them during teardown.
    @ObservationIgnored private var handle: OpaquePointer?
    @ObservationIgnored private var selfRetained: Unmanaged<RegistrationService>?

    /// In-progress host used by the C callback to fill out RegisteredHost.
    /// Set in `start`, cleared on completion.
    @ObservationIgnored private var pendingHost: Host?

    init() {}

    deinit {
        if let h = handle { chiaki_tv_regist_destroy(h) }
        selfRetained?.release()
    }

    // MARK: - Public API

    /// Starts a registration attempt. Returns immediately; observe `state`
    /// for completion. Cancels any prior attempt.
    func start(host: Host, pin: String, psnAccountIdBase64: String) {
        cancel()

        guard let pinValue = UInt32(pin) else {
            state = .failed("PIN must be numeric (\(pin))")
            return
        }

        guard let accountIdBytes = Self.decodePsnAccountId(psnAccountIdBase64) else {
            state = .failed("PSN account ID must be 8 bytes after base64 decode")
            return
        }

        pendingHost = host
        state = .running

        let retained = Unmanaged.passRetained(self)
        selfRetained = retained

        let target = chiaki_tv_target_ps5_1()

        let svc: OpaquePointer? = host.ipAddress.withCString { (ipC: UnsafePointer<CChar>) -> OpaquePointer? in
            accountIdBytes.withUnsafeBytes { (acctRaw: UnsafeRawBufferPointer) -> OpaquePointer? in
                guard let acctBase = acctRaw.bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return chiaki_tv_regist_start(
                    ipC, target, /*broadcast=*/ false,
                    acctBase,
                    pinValue,
                    /*console_pin=*/ 0,
                    Self.cCallback,
                    retained.toOpaque()
                )
            }
        }

        guard let svc = svc else {
            retained.release()
            selfRetained = nil
            pendingHost = nil
            state = .failed("Failed to start registration (chiaki_tv_regist_start returned NULL)")
            return
        }

        handle = svc
        chiakiLog("RegistrationService: started against \(host.ipAddress)",
                  category: .session, type: .info)
    }

    func cancel() {
        if let h = handle {
            chiaki_tv_regist_stop(h)
            chiaki_tv_regist_destroy(h)
            handle = nil
        }
        selfRetained?.release()
        selfRetained = nil
        pendingHost = nil
        if state == .running {
            state = .canceled
        }
    }

    /// Reset back to idle after the consumer has observed a terminal state.
    func acknowledge() {
        switch state {
        case .running, .idle:
            return
        default:
            state = .idle
        }
    }

    // MARK: - C callback plumbing

    private static let cCallback: @convention(c) (
        chiaki_tv_regist_event_type_t,
        UnsafePointer<chiaki_tv_regist_success_t>?,
        UnsafeMutableRawPointer?
    ) -> Void = { eventType, successPtr, userPtr in
        guard let userPtr = userPtr else { return }
        let me = Unmanaged<RegistrationService>.fromOpaque(userPtr).takeUnretainedValue()

        // Snapshot the success struct synchronously before returning — chiaki
        // stack-allocates it for the duration of the callback.
        let snapshot: chiaki_tv_regist_success_t? = successPtr?.pointee

        Task { @MainActor in
            me.handleEvent(eventType: eventType, success: snapshot)
        }
    }

    private func handleEvent(
        eventType: chiaki_tv_regist_event_type_t,
        success: chiaki_tv_regist_success_t?
    ) {
        defer {
            handle = nil
            selfRetained?.release()
            selfRetained = nil
            // Don't free `handle` here — chiaki finalize-on-thread-exit happens via
            // the destroy call we make on cancel/destroy. The handle pointer is
            // moot after the callback fires (the regist thread has exited), so
            // just drop our reference.
        }

        let pendingHost = self.pendingHost
        self.pendingHost = nil

        switch eventType {
        case CHIAKI_TV_REGIST_EVENT_SUCCESS:
            guard let success = success, let host = pendingHost else {
                state = .failed("Registration succeeded but the success snapshot was missing")
                return
            }
            let registered = Self.makeRegisteredHost(from: success, host: host)
            RegisteredHostStore.upsert(registered)
            chiakiLog("RegistrationService: paired '\(registered.nickname)' (mac=\(registered.mac))",
                      category: .session, type: .info)
            state = .succeeded(registered)

        case CHIAKI_TV_REGIST_EVENT_CANCELED:
            chiakiLog("RegistrationService: canceled", category: .session, type: .info)
            state = .canceled

        case CHIAKI_TV_REGIST_EVENT_FAILED:
            chiakiLog("RegistrationService: failed", category: .session, type: .error)
            state = .failed("Registration failed — check the PIN, account ID, and that the PS5 has Remote Play enabled.")

        default:
            chiakiLog("RegistrationService: unknown event \(eventType)",
                      category: .session, type: .error)
            state = .failed("Registration finished with an unexpected event")
        }
    }

    // MARK: - Conversions

    /// Decode an 8-byte PSN account ID from its base64 representation.
    /// Returns nil if the string is malformed or the result isn't exactly 8 bytes.
    static func decodePsnAccountId(_ base64: String) -> Data? {
        guard let data = Data(base64Encoded: base64),
              data.count == 8 else { return nil }
        return data
    }

    private static func makeRegisteredHost(
        from success: chiaki_tv_regist_success_t,
        host: Host
    ) -> RegisteredHost {
        // server_mac → "AA:BB:CC:DD:EE:FF"
        let macHex = withUnsafeBytes(of: success.server_mac) { ptr -> String in
            let bytes = ptr.bindMemory(to: UInt8.self)
            return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        }

        // server_nickname is NUL-padded fixed buffer.
        let nickname = withUnsafeBytes(of: success.server_nickname) { ptr -> String in
            let bytes = ptr.bindMemory(to: CChar.self)
            return String(cString: bytes.baseAddress!)
        }

        let rpRegistKey = withUnsafeBytes(of: success.rp_regist_key) { ptr -> Data in
            Data(bytes: ptr.baseAddress!, count: ptr.count)
        }
        let rpKey = withUnsafeBytes(of: success.rp_key) { ptr -> Data in
            Data(bytes: ptr.baseAddress!, count: ptr.count)
        }

        return RegisteredHost(
            nickname: nickname.isEmpty ? host.nickname : nickname,
            mac: macHex,
            targetVersion: Int(success.target),
            rpKeyBase64: rpKey.base64EncodedString(),
            rpRegistKeyBase64: rpRegistKey.base64EncodedString(),
            lastIpAddress: host.ipAddress,
            consolePin: success.console_pin == 0 ? nil : String(success.console_pin)
        )
    }
}
