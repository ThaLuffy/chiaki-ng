// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Horizontal segmented control for cycling enums on tvOS. A single
/// focusable unit; Left/Right on the D-pad cycles values live without
/// requiring `Return`. Designed to replace `Picker(.menu)` rows in
/// SettingsView per [`docs/ui/redesign-plan.md §4.4`](../../../docs/ui/redesign-plan.md).
///
/// Usage:
///
/// ```
/// ChiakiSegmented(
///     selection: $appState.settings.codec,
///     options: VideoCodec.allCases,
///     label: { $0.label }
/// )
/// ```
struct ChiakiSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<options.count, id: \.self) { idx in
                segment(for: options[idx])
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.ink800.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.ink600, lineWidth: 1)
        )
        .focusable(true)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .chiakiFocusRing(isFocused, cornerRadius: 14)
        .animation(Theme.focusSpring, value: isFocused)
        .onMoveCommand { direction in
            guard isFocused else { return }
            switch direction {
            case .left:  cyclePrev()
            case .right: cycleNext()
            default: break
            }
        }
    }

    @ViewBuilder
    private func segment(for value: T) -> some View {
        let isSelected = (value == selection)
        Text(label(value))
            .font(Theme.font(.bodyMed))
            .foregroundStyle(isSelected ? Theme.ink900 : Theme.mist300)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Theme.amber500 : Color.clear)
            )
            .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    private func cycleNext() {
        guard let i = options.firstIndex(of: selection),
              i + 1 < options.count else { return }
        selection = options[i + 1]
    }

    private func cyclePrev() {
        guard let i = options.firstIndex(of: selection),
              i > 0 else { return }
        selection = options[i - 1]
    }
}
