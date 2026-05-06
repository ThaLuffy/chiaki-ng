// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import CoreMedia
import ChiakiBridgeC

/// Top-level orchestration for an active streaming session. Wires the
/// chiaki-lib `chiaki_tv_session_*` bridge to:
///   - VideoDecoder + MetalRenderer (video sample callback)
///   - AudioPlayer (audio header + frame callbacks)
///   - ControllerService (state push)
///
/// Lifecycle:
///   `connect(...)` constructs the bridge session and starts it. On QUIT the
///   `state` flips to `.disconnected` (or `.failed`) and consumers should
///   release the StreamSession.
///
/// References:
///   - C bridge: `ChiakiBridgeC/include/ChiakiBridgeC/chiaki_bridge_session.h`
///   - Desktop reference: `gui/src/streamsession.cpp`
@MainActor
@Observable
final class StreamSession {

    enum State: Equatable {
        case idle
        case connecting
        case connected
        case loginPinRequired(retry: Bool)
        case disconnected
        case failed(String)
    }

    private(set) var state: State = .idle

    // MARK: Live telemetry — pulled from the bridge at 1 Hz while connected.
    // `StreamHUDOverlay` binds to these directly.
    private(set) var measuredBitrateMbps: Double = 0
    private(set) var packetLossPct: Double = 0
    private(set) var framesReceived: Int = 0
    private(set) var framesLost: Int = 0
    private(set) var framesRecovered: Int = 0
    private(set) var latencyMs: Int = 0
    private(set) var audioBufferMs: Int = 0

    /// Wall-clock time the bridge transitioned to `.connected`. Cleared on
    /// disconnect. The HUD derives its uptime readout from
    /// `Date().timeIntervalSince(connectedAt)` rather than tracking a tick
    /// count — a single timestamp is the smallest piece of state that survives
    /// briefly-paused stats pumps and view rebuilds.
    private(set) var connectedAt: Date? = nil

    /// Latest CMFormatDescription from the decoder. Drives
    /// `AVDisplayManager.preferredDisplayCriteria` in `StreamMetalView` so
    /// the Apple TV negotiates an HDR + correct-refresh-rate HDMI link.
    /// Cleared on disconnect.
    private(set) var formatDescription: CMFormatDescription?

    /// Renderer + decoder are owned by the session — created in init, reused
    /// across reconnects to avoid Metal device churn.
    let renderer: MetalRenderer
    @ObservationIgnored private let decoder: VideoDecoder
    @ObservationIgnored private let audio = AudioPlayer()
    @ObservationIgnored private let controller: ControllerService

    // C-bridge plumbing — not view-observable. Keeping these out of the
    // `@Observable` tracking machinery so `deinit` (nonisolated) can release
    // them during teardown.
    @ObservationIgnored private var sessionHandle: OpaquePointer?
    @ObservationIgnored private var selfRetained: Unmanaged<StreamSession>?

    /// Registered codec for the current session (chiaki_tv_codec_t value).
    @ObservationIgnored private var currentCodec: VideoDecoder.Codec = .h265

    /// 1 Hz telemetry pump. Cancelled on disconnect so a destroyed session
    /// can never have its handle dereferenced from a stale poll.
    @ObservationIgnored private var statsTask: Task<Void, Never>? = nil

    init(controllerService: ControllerService) {
        self.renderer = MetalRenderer()
        self.decoder = VideoDecoder()
        self.controller = controllerService

        // Hook decoder output → renderer.
        self.decoder.onPixelBuffer = { [weak self] buffer in
            self?.renderer.present(buffer)
        }

        // Hook decoder format-description → @Observable property so the
        // SwiftUI host can drive `AVDisplayManager.preferredDisplayCriteria`
        // (HDR + refresh-rate negotiation with the TV).
        self.decoder.onFormatDescriptionReady = { [weak self] desc in
            guard let self = self else { return }
            Task { @MainActor in
                self.formatDescription = desc
            }
        }

        // Hook controller state changes → bridge.
        self.controller.onState = { [weak self] state in
            guard let self = self, let h = self.sessionHandle else { return }
            var s = state
            chiaki_tv_session_set_controller_state(h, &s)
        }
    }

    deinit {
        if let h = sessionHandle {
            chiaki_tv_session_destroy(h)
        }
        selfRetained?.release()
    }

    // MARK: - Public

    /// Open a connection to a registered host. Reuses the bridge session
    /// machinery already wired in `init`.
    func connect(
        registered: RegisteredHost,
        host: Host,
        settings: AppSettings
    ) {
        disconnect()
        state = .connecting

        // Pick the most reliable IP we have. Fresh discovery is preferred, but
        // can be empty / "0.0.0.0" right after a wake (the PS5 hasn't responded
        // to discovery yet). Fall back to the IP we cached at registration time
        // — typically stable on a home LAN with DHCP reservations.
        let resolvedIp = Self.resolveHostIp(discovered: host.ipAddress,
                                            registered: registered.lastIpAddress)
        guard !resolvedIp.isEmpty else {
            chiakiLog("StreamSession: refusing to connect — no usable IP (discovered='\(host.ipAddress)' registered='\(registered.lastIpAddress)')",
                      category: .session, type: .error)
            state = .failed("No reachable IP for \(host.nickname). Wait a moment after wake, or re-register.")
            return
        }

        guard let regKey = Data(base64Encoded: registered.rpRegistKeyBase64),
              let rpKey  = Data(base64Encoded: registered.rpKeyBase64),
              regKey.count == 16, rpKey.count == 16 else {
            state = .failed("RegisteredHost has malformed keys")
            return
        }
        guard let acctId = RegistrationService.decodePsnAccountId(settings.psnAccountId) else {
            state = .failed("PSN account ID invalid")
            return
        }

        let codec: VideoDecoder.Codec = {
            switch settings.codec {
            case .h265:    return .h265
            case .h265hdr: return .h265HDR
            }
        }()
        currentCodec = codec
        formatDescription = nil
        renderer.prepare(forHDR: codec == .h265HDR)
        let codecValue: Int32 = {
            switch codec {
            case .h264:    return Int32(CHIAKI_TV_CODEC_H264.rawValue)
            case .h265:    return Int32(CHIAKI_TV_CODEC_H265.rawValue)
            case .h265HDR: return Int32(CHIAKI_TV_CODEC_H265_HDR.rawValue)
            }
        }()

        let resolution = settings.resolution.dimensions
        let fps = UInt32(settings.fps.rawValue)
        let bitrate = UInt32(settings.bitrateKbps)

        let retained = Unmanaged.passRetained(self)
        selfRetained = retained

        let bridgeSession: OpaquePointer? =
        resolvedIp.withCString { (ipCStr: UnsafePointer<CChar>) -> OpaquePointer? in
            regKey.withUnsafeBytes { regBytes in
                rpKey.withUnsafeBytes { rpBytes in
                    acctId.withUnsafeBytes { acctBytes in
                        var config = chiaki_tv_session_config_t()
                        config.ps5 = true
                        config.host_ip = ipCStr
                        config.regist_key = regBytes.bindMemory(to: UInt8.self).baseAddress
                        config.rp_key     = rpBytes.bindMemory(to: UInt8.self).baseAddress
                        config.psn_account_id = acctBytes.bindMemory(to: UInt8.self).baseAddress
                        config.video_width  = UInt32(resolution.width)
                        config.video_height = UInt32(resolution.height)
                        config.video_max_fps = fps
                        config.video_bitrate_kbps = bitrate
                        config.video_codec = codecValue
                        config.video_profile_auto_downgrade = true
                        config.enable_dualsense = false
                        config.audio_video_disabled = Int32(CHIAKI_TV_AV_BOTH_ENABLED.rawValue)
                        config.auto_regist = false
                        config.packet_loss_max = 0.05
                        config.enable_idr_on_fec_failure = true

                        config.event_cb = Self.cEventCallback
                        config.event_cb_user = retained.toOpaque()
                        config.video_sample_cb = Self.cVideoCallback
                        config.video_sample_cb_user = retained.toOpaque()
                        config.audio_header_cb = Self.cAudioHeaderCallback
                        config.audio_frame_cb  = Self.cAudioFrameCallback
                        config.audio_user = retained.toOpaque()

                        return chiaki_tv_session_create(&config)
                    }
                }
            }
        }

        guard let svc = bridgeSession else {
            retained.release()
            selfRetained = nil
            state = .failed("Failed to construct chiaki session")
            return
        }
        sessionHandle = svc

        if !chiaki_tv_session_start(svc) {
            chiaki_tv_session_destroy(svc)
            sessionHandle = nil
            retained.release()
            selfRetained = nil
            state = .failed("Failed to start chiaki session")
            return
        }
        chiakiLog("StreamSession: started against \(resolvedIp) (discovered='\(host.ipAddress)' registered='\(registered.lastIpAddress)') \(resolution.width)x\(resolution.height) @\(fps)fps codec=\(codec))",
                  category: .session, type: .info)
        startStatsPump()
    }

    /// Background pump that pulls live stats from the bridge each second.
    /// `StreamHUDOverlay` observes the resulting properties directly — there
    /// is no second consumer, so the pump writes once per cycle and exits.
    private func startStatsPump() {
        statsTask?.cancel()
        statsTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self, let h = self.sessionHandle else { return }
                var stats = chiaki_tv_session_stats_t()
                chiaki_tv_session_get_stats(h, &stats)
                self.measuredBitrateMbps = stats.measured_bitrate_mbps
                self.packetLossPct       = stats.packet_loss * 100.0
                self.framesReceived      = Int(stats.frames_received)
                self.framesLost          = Int(stats.frames_lost)
                self.framesRecovered     = Int(stats.frames_recovered)
                self.latencyMs           = Int(stats.latency_ms)
                self.audioBufferMs       = self.audio.bufferMs
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopStatsPump() {
        statsTask?.cancel()
        statsTask = nil
        measuredBitrateMbps = 0
        packetLossPct = 0
        framesReceived = 0
        framesLost = 0
        framesRecovered = 0
        latencyMs = 0
        audioBufferMs = 0
        connectedAt = nil
        formatDescription = nil
    }

    /// Picks the most reachable IPv4 string we have. Empty string + literal
    /// "0.0.0.0" are both treated as unusable (the latter is what chiaki-lib
    /// resolves an empty host to via getaddrinfo). Returns "" when neither
    /// source is usable so the caller can surface a clear error.
    private static func resolveHostIp(discovered: String, registered: String) -> String {
        let d = discovered.trimmingCharacters(in: .whitespaces)
        if !d.isEmpty && d != "0.0.0.0" { return d }
        let r = registered.trimmingCharacters(in: .whitespaces)
        if !r.isEmpty && r != "0.0.0.0" {
            chiakiLog("StreamSession: discovered host has no IP, falling back to registered.lastIpAddress=\(r)",
                      category: .session, type: .info)
            return r
        }
        return ""
    }

    /// User entered the on-PS5 login PIN after a `loginPinRequired` event.
    func submitLoginPin(_ pin: String) {
        guard let h = sessionHandle else { return }
        pin.withCString { cstr in
            chiaki_tv_session_set_login_pin(h, cstr)
        }
    }

    func disconnect() {
        guard let h = sessionHandle else { return }
        chiakiLog("StreamSession: disconnecting", category: .session, type: .info)
        stopStatsPump()
        chiaki_tv_session_destroy(h)
        sessionHandle = nil
        selfRetained?.release()
        selfRetained = nil
        audio.stop()
        if state != .idle {
            state = .disconnected
        }
    }

    // MARK: - C callbacks

    private static let cEventCallback: @convention(c) (
        UnsafePointer<chiaki_tv_session_event_t>?, UnsafeMutableRawPointer?
    ) -> Void = { eventPtr, userPtr in
        guard let userPtr = userPtr, let eventPtr = eventPtr else { return }
        let me = Unmanaged<StreamSession>.fromOpaque(userPtr).takeUnretainedValue()
        let event = eventPtr.pointee
        Task { @MainActor in
            me.handleEvent(event)
        }
    }

    private func handleEvent(_ event: chiaki_tv_session_event_t) {
        switch event.type {
        case CHIAKI_TV_SESSION_EVENT_CONNECTED:
            chiakiLog("StreamSession: connected", category: .session, type: .info)
            state = .connected
            connectedAt = Date()
        case CHIAKI_TV_SESSION_EVENT_LOGIN_PIN_REQUEST:
            state = .loginPinRequired(retry: event.pin_incorrect)
        case CHIAKI_TV_SESSION_EVENT_QUIT:
            let reasonStr = event.quit_reason_str.map { String(cString: $0) } ?? "?"
            chiakiLog("StreamSession: quit reason=\(event.quit_reason) (\(reasonStr))",
                      category: .session, type: .info)
            // QUIT_REASON_STOPPED (1) and QUIT_REASON_STREAM_CONNECTION_REMOTE_SHUTDOWN
            // (12) are clean shutdowns; everything else is failure.
            if event.quit_reason == 1 || event.quit_reason == 12 {
                state = .disconnected
            } else {
                state = .failed("Quit: \(reasonStr) (\(event.quit_reason))")
            }
        case CHIAKI_TV_SESSION_EVENT_NICKNAME_RECEIVED:
            chiakiLog("StreamSession: nickname received", category: .session, type: .info)
        case CHIAKI_TV_SESSION_EVENT_RUMBLE:
            // DualSense haptics — Phase 2 polish.
            break
        default:
            break
        }
    }

    private static let cVideoCallback: @convention(c) (
        UnsafeMutablePointer<UInt8>?, Int, Int32, Bool, UnsafeMutableRawPointer?
    ) -> Bool = { bufPtr, bufSize, _, _, userPtr in
        guard let bufPtr = bufPtr, let userPtr = userPtr, bufSize > 0 else {
            return false
        }
        let me = Unmanaged<StreamSession>.fromOpaque(userPtr).takeUnretainedValue()
        let buffer = UnsafeBufferPointer(start: bufPtr, count: bufSize)
        // Video receiver thread — call decoder synchronously here.
        return me.decoder.submitSynchronously(buffer, codec: me.currentCodec)
    }

    private static let cAudioHeaderCallback: @convention(c) (
        UnsafePointer<chiaki_tv_audio_header_t>?, UnsafeMutableRawPointer?
    ) -> Void = { headerPtr, userPtr in
        guard let headerPtr = headerPtr, let userPtr = userPtr else { return }
        let me = Unmanaged<StreamSession>.fromOpaque(userPtr).takeUnretainedValue()
        let h = headerPtr.pointee
        Task { @MainActor in
            me.audio.configure(channels: UInt32(h.channels),
                               sampleRate: Double(h.rate),
                               bits: UInt32(h.bits))
        }
    }

    private static let cAudioFrameCallback: @convention(c) (
        UnsafePointer<Int16>?, Int, UnsafeMutableRawPointer?
    ) -> Void = { pcmPtr, byteCount, userPtr in
        guard let pcmPtr = pcmPtr, let userPtr = userPtr, byteCount > 0 else { return }
        let me = Unmanaged<StreamSession>.fromOpaque(userPtr).takeUnretainedValue()
        // chiaki audio receiver thread. AudioPlayer's enqueue is thread-safe
        // for scheduling buffers (AVAudioPlayerNode.scheduleBuffer is).
        me.audio.enqueue(pcmPtr, byteCount: byteCount)
    }
}

// MARK: - Resolution helper

private extension VideoResolution {
    var dimensions: (width: Int, height: Int) {
        switch self {
        case .res720p:  return (1280,  720)
        case .res1080p: return (1920, 1080)
        case .res1440p: return (2560, 1440)
        case .res2160p: return (3840, 2160)
        }
    }
}
