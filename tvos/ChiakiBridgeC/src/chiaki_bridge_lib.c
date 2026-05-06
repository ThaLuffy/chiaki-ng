/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * Smoke-test entry point that exercises a real chiaki-lib symbol. Compiles
 * with the upstream public headers in `Vendors/prefix/<slice>/include/`. If
 * this object file links cleanly, libchiaki.a is wired in correctly.
 */

#include "ChiakiBridgeC/chiaki_bridge.h"

#include <chiaki/log.h>
#include <chiaki/config.h>

uint32_t chiaki_tv_lib_version_packed(void) {
    /*
     * chiaki-lib doesn't ship a version constant we can read at runtime, so
     * we encode a synthetic identity from build-time facts:
     *   - high byte: 0xCA (literal "chiaki" tag)
     *   - middle byte: CHIAKI_LIB_ENABLE_OPUS  (1 if lib was built with opus)
     *   - low 16 bits: result of a real chiaki_log_level_char(INFO) call,
     *     padded with the level enum value. Forces the linker to actually
     *     pull a chiaki-lib symbol in, which is the point of the smoke test.
     */
    uint8_t info_char = (uint8_t)chiaki_log_level_char(CHIAKI_LOG_INFO);
    uint8_t opus_bit  = (uint8_t)CHIAKI_LIB_ENABLE_OPUS;
    return ((uint32_t)0xCA << 24) | ((uint32_t)opus_bit << 16) | info_char;
}
