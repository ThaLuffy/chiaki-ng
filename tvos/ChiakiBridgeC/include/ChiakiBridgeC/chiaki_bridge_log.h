/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * @file chiaki_bridge_log.h
 * @brief Typed Swift-friendly wrapper around chiaki-lib's `ChiakiLog`.
 *
 * chiaki-lib emits log lines via `ChiakiLog *log` (`lib/include/chiaki/log.h`).
 * The desktop routes them to stdout via `chiaki_log_cb_print`. On tvOS we
 * want OSLog so the lines show up in Console.app under our subsystem.
 *
 * Bridge contract:
 *   - One process-wide log handle (`chiaki_tv_log_get`) — chiaki-lib only
 *     stores a pointer, no thread-locals, so a singleton is fine.
 *   - Swift registers a typed callback once at app launch via
 *     `chiaki_tv_log_set_callback`. Callback receives the level, a NUL-
 *     terminated message, and an opaque user pointer.
 *   - Levels are re-exposed as plain integers so Swift doesn't need to
 *     import `<chiaki/log.h>` transitively.
 *
 * Reference: `lib/include/chiaki/log.h`, `lib/src/log.c`.
 */

#ifndef CHIAKI_BRIDGE_LOG_H
#define CHIAKI_BRIDGE_LOG_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Mirrors `ChiakiLogLevel` — re-exposed so Swift doesn't import the chiaki
 * header. Values match upstream's enum bits exactly. */
typedef enum {
    CHIAKI_TV_LOG_DEBUG   = (1 << 4),
    CHIAKI_TV_LOG_VERBOSE = (1 << 3),
    CHIAKI_TV_LOG_INFO    = (1 << 2),
    CHIAKI_TV_LOG_WARNING = (1 << 1),
    CHIAKI_TV_LOG_ERROR   = (1 << 0),
} chiaki_tv_log_level_t;

/* Callback signature. Runs on whichever thread chiaki-lib emitted the log
 * line from (often a streaming thread). Must NOT block — copy into a
 * thread-safe sink and return. */
typedef void (*chiaki_tv_log_cb_t)(int32_t level, const char *msg, void *user);

/**
 * Returns the process-wide opaque log handle, lazily-initialized. Pass this
 * (cast to `void *`) wherever chiaki-lib needs a `ChiakiLog *`. Internally
 * it's a `ChiakiLog` whose callback bounces into the Swift callback set via
 * `chiaki_tv_log_set_callback`.
 */
void *chiaki_tv_log_get(void);

/**
 * Set the Swift-side callback. Pass NULL to fall back to stdout (chiaki-lib's
 * own `chiaki_log_cb_print`).
 */
void chiaki_tv_log_set_callback(chiaki_tv_log_cb_t cb, void *user);

/**
 * Set the verbosity mask. Values are the OR of `chiaki_tv_log_level_t`. Use
 * `CHIAKI_TV_LOG_ALL` to enable all levels (matches upstream `CHIAKI_LOG_ALL`
 * but with verbose excluded by default — pass the OR explicitly to enable it).
 */
#define CHIAKI_TV_LOG_ALL ((1 << 5) - 1)
void chiaki_tv_log_set_level_mask(uint32_t level_mask);

#ifdef __cplusplus
}
#endif

#endif /* CHIAKI_BRIDGE_LOG_H */
