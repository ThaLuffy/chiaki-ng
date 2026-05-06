// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// A single 180-px row in the host list. Mirrors the desktop's
/// `ItemDelegate` in [`MainView.qml:171-389`](../../../../gui/src/qml/MainView.qml).
///
/// Layout columns (left → right):
/// 1. PS5 console icon, 150 px wide.
/// 2. Identity column: nickname, IP, MAC + reg state, discovery tag.
/// 3. Status column: state, current app, title ID.
/// 4. Action stack (right edge): Connect (primary), Delete/Hide, Wake Up, Update PIN.
///
/// **Focus model:** the row is laid out as a `focusSection()`, NOT a
/// single Button. That lets the focus engine reach the inline action
/// buttons via the Siri Remote — nesting Buttons (a `Button` row containing
/// other Buttons) collapses focus onto only the outer one. The primary
/// "Connect" action lives on the topmost button in the action stack so
/// Select-from-row-focus routes there naturally.
struct HostTile: View {
    let host: Host
    var onConnect: () -> Void = {}
    var onDelete: () -> Void = {}
    var onWakeUp: () -> Void = {}
    var onUpdatePin: () -> Void = {}

    /// The inline actions a row can have. Used as the focus binding key so
    /// the parent always knows which (if any) inline button is focused —
    /// drives the shared row highlight precisely (lights up while focus is
    /// inside the row, clears when focus leaves).
    private enum Action: Hashable { case connect, delete, wake, updatePin }

    @FocusState private var focusedAction: Action?
    private var rowFocused: Bool { focusedAction != nil }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.hostTileSubitemSpacing) {

            consoleIcon
                .frame(width: Theme.consoleIconWidth)

            identityColumn

            statusColumn

            Spacer(minLength: 0)

            actionStack
        }
        .padding(.leading, Theme.hostTileLeftMargin)
        .padding(.trailing, Theme.hostTileRightMargin)
        .padding(.vertical, Theme.hostTileVerticalMargin)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.hostTileHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.smallRadius)
                .fill(rowFocused ? Theme.accent.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.smallRadius)
                .stroke(rowFocused ? Theme.accent : Color.white.opacity(0.06),
                        lineWidth: rowFocused ? 2 : 1)
        )
        // Group all of this row's focusable children — focus engine treats
        // them as one navigable region, which means swiping Down from any
        // host moves focus to the next host (not the next inline action),
        // and swiping Right walks through the actions.
        .focusSection()
    }

    // MARK: - Subviews

    private var consoleIcon: some View {
        Image(systemName: host.state == .ready ? "playstation.logo" : "moon.zzz.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(host.state == .ready ? Theme.psBlue : Theme.tertiaryText)
            .padding(20)
    }

    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(host.nickname)
                .font(.system(size: Theme.baseFontSize, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            Text("Address: \(host.ipAddress.isEmpty ? "hidden" : host.ipAddress)")
                .font(.system(size: Theme.dialogHeaderFontSize))
                .foregroundStyle(Theme.secondaryText)

            Text("ID: \(host.mac.isEmpty ? "—" : host.mac) " +
                 "(\(host.registered ? "registered" : "unregistered"))")
                .font(.system(size: Theme.dialogHeaderFontSize))
                .foregroundStyle(Theme.secondaryText)

            Text(discoveryTag)
                .font(.system(size: Theme.dialogHeaderFontSize, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("State: \(host.state.rawValue)")
                .font(.system(size: Theme.dialogHeaderFontSize))
                .foregroundStyle(Theme.secondaryText)

            if let app = host.runningApp, !app.isEmpty {
                Text("App: \(app)")
                    .font(.system(size: Theme.dialogHeaderFontSize))
                    .foregroundStyle(Theme.secondaryText)
            }

            if let titleId = host.titleId, !titleId.isEmpty {
                Text("Title ID: \(titleId)")
                    .font(.system(size: Theme.dialogHeaderFontSize))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(width: 280, alignment: .leading)
    }

    private var actionStack: some View {
        VStack(spacing: 0) {
            // Primary action — topmost so directional navigation lands on
            // it first when entering the row.
            inlineAction(.connect, title: "Connect",
                         glyph: "play.circle.fill", action: onConnect)

            inlineAction(.delete,
                         title: host.discovered ? "Delete" : "Hide",
                         glyph: "square.fill", action: onDelete)

            if host.registered && host.state == .standby {
                inlineAction(.wake, title: "Wake Up",
                             glyph: "triangle.fill", action: onWakeUp)
            }

            if host.registered {
                inlineAction(.updatePin, title: "Update Pin",
                             glyph: "l1.button.roundedbottom.horizontal.fill",
                             action: onUpdatePin)
            }
        }
    }

    @ViewBuilder
    private func inlineAction(_ key: Action,
                              title: String, glyph: String,
                              action: @escaping () -> Void) -> some View {
        let isFocused = (focusedAction == key)
        Button(action: action) {
            HStack(spacing: 12) {
                if isFocused {
                    Image(systemName: glyph)
                        .font(.system(size: Theme.smallIconSize))
                        .frame(width: Theme.smallIconSize, height: Theme.smallIconSize)
                }
                Text(title)
                    .font(.system(size: Theme.baseFontSize, weight: .medium))
            }
            .padding(.leading, isFocused ? 50 : 0)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .foregroundStyle(Theme.primaryText)
        }
        .buttonStyle(.plain)
        .focused($focusedAction, equals: key)
    }

    private var discoveryTag: String {
        if host.manual && host.discovered {
            return "manual + discovered"
        } else if host.manual {
            return "manual"
        } else if host.discovered {
            return "discovered"
        } else {
            return "automatic"
        }
    }
}

#Preview {
    VStack(spacing: 4) {
        HostTile(host: .previewReady)
        HostTile(host: .previewStandby)
        HostTile(host: .previewManual)
    }
    .padding()
    .background(Theme.background)
}
