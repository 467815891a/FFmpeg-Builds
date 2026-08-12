#!/bin/bash

# 2026-08-12 换源: 原主机(svn.xvid.org / git.code.sf.net)不可达, 改指 github 镜像
SCRIPT_REPO="https://github.com/chirlu/soxr.git"
SCRIPT_COMMIT="945b592b70470e29f917f4de89b4281fbbd540c0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    sed -i 's/VERSION 3.1 /VERSION 3.1...3.10 /g' CMakeLists.txt

    # Short-circuit the check to generate a .pc file. We always want it.
    sed -i 's/NOT WIN32/1/g' src/CMakeLists.txt

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DWITH_OPENMP="$([[ $TARGET == winarm64 ]] && echo OFF || echo ON)" \
        -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_SHARED_LIBS=OFF \
        ..
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    if [[ $TARGET != winarm64 ]]; then
        echo "Libs.private: -lgomp" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/soxr.pc
    fi
}

ffbuild_configure() {
    echo --enable-libsoxr
}

ffbuild_unconfigure() {
    echo --disable-libsoxr
}

ffbuild_ldflags() {
    echo -pthread
}

ffbuild_libs() {
    [[ $TARGET != winarm64 ]] && echo -lgomp
}
