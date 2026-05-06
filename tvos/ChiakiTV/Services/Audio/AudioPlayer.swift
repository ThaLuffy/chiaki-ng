// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import AVFoundation
import os

/// Plays Opus-decoded PCM frames delivered from chiaki's audio sink. Uses
/// `AVAudioEngine` + `AVAudioPlayerNode` with int16 interleaved buffers
/// scheduled per chiaki audio frame (~50 Hz typical).
///
/// Buffer life cycle:
///   - chiaki audio sink fires `frame_cb` with int16 PCM (channels × frame_size).
///   - We allocate an `AVAudioPCMBuffer` matching the negotiated format, copy
///     the PCM into it, and schedule it on the player node.
///   - `AVAudioEngine` mixes through `mainMixerNode` and renders to the
///     hardware via the system output.
///
/// References:
///   - `docs/architecture/audio-pipeline.md`
///   - `lib/include/chiaki/audioreceiver.h` for the upstream sink contract
final class AudioPlayer: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var format: AVAudioFormat?
    private var configured: Bool = false

    /// Frames scheduled on the player node but not yet rendered. Incremented
    /// in `enqueue`, decremented from each scheduled buffer's completion
    /// handler. `enqueue` runs on chiaki's audio receiver thread; completion
    /// handlers fire on AVAudioEngine's internal queue — both contend on the
    /// same counter, so it's locked.
    private let scheduledFramesLock = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Buffered audio expressed in milliseconds. Returns 0 when the engine
    /// hasn't been configured yet (so the HUD can show "0 ms" rather than
    /// stale state). Read at any thread safety level.
    var bufferMs: Int {
        guard let f = format, f.sampleRate > 0 else { return 0 }
        let frames = scheduledFramesLock.withLock { $0 }
        return Int(Double(frames) * 1000.0 / f.sampleRate)
    }

    /// User-side volume scaling (0.0–1.0). Applied to the player node.
    var volume: Float = 1.0 {
        didSet { player.volume = volume }
    }

    init() {}

    deinit {
        stop()
    }

    /// Configure for the negotiated audio header. Idempotent for matching
    /// formats; rebuilds the engine if channel count or sample rate change.
    func configure(channels: UInt32, sampleRate: Double, bits: UInt32) {
        if configured, let f = format,
           Int(f.channelCount) == Int(channels), f.sampleRate == sampleRate {
            return
        }
        stop()

        configureAVAudioSession()

        let common: AVAudioCommonFormat = (bits == 16) ? .pcmFormatInt16 : .pcmFormatFloat32
        guard let f = AVAudioFormat(commonFormat: common,
                                    sampleRate: sampleRate,
                                    channels: AVAudioChannelCount(channels),
                                    interleaved: true) else {
            chiakiLog("AudioPlayer: AVAudioFormat init failed (rate=\(sampleRate) ch=\(channels) bits=\(bits))",
                      category: .audio, type: .error)
            return
        }
        self.format = f

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: f)

        do {
            try engine.start()
            player.play()
            configured = true
            chiakiLog("AudioPlayer: started (rate=\(sampleRate) ch=\(channels) bits=\(bits))",
                      category: .audio, type: .info)
        } catch {
            chiakiLog("AudioPlayer: engine.start failed: \(error)",
                      category: .audio, type: .error)
        }
    }

    /// Schedule a chiaki int16 PCM frame.
    func enqueue(_ pcm: UnsafePointer<Int16>, byteCount: Int) {
        guard configured, let format = format,
              let bytesPerFrame = Optional(Int(format.streamDescription.pointee.mBytesPerFrame)),
              bytesPerFrame > 0 else {
            return
        }
        let frameCount = byteCount / bytesPerFrame
        guard frameCount > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        if format.commonFormat == .pcmFormatInt16,
           let dst = buffer.int16ChannelData?[0] {
            // Interleaved stereo => a single contiguous block exposed at index 0.
            memcpy(dst, pcm, byteCount)
        } else if format.commonFormat == .pcmFormatFloat32,
                  let dst = buffer.floatChannelData?[0] {
            // Convert int16 -> float (rare path; chiaki ships int16 always).
            let scale: Float = 1.0 / 32768.0
            for i in 0..<(byteCount / 2) {
                dst[i] = Float(pcm[i]) * scale
            }
        } else {
            return
        }
        scheduledFramesLock.withLock { $0 += frameCount }
        player.scheduleBuffer(buffer) { [weak self] in
            self?.scheduledFramesLock.withLock { $0 = max(0, $0 - frameCount) }
        }
    }

    func stop() {
        if configured {
            player.stop()
            engine.stop()
            engine.detach(player)
            configured = false
            format = nil
        }
        // Player's stop drops any buffers that hadn't completed; their
        // completion handlers are not guaranteed to fire, so reset the
        // counter manually rather than letting it drift.
        scheduledFramesLock.withLock { $0 = 0 }
    }

    private func configureAVAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            chiakiLog("AudioPlayer: AVAudioSession config failed: \(error)",
                      category: .audio, type: .error)
        }
    }
}
