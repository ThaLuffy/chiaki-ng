# Bridge Layer

The `ChiakiBridgeC` module is the only place Swift talks to chiaki-ng's `lib/`. Phase 0 shipped a smoke-test version function and a link smoke-test (`chiaki_log_level_char` round-trip). Phase 1 has begun filling in typed wrappers — discovery is the first one and is documented in [§Discovery service](#discovery-service-shipped-2026-05-05) below.

## Why a separate bridge instead of importing `chiaki/*.h` from Swift directly

Swift can in principle import a C module directly. Two reasons we don't:

1. **Callback ergonomics.** chiaki-lib uses C function pointers (`void (*cb)(uint8_t *buf, size_t buf_size, void *user)`). Swift can pass a `@convention(c)` function pointer, but it can't capture state — so every callback signature needs a thin C trampoline that knows how to bounce into a Swift method. Centralizing those trampolines keeps the per-call overhead known.
2. **Hot-path discipline.** The video / audio callbacks fire at packet rate. Letting them flow into Swift through a generated import surface invites `Data`/`Array` copies. A hand-written bridge gives us a place to enforce the zero-allocation rule in code, not just in policy.

## Surface (Phase 1 plan)

```c
// chiaki_bridge.h (Phase 1 sketch — not yet written)

// ── Log routing ────────────────────────────────────────────────────────
typedef void (*chiaki_tv_log_fn)(int level, const char *line, void *user);
void chiaki_tv_set_log_callback(chiaki_tv_log_fn fn, void *user);
// chiaki-lib calls our log callback; we route into Swift Logger via OSLog.

// ── Session lifecycle ──────────────────────────────────────────────────
typedef struct chiaki_tv_session_handle chiaki_tv_session_handle;
chiaki_tv_session_handle *chiaki_tv_session_create(/* …connect info… */);
int  chiaki_tv_session_start(chiaki_tv_session_handle *h);
void chiaki_tv_session_stop(chiaki_tv_session_handle *h);
void chiaki_tv_session_destroy(chiaki_tv_session_handle *h);

// ── Video sample push ──────────────────────────────────────────────────
typedef bool (*chiaki_tv_video_sample_fn)(
    uint8_t *buf, size_t buf_size, int32_t frames_lost, bool frame_recovered, void *user);
void chiaki_tv_session_set_video_sample_callback(
    chiaki_tv_session_handle *h, chiaki_tv_video_sample_fn fn, void *user);
// fn must be allocation-free. Swift wraps via UnsafeMutableBufferPointer.

// ── Audio sink push ────────────────────────────────────────────────────
typedef void (*chiaki_tv_audio_frame_fn)(
    int16_t *pcm, size_t pcm_samples, void *user);
void chiaki_tv_session_set_audio_callback(
    chiaki_tv_session_handle *h, chiaki_tv_audio_frame_fn fn, void *user);

// ── Controller state push (Swift → C) ──────────────────────────────────
typedef struct chiaki_tv_controller_state {
    uint32_t buttons;
    uint8_t  l2, r2;
    int16_t  lx, ly, rx, ry;
    int16_t  gyro_x, gyro_y, gyro_z;
    int16_t  accel_x, accel_y, accel_z;
    // …touchpad fingers, orientation, etc.
} chiaki_tv_controller_state;
void chiaki_tv_session_set_controller_state(
    chiaki_tv_session_handle *h, const chiaki_tv_controller_state *state);
```

The Phase 0 stubs are `chiaki_tv_bridge_version()` and `chiaki_tv_lib_version_packed()` — see [`../../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge.h`](../../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge.h).

## Discovery service (shipped 2026-05-05)

The first typed Phase 1 wrapper. Header [`../../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_discovery.h`](../../ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_discovery.h), implementation [`../../ChiakiBridgeC/src/chiaki_bridge_discovery.c`](../../ChiakiBridgeC/src/chiaki_bridge_discovery.c), Swift driver [`../../ChiakiTV/Services/Discovery/DiscoveryService.swift`](../../ChiakiTV/Services/Discovery/DiscoveryService.swift).

### Shape

```c
typedef struct {
    chiaki_tv_discovery_host_state_t state;  // unknown | ready | standby
    uint16_t host_request_port;
    bool ps5;
    const char *host_addr;
    const char *system_version;
    const char *device_discovery_protocol_version;
    const char *host_name;
    const char *host_type;
    const char *host_id;
    const char *running_app_titleid;
    const char *running_app_name;
} chiaki_tv_discovery_host_t;

typedef void (*chiaki_tv_discovery_cb)(
    const chiaki_tv_discovery_host_t *hosts, size_t count, void *user);

chiaki_tv_discovery_service_t *chiaki_tv_discovery_service_create(
    chiaki_tv_discovery_cb cb, void *cb_user);
void chiaki_tv_discovery_service_destroy(chiaki_tv_discovery_service_t *service);

bool chiaki_tv_discovery_service_send_wakeup(
    const char *host_ip, const char *regist_key_hex, bool ps5);
```

### Why the POD reshape

Upstream's `ChiakiDiscoveryServiceCb` hands you a `ChiakiDiscoveryHost *`. Its `const char *` members live inside chiaki-lib's mutex-protected internal storage (see `lib/src/discoveryservice.c:122–128` for the `free` path). Swift cannot retain those pointers across the callback return — the next ping-and-drop frees them. The bridge snapshots into a stack array of `chiaki_tv_discovery_host_t` (POD) inside the chiaki callback while the lib mutex is still held, hands Swift a pointer that is *only* valid during the call, and Swift copies into Swift `String` synchronously. The 16-host cap matches `CHIAKI_TV_DISC_HOSTS_MAX`, so the stack array is bounded.

### Broadcast addresses

The implementation mirrors the desktop's POSIX path (`gui/src/discoverymanager.cpp:151–202`): send to `255.255.255.255` (limited broadcast) AND each up/running interface's directed broadcast via `getifaddrs()`. Some consumer Wi-Fi gear filters limited broadcast; per-interface directed broadcast is what makes discovery reliable across routers. IPv6 (`FF02::1`) is dropped — out of scope for this LAN-only port.

### Threading & lifecycle

The chiaki callback runs on its own discovery thread, holding `service->state_mutex`. Inside the bridge:

1. Shape into the POD snapshot array (no allocation, no lib calls outside the mutex's protection).
2. Hand to the Swift trampoline.
3. Swift copies into Swift `String` and dispatches a `Task { @MainActor in ... }` to publish.
4. Return — the lib unlocks the mutex.

`chiaki_tv_discovery_service_destroy` calls `chiaki_discovery_service_fini`, which joins the discovery thread before returning. Once destroy returns, no further callbacks can fire — Swift's `DiscoveryService.deinit` and `stop()` rely on this contract for safety.

### Wakeup

`chiaki_tv_discovery_service_send_wakeup` is independent of any active service — chiaki creates a temporary `ChiakiDiscovery` internally per `chiaki_discovery_wakeup`. Hex-string parsing matches the desktop's `DiscoveryManager::SendWakeup` (`gui/src/discoverymanager.cpp:286–292`): up to 8 hex chars, parsed with `strtoull` base 16. We surface this through `DiscoveryService.sendWakeup(hostIp:registKeyHex:ps5:)`.

## Hot-path rules for the bridge

These mirror Hard Rules #2–#5 from [`../../AGENTS.md`](../../AGENTS.md):

1. **No malloc inside any function called per-packet.** All buffers are caller-owned. The Swift consumer is responsible for any necessary persistence.
2. **No `Data` / `Array` / `String` allocations on the Swift side of these callbacks.** Use `UnsafeBufferPointer` views over the C-side buffer. If you need to copy, copy into a pre-allocated Swift buffer.
3. **No `MainActor` hops on the per-packet path.** The video / audio callbacks dispatch onto dedicated `userInteractive` queues (`videoDispatchQueue`, `audioDispatchQueue`) directly via `dispatch_async`, *not* via `Task { @MainActor in … }`.
4. **No locks on the per-packet path.** `MetalRenderer.pendingPixelBuffer` is a single-slot atomic store; the audio ring buffer is lock-free. If a service needs a lock, it goes outside the per-packet path (init/teardown only).

## Mapping callbacks to Swift methods

Pattern: every C callback that targets a Swift instance follows the trampoline shape:

```c
static void chiaki_tv_video_sample_trampoline(uint8_t *buf, size_t buf_size,
                                              int32_t frames_lost, bool recovered,
                                              void *user) {
    /* user is a __bridge-retained Unmanaged<MyClass>.toOpaque() */
    __unsafe_unretained id<ChiakiTVVideoSink> sink =
        (__bridge id<ChiakiTVVideoSink>)user;
    [sink consumeNAL:buf length:buf_size lost:frames_lost recovered:recovered];
}
```

…or in pure C with a Swift `@objc` protocol on the consumer side. Phase 1 will pin down whether we use `@objc` protocols or `@convention(c)` Swift closures with `Unmanaged.fromOpaque(user)` — the choice depends on whether we need ARC-aware ownership of the consumer (probably yes; sessions outlive their callbacks).

## Logging route

chiaki-lib emits log lines via `ChiakiLog *log` (`../../lib/include/chiaki/log.h`). Pattern:

```
chiaki_log_init(&log, mask, chiaki_tv_log_callback, swift_logger_ptr);
```

…where `chiaki_tv_log_callback` is a C function in `chiaki_bridge.c` that translates the C `(level, line)` into a Swift `Logger.log(level: .debug, "\(line, privacy: .public)")` via the global `chiakiLog(_:category:type:)` shim. Phase 1 will wire this up so every chiaki-lib log line shows up in `Console.app` under `subsystem=org.streetpea.chiakitv`, alongside Swift's own output.
