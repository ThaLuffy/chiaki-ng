/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * @file chiaki_bridge_regist.h
 * @brief Typed Swift-friendly wrapper around chiaki-lib's `ChiakiRegist`.
 *
 * Registration runs on its own thread inside chiaki-lib. The bridge owns
 * the `ChiakiRegist` instance and exposes:
 *   - a single start function with primitive C arguments,
 *   - a typed event callback that delivers a flat success snapshot or
 *     a cancel/fail signal,
 *   - explicit stop + destroy.
 *
 * Reference: `lib/include/chiaki/regist.h`, `lib/src/regist.c`,
 * `gui/src/registdialog.cpp`, `gui/src/qmlregist.cpp`.
 */

#ifndef CHIAKI_BRIDGE_REGIST_H
#define CHIAKI_BRIDGE_REGIST_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Mirrors chiaki-lib `ChiakiRegistEventType` (1:1 numeric values). */
typedef enum {
    CHIAKI_TV_REGIST_EVENT_FAILED   = 0,
    CHIAKI_TV_REGIST_EVENT_CANCELED = 1,
    CHIAKI_TV_REGIST_EVENT_SUCCESS  = 2,
} chiaki_tv_regist_event_type_t;

/* Flat snapshot of `ChiakiRegisteredHost`, copied at callback time. The
 * char buffers are NUL-padded to their fixed size. */
typedef struct {
    int32_t target;                  /* `ChiakiTarget` value */
    uint8_t server_mac[6];
    char    server_nickname[0x20];   /* NUL-padded */
    uint8_t rp_regist_key[0x10];     /* raw bytes (NUL-padded) */
    uint32_t rp_key_type;
    uint8_t rp_key[0x10];            /* raw bytes */
    uint32_t console_pin;
} chiaki_tv_regist_success_t;

/**
 * Callback. Runs on chiaki-lib's regist thread (NOT MainActor). On SUCCESS
 * `success_info` points to a stack-allocated snapshot — copy out
 * synchronously. On other event types `success_info` is NULL.
 */
typedef void (*chiaki_tv_regist_cb_t)(
    chiaki_tv_regist_event_type_t event_type,
    const chiaki_tv_regist_success_t *success_info,
    void *user);

typedef struct chiaki_tv_regist chiaki_tv_regist_t;

/**
 * Spin up a registration attempt. Returns NULL on immediate failure
 * (e.g. invalid args); otherwise returns a handle that the caller must
 * eventually pass to `chiaki_tv_regist_destroy`.
 *
 * @param host_ip          dotted IPv4 address of the PS5
 * @param target           ChiakiTarget value (use `chiaki_tv_target_ps5_1()`)
 * @param broadcast        true if `host_ip` is a broadcast address
 * @param psn_account_id   8-byte raw account ID (decoded from the user's
 *                         base64 PSN account ID)
 * @param pin              registration PIN shown on the PS5 screen
 * @param console_pin      additional console PIN (0 if not requested)
 */
chiaki_tv_regist_t *chiaki_tv_regist_start(
    const char *host_ip,
    int32_t target,
    bool broadcast,
    const uint8_t *psn_account_id,
    uint32_t pin,
    uint32_t console_pin,
    chiaki_tv_regist_cb_t cb,
    void *cb_user);

/** Asynchronously cancel an in-flight registration. */
void chiaki_tv_regist_stop(chiaki_tv_regist_t *regist);

/** Join the regist thread (synchronously) and free the handle. Safe with NULL. */
void chiaki_tv_regist_destroy(chiaki_tv_regist_t *regist);

/* Convenience constants — Swift gets these via direct call rather than
 * importing `<chiaki/common.h>`. */
int32_t chiaki_tv_target_ps5_1(void);
int32_t chiaki_tv_target_ps5_unknown(void);

#ifdef __cplusplus
}
#endif

#endif /* CHIAKI_BRIDGE_REGIST_H */
