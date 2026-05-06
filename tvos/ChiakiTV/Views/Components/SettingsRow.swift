// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// A single row in `SettingsView`'s tabbed forms with a **fixed-width
/// label column** and a flexible value column, plus a `minHeight` so
/// every row in a section visually aligns.
///
/// `LabeledContent` would be the obvious choice but its label column
/// width is intrinsic — a "Codec" row's label is narrower than a
/// "Render preset" row's label, so the value control starts at a
/// different x position on each row. That breaks the LearnUI
/// "vertical guide line" rule for stacked siblings.
///
/// `SettingsRow` enforces a single label column width for all rows
/// inside a section, plus a fixed-ish row height so a `TVSlider` row
/// doesn't read taller than a segmented `Picker` row. Use it
/// everywhere inside `Form { Section { ... } }` instead of
/// `LabeledContent` or bare `Picker(title:)`.
///
/// ```swift
/// SettingsRow("Resolution") {
///     Picker("", selection: $resolution) { ... }
///         .pickerStyle(.segmented)
/// }
/// ```
struct SettingsRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value

    /// Fixed label-column width. Wide enough for the longest label in
    /// the app's settings ("Reported loss ceiling" at ~260pt with body
    /// font); 280pt leaves a small buffer.
    private let labelColumnWidth: CGFloat = 280

    /// Minimum row height. Picks up the natural height of
    /// `.controlSize(.large)` segmented controls (~76pt) plus a couple
    /// pt of breathing room so toggles / slider rows match.
    private let minRowHeight: CGFloat = 80

    init(_ label: String, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(spacing: Theme.space5) {
            Text(label)
                .font(.system(.body, design: .default))
                .lineLimit(1)
                .frame(width: labelColumnWidth, alignment: .leading)

            value()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: minRowHeight)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}
