#!/bin/bash

# 2026-08-12 换源: 原主机(svn.xvid.org / git.code.sf.net)不可达, 改指 github 镜像
SCRIPT_REPO="https://github.com/arthenica/xvidcore.git"
SCRIPT_COMMIT="64024ed9552fd40325da6a85156c257dba809cfb"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return -1
    return 0
}



ffbuild_dockerbuild() {
    cd xvidcore

    # 2026-08-13: GCC 15 默认以 C23 编译, 'bool' 成为保留关键字,
    # xvid 的 'typedef int bool;' 会触发 "cannot be defined via typedef" 错误。
    # 双保险: 强制回退到 gnu99 标准, 并把该 typedef 条件化(仅在 <C23 时保留)。
    export CFLAGS="$CFLAGS -std=gnu99"
    find . -type f \( -name '*.h' -o -name '*.c' \) \
        -exec sed -i 's/typedef[[:space:]]*int[[:space:]]*bool;/#if !defined(__STDC_VERSION__) || __STDC_VERSION__ < 202311L\ntypedef int bool;\n#endif/' {} +

    cd build/generic


    # The original code fails on a two-digit major...
    sed -i\
        -e 's/GCC_MAJOR=.*/GCC_MAJOR=10/' \
        -e 's/GCC_MINOR=.*/GCC_MINOR=0/' \
        configure.in

    ./bootstrap.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
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

    if [[ $TARGET == win* ]]; then
        rm "$FFBUILD_DESTPREFIX"/{bin/libxvidcore.dll,lib/libxvidcore.dll.a}
    elif [[ $TARGET == linux* ]]; then
        rm "$FFBUILD_DESTPREFIX"/lib/libxvidcore.so*
    fi
}

ffbuild_configure() {
    echo --enable-libxvid
}

ffbuild_unconfigure() {
    echo --disable-libxvid
}
