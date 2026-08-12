#!/bin/bash

# 2026-08-13 换源(第 2 版): 用户提供 Ubuntu old-releases 官方打包的 librist 0.2.10 orig tarball。
# 背景:
#   - 原 code.videolan.org/rist/librist.git 被 Anubis 反爬封禁(git 协议与网页归档均 502/"Oh noes!" 挑战页);
#   - 第 1 版换源用 nanake fork tag v0.2.6(codeload), 依赖编译通过(含 clock_gettime 修复), 但
#     FFmpeg release/9.0 的 configure 要求 librist >= 0.2.7 -> v0.2.6 太旧, build.sh 阶段失败;
#   - nanake fork 无 v0.2.7+ tag (仅到 v0.2.6); videolan 官方无可下载 tarball;
#   - 用户提供: https://old-releases.ubuntu.com/ubuntu/pool/universe/libr/librist/librist_0.2.10+dfsg.orig.tar.xz (HTTP 200, 157KB)。
# 0.2.10 相对 v0.2.6 的关键差异 (已逐文件核实):
#   1) contrib/time-shim.c:12 已自带 `#if defined(_WIN32) && !HAVE_CLOCK_GETTIME` 守卫 (上游已修) ->
#      之前 v0.2.6 时代的 python 补丁 + 探测宏全部不再需要, 已还原为干净脚本;
#      HAVE_CLOCK_GETTIME 由 meson.build Windows 分支 (have_mingw_pthreads=true 时)
#      cc.has_function('clock_gettime', prefix:'#include <time.h>', dependencies: threads) 检测并
#      cdata.set10 写入 config.h (time-shim.h #include "config.h" 传入 TU)。
#   2) dfsg 打包剥掉了捆绑第三方库 contrib/contrib_cJSON (cJSON) -> 容器无外部 cjson,
#      meson 会 fallback builtin_cjson=true 引用 contrib/contrib_cJSON/cjson/cJSON.c -> 必须自备:
#      ffbuild_dockerbuild 里从 DaveGamble/cJSON v1.7.18 拉 cJSON.c/cJSON.h 放入该路径。
#   3) crypto/psk.h 仍 #include "mbedtls/aes.h" (2.x/3.x API) -> 内部 40-mbedtls.sh 锁定 v3.6.3 必须保留;
#      contrib/mbedtls/meson.build 在 builtin_mbedtls=false 时走外部 dependency('mbedcrypto')
#      (has_headers: ['mbedtls/aes.h']) -> 由 40-mbedtls.sh stage 安装的 v3.6.3 满足。
# 版本检查: pkg-config librist 报 0.2.10 >= 0.2.7 ✓。
ffbuild_dockerdl() {
    echo "retry-tool sh -c \"curl -sSL -o librist.tar.xz 'https://old-releases.ubuntu.com/ubuntu/pool/universe/libr/librist/librist_0.2.10+dfsg.orig.tar.xz' && tar xJf librist.tar.xz --strip-components=1\""
    return
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # dfsg tarball 无捆绑 cJSON; 若外部 cjson 缺失, meson 会 fallback 到内置
    # contrib/contrib_cJSON/cjson/cJSON.c -> 补齐 (DaveGamble/cJSON v1.7.18, 与 librist 0.2.x 内置版兼容)。
    mkdir -p contrib/contrib_cJSON/cjson
    curl -sSL -o contrib/contrib_cJSON/cjson/cJSON.c 'https://raw.githubusercontent.com/DaveGamble/cJSON/v1.7.18/cJSON.c'
    curl -sSL -o contrib/contrib_cJSON/cjson/cJSON.h 'https://raw.githubusercontent.com/DaveGamble/cJSON/v1.7.18/cJSON.h'
    ls -l contrib/contrib_cJSON/cjson/

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=static
        -Duse_mbedtls=true
        -Dbuiltin_mbedtls=false
        -Dbuilt_tools=false
        -Dtest=false
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            -Dhave_mingw_pthreads=true
        )
    fi

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return -1
    fi

    meson "${myconf[@]}" ..
    ninja -j"$(nproc)"
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    echo "Requires: mbedcrypto" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/librist.pc
}

ffbuild_configure() {
    echo --enable-librist
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 404 )) || return 0
    echo --disable-librist
}
