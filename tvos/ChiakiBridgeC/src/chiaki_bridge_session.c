/* SPDX-License-Identifier: AGPL-3.0-only */
/*
 * Wraps `ChiakiSession` from `lib/include/chiaki/session.h`. Sets up the
 * audio sink + video sample callback + event callback so the upstream
 * receivers fan out to caller-provided typed callbacks.
 *
 * Threading: chiaki-lib spawns its own threads inside `chiaki_session_start`.
 * Callbacks fire on those threads, NOT on the caller's. The video sample
 * callback in particular fires at packet rate — keep work allocation-free.
 *
 * Reference orchestration: `gui/src/streamsession.cpp`.
 */

#include "ChiakiBridgeC/chiaki_bridge_session.h"
#include "ChiakiBridgeC/chiaki_bridge_log.h"

#include <chiaki/session.h>
#include <chiaki/audioreceiver.h>
#include <chiaki/opusdecoder.h>
#include <chiaki/controller.h>
#include <chiaki/log.h>
#include <chiaki/common.h>
#include <chiaki/audio.h>
#include <chiaki/streamconnection.h>
#include <chiaki/congestioncontrol.h>

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct chiaki_tv_session {
    ChiakiSession session;
    bool initialized;
    bool started;

    /* Opus decoder sits between session.audio_sink and our trampolines.
     * The session sink delivers raw Opus packets; libopus produces int16
     * PCM that we then forward to Swift. Mirrors gui/src/streamsession.cpp
     * (chiaki_opus_decoder_set_cb + chiaki_opus_decoder_get_sink). */
    ChiakiOpusDecoder opus_decoder;
    bool opus_initialized;

    /* Caller-provided config (callbacks + user pointers). */
    chiaki_tv_session_event_cb_t event_cb;
    void *event_cb_user;
    chiaki_tv_video_sample_cb_t video_sample_cb;
    void *video_sample_cb_user;
    chiaki_tv_audio_header_cb_t audio_header_cb;
    chiaki_tv_audio_frame_cb_t audio_frame_cb;
    void *audio_user;

    /* Per-trampoline counters — written from chiaki's video receiver thread,
     * read from the Swift-side stats poller (typically MainActor at 1 Hz).
     * Use atomics so we don't have to take a mutex on the hot video path. */
    _Atomic uint32_t frames_received;
    _Atomic uint32_t frames_lost;
    _Atomic uint32_t frames_recovered;
};

static int32_t map_quit_reason(ChiakiQuitReason r)
{
    /* 1:1 numeric mirroring — enum values from session.h CHIAKI_QUIT_REASON_*. */
    return (int32_t)r;
}

/* Event trampoline. Runs on chiaki's session thread. */
static void chiaki_tv_event_trampoline(ChiakiEvent *event, void *user)
{
    struct chiaki_tv_session *self = user;
    if(!self || !self->event_cb) return;

    chiaki_tv_session_event_t out;
    memset(&out, 0, sizeof(out));

    switch(event->type) {
        case CHIAKI_EVENT_CONNECTED:
            out.type = CHIAKI_TV_SESSION_EVENT_CONNECTED;
            break;
        case CHIAKI_EVENT_LOGIN_PIN_REQUEST:
            out.type = CHIAKI_TV_SESSION_EVENT_LOGIN_PIN_REQUEST;
            out.pin_incorrect = event->login_pin_request.pin_incorrect;
            break;
        case CHIAKI_EVENT_QUIT:
            out.type = CHIAKI_TV_SESSION_EVENT_QUIT;
            out.quit_reason = map_quit_reason(event->quit.reason);
            out.quit_reason_str = event->quit.reason_str;
            break;
        case CHIAKI_EVENT_NICKNAME_RECEIVED:
            out.type = CHIAKI_TV_SESSION_EVENT_NICKNAME_RECEIVED;
            memcpy(out.server_nickname, event->server_nickname,
                   sizeof(out.server_nickname));
            break;
        case CHIAKI_EVENT_RUMBLE:
            out.type = CHIAKI_TV_SESSION_EVENT_RUMBLE;
            out.rumble_left = event->rumble.left;
            out.rumble_right = event->rumble.right;
            break;
        case CHIAKI_EVENT_TRIGGER_EFFECTS:
            out.type = CHIAKI_TV_SESSION_EVENT_TRIGGER_EFFECTS;
            break;
        case CHIAKI_EVENT_REGIST:
            out.type = CHIAKI_TV_SESSION_EVENT_AUTO_REGIST_SUCCESS;
            break;
        default:
            /* Unsurfaced event types are dropped silently — Phase 1 doesn't
             * route them to Swift (keyboard, holepunch, LED, haptic
             * intensity, FEC failure all stay inside the bridge). */
            return;
    }

    self->event_cb(&out, self->event_cb_user);
}

/* Video sample trampoline. Runs on chiaki video receiver thread.
 * HOT PATH — no allocations. Atomic counters bump before forwarding so a
 * Swift-side getter never sees the cb but not the increment. */
static bool chiaki_tv_video_trampoline(uint8_t *buf, size_t buf_size,
                                        int32_t frames_lost, bool frame_recovered,
                                        void *user)
{
    struct chiaki_tv_session *self = user;
    if(!self || !self->video_sample_cb) return false;
    atomic_fetch_add_explicit(&self->frames_received, 1, memory_order_relaxed);
    if(frames_lost > 0) {
        atomic_fetch_add_explicit(&self->frames_lost,
                                  (uint32_t)frames_lost, memory_order_relaxed);
    }
    if(frame_recovered) {
        atomic_fetch_add_explicit(&self->frames_recovered, 1, memory_order_relaxed);
    }
    return self->video_sample_cb(buf, buf_size, frames_lost,
                                  frame_recovered, self->video_sample_cb_user);
}

/* Opus-decoder settings trampoline. Fires after the opus decoder reads the
 * audio header off the session sink and successfully creates an OpusDecoder.
 * The decoder has already populated `self->opus_decoder.audio_header` (see
 * lib/src/opusdecoder.c:46) by the time this fires, so we read bits and
 * frame_size from there to reconstruct the Swift-facing header snapshot. */
static void chiaki_tv_audio_settings_trampoline(uint32_t channels, uint32_t rate, void *user)
{
    struct chiaki_tv_session *self = user;
    if(!self || !self->audio_header_cb) return;
    chiaki_tv_audio_header_t snap = {
        .channels = channels,
        .bits = self->opus_decoder.audio_header.bits,
        .rate = rate,
        .frame_size = self->opus_decoder.audio_header.frame_size,
    };
    self->audio_header_cb(&snap, self->audio_user);
}

/* Opus-decoder PCM frame trampoline. Fires per decoded frame at the audio
 * frame rate (rate/frame_size = ~100 Hz at 48000/480). `samples_count` is
 * the per-channel sample count returned by opus_decode (i.e. frame_size).
 * Convert to a byte count for the Swift contract, which keeps the existing
 * `(const int16_t *pcm, size_t pcm_byte_count)` shape on the Swift side. */
static void chiaki_tv_audio_frame_trampoline(int16_t *buf, size_t samples_count, void *user)
{
    struct chiaki_tv_session *self = user;
    if(!self || !self->audio_frame_cb) return;
    size_t channels = self->opus_decoder.audio_header.channels;
    size_t byte_count = samples_count * channels * sizeof(int16_t);
    self->audio_frame_cb((const int16_t *)buf, byte_count, self->audio_user);
}

chiaki_tv_session_t *chiaki_tv_session_create(
    const chiaki_tv_session_config_t *config)
{
    if(!config || !config->host_ip || !config->regist_key
        || !config->rp_key || !config->psn_account_id) {
        return NULL;
    }

    struct chiaki_tv_session *self = calloc(1, sizeof(*self));
    if(!self) return NULL;

    self->event_cb              = config->event_cb;
    self->event_cb_user         = config->event_cb_user;
    self->video_sample_cb       = config->video_sample_cb;
    self->video_sample_cb_user  = config->video_sample_cb_user;
    self->audio_header_cb       = config->audio_header_cb;
    self->audio_frame_cb        = config->audio_frame_cb;
    self->audio_user            = config->audio_user;

    ChiakiConnectInfo ci;
    memset(&ci, 0, sizeof(ci));
    ci.ps5 = config->ps5;
    ci.host = config->host_ip;
    memcpy(ci.regist_key, config->regist_key, sizeof(ci.regist_key));
    memcpy(ci.morning, config->rp_key, sizeof(ci.morning));
    ci.video_profile.width   = config->video_width;
    ci.video_profile.height  = config->video_height;
    ci.video_profile.max_fps = config->video_max_fps;
    ci.video_profile.bitrate = config->video_bitrate_kbps;
    ci.video_profile.codec   = (ChiakiCodec)config->video_codec;
    ci.video_profile_auto_downgrade = config->video_profile_auto_downgrade;
    ci.enable_keyboard       = false;
    ci.enable_dualsense      = config->enable_dualsense;
    ci.audio_video_disabled  = (ChiakiDisableAudioVideo)config->audio_video_disabled;
    ci.auto_regist           = config->auto_regist;
    ci.rudp_sock             = NULL;
    memcpy(ci.psn_account_id, config->psn_account_id, sizeof(ci.psn_account_id));
    ci.packet_loss_max       = config->packet_loss_max;
    ci.enable_idr_on_fec_failure = config->enable_idr_on_fec_failure;

    ChiakiLog *log = (ChiakiLog *)chiaki_tv_log_get();
    ChiakiErrorCode err = chiaki_session_init(&self->session, &ci, log);
    if(err != CHIAKI_ERR_SUCCESS) {
        CHIAKI_LOGE(log, "chiaki_tv_session_create: chiaki_session_init failed (%d)",
                    (int)err);
        free(self);
        return NULL;
    }
    self->initialized = true;

    /* Wire callbacks. The audio sink is a struct of two callbacks; chiaki
     * copies it on assignment so the local sink can be stack-allocated. */
    chiaki_session_set_event_cb(&self->session,
                                chiaki_tv_event_trampoline, self);
    chiaki_session_set_video_sample_cb(&self->session,
                                       chiaki_tv_video_trampoline, self);

    /* Insert the chiaki Opus decoder between the session and our typed
     * audio callbacks. The session's audio sink hands raw Opus packets;
     * chiaki_opus_decoder_get_sink() exposes a sink that decodes via libopus
     * and forwards int16 PCM through our settings/frame trampolines.
     * Pattern mirrors gui/src/streamsession.cpp:372-375. */
    chiaki_opus_decoder_init(&self->opus_decoder, log);
    self->opus_initialized = true;
    chiaki_opus_decoder_set_cb(&self->opus_decoder,
                               chiaki_tv_audio_settings_trampoline,
                               chiaki_tv_audio_frame_trampoline,
                               self);
    ChiakiAudioSink audio_sink;
    chiaki_opus_decoder_get_sink(&self->opus_decoder, &audio_sink);
    chiaki_session_set_audio_sink(&self->session, &audio_sink);

    return self;
}

bool chiaki_tv_session_start(chiaki_tv_session_t *self)
{
    if(!self || !self->initialized || self->started) return false;
    ChiakiErrorCode err = chiaki_session_start(&self->session);
    if(err != CHIAKI_ERR_SUCCESS) {
        ChiakiLog *log = (ChiakiLog *)chiaki_tv_log_get();
        CHIAKI_LOGE(log, "chiaki_tv_session_start failed (%d)", (int)err);
        return false;
    }
    self->started = true;
    return true;
}

void chiaki_tv_session_stop(chiaki_tv_session_t *self)
{
    if(!self || !self->started) return;
    chiaki_session_stop(&self->session);
}

void chiaki_tv_session_join(chiaki_tv_session_t *self)
{
    if(!self || !self->started) return;
    chiaki_session_join(&self->session);
}

void chiaki_tv_session_destroy(chiaki_tv_session_t *self)
{
    if(!self) return;
    if(self->started) {
        chiaki_session_stop(&self->session);
        chiaki_session_join(&self->session);
        self->started = false;
    }
    if(self->opus_initialized) {
        chiaki_opus_decoder_fini(&self->opus_decoder);
        self->opus_initialized = false;
    }
    if(self->initialized) {
        chiaki_session_fini(&self->session);
        self->initialized = false;
    }
    free(self);
}

void chiaki_tv_session_set_controller_state(
    chiaki_tv_session_t *self,
    const chiaki_tv_controller_state_t *state)
{
    if(!self || !self->started || !state) return;

    ChiakiControllerState s;
    chiaki_controller_state_set_idle(&s);
    s.buttons      = state->buttons;
    s.l2_state     = state->l2_state;
    s.r2_state     = state->r2_state;
    s.left_x       = state->left_x;
    s.left_y       = state->left_y;
    s.right_x      = state->right_x;
    s.right_y      = state->right_y;
    s.gyro_x       = state->gyro_x;
    s.gyro_y       = state->gyro_y;
    s.gyro_z       = state->gyro_z;
    s.accel_x      = state->accel_x;
    s.accel_y      = state->accel_y;
    s.accel_z      = state->accel_z;
    s.orient_x     = state->orient_x;
    s.orient_y     = state->orient_y;
    s.orient_z     = state->orient_z;
    s.orient_w     = state->orient_w;

    chiaki_session_set_controller_state(&self->session, &s);
}

void chiaki_tv_session_set_login_pin(
    chiaki_tv_session_t *self, const char *pin_digits)
{
    if(!self || !self->started || !pin_digits) return;
    size_t len = strlen(pin_digits);
    chiaki_session_set_login_pin(&self->session, (const uint8_t *)pin_digits, len);
}

void chiaki_tv_session_request_idr(chiaki_tv_session_t *self)
{
    if(!self || !self->started) return;
    chiaki_session_request_idr(&self->session);
}

void chiaki_tv_session_get_stats(
    chiaki_tv_session_t *self,
    chiaki_tv_session_stats_t *out)
{
    if(!out) return;
    memset(out, 0, sizeof(*out));
    if(!self || !self->started) return;
    /* `stream_connection` and `congestion_control` are POD members of
     * ChiakiSession (see lib/include/chiaki/session.h, streamconnection.h,
     * congestioncontrol.h). The desktop GUI reads them the same way:
     * gui/src/streamsession.cpp:484, 2633. Reads of an aligned `double`
     * are atomic on aarch64; we accept a sub-frame of staleness rather
     * than serializing every video packet through a mutex. */
    out->measured_bitrate_mbps = self->session.stream_connection.measured_bitrate;
    out->packet_loss = self->session.stream_connection.congestion_control.packet_loss;
    out->frames_received  = atomic_load_explicit(&self->frames_received,  memory_order_relaxed);
    out->frames_lost      = atomic_load_explicit(&self->frames_lost,      memory_order_relaxed);
    out->frames_recovered = atomic_load_explicit(&self->frames_recovered, memory_order_relaxed);
    /* rtt_us is set once by Senkusha at session start. lib/src/streamconnection.c:1002
     * does the same divide-by-1000 conversion when seeding the launch spec. */
    out->latency_ms = (uint32_t)(self->session.rtt_us / 1000);
}
