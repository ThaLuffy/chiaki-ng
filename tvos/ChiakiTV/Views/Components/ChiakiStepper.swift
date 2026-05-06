// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// A `Stepper` replacement for tvOS, where the system `Stepper` and
/// `Slider` are both unavailable. Two focusable buttons flank a numeric
/// readout: pressing select / Return on the focused side increments or
/// decrements the value by `step`, clamped to `range`.
///
/// Used by SettingsView's numeric rows and StreamMenuOverlay's volume.
struct ChiakiStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var width: CGFloat = 100

    var body: some View {
        HStack(spacing: 12) {
            stepButton(systemImage: "minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text("\(value)")
                .font(.system(size: Theme.baseFontSize, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .frame(width: width)
                .multilineTextAlignment(.center)
            stepButton(systemImage: "plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
    }

    @ViewBuilder
    private func stepButton(systemImage: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        StepperButton(systemImage: systemImage, enabled: enabled, action: action)
    }
}

private struct StepperButton: View {
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.smallIconSize, weight: .bold))
                .frame(width: 60, height: 50)
                .foregroundStyle(enabled ? Theme.primaryText : Theme.tertiaryText)
                .background(
                    RoundedRectangle(cornerRadius: Theme.smallRadius)
                        .fill(isFocused ? Theme.accent : Theme.surface)
                )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .disabled(!enabled)
    }
}

#Preview {
    StepperPreviewHost()
        .padding()
        .background(Theme.background)
}

private struct StepperPreviewHost: View {
    @State private var value: Int = 50
    var body: some View {
        ChiakiStepper(value: $value, range: 0...100, step: 5)
    }
}
