// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Ranged-numeric slider for tvOS. SwiftUI's `Slider` is unavailable on
/// tvOS, and the alternative — a `Picker` with hundreds of stride values —
/// hijacks the entire screen. This is a focusable horizontal track that
/// the user adjusts with the D-pad: Left/Right step by `step`, Up/Down for
/// `bigStep` (default = 5×).
///
/// Drop-in replacement for `Picker`-with-stride pattern in `SettingsView`.
///
/// ```swift
/// TVSlider(value: $appState.settings.bitrateKbps,
///          range: 2_000...50_000, step: 500,
///          format: { "\($0 / 1_000) Mbps" })
/// ```
struct TVSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    /// "Big step" for D-pad Up/Down. Defaults to `step × 10` (rounded up
    /// to a clean value) so users can traverse the full range in ≤ 10
    /// presses on either axis.
    var bigStep: Int? = nil
    let format: (Int) -> String

    @FocusState private var isFocused: Bool

    private var span: Double { Double(range.upperBound - range.lowerBound) }
    private var progress: Double {
        guard span > 0 else { return 0 }
        return Double(value - range.lowerBound) / span
    }
    private var resolvedBigStep: Int { bigStep ?? max(step * 10, 1) }

    var body: some View {
        HStack(spacing: 24) {
            track
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            Text(format(value))
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(minWidth: 140, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .focusable(true)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.smooth(duration: 0.2), value: isFocused)
        .onMoveCommand { direction in
            guard isFocused else { return }
            switch direction {
            case .left:  value = max(range.lowerBound, value - step)
            case .right: value = min(range.upperBound, value + step)
            case .up:    value = min(range.upperBound, value + resolvedBigStep)
            case .down:  value = max(range.lowerBound, value - resolvedBigStep)
            default:     break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Slider"))
        .accessibilityValue(Text(format(value)))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let filled = max(8, w * progress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(isFocused ? 0.35 : 0.20))
                    .frame(height: 8)

                Capsule()
                    .fill(.tint)
                    .frame(width: filled, height: 8)

                Circle()
                    .fill(.tint)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isFocused ? 0.95 : 0.0),
                                    lineWidth: 2)
                    )
                    .shadow(color: isFocused ? Color.orange.opacity(0.5) : .clear,
                            radius: isFocused ? 12 : 0)
                    .offset(x: max(0, filled - 12))
                    .animation(.easeOut(duration: 0.12), value: value)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

#Preview {
    @Previewable @State var bitrate = 15_000
    @Previewable @State var buffer = 80

    return Form {
        Section("Quality") {
            LabeledContent("Bitrate") {
                TVSlider(value: $bitrate, range: 2_000...50_000, step: 500,
                         format: { "\($0 / 1_000) Mbps" })
            }
            LabeledContent("Audio buffer") {
                TVSlider(value: $buffer, range: 20...500, step: 10,
                         format: { "\($0) ms" })
            }
        }
    }
    .formStyle(.grouped)
    .padding()
    .tint(.orange)
}
