/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * Annex-B → AVCC walker. See `chiaki_bridge_video.h` for design notes.
 */

#include <ChiakiBridgeC/chiaki_bridge_video.h>

#include <stdlib.h>
#include <string.h>

/* Maximum NAL units per video sample. PS5 streams typically pack <8 NALs per
 * frame (slice + parameter sets + SEI). 64 is comfortably above the worst case
 * we've observed; bump if a real stream ever exceeds it. */
#define WALK_MAX_NALS 64

typedef struct {
    size_t nal_start;   /* offset into input buffer of NAL byte 0 */
    size_t nal_len;     /* length of NAL (excluding the start code) */
} walk_range_t;

static inline bool walk_classify_h265(uint8_t nal_header_byte,
                                       chiaki_tv_avcc_walk_t *out,
                                       const uint8_t *buf, size_t nal_start, size_t nal_len)
{
    /* HEVC NAL header layout: forbidden_zero_bit + nal_unit_type[6] + ... */
    uint8_t nal_type = (nal_header_byte >> 1) & 0x3F;
    switch (nal_type) {
        case 32: out->vps_ptr = buf + nal_start; out->vps_len = nal_len; return false;
        case 33: out->sps_ptr = buf + nal_start; out->sps_len = nal_len; return false;
        case 34: out->pps_ptr = buf + nal_start; out->pps_len = nal_len; return false;
        case 16: case 17: case 18: case 19: case 20: case 21: case 22: case 23:
            /* IDR / BLA / CRA */
            return true;
        case 0: case 1: case 2: case 3: case 4: case 5: case 6: case 7: case 8: case 9:
            /* trail / TSA / STSA */
            return true;
        default:
            return false;
    }
}

static inline bool walk_classify_h264(uint8_t nal_header_byte,
                                       chiaki_tv_avcc_walk_t *out,
                                       const uint8_t *buf, size_t nal_start, size_t nal_len)
{
    uint8_t nal_type = nal_header_byte & 0x1F;
    switch (nal_type) {
        case 7: out->sps_ptr = buf + nal_start; out->sps_len = nal_len; return false;
        case 8: out->pps_ptr = buf + nal_start; out->pps_len = nal_len; return false;
        case 5: case 1: return true; /* IDR / non-IDR slice */
        default: return false;
    }
}

bool chiaki_tv_walk_annex_b(
    const uint8_t *buf, size_t buf_size,
    chiaki_tv_video_codec_t codec,
    chiaki_tv_avcc_walk_t *out)
{
    if (!buf || !out || buf_size < 4) return false;

    /* Reset out struct. */
    memset(out, 0, sizeof(*out));

    walk_range_t ranges[WALK_MAX_NALS];
    size_t range_count = 0;

    /* Pass 1 — find Annex-B start codes (00 00 01 or 00 00 00 01) and record
     * (start, length) for each NAL. */
    {
        size_t starts[WALK_MAX_NALS];
        size_t prefix_len[WALK_MAX_NALS];
        size_t start_count = 0;

        size_t i = 0;
        while (i + 2 < buf_size && start_count < WALK_MAX_NALS) {
            if (buf[i] == 0 && buf[i + 1] == 0) {
                if (buf[i + 2] == 0x01) {
                    starts[start_count]      = i + 3;
                    prefix_len[start_count]  = 3;
                    start_count++;
                    i += 3;
                    continue;
                } else if (buf[i + 2] == 0 && i + 3 < buf_size && buf[i + 3] == 0x01) {
                    starts[start_count]      = i + 4;
                    prefix_len[start_count]  = 4;
                    start_count++;
                    i += 4;
                    continue;
                }
            }
            i++;
        }

        for (size_t k = 0; k < start_count; k++) {
            size_t nal_start = starts[k];
            size_t nal_end   = (k + 1 < start_count)
                                 ? (starts[k + 1] - prefix_len[k + 1])
                                 : buf_size;
            if (nal_end <= nal_start || nal_end > buf_size) continue;
            ranges[range_count].nal_start = nal_start;
            ranges[range_count].nal_len   = nal_end - nal_start;
            range_count++;
        }
    }

    if (range_count == 0) return true; /* nothing to do, but not an error */

    /* Pass 2 — classify NALs. Decide which (if any) are parameter sets, and
     * whether the buffer contains a slice. */
    bool has_slice = false;
    for (size_t k = 0; k < range_count; k++) {
        if (ranges[k].nal_len < 1) continue;
        uint8_t header = buf[ranges[k].nal_start];
        bool is_slice;
        if (codec == CHIAKI_TV_VIDEO_CODEC_H265 || codec == CHIAKI_TV_VIDEO_CODEC_H265_HDR) {
            is_slice = walk_classify_h265(header, out, buf, ranges[k].nal_start, ranges[k].nal_len);
        } else {
            is_slice = walk_classify_h264(header, out, buf, ranges[k].nal_start, ranges[k].nal_len);
        }
        if (is_slice) has_slice = true;
    }
    out->has_slice = has_slice;

    /* Pass 3 — build AVCC only if there's an actual slice to decode. The
     * out-of-band parameter-set delivery from `lib/src/videoreceiver.c:140-141`
     * has no slice — we just want the param-set pointers, no AVCC alloc. */
    if (!has_slice) return true;

    size_t total = 0;
    for (size_t k = 0; k < range_count; k++) {
        total += 4 + ranges[k].nal_len;
    }
    if (total == 0) return true;

    uint8_t *avcc = (uint8_t *)malloc(total);
    if (!avcc) return false;

    size_t off = 0;
    for (size_t k = 0; k < range_count; k++) {
        uint32_t len = (uint32_t)ranges[k].nal_len;
        avcc[off++] = (uint8_t)((len >> 24) & 0xFF);
        avcc[off++] = (uint8_t)((len >> 16) & 0xFF);
        avcc[off++] = (uint8_t)((len >>  8) & 0xFF);
        avcc[off++] = (uint8_t)( len        & 0xFF);
        memcpy(avcc + off, buf + ranges[k].nal_start, ranges[k].nal_len);
        off += ranges[k].nal_len;
    }

    out->avcc_buf  = avcc;
    out->avcc_size = total;
    return true;
}
