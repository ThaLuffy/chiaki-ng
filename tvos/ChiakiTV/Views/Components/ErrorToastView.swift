// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Bottom-center error toast. Mirrors the toast in
/// [`gui/src/qml/Main.qml:404-432`](../../../../gui/src/qml/Main.qml):
///
/// - Anchored bottom-center, `bottomMargin 30`.
/// - 24 px bold title, 20 px body.
/// - Background `Material.accent` (`Theme.accent`), 8 px radius (Medium scale).
/// - Opacity ramps `0 → 0.8` over 500 ms; auto-dismiss after 2 s
///   ([`Main.qml:430` `errorHideTimer`](../../../../gui/src/qml/Main.qml)).
struct ErrorToastView: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    @State private var visible = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: Theme.errorTitleFontSize, weight: .bold))
                Text(message)
                    .font(.system(size: Theme.errorTextFontSize))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, Theme.toastInsetH)
            .padding(.vertical, Theme.toastInsetV)
            .background(
                RoundedRectangle(cornerRadius: Theme.mediumRadius)
                    .fill(Theme.accent.opacity(0.8))
            )
            .padding(.bottom, Theme.toastBottomMargin)
            .opacity(visible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: Theme.toastFadeDuration), value: visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        // `.task` cancels on view disappear, so the dismissal timer can't
        // fire after the toast has already been removed (the previous
        // `DispatchQueue.main.asyncAfter` chain leaked in that scenario).
        .task {
            visible = true
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            visible = false
            try? await Task.sleep(for: .seconds(Theme.toastFadeDuration))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        ErrorToastView(title: "Connection failed",
                       message: "Could not reach the console at 192.168.1.42",
                       onDismiss: {})
    }
}
