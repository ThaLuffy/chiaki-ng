// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Top-level shell. Mirrors [`gui/src/qml/Main.qml`](../../../gui/src/qml/Main.qml):
///
/// - A single `ZStack` that switches its primary child on `AppState.route`
///   with a 200 ms opacity cross-fade (the desktop's `StackView.replace`
///   animation duration).
/// - Modal overlays — `ConfirmDialog`, `RemindDialog`, info dialog, error
///   toast — stack on top regardless of route, matching the desktop's
///   "Overlay.overlay parent" modal pattern.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Cross-fade routes via .transition + .animation. We deliberately
            // do NOT pin .id(appState.route) on top of this — `_ConditionalContent`
            // already provides distinct identities per case, and stacking an
            // explicit `.id` resets state on every change (per the
            // swiftui-performance "Top-level conditional view swapping" rule).
            currentRoute
                .transition(.opacity)
                .animation(.easeInOut(duration: Theme.stackTransitionDuration),
                           value: appState.route)

            modalOverlay
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Route switch

    @ViewBuilder
    private var currentRoute: some View {
        switch appState.route {
        case .hostList:
            HostListView()
        case .manualHost:
            ManualHostDialog()
        case .registration(let host):
            RegistrationView(host: host)
        case .consolePin(let hostId):
            ConsolePinDialog(hostId: hostId)
        case .settings:
            SettingsView()
        case .stream:
            StreamView()
        case .autoConnect(let hostId):
            AutoConnectView(hostId: hostId)
        }
    }

    // MARK: - Modal layer

    @ViewBuilder
    private var modalOverlay: some View {
        if let modal = appState.modal {
            switch modal {
            case .confirm(let model):
                ConfirmDialog(model: model, onDismiss: appState.dismissModal)
            case .remind(let model):
                RemindDialog(model: model, onDismiss: appState.dismissModal)
            case .info(let title, let message):
                // Info dialogs have no reject path — we hand `ConfirmDialog` a
                // no-op reject so its `.onExitCommand` can still dismiss the
                // modal when the user presses Menu / B.
                ConfirmDialog(model: ConfirmDialogModel(
                    title: title,
                    message: message,
                    onConfirm: ConfirmAction.noop,
                    onReject: ConfirmAction.noop
                ), onDismiss: appState.dismissModal)
            case .errorToast(let title, let message):
                ErrorToastView(title: title, message: message,
                               onDismiss: appState.dismissModal)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState.preview())
}
