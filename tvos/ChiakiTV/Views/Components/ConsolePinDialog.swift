// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// "Set Console PIN" sheet. Reskin of the prior back-chevron-toolbar form
/// per [`docs/ui/redesign-plan.md §4.5 + §5.7`](../../../docs/ui/redesign-plan.md).
/// The 4-digit Remote Play PIN is entered via `ChiakiDigitPicker` instead
/// of `Button + .alert(TextField)` (which would route the user through the
/// tvOS on-screen keyboard).
///
/// Phase 0 stub — Phase 1 calls `Chiaki.setConsolePin(hostId, pin)`.
struct ConsolePinDialog: View {
    @Environment(AppState.self) private var appState
    let hostId: String

    @State private var pin: String = "0000"

    private var isValid: Bool {
        pin.count == 4 && pin.allSatisfy(\.isNumber) && pin != "0000"
    }

    var body: some View {
        ChiakiSheet(
            title: "Set Console PIN",
            subtitle: "Enter the 4-digit PIN you set for this PS5.",
            onBack: { appState.showHostList() },
            content: {
                VStack(spacing: 28) {
                    ChiakiDigitPicker(value: $pin, length: 4)

                    Text("Find this on your PS5: Settings → System → Remote Play.")
                        .font(Theme.font(.bodyMed))
                        .foregroundStyle(Theme.mist500)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 600)
                }
                .frame(maxWidth: .infinity)
            },
            footer: {
                ChiakiSheetSecondaryButton(title: "Cancel",
                                           systemImage: "xmark") {
                    appState.showHostList()
                }
                ChiakiSheetPrimaryButton(title: "Set PIN",
                                         systemImage: "checkmark.circle.fill",
                                         isEnabled: isValid) {
                    // TODO(Phase 1): Chiaki.setConsolePin(hostId, pin) — `hostId`
                    // is used here to scope the call.
                    _ = hostId
                    appState.showHostList()
                }
            }
        )
    }
}

#Preview {
    ConsolePinDialog(hostId: "preview-host")
        .environment(AppState.preview())
}
