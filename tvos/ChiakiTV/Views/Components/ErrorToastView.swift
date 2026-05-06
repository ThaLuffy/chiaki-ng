// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Bottom-center error toast. Reskinned per the redesign tokens:
/// rose-tinted (errors are *errors*, not the ambient amber action color),
/// a leading triangle glyph for at-distance recognition, drop-shadow for
/// elevation off the canvas. Auto-dismisses after 2 s.
struct ErrorToastView: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    @State private var visible = false

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.rose500)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.font(.titleMed).weight(.semibold))
                        .foregroundStyle(Theme.white50)
                    Text(message)
                        .font(Theme.font(.bodyMed))
                        .foregroundStyle(Theme.mist300)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 720, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.ink800)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.rose500.opacity(0.6), lineWidth: 1.5)
            )
            .shadow(color: Theme.rose500.opacity(0.3), radius: 24, x: 0, y: 0)
            .padding(.bottom, Theme.toastBottomMargin)
            .opacity(visible ? 1.0 : 0.0)
            .scaleEffect(visible ? 1.0 : 0.95)
            .animation(.easeOut(duration: Theme.toastFadeDuration), value: visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
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
