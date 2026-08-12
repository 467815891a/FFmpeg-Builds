#!/bin/bash

SCRIPT_REPO="https://svn.code.sf.net/p/lame/svn/trunk/lame"
SCRIPT_REV="6531"

ffbuild_depends() {
    echo base
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # 2026-08-12 换源: svn.code.sf.net 不可达, 改下 sourceforge 官方 tarball
    echo "retry-tool sh -c \"curl -sSL -o lame.tar.gz 'https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz' && tar xzf lame.tar.gz --strip-components=1\""
    return
}

ffbuild_dockerbuild() {
    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --enable-nasm
        --disable-gtktest
        --disable-cpml
        --disable-frontend
        --disable-decoder
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    export CFLAGS="$CFLAGS -DNDEBUG -Wno-error=incompatible-pointer-types"

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libmp3lame
}

ffbuild_unconfigure() {
    echo --disable-libmp3lame
}
