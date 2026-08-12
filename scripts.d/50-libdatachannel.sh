#!/bin/bash

SCRIPT_REPO="https://github.com/paullouisageneau/libdatachannel.git"
SCRIPT_COMMIT="v0.24.5"
SCRIPT_TAGFILTER="v0.*"

ffbuild_depends() {
    echo base
    echo zlib
    echo mbedtls
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # deps/json is only pulled in by the examples/tests targets, and both are
    # turned off below, so it is left out to keep the download cache small.
    echo "git submodule update --init --recursive --depth=1 deps/plog deps/usrsctp deps/libjuice deps/libsrtp"
}

# Static libdatachannel drags in its bundled submodules, mbedTLS and the Win32
# socket stack. FFmpeg probes the library with a plain check_lib (not
# pkg-config), so these have to reach the --extra-libs line for both the
# configure probe and the final link to resolve.
#
# The tail after -lcrypto mirrors "Libs.private" of the mbedtls stage's
# mbedcrypto.pc (-lz -lws2_32 -lgdi32 -lcrypt32 -lwinmm); since openssl declares no
# ffbuild_libs of its own, every static consumer has to carry them.
# The list is in strict dependency order so a single left-to-right link pass
# resolves without --start-group.
# -ldatachannel is listed FIRST, ahead of everything it depends on, so a single
# left-to-right link pass resolves (the dependent must precede its dependencies).
# FFmpeg's own `require` also appends -ldatachannel; the duplicate is harmless.
ffbuild_ldc_libs() {
    local libs=( -ldatachannel -ljuice -lsrtp2 -lusrsctp -lmbedtls -lmbedx509 -lmbedcrypto -lz )
    [[ $TARGET == win* ]] && libs+=( -lbcrypt -lcrypt32 -lgdi32 -liphlpapi -lws2_32 -lwinmm )
    libs+=( -lstdc++ )
    echo "${libs[@]}"
}

# The WHIP/WHEP patch is now part of the custom FFmpeg-WHEP source, so the
# --enable-libdatachannel switch always exists. Wire it in unconditionally:
# the library is built and handed to FFmpeg on every build.


ffbuild_dockerbuild() {
    local version
    version="$(sed -n 's/^[[:space:]]*VERSION[[:space:]]\+\([0-9][0-9.]*\).*/\1/p' CMakeLists.txt | head -n1)"

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_INSTALL_LIBDIR=lib
        # deps/plog still declares cmake_minimum_required(VERSION 3.0)
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_SHARED_DEPS_LIBS=OFF
        -DPREFER_SYSTEM_LIB=OFF
        -DUSE_GNUTLS=OFF
        -DUSE_MBEDTLS=ON
        -DUSE_NICE=OFF

        # libsrtp (bundled submodule) enables -Werror by default and GCC 15.2
        # trips on a %x/long format mismatch in its debug macros. Turn it off so
        # the static library compiles cleanly.
        -DENABLE_WARNINGS_AS_ERRORS=OFF
        -DNO_WEBSOCKET=OFF
        -DNO_MEDIA=OFF
        -DNO_EXAMPLES=ON
        -DNO_TESTS=ON
    )

    cmake "${myconf[@]}" ..
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Upstream ships CMake package files only. FFmpeg does not need a .pc here,
    # but providing one keeps the prefix consistent with every other library and
    # makes the static link line discoverable by pkg-config consumers.
    mkdir -p "$FFBUILD_DESTPREFIX"/lib/pkgconfig
    cat <<EOF > "$FFBUILD_DESTPREFIX"/lib/pkgconfig/libdatachannel.pc
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libdatachannel
Description: C/C++ WebRTC network library featuring Data Channels, Media Transport and WebSockets
URL: https://github.com/paullouisageneau/libdatachannel
Version: ${version}
Libs: -L\${libdir} -ldatachannel
Libs.private: $(ffbuild_ldc_libs)
Cflags: -I\${includedir} -DRTC_STATIC
EOF
}

ffbuild_configure() {
    echo --enable-libdatachannel
}

ffbuild_unconfigure() {
    echo --disable-libdatachannel
}

# Without RTC_STATIC the public headers declare every entry point as
# __declspec(dllimport) on Windows, which turns rtcCreatePeerConnection into
# __imp_rtcCreatePeerConnection and breaks the link against the static archive.
ffbuild_cflags() {
    echo -DRTC_STATIC
}

ffbuild_cxxflags() {
    echo -DRTC_STATIC
}

ffbuild_libs() {
    ffbuild_ldc_libs
}
