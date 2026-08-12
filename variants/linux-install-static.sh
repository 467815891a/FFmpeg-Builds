#!/bin/bash

package_variant() {
    IN="$1"
    OUT="$2"

    pkg_copy "$IN/bin/*" "$OUT/bin"

    pkg_copy "$IN/share/doc/ffmpeg/*" "$OUT/doc"

    pkg_copy "$IN/share/man/*" "$OUT/man"

    pkg_copy "$IN/share/ffmpeg/*.ffpreset" "$OUT/presets"
}
