/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * Wraps `chiaki_regist_start`. The handle owns:
 *   - the upstream `ChiakiRegist` (initialized in-place; must be `chiaki_regist_fini`'d)
 *   - the user callback + user pointer
 *
 * Lifecycle: `chiaki_tv_regist_start` returns a malloc'd handle. The caller
 * is responsible for calling `chiaki_tv_regist_destroy` to join + free.
 *
 * Reference: `gui/src/qmlregist.cpp` (desktop QML reference) and
 * `lib/src/regist.c` (the upstream thread loop).
 */

#include "ChiakiBridgeC/chiaki_bridge_regist.h"
#include "ChiakiBridgeC/chiaki_bridge_log.h"

#include <chiaki/regist.h>
#include <chiaki/common.h>
#include <chiaki/log.h>

#include <stdlib.h>
#include <string.h>

struct chiaki_tv_regist {
    ChiakiRegist regist;
    bool started;
    chiaki_tv_regist_cb_t user_cb;
    void *user_cb_user;
};

static void chiaki_tv_regist_trampoline(ChiakiRegistEvent *event, void *user)
{
    struct chiaki_tv_regist *self = user;
    if(!self || !self->user_cb) return;

    chiaki_tv_regist_event_type_t mapped = CHIAKI_TV_REGIST_EVENT_FAILED;
    chiaki_tv_regist_success_t success;
    const chiaki_tv_regist_success_t *success_ptr = NULL;

    switch(event->type) {
        case CHIAKI_REGIST_EVENT_TYPE_FINISHED_SUCCESS:
            mapped = CHIAKI_TV_REGIST_EVENT_SUCCESS;
            if(event->registered_host) {
                ChiakiRegisteredHost *src = event->registered_host;
                memset(&success, 0, sizeof(success));
                success.target = (int32_t)src->target;
                memcpy(success.server_mac, src->server_mac, sizeof(success.server_mac));
                memcpy(success.server_nickname, src->server_nickname,
                       sizeof(success.server_nickname));
                memcpy(success.rp_regist_key, src->rp_regist_key,
                       sizeof(success.rp_regist_key));
                success.rp_key_type = src->rp_key_type;
                memcpy(success.rp_key, src->rp_key, sizeof(success.rp_key));
                success.console_pin = src->console_pin;
                success_ptr = &success;
            }
            break;
        case CHIAKI_REGIST_EVENT_TYPE_FINISHED_CANCELED:
            mapped = CHIAKI_TV_REGIST_EVENT_CANCELED;
            break;
        case CHIAKI_REGIST_EVENT_TYPE_FINISHED_FAILED:
        default:
            mapped = CHIAKI_TV_REGIST_EVENT_FAILED;
            break;
    }

    self->user_cb(mapped, success_ptr, self->user_cb_user);
}

chiaki_tv_regist_t *chiaki_tv_regist_start(
    const char *host_ip,
    int32_t target,
    bool broadcast,
    const uint8_t *psn_account_id,
    uint32_t pin,
    uint32_t console_pin,
    chiaki_tv_regist_cb_t cb,
    void *cb_user)
{
    if(!host_ip || !psn_account_id || !cb) return NULL;

    struct chiaki_tv_regist *self = calloc(1, sizeof(*self));
    if(!self) return NULL;

    self->user_cb = cb;
    self->user_cb_user = cb_user;

    ChiakiRegistInfo info;
    memset(&info, 0, sizeof(info));
    info.target = (ChiakiTarget)target;
    info.host = host_ip;       /* chiaki-lib copies internally */
    info.broadcast = broadcast;
    info.psn_online_id = NULL; /* prefer account_id path (PS4 >= 7.0 / PS5) */
    memcpy(info.psn_account_id, psn_account_id, CHIAKI_PSN_ACCOUNT_ID_SIZE);
    info.pin = pin;
    info.console_pin = console_pin;
    info.holepunch_info = NULL;  /* LAN-only */
    info.rudp = NULL;            /* LAN-only */

    ChiakiLog *log = (ChiakiLog *)chiaki_tv_log_get();
    ChiakiErrorCode err = chiaki_regist_start(&self->regist, log, &info,
                                              chiaki_tv_regist_trampoline, self);
    if(err != CHIAKI_ERR_SUCCESS) {
        CHIAKI_LOGE(log, "chiaki_tv_regist_start: chiaki_regist_start failed (%d)", (int)err);
        free(self);
        return NULL;
    }

    self->started = true;
    return self;
}

void chiaki_tv_regist_stop(chiaki_tv_regist_t *self)
{
    if(!self || !self->started) return;
    chiaki_regist_stop(&self->regist);
}

void chiaki_tv_regist_destroy(chiaki_tv_regist_t *self)
{
    if(!self) return;
    if(self->started) {
        chiaki_regist_fini(&self->regist);
        self->started = false;
    }
    free(self);
}

int32_t chiaki_tv_target_ps5_1(void)
{
    return (int32_t)CHIAKI_TARGET_PS5_1;
}

int32_t chiaki_tv_target_ps5_unknown(void)
{
    return (int32_t)CHIAKI_TARGET_PS5_UNKNOWN;
}
