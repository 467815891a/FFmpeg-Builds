#!/bin/bash

# 2026-08-12 换源: code.videolan.org 被 Anubis 反爬封禁, 改指镜像(见下方注释)
# 2026-08-12 换源: code.videolan.org 被 Anubis 反爬封禁, 改用官方发布 tarball(download.videolan.org)
ffbuild_dockerdl() {
    echo "retry-tool sh -c \"curl -sSL -o dvdnav.tar.bz2 'https://download.videolan.org/pub/videolan/libdvdnav/6.1.1/libdvdnav-6.1.1.tar.bz2' && tar xjf dvdnav.tar.bz2 --strip-components=1\""
    return
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return -1
    (( $(ffbuild_ffver) >= 700 )) || return -1
    return 0
}

ffbuild_dockerbuild() {
    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libdvdnav
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 700 )) || return 0
    echo --disable-libdvdnav
}
