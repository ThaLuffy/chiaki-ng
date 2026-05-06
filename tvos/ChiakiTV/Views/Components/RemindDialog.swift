// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Centered Yes / No / Remind-Me-Later modal. Mirrors
/// [`gui/src/qml/RemindDialog.qml`](../../../../gui/src/qml/RemindDialog.qml):
///
/// Three buttons in a horizontal row, same chrome as `ConfirmDialog`:
///   Yes  = cross icon       → `onYes`
///   No   = moon (circle)    → `onNo`   (also flips `remind*Ask = false` upstream)
///   Later = pyramid (▲)     → `onLater`
struct RemindDialog: View {
    let model: RemindDialogModel
    let onDismiss: () -> Void

    @FocusState private var focus: RemindFocus?

    enum RemindFocus: Hashable { case yes, no, later }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    model.onLater.perform()
                    onDismiss()
                }

            VStack(spacing: Theme.dialogColumnSpacing) {
                Text(model.title)
                    .font(.system(size: Theme.dialogTitleFontSize, weight: .bold))
                    .foregroundStyle(Theme.primaryText)

                Text(model.message)
                    .font(.system(size: Theme.baseFontSize))
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 700)

                HStack(spacing: Theme.dialogColumnSpacing) {
                    ChiakiButton(title: "Yes", systemImage: "xmark.circle.fill") {
                        model.onYes.perform()
                        onDismiss()
                    }
                    .focused($focus, equals: .yes)

                    ChiakiButton(title: "No", systemImage: "moon.fill") {
                        model.onNo.perform()
                        onDismiss()
                    }
                    .focused($focus, equals: .no)

                    ChiakiButton(title: "Remind Me Later", systemImage: "triangle.fill") {
                        model.onLater.perform()
                        onDismiss()
                    }
                    .focused($focus, equals: .later)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: Theme.mediumRadius)
                    .fill(Theme.surface)
            )
            .onAppear { focus = .yes }
            .onExitCommand {
                model.onLater.perform()
                onDismiss()
            }
        }
    }
}

#Preview {
    RemindDialog(model: RemindDialogModel(
        title: "Wake up console?",
        message: "The console is asleep. Send a Wake-on-LAN packet?",
        onYes: ConfirmAction(perform: {}),
        onNo: ConfirmAction(perform: {}),
        onLater: ConfirmAction(perform: {})
    ), onDismiss: {})
}
