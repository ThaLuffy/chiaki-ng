# Video Pipeline

## End-to-end path

```
PS5 ─UDP─► chiaki-lib (../../lib/src/{takion,videoreceiver,fec}.c)
              │  GMAC + AES-CTR + FEC + NAL reassembly
              ▼
       ChiakiBridgeC video sample callback (Phase 1)
              │  zero-copy: same buffer the C side wrote
              ▼
       videoDispatchQueue (userInteractive)
              │
              ▼
       VTDecompressionSession (HEVC HW decode)
              │  output handler: CVPixelBuffer (IOSurface-backed, NV12/P010)
              ▼
       MetalRenderer.pendingPixelBuffer  ◄── single-slot atomic store, drop-newest
              │
              ▼  CAMetalDisplayLink tick (60 Hz)
       CVMetalTextureCacheCreateTextureFromImage  → MTLTexture
              │
              ▼
       Custom Metal shader (YUV → RGB, optional tone-map)
              │
              ▼
       CAMetalLayer present at targetPresentationTimestamp
```

## Why not FFmpeg + libplacebo (the desktop path)

The desktop GUI uses FFmpeg → libplacebo via Vulkan/MoltenVK. We drop both:

- **FFmpeg.** chiaki-lib's `lib/src/videoreceiver.c` already produces complete NAL units. We feed them directly into VideoToolbox (Annex-B stream → AVCC `CMBlockBuffer`). The desktop already validates this codepath via [`../../gui/src/qmlbackend.cpp:831-883`](../../gui/src/qmlbackend.cpp) where `videotoolbox` is the auto-selected hardware decoder name on macOS.
- **libplacebo.** Its Vulkan-via-MoltenVK path works on tvOS but: (1) adds ~10 MB to the binary, (2) brings in the full Vulkan validation/ICD loader machinery, (3) most of its features (FSR / FSRCNNX / advanced tone-map) need shader code that's platform-specific to maintain. A native Metal renderer with bilinear/Lanczos via `MetalPerformanceShaders` covers what we need.

This is consistent with [`../../android/`](../../android/) — Android also drops FFmpeg/libplacebo and uses `AMediaCodec` + a custom GL renderer.

## Annex-B vs. AVCC framing

PS5 emits Annex-B (`00 00 00 01` start codes). VideoToolbox expects AVCC (4-byte big-endian length prefix). The Phase 1 path converts in place:

```
Input NAL buffer:  [00 00 00 01 NAL_BYTES … 00 00 00 01 NAL_BYTES …]
Walk Annex-B start codes, replace each [00 00 00 01] with the 4-byte length of the NAL that follows it (big-endian).
Output buffer (same memory):  [LEN1 NAL_BYTES … LEN2 NAL_BYTES …]
Wrap as CMBlockBuffer using kCFAllocatorMalloc + the original buffer pointer to transfer ownership without a copy.
```

This is exactly what the sibling [`../../../ps-remote-play/`](../../../ps-remote-play/) project's `walkAnnexB` does and is documented as zero-copy in its [`docs/optimization/latency-strategy.md`](../../../ps-remote-play/docs/optimization/latency-strategy.md).

## Parameter sets — out-of-band on PS5

The PS5 sends VPS / SPS / PPS **out-of-band** in the `STREAMINFO` control message's `ResolutionPayload.video_header`, **not inline in IDR frames**. chiaki-lib delivers this via `ChiakiVideoProfile`. The Swift `VideoDecoder` must `prime` itself with these parameter sets *before* feeding any frame, otherwise `VTDecompressionSessionCreate` will fail (or `DecodeFrame` will return `kVTVideoDecoderBadDataErr`). This was a hard-learned bug in the sibling project — see [`../../../ps-remote-play/docs/protocol/takion.md#parameter-sets-are-out-of-band-not-inline`](../../../ps-remote-play/docs/protocol/takion.md#parameter-sets-are-out-of-band-not-inline). Avoid relearning it.

## Latency-first VideoToolbox + Metal config

Borrowed from the sibling project's hardware-tested config:

| Setting | Value | Why |
|---|---|---|
| `kVTDecompressionPropertyKey_OutputPoolRequestedMinimumBufferCount` | 2 | Minimum that keeps decode and present alive simultaneously without buffering an extra frame |
| `kVTDecompressionPropertyKey_RealTime` | true | Hint to the HW decoder to prefer latency over throughput |
| `CAMetalLayer.maximumDrawableCount` | 2 | Same reason — third drawable is pure latency |
| `VTDecompressionSessionDecodeFrame` flags | `[]` (synchronous) | Output handler runs before `DecodeFrame` returns; serialize on a dedicated `decoderQueue` |
| Pre-decoder backpressure | none | The renderer's single-slot `pendingPixelBuffer` is the natural drop-newest boundary |

## HDR10 path

The PS5 emits HDR streams as BT.2020 + SMPTE-2084 PQ + BT.2020-NCL Y'CbCr (`lib/src/launchspec.c:81` `dynamicRange:HDR`). Three independent things have to line up for the Apple TV to display HDR correctly:

1. **`CMFormatDescription` extensions.** [`VideoDecoder.swift`](../../ChiakiTV/Services/Video/VideoDecoder.swift) (`hdr10ExtensionsDictionary` + `buildFormatDescription`) injects the colorimetry into the format description for HEVC HDR streams. VideoToolbox carries those tags onto the decoded `CVPixelBuffer`:

   - `kCVImageBufferColorPrimariesKey = kCVImageBufferColorPrimaries_ITU_R_2020`
   - `kCVImageBufferTransferFunctionKey = kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ`
   - `kCVImageBufferYCbCrMatrixKey = kCVImageBufferYCbCrMatrix_ITU_R_2020`

2. **Renderer + shader.** [`MetalRenderer.swift`](../../ChiakiTV/Services/Video/MetalRenderer.swift) `applyHDRConfig` switches the `MTKView` drawable to `.bgr10a2Unorm` and the layer colorspace to `CGColorSpace.itur_2100_PQ` for HDR sessions. Plane textures are bound as `r16Unorm` (Y) / `rg16Unorm` (CbCr) for P010 input. The `fs_p010_hdr` fragment shader in [`VideoShaders.metal`](../../ChiakiTV/Services/Video/VideoShaders.metal) applies the BT.2020 limited-range matrix and outputs PQ-encoded R'G'B' directly — the layer's PQ colorspace tag tells the compositor the values are PQ-encoded, so no inverse-PQ + tone-map round-trip is needed.

   `wantsExtendedDynamicRangeContent` is **iOS / macOS only**; on tvOS, HDR delivery is gated by the layer's colorspace + the AVDisplayCriteria below. A 10-bit drawable + Rec.2020 PQ is sufficient.

3. **HDMI link negotiation.** [`StreamMetalView.swift`](../../ChiakiTV/Services/Video/StreamMetalView.swift) sets `UIWindow.avDisplayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate:formatDescription:)` (tvOS 17+) whenever `StreamSession.formatDescription` updates. tvOS uses the format description's color tags + the requested refresh rate to switch the HDMI link to HDR + 60 Hz. The criteria is cleared on `dismantleUIView` so a future SDR app on the same Apple TV doesn't get pinned to HDR.

The session's preferred FPS comes from `AppSettings.fps`; defaults flip to `.res2160p` / `.fps60` / `.h265hdr` / 30 Mbps for the personal-use Apple TV 4K 3rd gen target. chiaki-lib's preset table caps at 1080p (`lib/src/session.c:92-122`), so we set width/height/fps directly on `ChiakiConnectVideoProfile` and rely on `video_profile_auto_downgrade=true` to negotiate down if the PS5 rejects the request.

## What goes wrong here

The decoder is a long line of single-point failures. Document anything you hit in [`../reference/known-issues.md`](../reference/known-issues.md). Recurring suspects (from the sibling project's hardware runs):

- **Wrong frame_index handling**: chiaki's `videoreceiver.c:147-188` flushes incomplete previous frames the moment a new `frame_index` arrives. Skipping that flush leaves stale partial frames in the assembler.
- **Reference frame invalidation**: when the FEC decoder reconstructs a frame whose reference is no longer in the 16-slot ref ring, the slice's `reference_frame` field needs to be rewritten in place. See chiaki's `bitstream.c` and `videoreceiver.c:264-292`.
- **CORRUPTFRAME signaling**: on FEC failure (`videoreceiver.c:203`) or frame-index gap (`:160-168`), send a CORRUPTFRAME control message so the PS5 knows to issue an IDR. Without it the stream stalls on the next P-slice that references the missing frame.
