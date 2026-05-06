// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// N-column numeric picker for PIN entry. Each column is a focusable digit
/// reel; D-pad Up/Down cycles 0–9 within the active column, Left/Right
/// walks columns. tvOS doesn't ship a native wheel-picker style (it's
/// macOS / iOS only), so the reel itself is hand-drawn — but focus chrome
/// is delegated to the system via `.focusable()` so we don't layer a
/// custom halo on top of the focus replicant.
///
/// The binding is always exactly `length` characters of `0–9`; the picker
/// pads with leading zeros and never returns an invalid string.
struct ChiakiDigitPicker: View {
    @Binding var value: String
    let length: Int

    @FocusState private var focusedColumn: Int?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<length, id: \.self) { col in
                DigitReel(digit: digitBinding(at: col))
                    .focused($focusedColumn, equals: col)
            }
        }
        .focusSection()
        .onAppear {
            if focusedColumn == nil { focusedColumn = 0 }
            value = padded(value)
        }
        .onChange(of: value) { _, new in
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

private struct DigitReel: View {
    @Binding var digit: Int
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(spacing: 0) {
            digitText(for: prevDigit).opacity(0.25)
            digitText(for: digit).opacity(1.0)
            digitText(for: nextDigit).opacity(0.25)
        }
        .frame(width: 96, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .focusable(true)
        .onMoveCommand { direction in
            guard isFocused else { return }
            switch direction {
            case .up:   digit = prevDigit
            case .down: digit = nextDigit
            default:    break
            }
        }
        .animation(.easeOut(duration: 0.16), value: digit)
    }

    private func digitText(for d: Int) -> some View {
        Text(String(d))
            .font(.system(size: 56, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .monospacedDigit()
    }

    private var prevDigit: Int { (digit + 9) % 10 }
    private var nextDigit: Int { (digit + 1) % 10 }
}

#Preview {
    @Previewable @State var pin = "0000"
    return VStack(spacing: 24) {
        ChiakiDigitPicker(value: $pin, length: 4)
        Text("Value: \(pin)")
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
