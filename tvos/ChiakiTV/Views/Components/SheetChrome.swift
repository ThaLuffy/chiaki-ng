// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Compact title-bar for `.sheet(item:)`-presented modals on tvOS.
/// tvOS doesn't render `NavigationStack`'s `.toolbar` placement reliably
/// inside a sheet (titles truncate, action buttons overlap the first form
/// row on tall content), so this gives explicit, predictable chrome:
/// `[Cancel ............... Title ............... Confirm]`.
///
/// Use it as the top of any sheet's body:
///
/// ```swift
/// VStack(spacing: 0) {
///     SheetChrome(
///         title: "Add Manual Console",
///         cancel: ("Cancel", { dismiss() }),
///         confirm: ("Add", isEnabled: canAdd, { ...; dismiss() })
///     )
///     Form { ... }
/// }
/// ```
struct SheetChrome: View {
    let title: String
    let cancel: (label: String, action: () -> Void)
    let confirm: (label: String, isEnabled: Bool, action: () -> Void)?

    init(title: String,
         cancel: (label: String, action: () -> Void),
         confirm: (label: String, isEnabled: Bool, action: () -> Void)? = nil) {
        self.title = title
        self.cancel = cancel
        self.confirm = confirm
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.space6) {
            Button(cancel.label, action: cancel.action)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .fixedSize()
                .tint(.secondary)

            Spacer(minLength: Theme.space4)

            Text(title)
                .font(.system(.title2, design: .default).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)

            Spacer(minLength: Theme.space4)

            if let confirm {
                Button(confirm.label, action: confirm.action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(!confirm.isEnabled)
            } else {
                Color.clear.frame(width: 120, height: 1)
            }
        }
        .padding(.horizontal, Theme.space7)
        .padding(.vertical, Theme.space5)
    }
}
