// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Centered Yes/No modal. Mirrors [`gui/src/qml/ConfirmDialog.qml`](../../../../gui/src/qml/ConfirmDialog.qml):
///
/// - Centered, modal, Material `MediumScale` rounded corners (8 px).
/// - Bold title.
/// - 20 px spacing column with the message text and a centered button row.
/// - Yes = cross icon, No = moon (here we use SF Symbols `xmark.circle.fill`
///   and `moon.fill` until we copy the SVGs across in Phase 1).
///
/// Esc / Menu = reject; Return / select = accept.
struct ConfirmDialog: View {
    let model: ConfirmDialogModel
    let onDismiss: () -> Void

    @FocusState private var focus: ConfirmFocus?

    enum ConfirmFocus: Hashable { case yes, no }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    model.onReject?.perform()
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
                        model.onConfirm.perform()
                        onDismiss()
                    }
                    .focused($focus, equals: .yes)

                    ChiakiButton(title: "No", systemImage: "moon.fill") {
                        model.onReject?.perform()
                        onDismiss()
                    }
                    .focused($focus, equals: .no)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: Theme.mediumRadius)
                    .fill(Theme.surface)
            )
            .onAppear { focus = .yes }
            .onExitCommand {
                model.onReject?.perform()
                onDismiss()
            }
        }
    }
}

#Preview {
    ConfirmDialog(model: ConfirmDialogModel(
        title: "Quit?",
        message: "Are you sure you want to quit ChiakiTV?",
        onConfirm: ConfirmAction(perform: {}),
        onReject: ConfirmAction(perform: {})
    ), onDismiss: {})
}
