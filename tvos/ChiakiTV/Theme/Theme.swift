// SPDX-License-Identifier: AGPL-3.0-only
//
// Material Dark palette + spacing tokens, mapped 1:1 from the desktop chiaki-ng
// QML GUI. Every value is justified in docs/ui/original-gui-spec.md.

import SwiftUI

enum Theme {

    // MARK: - Palette (Material Dark)

    /// `#00a7ff` — the only chromatic color used app-wide.
    /// Desktop source: gui/src/qml/qtquickcontrols2.conf
    static let accent = Color(red: 0.0,   green: 0.655, blue: 1.0)

    /// `#303030` — Qt Material Dark window background.
    static let background = Color(red: 0.188, green: 0.188, blue: 0.188)

    /// `#424242` — Qt Material Dark elevated surface (toolbars, dialog bg).
    static let surface = Color(red: 0.259, green: 0.259, blue: 0.259)

    /// `#2b2b2b` — the in-stream menu bar background.
    /// Desktop source: gui/src/qml/StreamMenuWindow.qml:84
    static let streamMenuSurface = Color(red: 0.169, green: 0.169, blue: 0.169)

    static let primaryText   = Color.white
    static let secondaryText = Color.white.opacity(0.7)
    static let tertiaryText  = Color.white.opacity(0.45)

    /// `#ef9a9a` — packet-loss + dropped-frame counters in the stream HUD.
    /// Desktop source: gui/src/qml/StreamMenuWindow.qml:404
    static let errorRed = Color(red: 0.937, green: 0.604, blue: 0.604)

    // MARK: - Spacing (px from the desktop spec)

    static let toolbarHeight:          CGFloat = 80
    static let dialogTopMargin:        CGFloat = 20
    static let dialogColumnSpacing:    CGFloat = 20
    static let dialogRowSpacing:       CGFloat = 20
    static let dialogFieldWidth:       CGFloat = 400

    static let hostTileHeight:         CGFloat = 180
    static let hostTileLeftMargin:     CGFloat = 30
    static let hostTileRightMargin:    CGFloat = 10
    static let hostTileVerticalMargin: CGFloat = 10
    static let hostTileSubitemSpacing: CGFloat = 50
    static let consoleIconWidth:       CGFloat = 150

    static let smallIconSize:          CGFloat = 28
    static let largeIconSize:          CGFloat = 50

    static let toastBottomMargin:      CGFloat = 30
    static let toastInsetH:            CGFloat = 20
    static let toastInsetV:            CGFloat = 10

    // MARK: - Typography

    static let baseFontSize:                CGFloat = 20
    static let dialogTitleFontSize:         CGFloat = 26
    static let dialogHeaderFontSize:        CGFloat = 14
    static let toolbarOkFontSize:           CGFloat = 25
    static let errorTitleFontSize:          CGFloat = 24
    static let errorTextFontSize:           CGFloat = 20
    static let bigCloseFontSize:            CGFloat = 60     // "×" close button
    static let streamMenuCloseFontSize:     CGFloat = 50
    static let streamHudBitrateFontSize:    CGFloat = 28
    static let streamHudCounterFontSize:    CGFloat = 18
    static let streamHudLabelFontSize:      CGFloat = 15

    // MARK: - Animation (seconds)

    static let stackTransitionDuration: Double = 0.20
    static let toastFadeDuration:       Double = 0.50
    static let streamLoadFade:          Double = 0.25
    static let streamMenuSlide:         Double = 0.25
    static let logoPulseDuration:       Double = 1.00

    // MARK: - Radii

    static let smallRadius:  CGFloat = 4    // Material.SmallScale
    static let mediumRadius: CGFloat = 8    // Material.MediumScale
}

// MARK: - View modifiers

extension View {
    /// Dark gradient backdrop used by HostListView + main shell.
    func chiakiBackground() -> some View {
        self.background(
            LinearGradient(
                colors: [Theme.background, Color(red: 0.0, green: 0.22, blue: 0.45).opacity(0.3), Theme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}
