// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// The 80px toolbar that sits at the top of every push-style dialog and the
/// main host list, mirroring `gui/src/qml/DialogView.qml` and the toolbar in
/// `MainView.qml`.
///
/// Layout: [back/quit on the left] · [title centered] · [primary action on
/// the right]. The right-side action is optional and is the only focusable
/// child. The left-side button is *focused only on tvOS* via the system's
/// `onExitCommand`.
struct ChiakiToolbar<TrailingActions: View>: View {
    let title: String
    var subtitle: String? = nil
    var leadingSystemImage: String? = "chevron.left"
    let onBack: () -> Void
    @ViewBuilder var trailingActions: () -> TrailingActions

    var body: some View {
        ZStack {
            // Background surface
            Theme.surface
                .ignoresSafeArea(edges: .top)

            HStack(spacing: 0) {
                if let leadingSystemImage {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: leadingSystemImage)
                            .font(.system(size: Theme.toolbarOkFontSize, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 100, height: Theme.toolbarHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 100)
                }

                Spacer()

                trailingActions()
                    .padding(.trailing, 10)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: Theme.dialogTitleFontSize, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: Theme.dialogHeaderFontSize, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .frame(height: Theme.toolbarHeight)
    }
}

extension ChiakiToolbar where TrailingActions == EmptyView {
    init(title: String, subtitle: String? = nil,
         leadingSystemImage: String? = "chevron.left",
         onBack: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.leadingSystemImage = leadingSystemImage
        self.onBack = onBack
        self.trailingActions = { EmptyView() }
    }
}

#Preview {
    VStack(spacing: 0) {
        ChiakiToolbar(title: "Settings", subtitle: "* Defaults marked with (Default)") {} trailingActions: {
            ChiakiButton(title: "OK", systemImage: "checkmark.circle.fill") {}
        }
        Spacer()
    }
    .background(Theme.background)
}
