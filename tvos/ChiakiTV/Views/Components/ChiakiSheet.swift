// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Centered modal-style chrome for short-lived forms. Replaces the
/// back-chevron-toolbar full-screen pattern (`ChiakiDialogChrome`) for
/// the three "task forms": Manual Host, Console PIN, Registration. See
/// [`docs/ui/redesign-plan.md §4.5`](../../../docs/ui/redesign-plan.md).
///
/// **Visual model:** the underlying chiakiBackground stays in place; on top
/// we layer a semi-opaque scrim, then a single elevated card centred in the
/// viewport. The card holds a header (title + optional subtitle), the body
/// (caller-supplied), and an action bar (caller-supplied buttons).
///
/// **Why not SwiftUI's `.sheet()`:** AppState's existing routing model is a
/// `Route` enum that drives full-screen-replacement. Converting that to a
/// presentation-stack would touch ~6 sites. Visually rendering the route
/// *as* a modal — without changing the routing primitive — gives us the new
/// look in one swap-in per call site.
struct ChiakiSheet<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String? = nil
    let onBack: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider()
                    .background(Theme.ink600)
                    .padding(.horizontal, Theme.modalContentPadding)
                contentArea
                Divider()
                    .background(Theme.ink600)
                    .padding(.horizontal, Theme.modalContentPadding)
                actionBar
            }
            .frame(maxWidth: Theme.modalMaxWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: Theme.modalCorner,
                                 style: .continuous)
                    .fill(Theme.ink800)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.modalCorner,
                                 style: .continuous)
                    .stroke(Theme.ink600, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.6), radius: 60, x: 0, y: 24)
            .padding(80)
        }
        .chiakiBackground()
        .onExitCommand(perform: onBack)
    }

    private var header: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(Theme.font(.titleLarge).weight(.semibold))
                .foregroundStyle(Theme.white50)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.font(.bodyMed))
                    .foregroundStyle(Theme.mist500)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, Theme.modalContentPadding)
    }

    private var contentArea: some View {
        content()
            .padding(.vertical, 24)
            .padding(.horizontal, Theme.modalContentPadding)
            .frame(maxWidth: .infinity)
            .focusSection()
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            Spacer()
            footer()
        }
        .padding(.vertical, 18)
        .padding(.horizontal, Theme.modalContentPadding)
        .focusSection()
    }
}

extension ChiakiSheet where Footer == EmptyView {
    init(title: String,
         subtitle: String? = nil,
         onBack: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.content = content
        self.footer = { EmptyView() }
    }
}

// MARK: - Sheet action buttons

/// Primary footer button — amber gradient, ink-on-amber type. Affirmative
/// action only (Add / Set / Register).
struct ChiakiSheetPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let s = systemImage {
                    Image(systemName: s)
                        .font(.system(size: 22, weight: .semibold))
                }
                Text(title)
                    .font(Theme.font(.titleMed).weight(.bold))
                    .tracking(0.5)
            }
            .foregroundStyle(Theme.ink900)
            .frame(minWidth: 220, minHeight: 64)
            .padding(.horizontal, 28)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Theme.amber400, Theme.amber500],
                        startPoint: .topLeading,
                        endPoint:   .bottomTrailing
                    ))
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.35)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .disabled(!isEnabled)
        .chiakiFocusRing(isFocused, cornerRadius: 16)
        .animation(Theme.focusSpring, value: isFocused)
    }
}

/// Secondary footer button — ink-700 fill, mist-300 type. Cancel / back.
struct ChiakiSheetSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let s = systemImage {
                    Image(systemName: s)
                        .font(.system(size: 20, weight: .medium))
                }
                Text(title)
                    .font(Theme.font(.titleMed))
            }
            .foregroundStyle(Theme.mist300)
            .frame(minWidth: 160, minHeight: 64)
            .padding(.horizontal, 28)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.ink700)
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .chiakiFocusRing(isFocused, cornerRadius: 16)
        .animation(Theme.focusSpring, value: isFocused)
    }
}
