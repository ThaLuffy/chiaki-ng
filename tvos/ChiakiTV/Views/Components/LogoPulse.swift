// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// The "alive cue" watermark behind the host list. Mirrors
/// [`MainView.qml:427-435`](../../../../gui/src/qml/MainView.qml):
///
/// > Image (chiaking-logo-white.svg) — centered, sized to `min(W,H) / 2`,
/// > opacity loops 0.05 → 0.20 over **1000 ms** with `Easing.OutCubic`.
///
/// **Phase 0**: uses the SF Symbol `gamecontroller.fill` placeholder. **Phase
/// 1** copies the SVG asset into `Assets.xcassets`. See
/// [`docs/ui/swift-ui-plan.md`](../../docs/ui/swift-ui-plan.md) §3.5 / §9.4.
struct LogoPulse: View {
    @State private var pulse = false
    @State private var side: CGFloat = 0

    var body: some View {
        // `.onGeometryChange` (iOS 16+) reads the proposed size without
        // forcing eager measurement the way `GeometryReader` does. With
        // `GeometryReader` here the host list's `LazyVStack` would lose
        // its lazy benefit because the geometry reader trips eager sizing
        // up the tree.
        Image(systemName: "gamecontroller.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Theme.primaryText)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(pulse ? 0.20 : 0.05)
            .allowsHitTesting(false)
            .onGeometryChange(for: CGFloat.self) { proxy in
                min(proxy.size.width, proxy.size.height) / 2
            } action: { newSide in
                side = newSide
            }
            .onAppear {
                withAnimation(.easeOut(duration: Theme.logoPulseDuration)
                    .repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        LogoPulse()
    }
}
