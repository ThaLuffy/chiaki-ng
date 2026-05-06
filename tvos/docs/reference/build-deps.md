# Build Dependencies (Phase 1 plan)

How we get chiaki-ng `lib/` and its dependencies onto an Apple TV.

> **Status: not yet implemented.** Phase 0 ships a `ChiakiBridgeC` that doesn't link against chiaki-lib at all. This page is the plan for Phase 1.

## What needs to compile for tvOS arm64

From the desktop's [`../../../CMakeLists.txt`](../../../CMakeLists.txt) and [`../../../lib/CMakeLists.txt`](../../../lib/CMakeLists.txt):

| Dependency | Source | Linkage | Why |
|---|---|---|---|
| `chiaki-lib` (the upstream library) | [`../../../lib/`](../../../lib/) | static | the protocol core |
| `OpenSSL` (Crypto only) | upstream | static | AES + ECDH + HMAC for `lib/src/rpcrypt.c`, `gkcrypt.c`, `ecdh.c` |
| `libcurl` with WS / WSS support | upstream | static | HTTP for registration + session, WebSocket for PSN holepunch (we won't use WS but the lib still wants the symbol) |
| `libevent` | upstream | static | used by `lib/src/remote/holepunch.c` (we don't run holepunch but `lib/` still references the symbol unless we patch it out) |
| `json-c` | upstream | static | parses PSN responses + holepunch JSON |
| `miniupnpc` | upstream | static | UPnP — only used by holepunch (potentially droppable) |
| `opus` | upstream | static | audio codec |
| `jerasure` | submodule [`../../../third-party/jerasure/`](../../../third-party/jerasure/) | static | FEC matrix math |
| `gf-complete` | submodule [`../../../third-party/gf-complete/`](../../../third-party/gf-complete/) | static | jerasure dependency |
| `nanopb` | submodule [`../../../third-party/nanopb/`](../../../third-party/nanopb/) | static | protobuf encode/decode for TakionMessage |

## Two paths considered

### Path A: build everything via CMake's tvOS toolchain

CMake supports `CMAKE_SYSTEM_NAME=tvOS` plus `CMAKE_OSX_SYSROOT=appletvos`. We'd:

1. Write a `tvos/scripts/build-deps-tvos.sh` that:
   - Builds OpenSSL → `Vendors/openssl/{lib/libcrypto.a, include/}`
   - Builds libcurl (against vendored OpenSSL, with WebSocket on) → `Vendors/curl/`
   - Builds libevent → `Vendors/libevent/`
   - Builds json-c → `Vendors/json-c/`
   - Builds opus → `Vendors/opus/`
   - Builds miniupnpc → `Vendors/miniupnpc/`
2. Configure chiaki-ng's CMake with `-DCMAKE_TOOLCHAIN_FILE=tvos.cmake` and a custom `find_package` setup that points at `Vendors/`. Build `chiaki-lib` to `Vendors/chiaki/libchiaki.a`.
3. Add the resulting `.a` files + headers to `project.yml`'s `OTHER_LDFLAGS` / `HEADER_SEARCH_PATHS`.

This is the path the Android port follows in spirit — it builds chiaki-lib via the existing CMake under the Android NDK.

### Path B: drop `lib/`'s deps that we don't need

`miniupnpc`, `libevent`, and big chunks of `libcurl` are pulled in only by `lib/src/remote/holepunch.c`. Since we're LAN-only:

- Patch `lib/CMakeLists.txt` to skip `holepunch.c` when a new `CHIAKI_ENABLE_HOLEPUNCH=OFF` flag is set.
- Drop `libevent` and `miniupnpc` entirely.
- libcurl could potentially be replaced by `URLSession` for the small registration HTTP request — but this would require touching `lib/src/regist.c` upstream. Probably not worth it; static libcurl + OpenSSL is ~1 MB and doesn't show up in latency.

We'll likely do both: take Path A as the build path and Path B as a build-flag patch upstream.

### Path C: XCFramework

Bundle everything as a single `Chiaki.xcframework` (arm64 device + arm64 simulator). This is the cleanest distribution shape and the easiest one to reuse if the port ever moves to a separate repo. We'll evaluate after the first successful Path A build.

## Build script (Phase 1, sketch)

```bash
# tvos/scripts/build-deps-tvos.sh
set -euo pipefail
ARCH=arm64
SDK=appletvos
SDKROOT=$(xcrun --sdk $SDK --show-sdk-path)
DEPLOYMENT=17.0
PREFIX=$PWD/Vendors

cflags="-arch $ARCH -isysroot $SDKROOT -mtvos-version-min=$DEPLOYMENT -fembed-bitcode"

# OpenSSL
cd third-party/openssl
./Configure ios64-cross --prefix=$PREFIX/openssl no-shared no-async no-engine \
    -arch $ARCH -isysroot $SDKROOT -mtvos-version-min=$DEPLOYMENT
make clean && make -j8 && make install_sw

# (similarly for libcurl, libevent, json-c, opus, miniupnpc)

# chiaki-lib
cd ../..
cmake -B build-tvos -G Ninja \
    -DCMAKE_SYSTEM_NAME=tvOS \
    -DCMAKE_OSX_ARCHITECTURES=$ARCH \
    -DCMAKE_OSX_SYSROOT=$SDKROOT \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$DEPLOYMENT \
    -DCHIAKI_ENABLE_GUI=OFF \
    -DCHIAKI_ENABLE_CLI=OFF \
    -DCHIAKI_ENABLE_TESTS=OFF \
    -DCHIAKI_ENABLE_FFMPEG_DECODER=OFF \
    -DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF \
    -DCHIAKI_ENABLE_SETSU=OFF \
    -DCHIAKI_ENABLE_RUDP=OFF \
    -DOPENSSL_ROOT_DIR=$PREFIX/openssl \
    -DCMAKE_PREFIX_PATH=$PREFIX
ninja -C build-tvos chiaki-lib
cp build-tvos/lib/libchiaki.a $PREFIX/chiaki/lib/
```

This sketch will need adjustment — chiaki-ng's CMake currently *requires* `CHIAKI_ENABLE_GUI=OFF` to skip the libplacebo and SDL2 lookups (GUI implies them). Add `CHIAKI_ENABLE_RUDP=OFF` once we add that flag (Phase 1 upstream contribution).

## After Phase 1 deps land

`project.yml`'s commented-out `LIBRARY_SEARCH_PATHS` / `OTHER_LDFLAGS` blocks (already present in the Phase 0 file) get uncommented and pointed at `Vendors/`. The Phase 0 stub `chiaki_tv_bridge_version()` becomes a smoke test that confirms `libchiaki.a` is linked: extend it to also call into a chiaki-lib version helper.
