// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// PS5 registration dialog. Mirrors the desktop's
/// [`gui/src/qml/RegistDialog.qml`](../../../gui/src/qml/RegistDialog.qml)
/// **slimmed for the LAN-only / PS5-only port**:
///
/// - PS4 firmware variants and the PS4 PSN-Online-ID field are dropped.
/// - The "PSN Login" + "Public Lookup" inline buttons are dropped — the
///   account ID is pulled from `AppSettings.psnAccountId` (prefilled).
///
/// Visible fields:
///   • Host (read-only)
///   • PSN Account-ID (from settings, read-only here)
///   • Remote Play PIN (8 digits)
///   • Console PIN (optional, 4 digits)
///
/// Phase 1: pressing Register kicks `RegistrationService.start(...)`. Live
/// state updates are surfaced inline; on success we route back to the host
/// list with the new RegisteredHost persisted.
struct RegistrationView: View {
    @Environment(AppState.self) private var appState
    let host: Host

    @State private var pin: String = ""
    @State private var consolePin: String = ""

    /// Identifies the focusable controls on this screen so we can drive
    /// initial focus via `.defaultFocus(...)`. tvOS's focus engine fights
    /// with `.textFieldStyle(.plain)` + custom backgrounds (it tries to
    /// attach a `_UIReplicantView` for the standard focus halo and warns
    /// when our layout swallows it), so the PIN row is a focusable Button
    /// that pops a system `.alert` containing the actual `TextField`.
    private enum Field: Hashable { case pin, consolePin }
    @FocusState private var focusedField: Field?

    /// Driven by the PIN-row buttons; tvOS shows a system keyboard sheet
    /// when the alert is presented.
    @State private var pinPromptShown = false
    @State private var consolePinPromptShown = false
    @State private var pinDraft: String = ""
    @State private var consolePinDraft: String = ""

    private var isValid: Bool {
        let pinOK = pin.count == 8 && pin.allSatisfy(\.isNumber)
        let cpinOK = consolePin.isEmpty
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
        case .idle:
            return nil
        case .running:
            return "Registering against \(host.ipAddress)…"
        case .succeeded(let h):
            return "Paired '\(h.nickname)'."
        case .failed(let msg):
            return msg
        case .canceled:
            return "Canceled."
        }
    }

    private var statusColor: Color {
        switch appState.registrationService.state {
        case .succeeded: return Theme.accent
        case .failed:    return Theme.errorRed
        default:         return Theme.secondaryText
        }
    }

    var body: some View {
        ChiakiDialogChrome(
            title: "Register Console",
            onBack: { appState.showHostList() }
        ) {
            ChiakiButton(
                title: isRunning ? "Registering…" : "Register",
                systemImage: "personalhotspot.circle.fill"
            ) {
                appState.registrationService.start(
                    host: host,
                    pin: pin,
                    psnAccountIdBase64: appState.settings.psnAccountId
                )
            }
            .disabled(!isValid || isRunning)
            .opacity((!isValid || isRunning) ? 0.4 : 1.0)
        } content: {
            VStack(alignment: .leading, spacing: Theme.dialogRowSpacing) {
                row("Host:") {
                    Text(host.ipAddress.isEmpty ? host.nickname : host.ipAddress)
                        .font(.system(size: Theme.baseFontSize))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: Theme.dialogFieldWidth, alignment: .leading)
                }

                row("PSN Account-ID:") {
                    Text(appState.settings.psnAccountId.isEmpty
                         ? "(set in Settings → General)"
                         : appState.settings.psnAccountId)
                        .font(.system(size: Theme.baseFontSize))
                        .foregroundStyle(appState.settings.psnAccountId.isEmpty
                                         ? Theme.errorRed
                                         : Theme.secondaryText)
                        .frame(width: Theme.dialogFieldWidth, alignment: .leading)
                }

                row("Remote Play PIN:") {
                    pinButton(text: $pin, max: 8, placeholder: "00000000",
                              field: .pin,
                              draft: $pinDraft, presented: $pinPromptShown)
                }

                row("Console PIN [Optional]:") {
                    pinButton(text: $consolePin, max: 4, placeholder: "0000",
                              field: .consolePin,
                              draft: $consolePinDraft,
                              presented: $consolePinPromptShown)
                }

                row("Console:") {
                    Text("PlayStation 5")
                        .font(.system(size: Theme.baseFontSize))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: Theme.dialogFieldWidth, alignment: .leading)
                }

                if let msg = statusMessage {
                    HStack {
                        Spacer().frame(width: 280)
                        Text(msg)
                            .font(.system(size: Theme.baseFontSize))
                            .foregroundStyle(statusColor)
                            .frame(width: Theme.dialogFieldWidth, alignment: .leading)
                    }
                }
            }
            // Land on the Remote Play PIN by default. `.defaultFocus` is the
            // tvOS-correct way to set initial focus — using `.onAppear` to
            // assign `@FocusState` races against the focus engine and gets
            // overridden.
            .defaultFocus($focusedField, .pin)
        }
        .onChange(of: appState.registrationService.state) { _, new in
            if case .succeeded = new {
                // Pop back to the host list shortly after success.
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    appState.registrationService.acknowledge()
                    appState.showHostList()
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func row<Trailing: View>(_ label: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Theme.dialogColumnSpacing) {
            Text(label)
                .font(.system(size: Theme.baseFontSize))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 280, alignment: .trailing)

            trailing()
        }
    }

    /// tvOS-friendly numeric input. The visible row is a focusable `Button`
    /// (which the focus engine handles cleanly); activating it pops an
    /// `.alert` with the real `TextField` inside, which tvOS pairs with the
    /// system keyboard automatically.
    private func pinButton(text: Binding<String>,
                           max: Int,
                           placeholder: String,
                           field: Field,
                           draft: Binding<String>,
                           presented: Binding<Bool>) -> some View {
        Button {
            draft.wrappedValue = text.wrappedValue
            presented.wrappedValue = true
        } label: {
            HStack {
                Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                    .font(.system(size: Theme.baseFontSize))
                    .foregroundStyle(text.wrappedValue.isEmpty
                                     ? Theme.tertiaryText
                                     : Theme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(width: Theme.dialogFieldWidth)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .fill(focusedField == field
                          ? Theme.accent.opacity(0.25)
                          : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .stroke(focusedField == field ? Theme.accent : .clear,
                            lineWidth: 4)
            )
        }
        .buttonStyle(.plain)
        .focused($focusedField, equals: field)
        .alert("Enter PIN", isPresented: presented) {
            TextField(placeholder, text: draft)
                .keyboardType(.numberPad)
            Button("OK") {
                let digits = draft.wrappedValue.filter(\.isNumber)
                text.wrappedValue = String(digits.prefix(max))
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

#Preview {
    RegistrationView(host: .previewReady)
        .environment(AppState.preview())
}
