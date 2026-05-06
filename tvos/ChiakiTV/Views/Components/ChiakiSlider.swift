// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Continuous numeric slider for tvOS. Single focusable unit; Left/Right
/// on the D-pad adjusts the value by `step`. Renders a filled track with
/// an amber handle and a tabular-figures readout to the right. Replaces
/// `ChiakiStepper` for ranged scalars per
/// [`docs/ui/redesign-plan.md §4.4`](../../../docs/ui/redesign-plan.md).
///
/// Usage:
///
/// ```
/// ChiakiSlider(
///     value: $appState.settings.audioBufferMs,
///     range: 20...500, step: 10,
///     format: { "\($0) ms" }
/// )
/// ```
struct ChiakiSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 18) {
            track
                .frame(height: 28)

            Text(format(value))
                .font(Theme.font(.monoMed))
                .foregroundStyle(Theme.mist300)
                .frame(minWidth: 110, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.ink800.opacity(0.5))
        )
        .focusable(true)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .chiakiFocusRing(isFocused, cornerRadius: 14)
        .animation(Theme.focusSpring, value: isFocused)
        .onMoveCommand { direction in
            guard isFocused else { return }
            switch direction {
            case .left:  decrement()
            case .right: increment()
            default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let filled = w * progress

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Theme.ink700)
                    .frame(height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)

                // Fill
                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.amber400, Theme.amber500],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(filled, 6), height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)

                // Handle
                Circle()
                    .fill(Theme.amber500)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(Theme.white50.opacity(isFocused ? 0.85 : 0.0),
                                    lineWidth: 2)
                    )
                    .shadow(color: isFocused ? Theme.amberGlow : .clear,
                            radius: isFocused ? 14 : 0)
                    .offset(x: max(filled - 11, 0))
                    .animation(.easeOut(duration: 0.12), value: value)
            }
        }
    }

    private var progress: CGFloat {
        let span = CGFloat(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        let p = CGFloat(value - range.lowerBound) / span
        return min(max(p, 0), 1)
    }

    private func increment() {
        let next = min(value + step, range.upperBound)
        if next != value { value = next }
    }

    private func decrement() {
        let next = max(value - step, range.lowerBound)
        if next != value { value = next }
    }
}
