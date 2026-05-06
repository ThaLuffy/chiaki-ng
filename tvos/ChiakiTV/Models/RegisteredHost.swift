// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// A successfully-paired PS5. Produced by the registration flow
/// (chiaki-lib's `chiaki_regist_start` →
/// [`gui/include/host.h:RegisteredHost`](../../../gui/include/host.h)).
///
/// Phase 0 stores this in-memory; Phase 1 persists it as JSON in
/// `Application Support/ChiakiTV/registered_hosts.json` keyed by `mac`.
struct RegisteredHost: Codable, Identifiable, Equatable, Hashable {

    /// Matches `Host.id`.
    var id: String { mac }

    /// PS5 server nickname.
    var nickname: String

    /// MAC address — used as the durable identity.
    var mac: String

    /// PS5 firmware target enum value (we only persist PS5 / `1000100` for now).
    var targetVersion: Int

    /// 16-byte RP key, base64-encoded.
    var rpKeyBase64: String

    /// 16-byte RP regist key, base64-encoded.
    var rpRegistKeyBase64: String

    /// Last-known LAN IP (cached for one-tap connect).
    var lastIpAddress: String

    /// Optional console PIN (4 digits) — used by some PS5 firmware versions.
    var consolePin: String?

    /// Wake-on-LAN credential. Derives the chiaki wakeup hex from
    /// `rpRegistKeyBase64` the same way the desktop does in
    /// [`gui/src/discoverymanager.cpp:275-292`](../../../gui/src/discoverymanager.cpp):
    /// the regist key bytes are stored as ASCII hex; trim at the first
    /// NUL terminator and take up to the first 8 chars (chiaki widens to
    /// `uint64`). Returns `""` if the stored key isn't decodable as ASCII
    /// hex — the bridge's `chiaki_tv_discovery_service_send_wakeup` rejects
    /// the empty string explicitly.
    var wakeCredentialHex: String {
        guard let raw = Data(base64Encoded: rpRegistKeyBase64), !raw.isEmpty else {
            return ""
        }
        let trimmed: [UInt8] = {
            var bytes = [UInt8](raw)
            if let nul = bytes.firstIndex(of: 0) { bytes.removeSubrange(nul...) }
            return bytes
        }()
        guard let str = String(bytes: trimmed, encoding: .utf8) else { return "" }
        return String(str.prefix(8))
    }
}
