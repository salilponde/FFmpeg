#!/usr/bin/env bash
# Builds/installs the permissively licensed external dependencies used by
# lgpl-shared-libs.yml into <install-prefix>. Libraries are built as static,
# position-independent archives so they end up inside the FFmpeg libraries
# and add no runtime dependencies.
#
# usage: build-deps.sh <install-prefix> <scratch-dir>
# env:   DAV1D_VERSION, LIBVPX_VERSION                  (all platforms)
#        NV_CODEC_HEADERS_TAG                           (Linux, Windows x86_64)
#        AMF_TAG                                        (Windows x86_64)
#        ZLIB_VERSION                                   (Windows)
#        CC                                             (optional compiler)
#        MACOSX_DEPLOYMENT_TARGET                       (macOS)
#
# License texts are installed to <install-prefix>/licenses.

set -euo pipefail

PREFIX=$1
SRC=$2
mkdir -p "$PREFIX/include" "$PREFIX/lib" "$PREFIX/licenses" "$SRC"

case "$(uname -s)" in
    Darwin)               PLATFORM=macos;   OS=darwin20 ;; # darwin20 = macOS 11
    Linux)                PLATFORM=linux;   OS=linux    ;;
    MINGW*|UCRT*|MSYS*)   PLATFORM=windows; OS=win64    ;;
    *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64)        ARCH=x86_64 ;;
    arm64|aarch64) ARCH=arm64  ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
if [ "$PLATFORM" = macos ]; then JOBS=$(sysctl -n hw.ncpu); else JOBS=$(nproc); fi
# No NVIDIA or AMD GPUs exist for Windows on ARM.
GPU_SDKS=yes
if [ "$PLATFORM" = windows ] && [ "$ARCH" = arm64 ]; then GPU_SDKS=no; fi

# Prints the leading comment block (the license notice) of a source file.
header_notice() {
    awk 'NR == 1 && !/^\/\*/ { exit } { print } /\*\// { exit }' "$1"
}

# NVENC/NVDEC API headers (MIT). Header-only; the dynamic loader is compiled
# into FFmpeg, so the notices go into the license bundle.
if [ "$PLATFORM" != macos ] && [ "$GPU_SDKS" = yes ]; then
    git clone --depth 1 --branch "$NV_CODEC_HEADERS_TAG" \
        https://github.com/FFmpeg/nv-codec-headers.git "$SRC/nv-codec-headers"
    make -C "$SRC/nv-codec-headers" install PREFIX="$PREFIX"
    for h in "$SRC"/nv-codec-headers/include/ffnvcodec/*.h; do
        echo "== $(basename "$h") =="
        header_notice "$h"
        echo
    done > "$PREFIX/licenses/nv-codec-headers-LICENSE.txt"
fi

if [ "$PLATFORM" = windows ] && [ "$GPU_SDKS" = yes ]; then
    # AMD AMF headers (MIT). Header-only; the runtime is loaded on demand.
    git clone --depth 1 --branch "$AMF_TAG" --filter=blob:none --sparse \
        https://github.com/GPUOpen-LibrariesAndSDKs/AMF "$SRC/amf"
    git -C "$SRC/amf" sparse-checkout set --no-cone /amf/public/include /LICENSE.txt
    mkdir -p "$PREFIX/include/AMF"
    cp -R "$SRC/amf/amf/public/include/." "$PREFIX/include/AMF/"
    cp "$SRC/amf/LICENSE.txt" "$PREFIX/licenses/amf-LICENSE.txt"
fi

if [ "$PLATFORM" = windows ]; then
    # zlib (zlib license). Windows has no system zlib, so link it statically.
    git clone --depth 1 --branch "$ZLIB_VERSION" \
        https://github.com/madler/zlib.git "$SRC/zlib"
    make -C "$SRC/zlib" -f win32/Makefile.gcc -j"$JOBS" CC="${CC:-gcc}" AR=ar libz.a
    cp "$SRC/zlib/zlib.h" "$SRC/zlib/zconf.h" "$PREFIX/include/"
    cp "$SRC/zlib/libz.a" "$PREFIX/lib/"
    cp "$SRC/zlib/LICENSE" "$PREFIX/licenses/zlib-LICENSE"
fi

# dav1d: AV1 decoder (BSD-2-Clause)
git clone --depth 1 --branch "$DAV1D_VERSION" \
    https://code.videolan.org/videolan/dav1d.git "$SRC/dav1d"
meson setup "$SRC/dav1d/build" "$SRC/dav1d" \
    --prefix="$PREFIX" --libdir=lib \
    --buildtype=release --default-library=static \
    -Denable_tools=false -Denable_tests=false
ninja -C "$SRC/dav1d/build" install
cp "$SRC/dav1d/COPYING" "$PREFIX/licenses/dav1d-COPYING"

# libvpx: VP8/VP9 encoder and decoder (BSD-3-Clause + patent grant)
git clone --depth 1 --branch "$LIBVPX_VERSION" \
    https://chromium.googlesource.com/webm/libvpx "$SRC/libvpx"
(
    cd "$SRC/libvpx"
    ./configure --prefix="$PREFIX" --target="$ARCH-$OS-gcc" \
        --enable-static --disable-shared --enable-pic \
        --enable-vp8 --enable-vp9 --enable-vp9-highbitdepth \
        --disable-examples --disable-tools --disable-docs --disable-unit-tests
    make -j"$JOBS"
    make install
)
cp "$SRC/libvpx/LICENSE" "$PREFIX/licenses/libvpx-LICENSE"
cp "$SRC/libvpx/PATENTS" "$PREFIX/licenses/libvpx-PATENTS"
