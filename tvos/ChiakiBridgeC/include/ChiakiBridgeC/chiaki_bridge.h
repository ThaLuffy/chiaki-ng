/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * @file chiaki_bridge.h
 * @brief Thin Swift ↔ chiaki-ng glue layer.
 *
 * Phase 0: this header declares only the bridge surface that exists today
 * (a smoke-test version function). Phase 1 will add typed wrappers for the
 * upstream callbacks Swift can't take directly:
 *   - ChiakiLog callback adapter (C log lines → Swift OSLog)
 *   - ChiakiSession event callback adapter
 *   - ChiakiVideoSampleCallback adapter (raw NAL units → Swift VideoToolbox feeder)
 *   - ChiakiAudio sink adapter (decoded PCM → Swift AudioUnit feeder)
 *   - ChiakiController state push (Swift → C)
 *
 * The bridge is the *only* place Swift talks to chiaki-lib. Do not import
 * the chiaki public headers from Swift directly — adding a typed bridge
 * wrapper here keeps the hot path zero-allocation and keeps Swift's type
 * checker out of the per-frame path.
 *
 * Hot-path rule: callbacks invoked at packet/frame rate must NEVER call
 * back into Swift via a method that allocates (no NSData, no Array, no
 * String). Use UnsafeBufferPointer or pass primitive integers + raw
 * pointers and let Swift wrap them on the consumer side.
 */

#ifndef CHIAKI_BRIDGE_H
#define CHIAKI_BRIDGE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ═══════════════════════════════════════════════════════════════════════════
 * Version
 * ═══════════════════════════════════════════════════════════════════════════ */

#define CHIAKI_BRIDGE_VERSION_MAJOR 0
#define CHIAKI_BRIDGE_VERSION_MINOR 1
#define CHIAKI_BRIDGE_VERSION_PATCH 0

/**
 * Returns a pointer to a static, NUL-terminated version string.
 * Useful as a smoke test that the bridge linked successfully.
 */
const char *chiaki_tv_bridge_version(void);

/**
 * Returns the upstream chiaki-lib version triplet packed as
 *   (major << 16) | (minor << 8) | patch
 * Smoke test that confirms libchiaki.a is linked into the bridge.
 *
 * Implemented in `chiaki_bridge_lib.c` to keep the lib include path
 * out of the otherwise-stub `chiaki_bridge.c`.
 */
uint32_t chiaki_tv_lib_version_packed(void);

#ifdef __cplusplus
}
#endif

/* ═══════════════════════════════════════════════════════════════════════════
 * Sub-headers — typed wrappers for individual chiaki-lib subsystems.
 * Each lives in its own translation unit; the umbrella exposes them all.
 * ═══════════════════════════════════════════════════════════════════════════ */

#include "chiaki_bridge_log.h"
#include "chiaki_bridge_discovery.h"
#include "chiaki_bridge_regist.h"
#include "chiaki_bridge_session.h"
#include "chiaki_bridge_video.h"

#endif /* CHIAKI_BRIDGE_H */
