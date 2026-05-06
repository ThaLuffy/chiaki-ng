/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * @file chiaki_bridge_session.h
 * @brief Typed Swift-friendly wrapper around chiaki-lib's `ChiakiSession`.
 *
 * The session is the streaming engine. Once started it spawns multiple
 * threads inside chiaki-lib (ctrl, takion, stream connection, audio/video
 * receivers) and emits NAL units + Opus PCM frames + control events to
 * the callbacks the caller registered before start.
 *
 * Hot-path callbacks (video sample, audio frame) run on chiaki-lib's
 * receiver threads. Caller MUST NOT block them. The audio sink also
 * receives a stream-info callback once at the start of the audio stream.
 *
 * Reference:
 *   - `lib/include/chiaki/session.h`
 *   - `lib/include/chiaki/audioreceiver.h`
 *   - `lib/include/chiaki/videoreceiver.h`
 *   - `gui/src/streamsession.cpp` (desktop reference for orchestration shape)
 */

#ifndef CHIAKI_BRIDGE_SESSION_H
#define CHIAKI_BRIDGE_SESSION_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ────── Codec / video ────────────────────────────────────────────────── */

/* Mirrors `ChiakiCodec`. */
typedef enum {
    CHIAKI_TV_CODEC_H264     = 0,
    CHIAKI_TV_CODEC_H265     = 1,
    CHIAKI_TV_CODEC_H265_HDR = 2,
} chiaki_tv_codec_t;

/* Mirrors `ChiakiDisableAudioVideo`. */
typedef enum {
    CHIAKI_TV_AV_BOTH_ENABLED  = 0,
    CHIAKI_TV_AV_AUDIO_ONLY    = 2,  /* video disabled */
    CHIAKI_TV_AV_VIDEO_ONLY    = 1,  /* audio disabled */
    CHIAKI_TV_AV_BOTH_DISABLED = 3,
} chiaki_tv_av_disable_t;

/* ────── Session events ───────────────────────────────────────────────── */

/* Subset of `ChiakiEventType` we surface to Swift. Values do NOT mirror
 * upstream — they're local. */
typedef enum {
    CHIAKI_TV_SESSION_EVENT_CONNECTED          = 0,
    CHIAKI_TV_SESSION_EVENT_LOGIN_PIN_REQUEST  = 1,
    CHIAKI_TV_SESSION_EVENT_QUIT               = 2,
    CHIAKI_TV_SESSION_EVENT_NICKNAME_RECEIVED  = 3,
    CHIAKI_TV_SESSION_EVENT_RUMBLE             = 4,
    CHIAKI_TV_SESSION_EVENT_TRIGGER_EFFECTS    = 5,
    CHIAKI_TV_SESSION_EVENT_AUTO_REGIST_SUCCESS = 6,
} chiaki_tv_session_event_type_t;

typedef struct {
    chiaki_tv_session_event_type_t type;

    /* Quit (valid for QUIT) */
    int32_t  quit_reason;          /* mirrors ChiakiQuitReason value */
    const char *quit_reason_str;   /* may be NULL */

    /* Login PIN (valid for LOGIN_PIN_REQUEST) */
    bool pin_incorrect;            /* false on first request, true if retry */

    /* Nickname (valid for NICKNAME_RECEIVED) */
    char server_nickname[0x20];    /* NUL-padded */

    /* Rumble (valid for RUMBLE) */
    uint8_t rumble_left;
    uint8_t rumble_right;
} chiaki_tv_session_event_t;

typedef void (*chiaki_tv_session_event_cb_t)(
    const chiaki_tv_session_event_t *event, void *user);

/* ────── Audio sink ───────────────────────────────────────────────────── */

typedef struct {
    uint8_t  channels;
    uint8_t  bits;
    uint32_t rate;
    uint32_t frame_size;
} chiaki_tv_audio_header_t;

typedef void (*chiaki_tv_audio_header_cb_t)(
    const chiaki_tv_audio_header_t *header, void *user);

/**
 * Audio frame. `pcm` is signed 16-bit interleaved samples (channels × frame_size
 * total samples; byte_count = samples × sizeof(int16_t)). Pointer is only
 * valid for the duration of the call; copy into a ring buffer.
 */
typedef void (*chiaki_tv_audio_frame_cb_t)(
    const int16_t *pcm, size_t pcm_byte_count, void *user);

/* ────── Video sink ───────────────────────────────────────────────────── */

/**
 * NAL unit batch from the chiaki video receiver. `buf` is mutable on the
 * upstream side (chiaki may have padded the end); for our purposes treat as
 * read-only. Return true if successfully consumed; false to request a new
 * keyframe.
 */
typedef bool (*chiaki_tv_video_sample_cb_t)(
    uint8_t *buf, size_t buf_size,
    int32_t frames_lost, bool frame_recovered, void *user);

/* ────── Controller state ─────────────────────────────────────────────── */

/* Bitmask values from chiaki-lib's `ChiakiControllerButton` (re-exposed so
 * Swift doesn't have to import controller.h). */
#define CHIAKI_TV_BTN_CROSS       (1u << 0)
#define CHIAKI_TV_BTN_CIRCLE      (1u << 1)   /* upstream MOON */
#define CHIAKI_TV_BTN_SQUARE      (1u << 2)   /* upstream BOX */
#define CHIAKI_TV_BTN_TRIANGLE    (1u << 3)   /* upstream PYRAMID */
#define CHIAKI_TV_BTN_DPAD_LEFT   (1u << 4)
#define CHIAKI_TV_BTN_DPAD_RIGHT  (1u << 5)
#define CHIAKI_TV_BTN_DPAD_UP     (1u << 6)
#define CHIAKI_TV_BTN_DPAD_DOWN   (1u << 7)
#define CHIAKI_TV_BTN_L1          (1u << 8)
#define CHIAKI_TV_BTN_R1          (1u << 9)
#define CHIAKI_TV_BTN_L3          (1u << 10)
#define CHIAKI_TV_BTN_R3          (1u << 11)
#define CHIAKI_TV_BTN_OPTIONS     (1u << 12)
#define CHIAKI_TV_BTN_SHARE       (1u << 13)
#define CHIAKI_TV_BTN_TOUCHPAD    (1u << 14)
#define CHIAKI_TV_BTN_PS          (1u << 15)

typedef struct {
    uint32_t buttons;
    uint8_t  l2_state;
    uint8_t  r2_state;
    int16_t  left_x, left_y;
    int16_t  right_x, right_y;
    /* gyro/accel/orient — set to 0 for the Phase 1 minimum. */
    float    gyro_x, gyro_y, gyro_z;
    float    accel_x, accel_y, accel_z;
    float    orient_x, orient_y, orient_z, orient_w;
} chiaki_tv_controller_state_t;

/* ────── Session lifecycle ───────────────────────────────────────────── */

typedef struct chiaki_tv_session chiaki_tv_session_t;

typedef struct {
    bool ps5;
    const char *host_ip;
    /* 16-byte registration auth key — comes from chiaki_tv_regist_success_t.rp_regist_key
     * (NUL-padded if shorter). */
    const uint8_t *regist_key;
    /* 16-byte rp_key — comes from chiaki_tv_regist_success_t.rp_key. */
    const uint8_t *rp_key;
    /* 8-byte raw PSN account id. */
    const uint8_t *psn_account_id;

    /* Video profile. */
    uint32_t video_width;
    uint32_t video_height;
    uint32_t video_max_fps;
    uint32_t video_bitrate_kbps;
    int32_t  video_codec;            /* chiaki_tv_codec_t */
    bool     video_profile_auto_downgrade;

    bool enable_dualsense;
    int32_t audio_video_disabled;    /* chiaki_tv_av_disable_t */
    bool auto_regist;
    double packet_loss_max;
    bool enable_idr_on_fec_failure;

    /* Callbacks. */
    chiaki_tv_session_event_cb_t event_cb;
    void *event_cb_user;
    chiaki_tv_video_sample_cb_t video_sample_cb;
    void *video_sample_cb_user;
    chiaki_tv_audio_header_cb_t audio_header_cb;
    chiaki_tv_audio_frame_cb_t audio_frame_cb;
    void *audio_user;
} chiaki_tv_session_config_t;

/**
 * Construct + init a session. Returns NULL on error (e.g. bad host IP, or
 * `chiaki_session_init` rejected the config).
 *
 * The handle is heap-allocated; pass to `chiaki_tv_session_destroy` to free.
 * Callbacks must remain valid for the lifetime of the handle.
 */
chiaki_tv_session_t *chiaki_tv_session_create(
    const chiaki_tv_session_config_t *config);

/** Spawn the session threads. Returns true on success. */
bool chiaki_tv_session_start(chiaki_tv_session_t *session);

/** Request the session to stop. Non-blocking; the QUIT event will fire. */
void chiaki_tv_session_stop(chiaki_tv_session_t *session);

/** Wait for the session thread to exit. */
void chiaki_tv_session_join(chiaki_tv_session_t *session);

/** Stop + join + free. Safe with NULL. */
void chiaki_tv_session_destroy(chiaki_tv_session_t *session);

/**
 * Push a controller state. Synchronous — chiaki-lib copies internally.
 * Call on every value change; do NOT batch.
 */
void chiaki_tv_session_set_controller_state(
    chiaki_tv_session_t *session,
    const chiaki_tv_controller_state_t *state);

/**
 * Submit the user-entered registration PIN after a LOGIN_PIN_REQUEST event.
 * `pin_digits` is a NUL-terminated ASCII string (typically 4 chars for PS5).
 */
void chiaki_tv_session_set_login_pin(
    chiaki_tv_session_t *session,
    const char *pin_digits);

/** Request a fresh keyframe (e.g. after FEC failure). */
void chiaki_tv_session_request_idr(chiaki_tv_session_t *session);

/* ────── Telemetry ───────────────────────────────────────────────────── */

/**
 * Live session stats. All fields are post-init values — call this any time
 * after `chiaki_tv_session_start`. Mirrors the readouts the desktop HUD pulls
 * from `session.stream_connection.{measured_bitrate, congestion_control.packet_loss}`
 * (gui/src/streamsession.cpp:484, 2633), plus our own per-trampoline counters
 * for frame loss / FEC recovery.
 */
typedef struct {
    /* Mbit/s — chiaki-lib already stores in megabit units (see
     * lib/src/streamconnection.c:704, divides bytes-per-window by 1e6 before
     * writing). 0 until at least one window has been measured. */
    double measured_bitrate_mbps;
    /* Fraction in [0.0, 1.0]; 0 until the first congestion-control window. */
    double packet_loss;
    /* Monotonic count of NAL-unit batches handed to the video trampoline. */
    uint32_t frames_received;
    /* Cumulative frames-lost reported by the video receiver across the session. */
    uint32_t frames_lost;
    /* Count of trampoline calls reporting `frame_recovered=true` (FEC repairs). */
    uint32_t frames_recovered;
    /* One-shot RTT in milliseconds, measured by Senkusha during session
     * handshake (lib/src/session.c:626 -> session->rtt_us, used by
     * lib/src/streamconnection.c:1002 to seed the launch spec). Static
     * after handshake; treat as a network-floor indicator, not a live
     * jitter reading. 0 until handshake completes. */
    uint32_t latency_ms;
} chiaki_tv_session_stats_t;

void chiaki_tv_session_get_stats(
    chiaki_tv_session_t *session,
    chiaki_tv_session_stats_t *out);

#ifdef __cplusplus
}
#endif

#endif /* CHIAKI_BRIDGE_SESSION_H */
