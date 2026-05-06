// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// "Set console PIN" push-style dialog. Mirrors
/// [`gui/src/qml/ConsolePinDialog.qml`](../../../../gui/src/qml/ConsolePinDialog.qml):
///
/// Single-row form: `Remote Play PIN (4 digits):` text field. Validator
/// regex `[0-9]{4}` enforces 4 digits exactly. Trailing **Set** button is
/// enabled only when the regex passes.
///
/// Phase 0 stub — Phase 1 calls `Chiaki.setConsolePin(hostId, pin)`.
struct ConsolePinDialog: View {
    @Environment(AppState.self) private var appState
    let hostId: String

    @State private var pin: String = ""
    @State private var pinPromptShown = false
    @State private var pinDraft: String = ""

    private var isValid: Bool {
        pin.count == 4 && pin.allSatisfy { $0.isNumber }
    }

    var body: some View {
        ChiakiDialogChrome(
            title: "Set Console PIN",
            onBack: { appState.showHostList() }
        ) {
            ChiakiButton(title: "Set", systemImage: "checkmark.circle.fill") {
                // TODO(Phase 1): Chiaki.setConsolePin(hostId, pin) — `hostId`
                // is used here to scope the call.
                _ = hostId
                appState.showHostList()
            }
            .disabled(!isValid)
            .opacity(isValid ? 1.0 : 0.4)
        } content: {
            HStack(spacing: Theme.dialogColumnSpacing) {
                Text("Remote Play PIN (4 digits):")
                    .font(.system(size: Theme.baseFontSize))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 320, alignment: .trailing)

                pinButton
            }
        }
    }

    /// Focusable Button + `.alert(TextField)` — same tvOS-friendly pattern
    /// used in RegistrationView and ManualHostDialog.
    private var pinButton: some View {
        Button {
            pinDraft = pin
            pinPromptShown = true
        } label: {
            HStack {
                Text(pin.isEmpty ? "0000" : pin)
                    .font(.system(size: Theme.baseFontSize))
                    .foregroundStyle(pin.isEmpty
                                     ? Theme.tertiaryText
                                     : Theme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(width: Theme.dialogFieldWidth)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .fill(Theme.surface)
            )
        }
        .buttonStyle(.plain)
        .alert("Enter 4-digit PIN", isPresented: $pinPromptShown) {
            TextField("0000", text: $pinDraft)
                .keyboardType(.numberPad)
            Button("OK") {
                pin = String(pinDraft.filter(\.isNumber).prefix(4))
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

#Preview {
    ConsolePinDialog(hostId: "preview-host")
        .environment(AppState.preview())
}
