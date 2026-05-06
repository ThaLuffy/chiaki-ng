// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// "Set Console PIN" sheet rebuilt against SwiftUI primitives per
/// [`docs/ui/redesign-v2-report.md §C3`](../../../docs/ui/redesign-v2-report.md):
/// presented via `.sheet(item:)` over the host list, with a top-bar
/// chrome (`SheetChrome`) and a `Form` body.
struct ConsolePinDialog: View {
    @Environment(AppState.self) private var appState
    let hostId: String

    @State private var pin: String = "0000"

    private var isValid: Bool {
        pin.count == 4 && pin.allSatisfy(\.isNumber) && pin != "0000"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetChrome(
                title: "Set Console PIN",
                cancel: ("Cancel", { appState.dismissSheet() }),
                confirm: ("Set PIN", isEnabled: isValid, {
                    _ = hostId
                    appState.dismissSheet()
                })
            )

            Form {
                Section {
                    HStack {
                        Spacer()
                        ChiakiDigitPicker(value: $pin, length: 4)
                        Spacer()
                    }
                } footer: {
                    Text("Find this on your PS5: Settings → System → Remote Play.")
                }
            }
            .formStyle(.grouped)
        }
    }
}

#Preview {
    ConsolePinDialog(hostId: "preview-host")
        .environment(AppState.preview())
}
