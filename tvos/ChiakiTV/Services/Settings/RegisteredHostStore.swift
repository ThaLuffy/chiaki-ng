// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import OSLog

/// Persistence for registered consoles to
/// `Application Support/ChiakiTV/registered_hosts.json`.
///
/// Keyed by `RegisteredHost.id` (= MAC address). Phase 1's registration flow
/// calls `add(_:)` once `chiaki_regist_finished` succeeds; the manual-host /
/// host-list paths read via `all()`.
///
/// Storage shape on disk: an array of `RegisteredHost`. We keep it as an
/// array (not a dict) so the file is greppable in support cases.
enum RegisteredHostStore {

    static let filename = "registered_hosts.json"

    /// Load every registered host. Returns `[]` on first launch or any
    /// decode failure (logged, not surfaced).
    static func load() -> [RegisteredHost] {
        do {
            if let saved = try JSONFileStore.read([RegisteredHost].self, from: filename) {
                return saved
            }
        } catch {
            chiakiLog("registered_hosts.json decode failed: \(error). Resetting list.",
                      category: .session, type: .error)
        }
        return []
    }

    /// Atomic write of the full list.
    static func save(_ hosts: [RegisteredHost]) {
        do {
            try JSONFileStore.write(hosts, to: filename)
        } catch {
            chiakiLog("registered_hosts.json write failed: \(error)",
                      category: .session, type: .error)
        }
    }

    /// Insert or update by `id` (MAC). The desktop's `RegisteredHost` is
    /// keyed the same way (`HostMAC`). Phase 1 calls this from the
    /// registration callback.
    static func upsert(_ host: RegisteredHost) {
        var list = load()
        if let i = list.firstIndex(where: { $0.id == host.id }) {
            list[i] = host
        } else {
            list.append(host)
        }
        save(list)
    }

    /// Remove by `id` (MAC).
    static func remove(id: String) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }
}
