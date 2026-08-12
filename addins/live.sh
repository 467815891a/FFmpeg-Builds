#!/bin/bash

# --- 0. 集中禁用清单(方案B) ---
# live 构建不下载、不编译的 stage。取值 = stage 文件 basename(含 NN- 前缀)，
# 与 download.sh / generate.sh 里的 STAGENAME 完全一致。
# 这些 stage 的源码文件保持上游原样，由 download.sh / generate.sh 的钩子按本清单跳过。
# ffbuild_target.sh 会 source 本文件并 export FFBUILD_EXCLUDE_STAGES 供 download.sh 读取；
# generate.sh 在 source addins 时自动获得该变量(未带 live addin 时为空 => 完全上游行为)。
FFBUILD_EXCLUDE_STAGES="50-dav1d 50-libbluray 30-libdvdcss 40-libdvdread 50-libdvdnav 50-libmp3lame 50-x264 50-soxr"
#
# live.sh -- 精简版 ffplay，面向 WHEP / RTSP 直播播放
#
#   ./makeimage.sh win32 gpl 9.0 live
#   ./build.sh     win32 gpl 9.0 live
#
# 本 addin 只追加 FF_CONFIGURE / FF_CONFIGURE_LATE，属于"烤进镜像 ENV"的改动，
# 必须先用 makeimage.sh 重建镜像才会生效（单独传给 build.sh 无效）。
#
# 全部 flag 已在 ffmpeg release/9.0 上实跑 configure 验证通过，无 "did not match anything" 告警。

# --- 1. 只产出 ffplay ---
FF_CONFIGURE="$FF_CONFIGURE --disable-programs --enable-ffplay"

# --- 1b. 体积优先 + 链接期 LTO 跨模块死代码消除 ---
FF_CONFIGURE="$FF_CONFIGURE --enable-small"

# --- 2. 全面禁用编码器与封装器(播放器用不到) ---
FF_CONFIGURE="$FF_CONFIGURE --disable-encoders --disable-muxers"

# --- 3. 解码器: 只保留直播常见编码 ---
#     注: G.722 的正确组件名是 adpcm_g722, 不是 g722
#     注: av1 为原生解码器(Vulkan hwaccel 必须挂在原生解码器上), libdav1d 作软解回退
FF_CONFIGURE="$FF_CONFIGURE --disable-decoders"
FF_CONFIGURE="$FF_CONFIGURE --enable-decoder=h264 --enable-decoder=hevc"
FF_CONFIGURE="$FF_CONFIGURE --enable-decoder=vp9"
FF_CONFIGURE="$FF_CONFIGURE --enable-decoder=aac --enable-decoder=aac_latm --enable-decoder=opus"
FF_CONFIGURE="$FF_CONFIGURE --enable-decoder=pcm_alaw --enable-decoder=pcm_mulaw"
FF_CONFIGURE="$FF_CONFIGURE --enable-decoder=pcm_s16le"

# --- 4. 硬件加速: 只保留 Vulkan ---
#     vp9_vulkan 额外依赖 vulkan_1_4 (需 Vulkan headers >= 1.4.317);
#     本项目 scripts.d/47-vulkan/40-vulkan-headers.sh 固定 v1.4.356, 满足。
FF_CONFIGURE="$FF_CONFIGURE --disable-hwaccels"
FF_CONFIGURE="$FF_CONFIGURE --enable-hwaccel=h264_vulkan --enable-hwaccel=hevc_vulkan"
FF_CONFIGURE="$FF_CONFIGURE --enable-hwaccel=vp9_vulkan"

# --- 5. 解封装器: 只保留 RTSP 链路 ---
#     rtsp_demuxer_select="http_protocol rtpdec"
#     rtpdec_select="asf_demuxer mov_demuxer mpegts_demuxer rm_demuxer rtp_protocol srtp"
#     => asf/mov/mpegts/rm 会被 configure 强制拉入, 属 RTP 解包的正常依赖
FF_CONFIGURE="$FF_CONFIGURE --disable-demuxers"
FF_CONFIGURE="$FF_CONFIGURE --enable-demuxer=rtsp --enable-demuxer=sdp --enable-demuxer=rtp"

# --- 6. 网络协议 ---
#     重要: ffmpeg 中不存在 rtsp 协议, RTSP 是 demuxer; 传输层由下列协议承担
FF_CONFIGURE="$FF_CONFIGURE --disable-protocols"
FF_CONFIGURE="$FF_CONFIGURE --enable-protocol=file --enable-protocol=data"
FF_CONFIGURE="$FF_CONFIGURE --enable-protocol=tcp  --enable-protocol=udp"
FF_CONFIGURE="$FF_CONFIGURE --enable-protocol=rtp  --enable-protocol=srtp"
FF_CONFIGURE="$FF_CONFIGURE --enable-protocol=http --enable-protocol=https"
FF_CONFIGURE="$FF_CONFIGURE --enable-protocol=tls  --enable-protocol=crypto"

# --- 7. 滤镜: ffplay 运行所必需的最小集合 ---
#     buffer/buffersink/abuffer/abuffersink 无需(也无法)显式启用:
#       libavfilter/Makefile 的无条件 OBJS 里含 buffersrc.o/buffersink.o,
#       且 allfilters.c 中它们写作 "extern  const"(双空格), 被 find_filters_extern 的
#       单空格 sed 规则排除在 FILTER_LIST 之外 —— 即永远内建、不可配置。
#     scale / aresample 是 libavfilter 格式协商失败时自动插入的转换滤镜(formats.c
#       conversion_filter), 必须保留, 否则 ffplay 建图直接失败。
#     hwupload/hwdownload/hwmap/scale_vulkan 用于 Vulkan 硬件加速链路。
#     crop/transpose/hflip/vflip/rotate 由 ffplay_select 强制拉入, 已通过在 build.sh
#       克隆 ffmpeg 后 sed 掉 ffplay_select 对应项 + 此处 --disable-filter 彻底移除。
FF_CONFIGURE="$FF_CONFIGURE --disable-filters"
FF_CONFIGURE="$FF_CONFIGURE --enable-filter=scale   --enable-filter=aresample"
FF_CONFIGURE="$FF_CONFIGURE --enable-filter=format  --enable-filter=aformat"
FF_CONFIGURE="$FF_CONFIGURE --enable-filter=null    --enable-filter=anull"
FF_CONFIGURE="$FF_CONFIGURE --enable-filter=hwupload --enable-filter=hwdownload --enable-filter=hwmap"
FF_CONFIGURE="$FF_CONFIGURE --enable-filter=scale_vulkan"

# --- 8. WebRTC / WHEP (libdatachannel) ---
#     上面的 --disable-muxers/--disable-demuxers/--disable-protocols 会把
#     whep_demuxer / whep_protocol 一并关掉, 这里显式重新打开,
#     否则 libdatachannel 编进去了却用不上(目标: 只支持播放 WebRTC + RTSP)。
#     WHIP Muxer(推流)按需求移除, 仅保留 WHEP 播放能力。
FF_CONFIGURE="$FF_CONFIGURE --enable-demuxer=whep"
FF_CONFIGURE="$FF_CONFIGURE --enable-protocol=whep"

# --- 9. Vulkan 渲染器(ffplay -enable_vulkan -hwaccel vulkan) 需要 vulkan + libplacebo ---
FF_CONFIGURE="$FF_CONFIGURE --enable-vulkan"

# --- 10. 硬件后端覆盖项: 必须排在各 stage 的 --enable-* 之后才生效 ---
# 本项目只做 WHEP/RTSP 软解播放, 不需要任何非 Vulkan 硬件后端。
# 这些 flag 全部放进 FF_CONFIGURE_LATE, 由 generate.sh 在所有 stage 拼接完之后再追加,
# 保证 --disable-* 压过各依赖库 stage 自己 emit 的 --enable-* (last wins)。
#
# 涉及的上游坑(已绕过, 不再改源码):
#   * hwcontext_amf.c 的 amf_ctx 仅被 #if CONFIG_DXVA2||CONFIG_D3D11VA 保护,
#     d3d12va 分支也用到它 —— 直接 --disable-amf 即可让该文件不被编译, 与 d3d12va 无关;
#     本项目明确也不想要 d3d12va, 一并关掉。
#   * hwcontext_opencl.c 用 CONFIG_LIBMFX(而非 CONFIG_QSV)作守卫,
#     --enable-libvpl 使 CONFIG_LIBMFX=1 -> hwcontext_opencl.o 悬空引用
#     ff_qsv_get_surface_base_handle, 链接 ffplay 报 undefined reference —— 关掉 opencl/mfx/vpl。
FF_CONFIGURE_LATE="${FF_CONFIGURE_LATE:-}"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-avdevice"
#  AMD / 微软 Windows 后端
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-amf"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-d3d12va --disable-dxva2 --disable-d3d11va"
#  Linux/X11 后端
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-vaapi --disable-vdpau --disable-libdrm"
#  NVIDIA
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-cuda --disable-cuda-llvm --disable-cuda-nvcc"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-nvdec --disable-nvenc --disable-ffnvcodec"
#  OpenCL / Intel QSV
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-opencl --disable-libmfx --disable-libvpl"

# --- 11. 外部库精简: 本项目只做 WHEP/RTSP 软解播放, 下列库都用不到 ---
# 这些值原本由各依赖库 stage 的 ffbuild_configure emit 成 --enable-lib*,
# 统一放到 FF_CONFIGURE_LATE 末尾, 确保 --disable 压过 stage 的 --enable。
# (仅让 ffmpeg 不链接这些库; Docker stage 仍会编译它们, 不影响产物正确性)
# 编码器
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libaom --disable-libkvazaar --disable-librav1e --disable-libsvtav1"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libx264 --disable-libx265 --disable-libxvid --disable-libtwolame"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libmp3lame --disable-libopus --disable-libopenh264 --disable-liboapv --disable-libxavs2"
# 冷门解码 / 封装 / 网络
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libaribb24 --disable-libaribcaption --disable-liblcevc-dec"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libdavs2 --disable-libuavs3d --disable-libtheora --disable-libvpx"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libjxl --disable-libwebp --disable-libopenjpeg --disable-libopenmpt --disable-libgme"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libdvdread --disable-libdvdnav --disable-libbluray --disable-libssh"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-librist --disable-libsrt --disable-avisynth --disable-chromaprint"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-frei0r --disable-lv2 --disable-libzmq --disable-libvorbis"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libsnappy --disable-libvidstab --disable-libvvenc --disable-libzimg --disable-libzvbi"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libopencore-amrnb --disable-libopencore-amrwb"
# 质量 / 工具 / 字幕栈
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libvmaf --disable-libxml2 --disable-lzma --disable-gmp --disable-librubberband"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-libsoxr"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-fontconfig --disable-libharfbuzz --disable-libfreetype --disable-libfribidi --disable-libass"

# --- 11b. 播放器用不到的音频/编码后端 ---
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-openal --disable-iconv"

# --- 12. 文档 / 调试 / 运行时 CPU 探测(进一步瘦身) ---
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-doc --disable-htmlpages --disable-manpages --disable-podpages"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-runtime-cpudetect --disable-debug"

# --- 13. 解析器精简: 只保留直播常见编码所需的 parser ---
#     --disable-parsers 关掉全部, 再只打开需要的; 这些是与解码器一一对应的帧边界解析器。
#     (mjpeg/mpeg4video/vp8 的 parser 随对应解码器一并移除)
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --disable-parsers"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --enable-parser=h264 --enable-parser=hevc"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --enable-parser=vp9"
FF_CONFIGURE_LATE="$FF_CONFIGURE_LATE --enable-parser=aac --enable-parser=opus"

# --- 14. 编译参数优化(减小体积) ---
# 通过 FFBUILD_*_EXTRA 交给 generate.sh 追加进 FF_CFLAGS/FF_CXXFLAGS/FF_LDFLAGS。
# 不能写进 FF_CONFIGURE 的 --extra-cflags: build.sh 在 FF_CONFIGURE 之后又追加了
# --extra-cflags="$FF_CFLAGS" 且后者覆盖前者, 写进去会被丢掉(并冲掉 -DRTC_STATIC)。
#   * --enable-small (configure 层)         : 尺寸优先的代码生成
#   * -ffunction-sections -fdata-sections -Os -fno-ident -fno-asynchronous-unwind-tables : 把函数/数据拆成独立段, 供链接器垃圾回收
#   *                                  : 链接期优化, 跨模块彻底剔除未引用代码
#   * -Wl,--gc-sections                     : 链接时删除未引用的段(死代码消除)
#   * -s                                    : 链接产物去符号表
FFBUILD_CFLAGS_EXTRA="${FFBUILD_CFLAGS_EXTRA:-} -ffunction-sections -fdata-sections -Os -fno-ident -fno-asynchronous-unwind-tables "
FFBUILD_CXXFLAGS_EXTRA="${FFBUILD_CXXFLAGS_EXTRA:-} -ffunction-sections -fdata-sections -Os -fno-ident -fno-asynchronous-unwind-tables "
FFBUILD_LDFLAGS_EXTRA="${FFBUILD_LDFLAGS_EXTRA:-} -Wl,--gc-sections -s -Wl,--as-needed "
