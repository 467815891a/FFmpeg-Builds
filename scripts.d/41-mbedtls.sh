#!/bin/bash

SCRIPT_REPO="https://github.com/ARMmbed/mbedtls.git"
SCRIPT_COMMIT="v3.6.3"
SCRIPT_TAGFILTER="v3.6.*"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git submodule update --init --recursive --depth=1"
}

ffbuild_dockerbuild() {
    if [[ $TARGET == win32 ]]; then
        python3 scripts/config.py unset MBEDTLS_AESNI_C
    fi

    # WebRTC/DTLS-SRTP support required by libdatachannel (off by default in mbedTLS 3.6.x)
    python3 scripts/config.py set MBEDTLS_SSL_DTLS_SRTP
    python3 scripts/config.py set MBEDTLS_SSL_PROTO_DTLS
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DMBEDTLS_FATAL_WARNINGS=OFF \
        -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DGEN_FILES=ON \
        -DUSE_STATIC_MBEDTLS_LIBRARY=ON -DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DINSTALL_MBEDTLS_HEADERS=ON \
        ..
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    if [[ $TARGET == win* ]]; then
        echo "Libs.private: -lws2_32 -lbcrypt -lwinmm -lgdi32" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/mbedcrypto.pc
    fi
}
