// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import OSLog

/// Persistence for `AppSettings` to `Application Support/ChiakiTV/settings.json`.
///
/// Mirrors the desktop's `gui/src/settings.cpp` behavior, minus the `QSettings`
/// abstraction — Codable JSON is enough for personal-use scope. New fields
/// added to `AppSettings` are non-breaking on read because `JSONDecoder`
/// fills missing fields from the struct's default values.
enum SettingsStore {

    static let filename = "settings.json"

    /// Load saved settings, or return `AppSettings()` defaults on first launch
    /// or any decode failure. Decode failure is logged but not surfaced — a
    /// corrupted settings file shouldn't block the app from starting.
    static func load() -> AppSettings {
        do {
            if let saved = try JSONFileStore.read(AppSettings.self, from: filename) {
                return saved
            }
        } catch {
            chiakiLog("settings.json decode failed: \(error). Using defaults.",
                      category: .session, type: .error)
        }
        return AppSettings()
    }

    /// Atomic write. Errors are logged and swallowed — failure to persist
    /// settings shouldn't crash the app or block UI changes.
    static func save(_ settings: AppSettings) {
        do {
            try JSONFileStore.write(settings, to: filename)
        } catch {
            chiakiLog("settings.json write failed: \(error)",
                      category: .session, type: .error)
        }
    }
}
