#!/bin/bash

package_variant() {
    IN="$1"
    OUT="$2"

    pkg_copy "$IN/bin/*.{exe,dll}" "$OUT/bin"

    pkg_copy "$IN/bin/*.lib" "$OUT/lib"
    pkg_copy "$IN/lib/*.{def,dll.a}" "$OUT/lib"

    pkg_copy -a "$IN/lib/pkgconfig/*.pc" "$OUT/lib/pkgconfig"
    if compgen -G "$OUT"/lib/pkgconfig/*.pc >/dev/null; then
        sed -i \
            -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
            -e 's|/ffbuild/prefix|${prefix}|' \
            -e '/Libs.private:/d' \
            "$OUT"/lib/pkgconfig/*.pc
    fi

    pkg_copy -r "$IN/include/*" "$OUT/include"

    pkg_copy "$IN/share/doc/ffmpeg/*" "$OUT/doc"

    pkg_copy "$IN/share/ffmpeg/*.ffpreset" "$OUT/presets"
}
