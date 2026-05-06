# tvOS Constraints

What tvOS does *not* let us do, and what we do about it.

## Multicast / broadcast

- **iOS / tvOS 14+** require `com.apple.developer.networking.multicast` to send to multicast addresses (`239.0.0.0/8`) or the broadcast `255.255.255.255`.
- **In practice**, sending UDP broadcast packets *to* a unicast LAN address (`192.168.1.x`) doesn't trigger this — and chiaki-lib's discovery does send to `255.255.255.255:9302` from `lib/src/discovery.c:251`.
- **For personal-use builds** signed with a personal team, the entitlement can be enabled if the developer account has it; for App Store distribution it requires Apple's manual review (1–8 weeks).
- **Our position**: don't ask for the entitlement on the dev / sideload path. If discovery breaks under a future tvOS release, add the entitlement; until then leave it off and rely on UDP broadcast working in practice + manual host entry as the fallback.

See the original investigation [`../../TVOS_PORT_INVESTIGATION.md`](../../TVOS_PORT_INVESTIGATION.md) §6.3 for the deeper context.

## No microphone, no speech APIs

Apple TV has no built-in microphone. The DualSense's mic is not exposed to the system via `AVCaptureDevice`. So:

- The `gui/src/streamsession.cpp` mic-capture + Speex echo-cancel path doesn't apply.
- We send silence packets on the mic channel via `chiaki_audiosender_*`. PS5 accepts that.

## App sandbox

- App container: `~/Library/...`-equivalent, accessible via `FileManager.default.urls(for:in:)`.
- No spawning child processes (no `fork`, no `exec`). chiaki-lib doesn't do this anyway.
- No reading from outside the container; no `FSEvents` or arbitrary-path APIs.
- Keychain access works.

## App suspend / background behavior

- tvOS does suspend foreground apps when the user goes home, and re-launches with state restoration; the streaming session must teardown cleanly on `applicationWillResignActive` and re-establish on `applicationDidBecomeActive`.
- No background networking. The streaming session has to be foreground.

## Local Network access prompt

- First send to a non-loopback address triggers the system permission prompt:
  > "ChiakiTV would like to find and connect to devices on your local network."
- The prompt copy comes from `NSLocalNetworkUsageDescription` in `Info.plist`.
- If the user denies, all LAN access fails silently. Have a recovery UI ("re-enable in Settings → ChiakiTV → Local Network").

## Input restrictions

- No keyboard / mouse on the streaming UI by default. tvOS supports an external Bluetooth keyboard via `GCKeyboard` (tvOS 14+) — useful for the host-list IP-entry text field via the on-screen keyboard, but the streaming view is controller-only.
- Siri Remote has only a touchpad + click — usable for menu navigation but not for actual gameplay input. Long-press gestures need to use `GCEventViewController.controllerUserInteractionEnabled = false` to be reliably captured.

## App size / RAM

- App Store IPA limit: 4 GB. We're nowhere near it.
- Per-app RAM: not formally documented; A15 has 4 GB total. Streaming allocates a few hundred MB at most (decode pool + Metal textures + ring buffers + Swift runtime). No concern at our scale.

## Code signing

- Personal-use sideload requires a free Apple Developer account (7-day cert) or paid ($99/yr, 1-year cert). For a living-room install, the paid cert is the convenient path.
- App Store distribution is out of scope (see [`../decisions.md`](../decisions.md)).

## VPN / DNS / proxy

- tvOS supports system VPN profiles (configured via tvOS Settings) and that does cover our app's traffic. For LAN-only personal use this isn't relevant.
- Proxy: tvOS does not honor system HTTP proxies for app sockets. Not a concern here since we don't go through HTTP proxies.

## HDMI-CEC

- Apple TV can interact with the TV via HDMI-CEC (turn on, switch input). We don't drive this — the user opens the app, the TV is on, the streaming starts.

## Why none of this matters very much for ChiakiTV specifically

LAN-only + personal-use + dev-cert collapses most of the tvOS friction surface. We don't need:

- App Store review compliance
- Multicast entitlement approval (probably)
- Microphone permission flows
- Background modes
- Family Sharing tax
- Privacy manifests beyond the bare `NSLocalNetworkUsageDescription`

…which is exactly the scope cut documented in [`../decisions.md#scope--lan-only-no-psn-oauth-no-app-store`](../decisions.md#scope--lan-only-no-psn-oauth-no-app-store).
