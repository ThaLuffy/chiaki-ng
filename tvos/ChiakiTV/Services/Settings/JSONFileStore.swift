// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// JSON-encoded blob persistence backed by `UserDefaults`. Both `SettingsStore`
/// and `RegisteredHostStore` share this base — the only per-store concerns are
/// the defaults key and the model type.
///
/// Why not files: tvOS sandboxes `Library/Application Support/` and
/// `Library/Documents/` as read-only on real hardware (works on the simulator
/// because that's a Mac process). Persistent app state must live in
/// `UserDefaults` or `NSUbiquitousKeyValueStore`. We keep JSON encoding so
/// the on-defaults shape stays diffable when dumping the plist.
///
/// Keys reuse the legacy filenames (`settings.json`, `registered_hosts.json`)
/// so the rest of the codebase didn't have to change. New fields added to the
/// model types are non-breaking on read because `JSONDecoder` falls back to
/// the struct's default values for missing fields.
enum JSONFileStore {

    static var defaults: UserDefaults { .standard }

    /// Decode `T` from the value stored under `key`. Returns `nil` if no data
    /// has been written yet; throws on decode failure.
    static func read<T: Decodable>(_ type: T.Type, from key: String) throws -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Encode `value` and store under `key`. Pretty-printed + sorted keys for
    /// diff readability when the plist is dumped during debugging.
    static func write<T: Encodable>(_ value: T, to key: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        defaults.set(data, forKey: key)
    }

    /// Test helper. Removes both store keys.
    static func reset() {
        defaults.removeObject(forKey: SettingsStore.filename)
        defaults.removeObject(forKey: RegisteredHostStore.filename)
    }
}
