#!/bin/bash

# 2026-08-12 换源: code.videolan.org 被 Anubis 反爬封禁, 改指镜像(见下方注释)
# 2026-08-12 换源: code.videolan.org 被 Anubis 反爬封禁, 改用官方发布 tarball(download.videolan.org)
ffbuild_dockerdl() {
    echo "retry-tool sh -c \"curl -sSL -o dvdread.tar.bz2 'https://download.videolan.org/pub/videolan/libdvdread/6.1.3/libdvdread-6.1.3.tar.bz2' && tar xjf dvdread.tar.bz2 --strip-components=1\""
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

    export CFLAGS="$CFLAGS -Dfile_open_default=libdvdread_file_open_default -Ddir_open_default=libdvdread_dir_open_default"

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    if [[ $TARGET == linux* ]]; then
        echo 'Cflags: -D_FILE_OFFSET_BITS=64 -D_LARGEFILE64_SOURCE' >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/dvdread.pc
    fi
}

ffbuild_configure() {
    echo --enable-libdvdread
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 700 )) || return 0
    echo --disable-libdvdread
}
