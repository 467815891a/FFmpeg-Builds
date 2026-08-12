#!/bin/bash

# 2026-08-13 换源: 原 code.videolan.org(git, meson) 被 Anubis 反爬封禁失效;
# download.videolan.org 发布 tarball 当前 502 不可达;
# 改用 Debian 源上的官方 orig tarball(libudfread_1.1.2.orig.tar.gz, 同源上游 1.1.2 重打包, 当前可达)。
# 注意: 该 orig tarball 是未生成 configure 的原始上游包(只含 bootstrap/configure.ac/Makefile.am/m4),
# 必须先用 ./bootstrap (= autoreconf -vif) 现生成 configure, 再走 autotools 构建。
ffbuild_dockerdl() {
    echo "retry-tool sh -c \"curl -sSL -o udfread.tar.gz 'https://deb.debian.org/debian/pool/main/libu/libudfread/libudfread_1.1.2.orig.tar.gz' && tar xzf udfread.tar.gz --strip-components=1\""
    return
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # 原始上游包无 configure, 先生成(autoreconf -vif)
    ./bootstrap

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
