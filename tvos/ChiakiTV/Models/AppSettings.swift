// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// User-configurable settings, persisted to disk in Phase 1
/// (`Application Support/ChiakiTV/settings.json`). Currently in-memory only.
///
/// Mirrors the subset of [`gui/src/settings.cpp`](../../../gui/src/settings.cpp)
/// that survives the tvOS scope cuts ([`docs/ui/swift-ui-plan.md`](../../docs/ui/swift-ui-plan.md) §1).
struct AppSettings: Codable, Equatable {

    // MARK: General
    var actionOnDisconnect: DisconnectAction = .askConfirm
    var actionOnSuspend:    SuspendAction    = .disconnect

    /// Toggles audio + video enable bits. 0 = both, 1 = audio only,
    /// 2 = video only, 3 = both disabled. Mirrors desktop's `audioVideoDisabled`.
    var audioVideoMode: AudioVideoMode = .both

    var streamerMode: Bool = false
    var verboseLogs:  Bool = false
    /// Toggles the in-stream telemetry HUD pinned to the top centre during
    /// gameplay (`StreamHUDOverlay`). Default on — users care about stream
    /// health and the HUD is unobtrusive (translucent pill, top-safe-area
    /// padded). Disable in Settings → General if it competes with game UI.
    var showStreamStats: Bool = true

    /// Prefilled PSN account ID — base64, 8 bytes. See
    /// [`docs/decisions.md#prefill-psn-account-id-no-oauth`](../../docs/decisions.md).
    /// Default ships Stephano's account so registration works on first launch
    /// without any UI; user can override in Settings.
    var psnAccountId: String = "TyiIo99CmXI="

    // MARK: Video
    var resolution: VideoResolution = .res1080p
    var fps:        VideoFPS        = .fps60
    var bitrateKbps: Int = 15_000
    var codec:      VideoCodec      = .h265
    var renderPreset: RenderPreset  = .highQuality
    var verticalSync: Bool          = true

    // MARK: Audio
    /// Audio buffer depth in milliseconds. Default 80 ms — see
    /// [`docs/architecture/audio-pipeline.md`](../../docs/architecture/audio-pipeline.md).
    var audioBufferMs: Int = 80
    var audioVolume:   Int = 100   // 0–100

    // MARK: Notifications
    var weakWifiThresholdPct:   Int = 5
    var packetLossReportedMax:  Int = 3
}

// MARK: - Forward-compatible Codable

extension AppSettings {

    /// Decode tolerantly: any field missing from the saved file falls back
    /// to the struct's default value. Without this, adding a new field in a
    /// future build would force every existing user's `settings.json` to
    /// reset to defaults on first launch — which silently wipes their
    /// PSN account ID, bitrate, etc.
    init(from decoder: Decoder) throws {
        var s = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)

        s.actionOnDisconnect    = try c.decodeIfPresent(DisconnectAction.self,  forKey: .actionOnDisconnect)    ?? s.actionOnDisconnect
        s.actionOnSuspend       = try c.decodeIfPresent(SuspendAction.self,     forKey: .actionOnSuspend)       ?? s.actionOnSuspend
        s.audioVideoMode        = try c.decodeIfPresent(AudioVideoMode.self,    forKey: .audioVideoMode)        ?? s.audioVideoMode
        s.streamerMode          = try c.decodeIfPresent(Bool.self,              forKey: .streamerMode)          ?? s.streamerMode
        s.verboseLogs           = try c.decodeIfPresent(Bool.self,              forKey: .verboseLogs)           ?? s.verboseLogs
        s.showStreamStats       = try c.decodeIfPresent(Bool.self,              forKey: .showStreamStats)       ?? s.showStreamStats
        s.psnAccountId          = try c.decodeIfPresent(String.self,            forKey: .psnAccountId)          ?? s.psnAccountId
        s.resolution            = try c.decodeIfPresent(VideoResolution.self,   forKey: .resolution)            ?? s.resolution
        s.fps                   = try c.decodeIfPresent(VideoFPS.self,          forKey: .fps)                   ?? s.fps
        s.bitrateKbps           = try c.decodeIfPresent(Int.self,               forKey: .bitrateKbps)           ?? s.bitrateKbps
        s.codec                 = try c.decodeIfPresent(VideoCodec.self,        forKey: .codec)                 ?? s.codec
        s.renderPreset          = try c.decodeIfPresent(RenderPreset.self,      forKey: .renderPreset)          ?? s.renderPreset
        s.verticalSync          = try c.decodeIfPresent(Bool.self,              forKey: .verticalSync)          ?? s.verticalSync
        s.audioBufferMs         = try c.decodeIfPresent(Int.self,               forKey: .audioBufferMs)         ?? s.audioBufferMs
        s.audioVolume           = try c.decodeIfPresent(Int.self,               forKey: .audioVolume)           ?? s.audioVolume
        s.weakWifiThresholdPct  = try c.decodeIfPresent(Int.self,               forKey: .weakWifiThresholdPct)  ?? s.weakWifiThresholdPct
        s.packetLossReportedMax = try c.decodeIfPresent(Int.self,               forKey: .packetLossReportedMax) ?? s.packetLossReportedMax

        self = s
    }
}

// MARK: - Enums

enum DisconnectAction: String, Codable, CaseIterable, Identifiable {
    case askConfirm
    case disconnect
    case sleep

    var id: String { rawValue }
    var label: String {
        switch self {
        case .askConfirm: return "Ask"
        case .disconnect: return "Disconnect"
        case .sleep:      return "Put PS5 in Sleep Mode"
        }
    }
}

enum SuspendAction: String, Codable, CaseIterable, Identifiable {
    case disconnect
    case keepAlive

    var id: String { rawValue }
    var label: String {
        switch self {
        case .disconnect: return "Disconnect"
        case .keepAlive:  return "Keep alive"
        }
    }
}

enum AudioVideoMode: String, Codable, CaseIterable, Identifiable {
    case both
    case audioOnly
    case videoOnly
    case disabled

    var id: String { rawValue }
    var label: String {
        switch self {
        case .both:      return "Audio and Video Enabled"
        case .audioOnly: return "Audio only"
        case .videoOnly: return "Video only"
        case .disabled:  return "Disabled"
        }
    }
}

enum VideoResolution: String, Codable, CaseIterable, Identifiable {
    case res720p
    case res1080p
    case res1440p
    case res2160p

    var id: String { rawValue }
    var label: String {
        switch self {
        case .res720p:  return "720p"
        case .res1080p: return "1080p"
        case .res1440p: return "1440p"
        case .res2160p: return "2160p (4K)"
        }
    }
}

enum VideoFPS: Int, Codable, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var label: String { "\(rawValue) fps" }
}

enum VideoCodec: String, Codable, CaseIterable, Identifiable {
    case h265
    case h265hdr

    var id: String { rawValue }
    var label: String {
        switch self {
        case .h265:    return "H.265 (Default)"
        case .h265hdr: return "H.265 HDR"
        }
    }
}

enum RenderPreset: String, Codable, CaseIterable, Identifiable {
    /// Bilinear scaling.
    case fast
    /// Lanczos via MetalPerformanceShaders.
    case highQuality

    var id: String { rawValue }
    var label: String {
        switch self {
        case .fast:        return "Fast (Bilinear)"
        case .highQuality: return "High Quality (Lanczos)"
        }
    }
}
