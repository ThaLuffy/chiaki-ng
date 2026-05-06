// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// PS5 registration sheet. Reskin per [`docs/ui/redesign-plan.md §5.7`](../../docs/ui/redesign-plan.md):
///
/// - Modal-style chrome instead of full-screen back-chevron toolbar.
/// - 8-digit Remote Play PIN entered via `ChiakiDigitPicker` (no keyboard).
/// - 4-digit Console PIN (optional) likewise.
/// - PSN Account-ID is read-only — display-only chip with a hint pointing
///   the user to Settings → App if they need to change it (resolves audit
///   issue D4).
struct RegistrationView: View {
    @Environment(AppState.self) private var appState
    let host: Host

    @State private var pin: String = "00000000"
    @State private var consolePin: String = "0000"
    @State private var useConsolePin: Bool = false

    private var isValid: Bool {
        let pinOK = pin.count == 8 && pin.allSatisfy(\.isNumber) && pin != "00000000"
        let cpinOK = !useConsolePin
            || (consolePin.count == 4 && consolePin.allSatisfy(\.isNumber))
        let accountOK = !appState.settings.psnAccountId.isEmpty
        return pinOK && cpinOK && accountOK
    }

    private var isRunning: Bool {
        if case .running = appState.registrationService.state { return true }
        return false
    }

    private var statusMessage: String? {
        switch appState.registrationService.state {
        case .idle:           return nil
        case .running:        return "Registering against \(host.ipAddress)…"
        case .succeeded(let h): return "Paired '\(h.nickname)'."
        case .failed(let msg):  return msg
        case .canceled:         return "Canceled."
        }
    }

    private var statusColor: Color {
        switch appState.registrationService.state {
        case .succeeded: return Theme.green500
        case .failed:    return Theme.rose500
        default:         return Theme.mist500
        }
    }

    var body: some View {
        ChiakiSheet(
            title: "Register Console",
            subtitle: "Pair this PS5 so future connections don't need a PIN.",
            onBack: { appState.showHostList() },
            content: {
                VStack(alignment: .leading, spacing: 22) {
                    summaryHeader

                    Divider().background(Theme.ink600)

                    pinField

                    if let msg = statusMessage {
                        statusLine(msg)
                    }
                }
                .frame(maxWidth: .infinity)
            },
            footer: {
                ChiakiSheetSecondaryButton(title: "Cancel",
                                           systemImage: "xmark") {
                    appState.showHostList()
                }
                ChiakiSheetPrimaryButton(
                    title: isRunning ? "Registering…" : "Register",
                    systemImage: "personalhotspot.circle.fill",
                    isEnabled: isValid && !isRunning
                ) {
                    appState.registrationService.start(
                        host: host,
                        pin: pin,
                        psnAccountIdBase64: appState.settings.psnAccountId
                    )
                }
            }
        )
        .onChange(of: appState.registrationService.state) { _, new in
            if case .succeeded = new {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    appState.registrationService.acknowledge()
                    appState.showHostList()
                }
            }
        }
    }

    // MARK: - Sections

    /// Read-only summary of what's about to be registered. PSN Account-ID
    /// is displayed but not editable here — it lives in Settings → App.
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow(label: "Host",
                       value: host.ipAddress.isEmpty ? host.nickname : host.ipAddress,
                       valueColor: Theme.mist300)
            summaryRow(label: "Console", value: "PlayStation 5",
                       valueColor: Theme.mist300)
            summaryRow(label: "PSN Account-ID",
                       value: appState.settings.psnAccountId.isEmpty
                              ? "Set this in Settings → App"
                              : appState.settings.psnAccountId,
                       valueColor: appState.settings.psnAccountId.isEmpty
                                   ? Theme.rose500 : Theme.mist300)
        }
    }

    private func summaryRow(label: String, value: String,
                            valueColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label.uppercased())
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.mist500)
                .tracking(1.2)
                .frame(width: 180, alignment: .leading)
            Text(value)
                .font(Theme.font(.monoMed))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
    }

    private var pinField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REMOTE PLAY PIN")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.mist500)
                .tracking(1.2)

            ChiakiDigitPicker(value: $pin, length: 8)

            Text("Find this on your PS5: Settings → System → Remote Play → Link Device.")
                .font(Theme.font(.bodySmall))
                .foregroundStyle(Theme.mist500)
                .italic()
        }
    }

    private func statusLine(_ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: statusGlyph)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusColor)
            Text(msg)
                .font(Theme.font(.bodyMed))
                .foregroundStyle(statusColor)
        }
        .padding(.top, 8)
    }

    private var statusGlyph: String {
        switch appState.registrationService.state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        case .running:   return "arrow.triangle.2.circlepath"
        default:         return "info.circle"
        }
    }
}

#Preview {
    RegistrationView(host: .previewReady)
        .environment(AppState.preview())
}
