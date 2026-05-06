// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// The in-stream menu — slides up from the bottom over the video. Mirrors
/// [`gui/src/qml/StreamMenuWindow.qml`](../../../../gui/src/qml/StreamMenuWindow.qml).
///
/// Slimmed for the LAN-only port (see [`docs/ui/swift-ui-plan.md`](../../docs/ui/swift-ui-plan.md) §1):
///   • Disconnect (left)
///   • Volume slider
///   • Stretch / Default-preset toggle pair
///   • "Connected to …" host label (right)
///
/// Live telemetry (bitrate, packet loss, audio buffer, dropped frames, FEC)
/// lives in [`StreamHUDOverlay`](StreamHUDOverlay.swift) — pinned to the top
/// centre of the screen and visible at a glance during gameplay, instead of
/// only when the user pulls up this menu. Toggleable via
/// `AppSettings.showStreamStats` (Settings → General).
///
/// 250 ms vertical slide; `#2b2b2b` background; bottomMargin 40, leftMargin 30.
struct StreamMenuOverlay: View {
    @Binding var isPresented: Bool
    @Binding var stretch: Bool
    @Binding var volume: Int              // 0...100
    var connectedTo: String = ""
    var onDisconnect: () -> Void = {}

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .center, spacing: 0) {
                ToolButton(systemImage: "xmark") {
                    onDisconnect()
                }
                .padding(.horizontal, 10)

                Divider().frame(width: 1, height: 60).background(Theme.tertiaryText)

                volumeColumn
                    .padding(.horizontal, 10)

                Divider().frame(width: 1, height: 60).background(Theme.tertiaryText)

                ToolToggle(systemImage: "rectangle.expand.vertical",
                           label: "Stretch", isOn: $stretch)
                    .padding(.horizontal, 10)

                Spacer()

                connectedLabel
            }
            .padding(.leading, 30)
            .padding(.trailing, 30)
            .padding(.bottom, 40)
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
            .background(Theme.streamMenuSurface)
        }
        .ignoresSafeArea()
        .transition(.move(edge: .bottom))
        .animation(.easeInOut(duration: Theme.streamMenuSlide), value: isPresented)
        .onExitCommand { isPresented = false }
    }

    // MARK: - Subviews

    private var volumeColumn: some View {
        VStack(spacing: 4) {
            ChiakiStepper(value: $volume, range: 0...100, step: 5, width: 60)
            Text("Volume")
                .font(.system(size: Theme.streamHudLabelFontSize))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var connectedLabel: some View {
        if !connectedTo.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Connected to")
                    .font(.system(size: Theme.streamHudLabelFontSize))
                    .foregroundStyle(Theme.tertiaryText)
                Text(connectedTo)
                    .font(.system(size: Theme.streamHudCounterFontSize, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
            }
        }
    }
}

// MARK: - HUD button primitives

private struct ToolButton: View {
    let systemImage: String
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.streamMenuCloseFontSize, weight: .light))
                .foregroundStyle(Theme.primaryText)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.smallRadius)
                        .fill(isFocused ? Theme.accent : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

private struct ToolToggle: View {
    let systemImage: String
    let label: String
    @Binding var isOn: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: Theme.smallIconSize))
                Text(label)
                    .font(.system(size: Theme.streamHudLabelFontSize))
            }
            .padding(10)
            .frame(width: 100)
            .foregroundStyle(Theme.primaryText)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .fill(isOn ? Theme.accent.opacity(0.4) :
                          (isFocused ? Theme.accent.opacity(0.2) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        StreamMenuOverlay(
            isPresented: .constant(true),
            stretch: .constant(false),
            volume: .constant(80 as Int),
            connectedTo: "Living Room PS5"
        )
    }
}
