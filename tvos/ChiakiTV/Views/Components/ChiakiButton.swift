// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// A flat button matching the desktop's `controls/Button.qml`:
///   • when focused, background = `Theme.accent`
///   • when not focused, transparent flat
///   • optional left-aligned icon (used by host-list buttons that show a
///     controller glyph only when their tile is highlighted)
///
/// tvOS focus is handled by the system focus engine; we only style for the
/// `isFocused` state.
struct ChiakiButton: View {
    let title: String
    var systemImage: String? = nil
    var isWide: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: Theme.smallIconSize))
                        .frame(width: Theme.smallIconSize, height: Theme.smallIconSize)
                }
                Text(title)
                    .font(.system(size: Theme.baseFontSize, weight: .medium))
            }
            .padding(.horizontal, isWide ? 50 : 30)
            .padding(.vertical, 18)
            .frame(maxWidth: isWide ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .fill(isFocused ? Theme.accent : Color.clear)
            )
            .foregroundStyle(isFocused ? Theme.primaryText : Theme.primaryText.opacity(0.85))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

#Preview {
    VStack(spacing: 30) {
        ChiakiButton(title: "Add Manual Host", systemImage: "plus.circle") {}
        ChiakiButton(title: "Settings", systemImage: "gearshape.fill") {}
        ChiakiButton(title: "Wake Up") {}
    }
    .padding(60)
    .background(Theme.background)
}
