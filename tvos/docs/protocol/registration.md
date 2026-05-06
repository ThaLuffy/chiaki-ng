# Registration

> Owner: upstream chiaki-ng `lib/`. This page summarizes with citations and captures tvOS-port-specific orchestration.

## Source files

- [`../../lib/src/regist.c`](../../lib/src/regist.c) — full registration flow
- [`../../lib/src/rpcrypt.c`](../../lib/src/rpcrypt.c) — `ps5_keys_0` / `ps5_keys_1` lookup tables, AES-CFB128 inner-payload encryption
- [`../../lib/include/chiaki/regist.h`](../../lib/include/chiaki/regist.h) — public API + `ChiakiRegistEvent`

## What the user types

- **PIN** (4 digits PS5, 8 digits PS4 — out of scope). Displayed by the PS5 under `Settings → System → Remote Play → Link Device`.
- **PSN account ID** (8 bytes, base64-encoded as ~12 ASCII chars, e.g. `xQuLZJEmkbo=`).

## Why prefilled, not OAuth

In this port the account ID is **prefilled in settings** rather than retrieved via PSN OAuth — see [`../decisions.md#prefill-psn-account-id-no-oauth`](../decisions.md#prefill-psn-account-id-no-oauth). Acquisition path:

1. Run desktop chiaki-ng on macOS / Linux / Windows.
2. Register against the PS5 there once (it does the OAuth dance via QtWebEngine).
3. Open the desktop's settings file and copy `account_id`.
4. Paste into ChiakiTV's settings.

Alternative: run [`../../scripts/psn-account-id.py`](../../scripts/psn-account-id.py) or [`../../scripts/psn-account-id.go`](../../scripts/psn-account-id.go) standalone with a Sony OAuth token. Either way, the result is an 8-byte ID.

## tvOS-side wrapper plan (Phase 1)

`Services/Session/RegistrationService.swift` (TBD name) wraps `chiaki_regist_start`:

```swift
struct RegistRequest {
    let host: String           // PS5 LAN IP
    let target: ChiakiTarget   // PS5_1 (latest)
    let pin: UInt32            // 4-digit PIN typed by user
    let accountId: Data        // 8 bytes from settings (prefilled)
    let psnOnlineId: String?   // unused for PS5 — leave nil
}

func register(_ req: RegistRequest, onEvent: (ChiakiRegistEvent) -> Void) async throws -> RegisteredHost
```

The bridge translates `ChiakiRegistEvent` callbacks into a Swift enum and surfaces them to the UI for live progress feedback ("Connecting…", "PIN accepted", "Generating key…", "Done").

## What gets persisted

On success, chiaki-lib hands us a `ChiakiRegisteredHost` containing:

- `ap_ssid`, `ap_bssid` — Access Point info (LAN-relevant only)
- `rp_regist_key` (16 bytes)
- `rp_key` (16 bytes)
- `rp_key_type` (PS4/PS5)
- `server_mac` (6 bytes)
- `server_nickname`

We persist this on disk in `Application Support/ChiakiTV/registered_hosts.json` (Codable). The Phase 1 `Settings/SettingsStore.swift` owns the file.

## Reference: desktop and sibling implementations

- Desktop GUI: [`../../gui/src/qml/RegistDialog.qml`](../../gui/src/qml/RegistDialog.qml) drives `chiaki_regist_start` via `gui/src/qmlbackend.cpp`.
- Sibling ps-remote-play: re-implemented registration in Swift; see [`../../../ps-remote-play/docs/protocol/registration.md`](../../../ps-remote-play/docs/protocol/registration.md) for an independent breakdown of byte layouts and key derivation. We *don't* re-implement — we use chiaki-lib — but the sibling doc is a good sanity check.
