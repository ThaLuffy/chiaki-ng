// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// PS5 registration sheet — `.sheet(item:)` over the host list with a
/// `SheetChrome` top bar and a `Form` body. PSN Account-ID is read-only
/// here (editing happens in Settings → App).
struct RegistrationView: View {
    @Environment(AppState.self) private var appState
    let host: Host

    @State private var pin: String = "00000000"

    private var isValid: Bool {
        let pinOK = pin.count == 8 && pin.allSatisfy(\.isNumber) && pin != "00000000"
        let accountOK = !appState.settings.psnAccountId.isEmpty
        return pinOK && accountOK
    }

    private var isRunning: Bool {
        if case .running = appState.registrationService.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetChrome(
                title: "Register Console",
                cancel: ("Cancel", { appState.dismissSheet() }),
                confirm: (isRunning ? "Registering…" : "Register",
                          isEnabled: isValid && !isRunning,
                          {
                              appState.registrationService.start(
                                  host: host,
                                  pin: pin,
                                  psnAccountIdBase64: appState.settings.psnAccountId
                              )
                          })
            )

            Form {
                Section {
                    LabeledContent("Host") {
                        Text(host.ipAddress.isEmpty ? host.nickname : host.ipAddress)
                            .font(Theme.font(.mono))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Console") {
                        Text("PlayStation 5")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("PSN Account-ID") {
                        Text(appState.settings.psnAccountId.isEmpty
                             ? "Set this in Settings → App"
                             : appState.settings.psnAccountId)
                            .font(Theme.font(.mono))
                            .foregroundStyle(appState.settings.psnAccountId.isEmpty
                                             ? Theme.rose500 : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } header: {
                    Text("Console")
                }

                Section {
                    HStack {
                        Spacer()
                        ChiakiDigitPicker(value: $pin, length: 8)
                        Spacer()
                    }
                } header: {
                    Text("Remote Play PIN")
                } footer: {
                    Text("Find this on your PS5: Settings → System → Remote Play → Link Device.")
                }

                if let msg = statusMessage {
                    Section {
                        Label(msg, systemImage: statusGlyph)
                            .foregroundStyle(statusColor)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: appState.registrationService.state) { _, new in
            if case .succeeded = new {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    appState.registrationService.acknowledge()
                    appState.dismissSheet()
                }
            }
        }
    }

    private var statusMessage: String? {
        switch appState.registrationService.state {
        case .idle:             return nil
        case .running:          return "Registering against \(host.ipAddress)…"
        case .succeeded(let h): return "Paired '\(h.nickname)'."
        case .failed(let msg):  return msg
        case .canceled:         return "Canceled."
        }
    }

    private var statusGlyph: String {
        switch appState.registrationService.state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        case .running:   return "arrow.triangle.2.circlepath"
        default:         return "info.circle"
        }
    }

    private var statusColor: Color {
        switch appState.registrationService.state {
        case .succeeded: return Theme.green500
        case .failed:    return Theme.rose500
        default:         return .secondary
        }
    }
}

#Preview {
    RegistrationView(host: .previewReady)
        .environment(AppState.preview())
}
