/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * IPv4-only discovery service wrapper. Mirrors the POSIX path of
 * gui/src/discoverymanager.cpp:151–202 (interface enumeration via
 * getifaddrs() + 255.255.255.255) but drops:
 *   - IPv6 (out of scope — single-LAN personal port; no link-local
 *     multicast entitlement needed)
 *   - Qt threading (callback delivery hops to MainActor on the Swift side)
 *   - Manual hosts (handled separately on the Swift side)
 *
 * Why mirror the POSIX path verbatim? Some routers don't forward limited
 * broadcast (255.255.255.255). Sending to per-interface directed broadcast
 * is what makes discovery reliable across consumer Wi-Fi gear; this is
 * also why upstream chiaki does it.
 */

#include "ChiakiBridgeC/chiaki_bridge_discovery.h"

#include <chiaki/discoveryservice.h>
#include <chiaki/discovery.h>
#include <chiaki/log.h>

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <net/if.h>
#include <ifaddrs.h>

/* Same magic numbers the desktop uses (gui/src/discoverymanager.cpp:21–23). */
#define CHIAKI_TV_DISC_PING_MS         500
#define CHIAKI_TV_DISC_HOSTS_MAX       16
#define CHIAKI_TV_DISC_DROP_PINGS      3

struct chiaki_tv_discovery_service {
    ChiakiLog log;
    ChiakiDiscoveryService service;
    bool service_active;

    chiaki_tv_discovery_cb user_cb;
    void *user_cb_user;
};

/*
 * Reshape callback. Runs on chiaki's discovery thread, holding
 * service->state_mutex (see lib/src/discoveryservice.c:385). Allocates a
 * stack array of POD snapshots and forwards to the user's callback.
 *
 * The 16-host cap matches CHIAKI_TV_DISC_HOSTS_MAX, so the stack array is
 * bounded.
 */
static void chiaki_tv_discovery_reshape_cb(
    ChiakiDiscoveryHost *hosts, size_t hosts_count, void *user)
{
    struct chiaki_tv_discovery_service *self = user;
    if(!self || !self->user_cb)
        return;

    if(hosts_count > CHIAKI_TV_DISC_HOSTS_MAX)
        hosts_count = CHIAKI_TV_DISC_HOSTS_MAX;

    chiaki_tv_discovery_host_t snapshot[CHIAKI_TV_DISC_HOSTS_MAX];
    memset(snapshot, 0, sizeof(snapshot));

    for(size_t i = 0; i < hosts_count; i++) {
        ChiakiDiscoveryHost *src = &hosts[i];
        chiaki_tv_discovery_host_t *dst = &snapshot[i];

        switch(src->state) {
            case CHIAKI_DISCOVERY_HOST_STATE_READY:
                dst->state = CHIAKI_TV_DISCOVERY_HOST_STATE_READY;
                break;
            case CHIAKI_DISCOVERY_HOST_STATE_STANDBY:
                dst->state = CHIAKI_TV_DISCOVERY_HOST_STATE_STANDBY;
                break;
            default:
                dst->state = CHIAKI_TV_DISCOVERY_HOST_STATE_UNKNOWN;
                break;
        }
        dst->host_request_port = src->host_request_port;
        dst->ps5 = chiaki_discovery_host_is_ps5(src);
        dst->host_addr = src->host_addr;
        dst->system_version = src->system_version;
        dst->device_discovery_protocol_version = src->device_discovery_protocol_version;
        dst->host_name = src->host_name;
        dst->host_type = src->host_type;
        dst->host_id = src->host_id;
        dst->running_app_titleid = src->running_app_titleid;
        dst->running_app_name = src->running_app_name;
    }

    self->user_cb(snapshot, hosts_count, self->user_cb_user);
}

/*
 * Walk getifaddrs(), collect each up/running/broadcast IPv4 interface's
 * sin_addr (the kernel returns broadcast addrs in ifa_broadaddr for
 * IFF_BROADCAST interfaces). Mirrors gui/src/discoverymanager.cpp:159–183.
 *
 * Caller frees `*out_addrs`.
 */
static bool chiaki_tv_discovery_collect_broadcast_addrs(
    struct sockaddr_storage **out_addrs, size_t *out_count)
{
    *out_addrs = NULL;
    *out_count = 0;

    struct ifaddrs *local_addrs = NULL;
    if(getifaddrs(&local_addrs) != 0)
        return false;

    /* First pass: count. */
    size_t count = 0;
    for(struct ifaddrs *ifa = local_addrs; ifa; ifa = ifa->ifa_next) {
        if(!ifa->ifa_addr) continue;
        if((ifa->ifa_flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK | IFF_BROADCAST))
                != (IFF_UP | IFF_RUNNING | IFF_BROADCAST))
            continue;
        if(ifa->ifa_addr->sa_family != AF_INET) continue;
        if(!ifa->ifa_broadaddr) continue;
        count++;
    }

    if(count == 0) {
        freeifaddrs(local_addrs);
        return true;  /* caller will fall back to limited broadcast only */
    }

    struct sockaddr_storage *arr = calloc(count, sizeof(struct sockaddr_storage));
    if(!arr) {
        freeifaddrs(local_addrs);
        return false;
    }

    /* Second pass: copy. Dedup by sin_addr.s_addr against what we already wrote. */
    size_t written = 0;
    for(struct ifaddrs *ifa = local_addrs; ifa; ifa = ifa->ifa_next) {
        if(!ifa->ifa_addr) continue;
        if((ifa->ifa_flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK | IFF_BROADCAST))
                != (IFF_UP | IFF_RUNNING | IFF_BROADCAST))
            continue;
        if(ifa->ifa_addr->sa_family != AF_INET) continue;
        if(!ifa->ifa_broadaddr) continue;

        struct sockaddr_in *bcast = (struct sockaddr_in *)ifa->ifa_broadaddr;
        bool dup = false;
        for(size_t j = 0; j < written; j++) {
            struct sockaddr_in *prev = (struct sockaddr_in *)&arr[j];
            if(prev->sin_addr.s_addr == bcast->sin_addr.s_addr) {
                dup = true;
                break;
            }
        }
        if(dup) continue;

        struct sockaddr_in entry = { 0 };
        entry.sin_family = AF_INET;
        entry.sin_addr.s_addr = bcast->sin_addr.s_addr;
        memcpy(&arr[written], &entry, sizeof(entry));
        written++;
    }

    freeifaddrs(local_addrs);
    *out_addrs = arr;
    *out_count = written;
    return true;
}

chiaki_tv_discovery_service_t *chiaki_tv_discovery_service_create(
    chiaki_tv_discovery_cb cb,
    void *cb_user)
{
    if(!cb) return NULL;

    struct chiaki_tv_discovery_service *self = calloc(1, sizeof(*self));
    if(!self) return NULL;

    self->user_cb = cb;
    self->user_cb_user = cb_user;

    /* Phase 1: route chiaki-lib log lines to stdout. A typed log bridge will
     * land later — for now this matches what the desktop does on init. */
    chiaki_log_init(&self->log,
        CHIAKI_LOG_ALL & ~CHIAKI_LOG_VERBOSE,
        chiaki_log_cb_print, NULL);

    ChiakiDiscoveryServiceOptions options;
    memset(&options, 0, sizeof(options));
    options.ping_ms = CHIAKI_TV_DISC_PING_MS;
    options.ping_initial_ms = CHIAKI_TV_DISC_PING_MS;
    options.hosts_max = CHIAKI_TV_DISC_HOSTS_MAX;
    options.host_drop_pings = CHIAKI_TV_DISC_DROP_PINGS;
    options.cb = chiaki_tv_discovery_reshape_cb;
    options.cb_user = self;

    /* Limited broadcast send target — chiaki-lib treats sin_addr.s_addr ==
     * 0xffffffff as the trigger to also send to each broadcast_addrs entry
     * (see lib/src/discoveryservice.c:215). */
    struct sockaddr_in send_addr = { 0 };
    send_addr.sin_family = AF_INET;
    send_addr.sin_addr.s_addr = 0xffffffff;

    struct sockaddr_storage send_storage;
    memset(&send_storage, 0, sizeof(send_storage));
    memcpy(&send_storage, &send_addr, sizeof(send_addr));
    options.send_addr = &send_storage;
    options.send_addr_size = sizeof(send_addr);

    /* Per-interface broadcast addrs. chiaki-lib copies these internally so it's
     * safe to free after init. */
    struct sockaddr_storage *bcast_addrs = NULL;
    size_t bcast_count = 0;
    if(!chiaki_tv_discovery_collect_broadcast_addrs(&bcast_addrs, &bcast_count)) {
        CHIAKI_LOGW(&self->log, "Discovery: getifaddrs() failed; falling back to limited broadcast only");
        bcast_addrs = NULL;
        bcast_count = 0;
    }
    options.broadcast_addrs = bcast_addrs;
    options.broadcast_num = bcast_count;

    ChiakiErrorCode err = chiaki_discovery_service_init(&self->service, &options, &self->log);
    free(bcast_addrs);

    if(err != CHIAKI_ERR_SUCCESS) {
        CHIAKI_LOGE(&self->log, "Discovery: chiaki_discovery_service_init failed (%d)", (int)err);
        free(self);
        return NULL;
    }

    self->service_active = true;
    return self;
}

void chiaki_tv_discovery_service_destroy(chiaki_tv_discovery_service_t *self)
{
    if(!self) return;
    if(self->service_active) {
        chiaki_discovery_service_fini(&self->service);
        self->service_active = false;
    }
    free(self);
}

bool chiaki_tv_discovery_service_send_wakeup(
    const char *host_ip,
    const char *regist_key_hex,
    bool ps5)
{
    if(!host_ip || !regist_key_hex)
        return false;

    /* Match desktop's parsing — the regist key is hex-encoded ASCII; up to 8
     * chars (8 hex chars = 32 bits, but chiaki widens to uint64_t). See
     * gui/src/discoverymanager.cpp:286–292. */
    size_t len = strlen(regist_key_hex);
    if(len == 0 || len > 8)
        return false;
    char *endp = NULL;
    unsigned long long credential = strtoull(regist_key_hex, &endp, 16);
    if(!endp || *endp != '\0')
        return false;

    ChiakiLog log;
    chiaki_log_init(&log, CHIAKI_LOG_ALL & ~CHIAKI_LOG_VERBOSE, chiaki_log_cb_print, NULL);

    ChiakiErrorCode err = chiaki_discovery_wakeup(&log, NULL, host_ip,
                                                  (uint64_t)credential, ps5);
    return err == CHIAKI_ERR_SUCCESS;
}
