// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// 70 × 70 indeterminate spinner. Mirrors the desktop's `BusyIndicator` in
/// [`AutoConnectView.qml:67-73`](../../../../gui/src/qml/AutoConnectView.qml)
/// and the loading state in [`StreamView.qml:118-130`](../../../../gui/src/qml/StreamView.qml).
///
/// SwiftUI's `ProgressView(.circular)` already animates with the system tint;
/// we tint with `Theme.accent` and force a square frame.
struct ChiakiSpinner: View {
    var size: CGFloat = 70

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(Theme.accent)
            .scaleEffect(size / 30)            // tvOS ProgressView default is ~30pt
            .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        ChiakiSpinner()
    }
}
