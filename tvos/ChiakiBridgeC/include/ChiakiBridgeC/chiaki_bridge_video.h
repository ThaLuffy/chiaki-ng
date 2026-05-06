/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * @file chiaki_bridge_video.h
 * @brief Annex-B → AVCC walker for video sample buffers from chiaki-lib.
 *
 * The PS5 emits video as Annex-B-framed NAL units (00 00 [00] 01 prefix).
 * VideoToolbox expects AVCC framing (4-byte big-endian length prefix per
 * NAL). We do the conversion in C rather than Swift so the per-frame `Data`
 * allocation Swift would otherwise do is eliminated — see
 * `docs/optimization/native-alternatives-latency-first.md` Phase A.2.
 *
 * Walks chiaki's input buffer in place (read-only), extracts pointers into
 * any VPS / SPS / PPS NAL units it finds, and (when the buffer contains a
 * slice) writes a malloc'd AVCC buffer the caller owns.
 *
 * Caller is expected to hand the AVCC buffer to a `CMBlockBuffer` with
 * `kCFAllocatorMalloc` so CoreMedia takes ownership of the free; if the
 * AVCC buffer is not consumed (e.g., due to an error), the caller must
 * `free()` it.
 *
 * Reference: `lib/src/videoreceiver.c:295-297` for how chiaki delivers
 * the input buffer (always Annex-B), and `videoreceiver.c:140-141` for
 * out-of-band parameter-set delivery (no slice).
 */

#ifndef CHIAKI_BRIDGE_VIDEO_H
#define CHIAKI_BRIDGE_VIDEO_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Codec selector. Must match `chiaki_tv_codec_t` in chiaki_bridge_session.h. */
typedef enum {
    CHIAKI_TV_VIDEO_CODEC_H264     = 0,
    CHIAKI_TV_VIDEO_CODEC_H265     = 1,
    CHIAKI_TV_VIDEO_CODEC_H265_HDR = 2,
} chiaki_tv_video_codec_t;

typedef struct {
    /* AVCC-framed slice buffer, malloc'd. Caller owns; transfer to
     * `CMBlockBufferCreateWithMemoryBlock` with `kCFAllocatorMalloc`, or
     * `free()` if not consumed. NULL when `has_slice` is false (we don't
     * waste an allocation building AVCC for parameter-set-only deliveries). */
    uint8_t *avcc_buf;
    size_t   avcc_size;

    /* Pointers into the *input* buffer for any parameter sets found.
     * Read-only; valid only for the duration of the call. The caller copies
     * these into its own cache before the next call.
     * NULL when not present in this buffer. */
    const uint8_t *vps_ptr;
    size_t         vps_len;
    const uint8_t *sps_ptr;
    size_t         sps_len;
    const uint8_t *pps_ptr;
    size_t         pps_len;

    /* True if at least one NAL classified as a slice was present. */
    bool has_slice;
} chiaki_tv_avcc_walk_t;

/**
 * Walk the Annex-B `buf` and produce AVCC framing + parameter-set ranges.
 *
 * @param buf       chiaki's video sample buffer (Annex-B framed, read-only).
 * @param buf_size  size in bytes.
 * @param codec     selects HEVC vs H.264 NAL-type bit layout.
 * @param out       populated by the walker. Caller-owned struct; the
 *                  `avcc_buf` field (if non-NULL) is heap-owned by `out`.
 *
 * Returns true on success (even if no slice — `out->has_slice` reports it),
 * false on malformed input or allocation failure.
 */
bool chiaki_tv_walk_annex_b(
    const uint8_t *buf, size_t buf_size,
    chiaki_tv_video_codec_t codec,
    chiaki_tv_avcc_walk_t *out
);

#ifdef __cplusplus
}
#endif

#endif /* CHIAKI_BRIDGE_VIDEO_H */
