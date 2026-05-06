// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Top-level shell. Replaces the prior bespoke `ConfirmDialog` /
/// `RemindDialog` overlays with native `.alert(...)` modifiers per
/// [`docs/ui/redesign-v2-report.md §C5`](../../docs/ui/redesign-v2-report.md).
/// `errorToast` keeps its overlay treatment because toasts are non-blocking
/// and don't fit the alert primitive's blocking-modal semantics.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            currentRoute
                .transition(.opacity)
                .animation(.easeInOut(duration: Theme.stackTransitionDuration),
                           value: appState.route)

            if case .errorToast(let title, let message) = appState.modal {
                ErrorToastView(title: title,
                               message: message,
                               onDismiss: appState.dismissModal)
            }
        }
        .applyChiakiTheme()
        .alert(
            confirmModel?.title ?? "",
            isPresented: confirmBinding,
            presenting: confirmModel,
            actions: { model in
                // Cancel is the safer default focus on a destructive
                // confirm — the user can always dismiss via Menu / B,
                // but a visible Cancel button is the explicit affordance.
                Button("Cancel", role: .cancel) {
                    model.onReject?.perform()
                    appState.dismissModal()
                }
                Button("Confirm", role: .destructive) {
                    model.onConfirm.perform()
                    appState.dismissModal()
                }
            },
            message: { model in
                Text(model.message)
            }
        )
        .alert(
            infoTitle ?? "",
            isPresented: infoBinding,
            actions: {
                Button("OK", role: .cancel) { appState.dismissModal() }
            },
            message: {
                if let infoMessage { Text(infoMessage) }
            }
        )
        .alert(
            remindModel?.title ?? "",
            isPresented: remindBinding,
            presenting: remindModel,
            actions: { model in
                Button("Yes") {
                    model.onYes.perform()
                    appState.dismissModal()
                }
                Button("Later") {
                    model.onLater.perform()
                    appState.dismissModal()
                }
                Button("No", role: .cancel) {
                    model.onNo.perform()
                    appState.dismissModal()
                }
            },
            message: { model in
                Text(model.message)
            }
        )
    }

    // MARK: - Route switch

    @ViewBuilder
    private var currentRoute: some View {
        switch appState.route {
        case .hostList:                  HostListView()
        case .manualHost:                ManualHostDialog()
        case .registration(let host):    RegistrationView(host: host)
        case .consolePin(let hostId):    ConsolePinDialog(hostId: hostId)
        case .settings:                  SettingsView()
        case .stream:                    StreamView()
        case .autoConnect(let hostId):   AutoConnectView(hostId: hostId)
        }
    }

    // MARK: - Alert binding helpers
    //
    // Each alert reads/writes a slice of `appState.modal` via a computed
    // Binding<Bool>. When the user dismisses the alert (via Menu / B / OS
    // tap), SwiftUI sets `isPresented = false`; we translate that to
    // `appState.dismissModal()`.

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirm = appState.modal { return true }
                return false
            },
            set: { isShowing in
                if !isShowing { appState.dismissModal() }
            }
        )
    }

    private var confirmModel: ConfirmDialogModel? {
        if case .confirm(let model) = appState.modal { return model }
        return nil
    }

    private var infoBinding: Binding<Bool> {
        Binding(
            get: {
                if case .info = appState.modal { return true }
                return false
            },
            set: { isShowing in
                if !isShowing { appState.dismissModal() }
            }
        )
    }

    private var infoTitle: String? {
        if case .info(let title, _) = appState.modal { return title }
        return nil
    }

    private var infoMessage: String? {
        if case .info(_, let message) = appState.modal { return message }
        return nil
    }

    private var remindBinding: Binding<Bool> {
        Binding(
            get: {
                if case .remind = appState.modal { return true }
                return false
            },
            set: { isShowing in
                if !isShowing { appState.dismissModal() }
            }
        )
    }

    private var remindModel: RemindDialogModel? {
        if case .remind(let model) = appState.modal { return model }
        return nil
    }
}

#Preview {
    ContentView()
        .environment(AppState.preview())
}
