#!/bin/bash

# 2026-08-12 换源: code.videolan.org 被 Anubis 反爬封禁, 改指镜像(见下方注释)
# 2026-08-12 换源: code.videolan.org 被 Anubis 反爬封禁, 改用官方发布 tarball(download.videolan.org)
ffbuild_dockerdl() {
    echo "retry-tool sh -c \"curl -sSL -o bluray.tar.bz2 'https://download.videolan.org/pub/videolan/libbluray/1.3.4/libbluray-1.3.4.tar.bz2' && tar xjf bluray.tar.bz2 --strip-components=1\""
    return
}

ffbuild_depends() {
    echo base
    echo libxml2
    echo fonts
    echo libudfread
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-pic
        # 2026-08-13: libbluray 1.3.4 configure 无 --disable-bdjava 选项
        # (autoconf 静默忽略), BD-Java JAR 默认构建 -> 强制查 ant 并报错。
        # 窗口静态构建不需要 JAR, 改用 --disable-bdjava-jar。
        --disable-bdjava-jar
        --disable-doxygen-doc
        --disable-examples
        --disable-utils
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    export CPPFLAGS="${CPPFLAGS} -Ddec_init=libbr_dec_init"

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libbluray
}

ffbuild_unconfigure() {
    echo --disable-libbluray
}
