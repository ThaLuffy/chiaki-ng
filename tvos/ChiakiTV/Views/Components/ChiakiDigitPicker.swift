// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// N-column numeric picker — each column is a focusable digit reel; D-pad
/// Up/Down cycles 0–9 within the active column, Left/Right walks columns.
/// Replaces `Button + .alert(TextField)` for PIN entry per
/// [`docs/ui/redesign-plan.md §4.5 + §5.7`](../../../docs/ui/redesign-plan.md).
///
/// Why this exists: tvOS's on-screen keyboard for a 4 / 8-digit numeric
/// PIN is the worst-case interaction model — Siri Remote → keyboard sheet
/// → tap-each-digit → confirm. The reel-picker turns it into a single
/// focus-captured row of D-pad swipes.
///
/// Usage:
/// ```
/// @State private var pin = "0000"
/// ChiakiDigitPicker(value: $pin, length: 4)
/// ```
///
/// The binding is always exactly `length` characters of `0–9`; the picker
/// pads with leading zeros and never returns an invalid string.
struct ChiakiDigitPicker: View {
    /// Digit string. Always equal to `length` numeric characters; the
    /// picker pads with leading '0's on assignment to the binding.
    @Binding var value: String
    let length: Int

    @FocusState private var focusedColumn: Int?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<length, id: \.self) { col in
                DigitReel(
                    digit: digitBinding(at: col),
                    isFocused: focusedColumn == col
                )
                .focused($focusedColumn, equals: col)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .focusSection()
        .onAppear {
            // Land on the first column so the user can start typing
            // immediately without an extra D-pad press.
            if focusedColumn == nil { focusedColumn = 0 }
            // Make sure the binding has the right shape on first appear.
            value = padded(value)
        }
        .onChange(of: value) { _, new in
            // Force `length` digits, all numeric. Defensive: if the caller
            // assigns a non-conforming string the picker stays consistent.
            let cleaned = padded(new)
            if cleaned != new { value = cleaned }
        }
    }

    private func digitBinding(at col: Int) -> Binding<Int> {
        Binding<Int>(
            get: {
                let chars = Array(padded(value))
                guard col < chars.count else { return 0 }
                return Int(String(chars[col])) ?? 0
            },
            set: { newDigit in
                var chars = Array(padded(value))
                if col < chars.count {
                    chars[col] = Character("\(((newDigit % 10) + 10) % 10)")
                    value = String(chars)
                }
            }
        )
    }

    private func padded(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count >= length { return String(digits.prefix(length)) }
        return String(repeating: "0", count: length - digits.count) + digits
    }
}

// MARK: - Single digit reel

private struct DigitReel: View {
    @Binding var digit: Int
    let isFocused: Bool

    /// The reel renders three values vertically — the previous digit
    /// (dimmed, above), the current digit (bright, centered), and the
    /// next digit (dimmed, below). Gives the reel-of-numbers feel
    /// without needing a real ScrollView.
    var body: some View {
        VStack(spacing: 0) {
            digitText(for: prevDigit)
                .opacity(0.25)
            digitText(for: digit)
                .opacity(1.0)
            digitText(for: nextDigit)
                .opacity(0.25)
        }
        .frame(width: 110, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFocused ? Theme.ink700 : Theme.ink800.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.ink600, lineWidth: 1)
        )
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .chiakiFocusRing(isFocused, cornerRadius: 16)
        .animation(Theme.focusSpring, value: isFocused)
        .animation(.easeOut(duration: 0.16), value: digit)
        .onMoveCommand { direction in
            guard isFocused else { return }
            switch direction {
            case .up:   decrement()
            case .down: increment()
            default: break
            }
        }
    }

    private func digitText(for d: Int) -> some View {
        Text(String(d))
            .font(.system(size: 64, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.white50)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .monospacedDigit()
    }

    private var prevDigit: Int { (digit + 9) % 10 }
    private var nextDigit: Int { (digit + 1) % 10 }

    private func increment() { digit = nextDigit }
    private func decrement() { digit = prevDigit }
}

#Preview {
    @Previewable @State var pin = "0000"
    return VStack(spacing: 24) {
        ChiakiDigitPicker(value: $pin, length: 4)
        Text("Value: \(pin)")
            .foregroundStyle(Theme.mist300)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .chiakiBackground()
}
