// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Centered confirm modal. Reskinned per
/// [`docs/ui/redesign-plan.md §4.5`](../../../docs/ui/redesign-plan.md):
///
/// - Same compact card geometry as `ChiakiSheet` but tighter (single line
///   message, paired primary/secondary buttons).
/// - Drops the prior PS-shape glyphs (✕ / ☾) on Yes/No — those didn't
///   correspond to user actions and visually conflicted with DualSense
///   button-cluster expectations (audit issue D3).
/// - Primary/secondary buttons match the sheet pattern: amber Confirm on
///   the right, ink-700 Cancel on the left.
///
/// Esc / Menu = reject; Return on the focused button = accept that button.
struct ConfirmDialog: View {
    let model: ConfirmDialogModel
    let onDismiss: () -> Void

    /// Default-on-appear focus prevents the dialog opening with focus
    /// "trapped" on the underlying view that triggered it. Per the prior
    /// implementation that always landed on Yes / Confirm.
    private enum Field: Hashable { case cancel, confirm }
    @FocusState private var focused: Field?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    model.onReject?.perform()
                    onDismiss()
                }

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(model.title)
                        .font(Theme.font(.titleLarge).weight(.semibold))
                        .foregroundStyle(Theme.white50)
                        .multilineTextAlignment(.center)

                    Text(model.message)
                        .font(Theme.font(.bodyMed))
                        .foregroundStyle(Theme.mist300)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 640)
                }

                HStack(spacing: 14) {
                    ChiakiSheetSecondaryButton(title: "Cancel",
                                               systemImage: "xmark") {
                        model.onReject?.perform()
                        onDismiss()
                    }
                    .focused($focused, equals: .cancel)

                    ChiakiSheetPrimaryButton(title: "Confirm",
                                             systemImage: "checkmark.circle.fill") {
                        model.onConfirm.perform()
                        onDismiss()
                    }
                    .focused($focused, equals: .confirm)
                }
                .padding(.top, 4)
            }
            .padding(36)
            .frame(maxWidth: 640)
            .background(
                RoundedRectangle(cornerRadius: Theme.modalCorner,
                                 style: .continuous)
                    .fill(Theme.ink800)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.modalCorner,
                                 style: .continuous)
                    .stroke(Theme.ink600, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 50, x: 0, y: 20)
            .focusSection()
            .onAppear {
                // Land on Cancel by default — destructive Confirm should
                // require an explicit move-and-press, never an accidental
                // Return-on-default.
                focused = .cancel
            }
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
