/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * Singleton ChiakiLog whose internal callback fan-outs to a Swift-set
 * callback. Threadsafe for read (the cb pointer is set once at app launch
 * and not changed); writes are serialized via the global lock.
 *
 * We initialize lazily so that `chiaki_tv_log_get()` returning a stable
 * pointer doesn't require static-init ordering with the C runtime.
 */

#include "ChiakiBridgeC/chiaki_bridge_log.h"

#include <chiaki/log.h>

#include <pthread.h>
#include <stddef.h>

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static ChiakiLog g_log;
static bool g_log_initialized = false;
static chiaki_tv_log_cb_t g_user_cb = NULL;
static void *g_user_user = NULL;

static void chiaki_tv_log_trampoline(ChiakiLogLevel level, const char *msg, void *user)
{
    (void)user;
    chiaki_tv_log_cb_t cb;
    void *cb_user;
    pthread_mutex_lock(&g_lock);
    cb = g_user_cb;
    cb_user = g_user_user;
    pthread_mutex_unlock(&g_lock);

    if(cb) {
        cb((int32_t)level, msg, cb_user);
    } else {
        /* Fall back to stdout if Swift hasn't wired anything up yet. */
        chiaki_log_cb_print(level, msg, NULL);
    }
}

static void chiaki_tv_log_ensure_init(void)
{
    if(g_log_initialized) return;
    pthread_mutex_lock(&g_lock);
    if(!g_log_initialized) {
        chiaki_log_init(&g_log,
            CHIAKI_LOG_ALL & ~CHIAKI_LOG_VERBOSE,
            chiaki_tv_log_trampoline, NULL);
        g_log_initialized = true;
    }
    pthread_mutex_unlock(&g_lock);
}

void *chiaki_tv_log_get(void)
{
    chiaki_tv_log_ensure_init();
    return &g_log;
}

void chiaki_tv_log_set_callback(chiaki_tv_log_cb_t cb, void *user)
{
    chiaki_tv_log_ensure_init();
    pthread_mutex_lock(&g_lock);
    g_user_cb = cb;
    g_user_user = user;
    pthread_mutex_unlock(&g_lock);
}

void chiaki_tv_log_set_level_mask(uint32_t level_mask)
{
    chiaki_tv_log_ensure_init();
    chiaki_log_set_level(&g_log, level_mask);
}
