#!/usr/bin/env bash
# Cross-compile chiaki-ng's C dependencies + chiaki-lib itself for tvOS.
#
# Outputs go to Vendors/prefix/<slice>/{lib,include}/ where <slice> is one of:
#   - appletvos              (arm64 device)
#   - appletvsimulator       (arm64 simulator)
#
# Usage:
#   ./scripts/build-deps-tvos.sh openssl
#   ./scripts/build-deps-tvos.sh opus
#   ./scripts/build-deps-tvos.sh all
#
# Each dep step is idempotent — re-running with the same arg skips already-built
# slices unless `CLEAN=1` is set.
#
# See docs/reference/build-deps.md for the design rationale and dep DAG.

set -euo pipefail

# ─── Layout ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TVOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDORS_DIR="$TVOS_DIR/Vendors"
SRC_DIR="$VENDORS_DIR/src"
BUILD_DIR="$VENDORS_DIR/build"
PREFIX_DIR="$VENDORS_DIR/prefix"

mkdir -p "$SRC_DIR" "$BUILD_DIR" "$PREFIX_DIR"

# ─── Toolchain ───────────────────────────────────────────────────────────────
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-17.0}"

CLANG=$(xcrun --find clang)
AR=$(xcrun --find ar)
RANLIB=$(xcrun --find ranlib)
LD=$(xcrun --find ld)

# Slice → SDK + min-target flag mapping.
slice_sdk()  { case "$1" in
                  appletvos)        echo "appletvos" ;;
                  appletvsimulator) echo "appletvsimulator" ;;
                  *) echo "unknown slice $1" >&2; return 1 ;;
              esac; }

slice_arch() { echo "arm64"; }   # tvOS-arm64 only on both device and sim — A15/Apple TV 4K 3rd gen.

slice_target_flag() {
    case "$1" in
        appletvos)        echo "-target arm64-apple-tvos${DEPLOYMENT_TARGET}" ;;
        appletvsimulator) echo "-target arm64-apple-tvos${DEPLOYMENT_TARGET}-simulator" ;;
    esac
}

slice_sysroot() {
    xcrun --sdk "$(slice_sdk "$1")" --show-sdk-path
}

# Build a clean CFLAGS / LDFLAGS env for the current slice.
slice_env() {
    local slice="$1"
    local sysroot
    sysroot=$(slice_sysroot "$slice")
    local target_flag
    target_flag=$(slice_target_flag "$slice")

    export CC="$CLANG"
    export CXX="$(xcrun --find clang++)"
    export AR RANLIB LD

    # Bitcode is deprecated as of Xcode 14+ — emitting markers makes the
    # newer ld parse `marker` as a positional file arg and fail. Skip it.
    local common_flags="$target_flag -isysroot $sysroot"
    export CFLAGS="$common_flags -O2 -fPIC"
    export CXXFLAGS="$common_flags -O2 -fPIC"
    export LDFLAGS="$common_flags"
    export CPPFLAGS="-I$PREFIX_DIR/$slice/include"

    # Things that bite on tvOS:
    #  - tvOS has no fork/exec/system; deps that #ifdef on TARGET_OS_IOS often
    #    pick the right code path, but some configure scripts probe for
    #    fork()/system() and assume Linux defaults when cross-compiling.
    #  - Don't link Cocoa / no shared libs.
    export PKG_CONFIG_PATH="$PREFIX_DIR/$slice/lib/pkgconfig"
}

SLICES=(appletvos appletvsimulator)

# ─── Logging ────────────────────────────────────────────────────────────────
say()  { printf "\033[1;34m[build-deps]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[build-deps]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[build-deps]\033[0m %s\n" "$*" >&2; exit 1; }

# ─── Source fetch helpers ────────────────────────────────────────────────────
fetch_tarball() {
    local name="$1" url="$2" expected_sha256="$3"
    local tarball="$SRC_DIR/$name.tar.gz"
    local extracted="$SRC_DIR/$name"

    if [[ -d "$extracted" ]]; then
        say "$name: already extracted"
        return 0
    fi

    if [[ ! -f "$tarball" ]]; then
        say "$name: fetching $url"
        curl -fsSL --output "$tarball" "$url"
    fi

    if [[ -n "$expected_sha256" ]]; then
        local got
        got=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
        [[ "$got" == "$expected_sha256" ]] || fail "$name: sha256 mismatch (got $got, expected $expected_sha256)"
    fi

    say "$name: extracting"
    mkdir -p "$extracted"
    tar -xzf "$tarball" -C "$extracted" --strip-components=1
}

# ─── Skip-if-built helper ────────────────────────────────────────────────────
already_built() {
    local slice="$1" marker="$2"
    [[ -f "$PREFIX_DIR/$slice/$marker" ]] && [[ -z "${CLEAN:-}" ]]
}

# ─── OpenSSL 3 ───────────────────────────────────────────────────────────────
build_openssl() {
    local version="3.0.15"
    local sha256="23c666d0edf20f14249b3d8f0368acaee9ab585b09e1de82107c66e1f3ec9533"
    fetch_tarball "openssl-$version" \
        "https://www.openssl.org/source/openssl-$version.tar.gz" \
        "$sha256"

    for slice in "${SLICES[@]}"; do
        if already_built "$slice" "lib/libcrypto.a.openssl-$version"; then
            say "openssl/$slice: already built"
            continue
        fi

        say "openssl/$slice: configuring"
        local build_path="$BUILD_DIR/openssl/$slice"
        rm -rf "$build_path"
        mkdir -p "$(dirname "$build_path")"
        cp -R "$SRC_DIR/openssl-$version" "$build_path"

        (
            cd "$build_path"
            slice_env "$slice"
            # OpenSSL's Configure is touchy about extra `-target` args — it
            # parses them as target-name overrides. We rely on CC/CFLAGS
            # (set in slice_env) to convey the target triple and sysroot,
            # and pass only the `darwin64-arm64-cc` preset name here.
            #
            # `no-asm` because OpenSSL's arm64 asm calls into routines
            # that aren't valid on tvOS. The C fallback is fine for the
            # crypto we use (AES + ECDH + HMAC).
            ./Configure darwin64-arm64-cc \
                --prefix="$PREFIX_DIR/$slice" \
                --openssldir="$PREFIX_DIR/$slice/ssl" \
                no-shared no-asm no-tests no-engine no-dso no-async \
                no-ui-console no-stdio

            say "openssl/$slice: building libcrypto only"
            make -j"$(sysctl -n hw.ncpu)" build_libs >/dev/null
            say "openssl/$slice: installing"
            make install_dev >/dev/null
        )

        # Stamp so we can skip on subsequent runs.
        touch "$PREFIX_DIR/$slice/lib/libcrypto.a.openssl-$version"
        say "openssl/$slice: done → $PREFIX_DIR/$slice/lib/libcrypto.a"
    done
}

# ─── Opus ────────────────────────────────────────────────────────────────────
build_opus() {
    local version="1.5.2"
    local sha256="65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"
    fetch_tarball "opus-$version" \
        "https://downloads.xiph.org/releases/opus/opus-$version.tar.gz" \
        "$sha256"

    for slice in "${SLICES[@]}"; do
        if already_built "$slice" "lib/libopus.a.opus-$version"; then
            say "opus/$slice: already built"
            continue
        fi

        local build_path="$BUILD_DIR/opus/$slice"
        rm -rf "$build_path"
        mkdir -p "$build_path"

        say "opus/$slice: configuring"
        (
            cd "$build_path"
            slice_env "$slice"
            cmake -G Ninja "$SRC_DIR/opus-$version" \
                -DCMAKE_SYSTEM_NAME=tvOS \
                -DCMAKE_OSX_ARCHITECTURES="$(slice_arch "$slice")" \
                -DCMAKE_OSX_SYSROOT="$(slice_sysroot "$slice")" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
                -DCMAKE_INSTALL_PREFIX="$PREFIX_DIR/$slice" \
                -DBUILD_SHARED_LIBS=OFF \
                -DOPUS_BUILD_PROGRAMS=OFF \
                -DOPUS_BUILD_TESTING=OFF \
                -DOPUS_INSTALL_PKG_CONFIG_MODULE=ON

            say "opus/$slice: building"
            ninja >/dev/null
            say "opus/$slice: installing"
            ninja install >/dev/null
        )

        touch "$PREFIX_DIR/$slice/lib/libopus.a.opus-$version"
        say "opus/$slice: done → $PREFIX_DIR/$slice/lib/libopus.a"
    done
}

# ─── json-c ──────────────────────────────────────────────────────────────────
build_jsonc() {
    local version="0.18"
    local sha256="876ab046479166b869afc6896d288183bbc0e5843f141200c677b3e8dfb11724"
    fetch_tarball "json-c-$version" \
        "https://s3.amazonaws.com/json-c_releases/releases/json-c-$version.tar.gz" \
        "$sha256"

    for slice in "${SLICES[@]}"; do
        if already_built "$slice" "lib/libjson-c.a.json-c-$version"; then
            say "json-c/$slice: already built"
            continue
        fi
        local build_path="$BUILD_DIR/json-c/$slice"
        rm -rf "$build_path"
        mkdir -p "$build_path"

        say "json-c/$slice: configuring"
        (
            cd "$build_path"
            slice_env "$slice"
            cmake -G Ninja "$SRC_DIR/json-c-$version" \
                -DCMAKE_SYSTEM_NAME=tvOS \
                -DCMAKE_OSX_ARCHITECTURES="$(slice_arch "$slice")" \
                -DCMAKE_OSX_SYSROOT="$(slice_sysroot "$slice")" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
                -DCMAKE_INSTALL_PREFIX="$PREFIX_DIR/$slice" \
                -DBUILD_SHARED_LIBS=OFF \
                -DBUILD_STATIC_LIBS=ON \
                -DDISABLE_BSYMBOLIC=ON \
                -DENABLE_THREADING=ON \
                -DDISABLE_WERROR=ON

            say "json-c/$slice: building"
            ninja >/dev/null
            say "json-c/$slice: installing"
            ninja install >/dev/null
        )
        touch "$PREFIX_DIR/$slice/lib/libjson-c.a.json-c-$version"
        say "json-c/$slice: done → $PREFIX_DIR/$slice/lib/libjson-c.a"
    done
}

# ─── libevent ────────────────────────────────────────────────────────────────
build_libevent() {
    local version="2.1.12-stable"
    local sha256="92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb"
    fetch_tarball "libevent-$version" \
        "https://github.com/libevent/libevent/releases/download/release-$version/libevent-$version.tar.gz" \
        "$sha256"

    for slice in "${SLICES[@]}"; do
        if already_built "$slice" "lib/libevent.a.libevent-$version"; then
            say "libevent/$slice: already built"
            continue
        fi
        local build_path="$BUILD_DIR/libevent/$slice"
        rm -rf "$build_path"
        mkdir -p "$build_path"

        say "libevent/$slice: configuring"
        (
            cd "$build_path"
            slice_env "$slice"
            # libevent's CMake disables OPENSSL by default if it can't find it.
            # We pass our cross-compiled OpenSSL prefix explicitly.
            cmake -G Ninja "$SRC_DIR/libevent-$version" \
                -DCMAKE_SYSTEM_NAME=tvOS \
                -DCMAKE_OSX_ARCHITECTURES="$(slice_arch "$slice")" \
                -DCMAKE_OSX_SYSROOT="$(slice_sysroot "$slice")" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
                -DCMAKE_INSTALL_PREFIX="$PREFIX_DIR/$slice" \
                -DCMAKE_PREFIX_PATH="$PREFIX_DIR/$slice" \
                -DCMAKE_FIND_ROOT_PATH="$PREFIX_DIR/$slice" \
                -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
                -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
                -DOPENSSL_ROOT_DIR="$PREFIX_DIR/$slice" \
                -DOPENSSL_INCLUDE_DIR="$PREFIX_DIR/$slice/include" \
                -DOPENSSL_CRYPTO_LIBRARY="$PREFIX_DIR/$slice/lib/libcrypto.a" \
                -DOPENSSL_SSL_LIBRARY="$PREFIX_DIR/$slice/lib/libssl.a" \
                -DEVENT__LIBRARY_TYPE=STATIC \
                -DEVENT__DISABLE_SAMPLES=ON \
                -DEVENT__DISABLE_TESTS=ON \
                -DEVENT__DISABLE_BENCHMARK=ON \
                -DEVENT__DISABLE_REGRESS=ON

            say "libevent/$slice: building"
            ninja >/dev/null
            say "libevent/$slice: installing"
            ninja install >/dev/null
        )
        touch "$PREFIX_DIR/$slice/lib/libevent.a.libevent-$version"
        say "libevent/$slice: done"
    done
}

# ─── libcurl ─────────────────────────────────────────────────────────────────
build_libcurl() {
    local version="8.10.1"
    local sha256="d15ebab765d793e2e96db090f0e172d127859d78ca6f6391d7eafecfd894bbc0"
    fetch_tarball "curl-$version" \
        "https://curl.se/download/curl-$version.tar.gz" \
        "$sha256"

    for slice in "${SLICES[@]}"; do
        if already_built "$slice" "lib/libcurl.a.curl-$version"; then
            say "libcurl/$slice: already built"
            continue
        fi
        local build_path="$BUILD_DIR/curl/$slice"
        rm -rf "$build_path"
        mkdir -p "$build_path"

        say "libcurl/$slice: configuring"
        (
            cd "$build_path"
            slice_env "$slice"
            # Curl on tvOS needs WebSocket on (chiaki-lib references it for
            # holepunch even though we won't use it). Disable everything
            # not strictly needed by our small registration HTTP path.
            cmake -G Ninja "$SRC_DIR/curl-$version" \
                -DCMAKE_SYSTEM_NAME=tvOS \
                -DCMAKE_OSX_ARCHITECTURES="$(slice_arch "$slice")" \
                -DCMAKE_OSX_SYSROOT="$(slice_sysroot "$slice")" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
                -DCMAKE_INSTALL_PREFIX="$PREFIX_DIR/$slice" \
                -DCMAKE_PREFIX_PATH="$PREFIX_DIR/$slice" \
                -DOPENSSL_ROOT_DIR="$PREFIX_DIR/$slice" \
                -DOPENSSL_INCLUDE_DIR="$PREFIX_DIR/$slice/include" \
                -DOPENSSL_CRYPTO_LIBRARY="$PREFIX_DIR/$slice/lib/libcrypto.a" \
                -DOPENSSL_SSL_LIBRARY="$PREFIX_DIR/$slice/lib/libssl.a" \
                -DBUILD_SHARED_LIBS=OFF \
                -DBUILD_STATIC_LIBS=ON \
                -DBUILD_CURL_EXE=OFF \
                -DBUILD_TESTING=OFF \
                -DCURL_USE_OPENSSL=ON \
                -DCURL_USE_LIBPSL=OFF \
                -DCURL_USE_LIBSSH2=OFF \
                -DUSE_LIBIDN2=OFF \
                -DENABLE_WEBSOCKETS=ON \
                -DCURL_DISABLE_LDAP=ON \
                -DCURL_DISABLE_LDAPS=ON \
                -DCURL_DISABLE_DICT=ON \
                -DCURL_DISABLE_FILE=ON \
                -DCURL_DISABLE_GOPHER=ON \
                -DCURL_DISABLE_IMAP=ON \
                -DCURL_DISABLE_MQTT=ON \
                -DCURL_DISABLE_POP3=ON \
                -DCURL_DISABLE_RTSP=ON \
                -DCURL_DISABLE_SMB=ON \
                -DCURL_DISABLE_SMTP=ON \
                -DCURL_DISABLE_TELNET=ON \
                -DCURL_DISABLE_TFTP=ON

            say "libcurl/$slice: building"
            ninja >/dev/null
            say "libcurl/$slice: installing"
            ninja install >/dev/null
        )
        touch "$PREFIX_DIR/$slice/lib/libcurl.a.curl-$version"
        say "libcurl/$slice: done"
    done
}

# ─── miniupnpc ───────────────────────────────────────────────────────────────
build_miniupnpc() {
    local version="2.2.7"
    local sha256="b0c3a27056840fd0ec9328a5a9bac3dc5e0ec6d2e8733349cf577b0aa1e70ac1"
    fetch_tarball "miniupnpc-$version" \
        "https://miniupnp.tuxfamily.org/files/miniupnpc-$version.tar.gz" \
        "$sha256"

    for slice in "${SLICES[@]}"; do
        if already_built "$slice" "lib/libminiupnpc.a.miniupnpc-$version"; then
            say "miniupnpc/$slice: already built"
            continue
        fi
        local build_path="$BUILD_DIR/miniupnpc/$slice"
        rm -rf "$build_path"
        mkdir -p "$build_path"

        say "miniupnpc/$slice: configuring"
        (
            cd "$build_path"
            slice_env "$slice"
            cmake -G Ninja "$SRC_DIR/miniupnpc-$version" \
                -DCMAKE_SYSTEM_NAME=tvOS \
                -DCMAKE_OSX_ARCHITECTURES="$(slice_arch "$slice")" \
                -DCMAKE_OSX_SYSROOT="$(slice_sysroot "$slice")" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
                -DCMAKE_INSTALL_PREFIX="$PREFIX_DIR/$slice" \
                -DUPNPC_BUILD_SHARED=OFF \
                -DUPNPC_BUILD_STATIC=ON \
                -DUPNPC_BUILD_TESTS=OFF \
                -DUPNPC_BUILD_SAMPLE=OFF

            say "miniupnpc/$slice: building"
            ninja >/dev/null
            say "miniupnpc/$slice: installing"
            ninja install >/dev/null
        )
        touch "$PREFIX_DIR/$slice/lib/libminiupnpc.a.miniupnpc-$version"
        say "miniupnpc/$slice: done"
    done
}

# nanopb / jerasure / gf-complete are built inline by chiaki-ng's top-level
# `third-party/CMakeLists.txt`. We don't compile them standalone — `build_chiaki_lib`
# below copies the resulting `.a` files out of the build tree once chiaki-lib
# itself is built.

# ─── chiaki-lib ──────────────────────────────────────────────────────────────
build_chiaki_lib() {
    local lib_source="$TVOS_DIR/../"
    [[ -f "$lib_source/lib/CMakeLists.txt" ]] || fail "chiaki-lib: $lib_source/lib not found"

    for slice in "${SLICES[@]}"; do
        if already_built "$slice" "lib/libchiaki.a.chiaki"; then
            say "chiaki-lib/$slice: already built"
            continue
        fi
        local build_path="$BUILD_DIR/chiaki/$slice"
        rm -rf "$build_path"
        mkdir -p "$build_path"

        say "chiaki-lib/$slice: configuring"
        (
            cd "$build_path"
            slice_env "$slice"
            cmake -G Ninja "$lib_source" \
                -DCMAKE_SYSTEM_NAME=tvOS \
                -DCMAKE_OSX_ARCHITECTURES="$(slice_arch "$slice")" \
                -DCMAKE_OSX_SYSROOT="$(slice_sysroot "$slice")" \
                -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
                -DCMAKE_INSTALL_PREFIX="$PREFIX_DIR/$slice" \
                -DCMAKE_PREFIX_PATH="$PREFIX_DIR/$slice" \
                -DCMAKE_FIND_ROOT_PATH="$PREFIX_DIR/$slice" \
                -DOPENSSL_ROOT_DIR="$PREFIX_DIR/$slice" \
                -DOPENSSL_INCLUDE_DIR="$PREFIX_DIR/$slice/include" \
                -DOPENSSL_CRYPTO_LIBRARY="$PREFIX_DIR/$slice/lib/libcrypto.a" \
                -DCHIAKI_ENABLE_TESTS=OFF \
                -DCHIAKI_ENABLE_CLI=OFF \
                -DCHIAKI_ENABLE_GUI=OFF \
                -DCHIAKI_ENABLE_ANDROID=OFF \
                -DCHIAKI_ENABLE_BOREALIS=OFF \
                -DCHIAKI_ENABLE_STEAM_SHORTCUT=OFF \
                -DCHIAKI_ENABLE_STEAMDECK_NATIVE=OFF \
                -DCHIAKI_ENABLE_FFMPEG_DECODER=OFF \
                -DCHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER=OFF \
                -DCHIAKI_LIB_ENABLE_OPUS=ON \
                -DCHIAKI_LIB_ENABLE_MBEDTLS=OFF \
                -DCHIAKI_USE_SYSTEM_CURL=ON

            say "chiaki-lib/$slice: building"
            ninja chiaki-lib
            # chiaki-lib's CMake doesn't install by default — copy by hand.
            # Upstream emits the archive as `libchiaki.a` (target name
            # `chiaki-lib`, but OUTPUT_NAME defaults to `chiaki`).
            mkdir -p "$PREFIX_DIR/$slice/lib" "$PREFIX_DIR/$slice/include"
            cp lib/libchiaki.a "$PREFIX_DIR/$slice/lib/libchiaki.a"
            # Pull out the third-party static libs that chiaki-lib needs at
            # link time (jerasure links gf-complete; the bridge will need
            # both alongside libchiaki.a). Upstream's third-party CMake
            # emits them at `third-party/lib<name>.a`.
            cp third-party/libjerasure.a "$PREFIX_DIR/$slice/lib/" 2>/dev/null || true
            cp third-party/libgf_complete.a "$PREFIX_DIR/$slice/lib/" 2>/dev/null || true
            cp third-party/nanopb/libprotobuf-nanopb.a "$PREFIX_DIR/$slice/lib/" 2>/dev/null || true
            cp -R "$lib_source/lib/include/chiaki" "$PREFIX_DIR/$slice/include/"
            cp lib/include/chiaki/config.h "$PREFIX_DIR/$slice/include/chiaki/" 2>/dev/null || true
        )
        touch "$PREFIX_DIR/$slice/lib/libchiaki.a.chiaki"
        say "chiaki-lib/$slice: done"
    done
}

# ─── Dispatcher ──────────────────────────────────────────────────────────────
case "${1:-}" in
    openssl)    build_openssl ;;
    opus)       build_opus ;;
    json-c)     build_jsonc ;;
    libevent)   build_libevent ;;
    libcurl)    build_libcurl ;;
    miniupnpc)  build_miniupnpc ;;
    chiaki-lib) build_chiaki_lib ;;
    deps)
        build_openssl
        build_opus
        build_jsonc
        build_libevent
        build_libcurl
        build_miniupnpc
        ;;
    all)
        build_openssl
        build_opus
        build_jsonc
        build_libevent
        build_libcurl
        build_miniupnpc
        build_chiaki_lib
        ;;
    "")        fail "usage: $0 {openssl|opus|json-c|libevent|libcurl|miniupnpc|chiaki-lib|deps|all}" ;;
    *)         fail "unknown target: $1" ;;
esac

say "build-deps: complete"
