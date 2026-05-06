// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// The push-style dialog shell. Mirrors [`gui/src/qml/DialogView.qml`](../../../../gui/src/qml/DialogView.qml):
///
/// - 80 px `ChiakiToolbar` at top with a back button on the left and an
///   optional primary action on the right.
/// - Content area below the toolbar, padded by `Theme.dialogTopMargin`
///   (20 px), centered horizontally.
/// - `onExitCommand` (Apple TV remote Menu / B-button) calls `onBack()`,
///   matching the desktop's "Escape closes & rejects" binding.
///
/// Used by every push-style dialog: ManualHost, ConsolePin, Registration,
/// Settings, AutoConnect, etc.
struct ChiakiDialogChrome<Content: View, TrailingActions: View>: View {
    let title: String
    var subtitle: String? = nil
    let onBack: () -> Void
    @ViewBuilder var trailingActions: () -> TrailingActions
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Each region is a separate `.focusSection()` so the tvOS focus
            // engine moves directional input deterministically between the
            // toolbar (Back / primary action) and the body content.
            // Without this, `Down` from the Back button can fail to find the
            // body's focusable controls because the toolbar elements are not
            // geometrically aligned with anything below them.
            ChiakiToolbar(title: title,
                          subtitle: subtitle,
                          onBack: onBack,
                          trailingActions: trailingActions)
                .focusSection()

            content()
                .padding(.top, Theme.dialogTopMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .focusSection()
        }
        .chiakiBackground()
        .onExitCommand(perform: onBack)
    }
}

// MARK: - Convenience inits

extension ChiakiDialogChrome where TrailingActions == EmptyView {
    init(title: String,
         subtitle: String? = nil,
         onBack: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.trailingActions = { EmptyView() }
        self.content = content
    }
}

#Preview {
    ChiakiDialogChrome(title: "Add Manual Console", onBack: {}) {
        ChiakiButton(title: "Add", systemImage: "plus.circle.fill") {}
    } content: {
        Text("Dialog body goes here")
            .foregroundStyle(Theme.primaryText)
            .font(.system(size: Theme.baseFontSize))
    }
}
