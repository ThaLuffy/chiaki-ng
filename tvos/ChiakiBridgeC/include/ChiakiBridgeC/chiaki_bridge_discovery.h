/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * @file chiaki_bridge_discovery.h
 * @brief Typed Swift-friendly wrapper around chiaki-lib's ChiakiDiscoveryService.
 *
 * Why a wrapper at all? `ChiakiDiscoveryHost` exposes raw `const char *` fields
 * that live inside chiaki-lib's mutex-protected internal storage. Swift cannot
 * safely retain those pointers across the callback return — the next ping that
 * drops a host frees them. We snapshot into a flat POD struct on the stack
 * during the callback and hand Swift a pointer that's only valid during the
 * call. Swift copies into Swift `String` synchronously and we unwind.
 *
 * Reference: ../../lib/include/chiaki/discoveryservice.h, ../../gui/src/discoverymanager.cpp.
 */

#ifndef CHIAKI_BRIDGE_DISCOVERY_H
#define CHIAKI_BRIDGE_DISCOVERY_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Mirrors chiaki/discovery.h ChiakiDiscoveryHostState. Re-declared here so the
 * Swift module doesn't have to import the upstream header transitively. */
typedef enum {
    CHIAKI_TV_DISCOVERY_HOST_STATE_UNKNOWN = 0,
    CHIAKI_TV_DISCOVERY_HOST_STATE_READY = 1,
    CHIAKI_TV_DISCOVERY_HOST_STATE_STANDBY = 2,
} chiaki_tv_discovery_host_state_t;

/**
 * Flat snapshot of one ChiakiDiscoveryHost. The `const char *` fields point
 * into chiaki-lib-owned storage and are ONLY valid during the callback that
 * received them. Copy into Swift `String` synchronously.
 */
typedef struct {
    chiaki_tv_discovery_host_state_t state;
    uint16_t host_request_port;
    bool ps5;
    /* All strings may be NULL. */
    const char *host_addr;
    const char *system_version;
    const char *device_discovery_protocol_version;
    const char *host_name;
    const char *host_type;
    const char *host_id;
    const char *running_app_titleid;
    const char *running_app_name;
} chiaki_tv_discovery_host_t;

/**
 * Called from chiaki's discovery thread whenever the host set changes (a new
 * host appeared, an existing host changed state, or a host was dropped after
 * missing too many pings). Holds chiaki-lib's state mutex for its duration —
 * MUST return promptly, MUST NOT take other chiaki-lib locks, MUST copy any
 * strings out of the host snapshots before returning.
 */
typedef void (*chiaki_tv_discovery_cb)(
    const chiaki_tv_discovery_host_t *hosts,
    size_t hosts_count,
    void *user);

/* Opaque handle. Owned by Swift via DiscoveryService. */
typedef struct chiaki_tv_discovery_service chiaki_tv_discovery_service_t;

/**
 * Spin up the IPv4 discovery service. Sends SRCH packets to:
 *   - 255.255.255.255 (limited broadcast)
 *   - each up/running interface's directed broadcast (matches desktop's
 *     getifaddrs() walk in gui/src/discoverymanager.cpp)
 * Listens on UDP for replies and invokes `cb` on every state change.
 *
 * Returns NULL on failure. On success the caller must eventually call
 * `chiaki_tv_discovery_service_destroy` to join the thread and free
 * resources.
 *
 * The callback runs on chiaki's discovery thread; see `chiaki_tv_discovery_cb`
 * for the contract.
 */
chiaki_tv_discovery_service_t *chiaki_tv_discovery_service_create(
    chiaki_tv_discovery_cb cb,
    void *cb_user);

/**
 * Stop the discovery thread, fini the underlying ChiakiDiscoveryService, and
 * free all bridge state. Safe to call with NULL.
 */
void chiaki_tv_discovery_service_destroy(chiaki_tv_discovery_service_t *service);

/**
 * Send a wakeup (Wake-on-LAN-style) packet to a standby PS5. The
 * `regist_key_hex` is the 8-char ASCII representation of the registration key
 * (matching the desktop's `DiscoveryManager::SendWakeup` parsing). Returns
 * true on success.
 *
 * Independent of any active discovery service — creates a temporary one
 * internally per chiaki_discovery_wakeup's contract.
 */
bool chiaki_tv_discovery_service_send_wakeup(
    const char *host_ip,
    const char *regist_key_hex,
    bool ps5);

#ifdef __cplusplus
}
#endif

#endif /* CHIAKI_BRIDGE_DISCOVERY_H */
