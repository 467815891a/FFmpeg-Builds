#!/bin/bash
set -e
shopt -s globstar
cd "$(dirname "$0")"
source util/vars.sh

export LC_ALL=C.UTF-8

ffbuild_addin_skips() {
    # return 0 if $1 (stage basename) is excluded for the current addin
    case " ${FFBUILD_EXCLUDE_STAGES:-} " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

ffbuild_guard() {
    # override ffbuild_enabled for addin-excluded stages (subshell-local)
    if ffbuild_addin_skips "$(basename "$SELF" | sed 's/.sh$//')"; then
        ffbuild_enabled() { return -1; }
    fi
}

rm -f Dockerfile Dockerfile.{dl,final,dl.final}

layername() {
    printf "layer-"
    basename "$1" | sed 's/.sh$//'
}

resolvestage() {
    [[ -d "$1" ]] && local SCRIPTDIR=("$1") || local SCRIPTDIR=(scripts.d/??-"$1")
    if [[ -d "${SCRIPTDIR[0]}" ]]; then
        echo scripts.d/??-"${1}"
    else
        echo scripts.d/??-"${1}.sh"
    fi
}

resolvescript() {
    local STAGE="$(resolvestage "$1")"
    if [[ -d "$STAGE" ]]; then
        ls -1 "$STAGE"/*.sh | tail -n 1
    else
        echo "$STAGE"
    fi
}

to_df() {
    local _of="${TODF:-Dockerfile}"
    printf "$@" >> "$_of"
    echo >> "$_of"
}

###
### Generate main Dockerfile
###

exec_dockerstage() {
    SCRIPT="$1"
    (
        SELF="$SCRIPT"
        STAGENAME="$(basename "$SCRIPT" | sed 's/.sh$//')"
        source util/dl_functions.sh
        source "$SCRIPT"

        ffbuild_guard

        ffbuild_enabled || exit 0

        to_df "ENV SELF=\"$SELF\" STAGENAME=\"$STAGENAME\""

        STG="$(ffbuild_dockerdl)"
        if [[ -n "$STG" ]]; then
            HASH="$(sha256sum <<<"$STG" | cut -d" " -f1)"
            export SELFCACHE=".cache/downloads/${STAGENAME}_${HASH}.tar.xz"
        fi

        ffbuild_dockerstage || exit $?
    )
}

get_stagedeps() {
    [[ -d "$1" ]] && local SCRIPTDIR=("$1") || local SCRIPTDIR=(scripts.d/??-"$1")
    if [[ -d "${SCRIPTDIR[0]}" ]]; then
        RESDEPS=()
        for SUBSCRIPT in "${SCRIPTDIR[0]}"/*.sh; do
            RESDEPS+=( $(get_stagedeps "${SUBSCRIPT}") )
        done
        tr ' ' '\n' <<< "${RESDEPS[@]}" | sort -u
    else
        [[ -f "$1" ]] && SCRIPT=("$1") || SCRIPT=(scripts.d/??-"${1}.sh")
        SCRIPT="${SCRIPT[0]}"
        (
            SELF="$SCRIPT"
            STAGENAME="$(basename "$SCRIPT" | sed 's/.sh$//')"
            source util/dl_functions.sh
            source "$SCRIPT"

            ffbuild_guard

            ffbuild_enabled || exit 0
            ffbuild_depends
        )
    fi
}

get_stagedeps_recursive_internal() {
    local CDEPS=($(get_stagedeps "$1"))
    for CDEP in "${CDEPS[@]}"; do
        get_stagedeps_recursive_internal "$CDEP"
    done
    printf '%s\n' "${CDEPS[@]}"
}

get_stagedeps_recursive() {
    declare -A ALREADY_PRINTED
    for CDEP in $(get_stagedeps_recursive_internal "$1"); do
        if ! [[ -v ALREADY_PRINTED["$CDEP"] ]]; then
            echo "$CDEP"
            ALREADY_PRINTED["$CDEP"]="1"
        fi
    done
}

get_filled_deps() {
    local CUR_DEPS=($(get_stagedeps "$1"))
    local UNFILLED_DEPS=()
    for DEP in "${CUR_DEPS[@]}"; do
        [[ -v FILLED_DEPS["$DEP"] ]] || UNFILLED_DEPS+=("$DEP")
    done
    if [[ "${#UNFILLED_DEPS[@]}" -eq 0 ]]; then
        echo "$1"
    else
        for DEP in "${UNFILLED_DEPS[@]}"; do
            get_filled_deps "$DEP" | sort -u
        done
    fi
}

get_output() {
    (
        SELF="$1"
        source "$1"
        ffbuild_guard
        if ffbuild_enabled; then
            ffbuild_$2 || exit 0
        else
            ffbuild_un$2 || exit 0
        fi
    )
}

export TODF="Dockerfile"

BASELAYER="base-layer"
to_df "FROM ${REGISTRY}/${REPO}/base-${TARGET}:latest${DOCKER_TAG_SUFFIX:-} AS ${BASELAYER}"
to_df "ENV TARGET=$TARGET VARIANT=$VARIANT REPO=$REPO ADDINS_STR=$ADDINS_STR FFVER=$(ffbuild_ffver)"
to_df "COPY --link util/run_stage.sh /usr/bin/run_stage"

for addin in "${ADDINS[@]}"; do
(
    source addins/"${addin}.sh"
    type ffbuild_dockeraddin &>/dev/null && ffbuild_dockeraddin || true
)
done

ENTRYSCRIPT="$(ls -1d scripts.d/* | tail -n 1)"
declare -A FILLED_DEPS
while true; do
    CURDEPS=($(get_filled_deps "$ENTRYSCRIPT" | sort -u))
    if [[ "${CURDEPS[@]}" == "$ENTRYSCRIPT" ]]; then
        break
    fi
    for CURDEP in "${CURDEPS[@]}"; do
        FILLED_DEPS["$CURDEP"]="1"

        SCRIPT="$(resolvescript "$CURDEP")"
        (
            SELF="$SCRIPT"
            source "$SCRIPT"
            ffbuild_guard
            ffbuild_enabled || exit $?
            to_df "FROM ${BASELAYER} AS ${CURDEP}"
        ) || continue

        for SUBDEP in $(get_stagedeps_recursive "${CURDEP}"); do
            SCRIPT="$(resolvescript "$SUBDEP")"
            (
                SELF="$SCRIPT"
                SELFLAYER="$SUBDEP"
                source "$SCRIPT"
                ffbuild_guard
                ffbuild_enabled || exit 0
                ffbuild_dockerlayer || exit $?
            )
        done

        STAGE="$(resolvestage "$CURDEP")"
        if [[ -d "$STAGE" ]]; then
            for STAGE in "${STAGE}"/??-*.sh; do
                exec_dockerstage "$STAGE"
            done
        else
            exec_dockerstage "$STAGE"
        fi
    done
done

source "variants/${TARGET}-${VARIANT}.sh"

for addin in ${ADDINS[*]}; do
    source "addins/${addin}.sh"
done

COMBINELAYER="combine-layer"
to_df "FROM ${BASELAYER} AS ${COMBINELAYER}"
for SUBDEP in $(get_stagedeps_recursive "${ENTRYSCRIPT}"); do
    STAGE="$(resolvestage "$SUBDEP")"
    [[ -d "$STAGE" ]] && SCRIPTS=("${STAGE}"/??-*.sh) || SCRIPTS=("${STAGE}")

    SCRIPT="${SCRIPTS[-1]}"
    (
        SELF="$SCRIPT"
        COMBINING="1"
        SELFLAYER="$SUBDEP"
        source "$SCRIPT"
        ffbuild_guard
        ffbuild_enabled || exit 0
        ffbuild_dockerlayer || exit $?
        TODF="Dockerfile.final" PREVLAYER="$COMBINELAYER" \
            ffbuild_dockerfinal || exit $?
    )

    for SCRIPT in "${SCRIPTS[@]}"; do
        FF_CONFIGURE+=" $(get_output "$SCRIPT" configure)"
        FF_CFLAGS+=" $(get_output "$SCRIPT" cflags)"
        FF_CXXFLAGS+=" $(get_output "$SCRIPT" cxxflags)"
        FF_LDFLAGS+=" $(get_output "$SCRIPT" ldflags)"
        FF_LDEXEFLAGS+=" $(get_output "$SCRIPT" ldexeflags)"
        FF_LIBS+=" $(get_output "$SCRIPT" libs)"
    done
done

to_df "FROM ${BASELAYER}"
sort -u < Dockerfile.final >> Dockerfile
rm Dockerfile.final

# Addins are sourced before the per-stage ffbuild_configure output is
# appended, so an addin's --disable-foo loses to a stage's --enable-foo.
# FF_CONFIGURE_LATE is appended last, giving addins the final word.
FF_CONFIGURE+=" ${FF_CONFIGURE_LATE:-}"
# Size-optimization flags contributed by an addin (e.g. the "live" addin sets
# FFBUILD_CFLAGS_EXTRA / FFBUILD_CXXFLAGS_EXTRA / FFBUILD_LDFLAGS_EXTRA). They are
# appended here, AFTER the per-stage ffbuild_cflags/ffbuild_ldflags output has
# been assembled into FF_CFLAGS/FF_CXXFLAGS/FF_LDFLAGS, so they are not lost to
# build.sh's trailing --extra-cflags="$FF_CFLAGS" (which overrides any
# --extra-cflags present inside FF_CONFIGURE, risking -DRTC_STATIC being dropped).
FF_CFLAGS+=" ${FFBUILD_CFLAGS_EXTRA:-}"
FF_CXXFLAGS+=" ${FFBUILD_CXXFLAGS_EXTRA:-}"
FF_LDFLAGS+=" ${FFBUILD_LDFLAGS_EXTRA:-}"

# Collapse bare --enable-X/--disable-X toggles so the final FF_CONFIGURE has
# no contradictory duplicate (last occurrence wins). '=...' variants are left
# untouched, so e.g. --enable-decoder=h264 and --disable-decoders stay distinct.
_collapsed=()
for _tok in $FF_CONFIGURE; do
    if [[ $_tok =~ ^--(enable|disable)-([A-Za-z0-9_-]+)$ ]]; then
        _name="${BASH_REMATCH[2]}"
        _tmp=()
        for _t in "${_collapsed[@]}"; do
            [[ $_t =~ ^--(enable|disable)-${_name}$ ]] && continue
            _tmp+=("$_t")
        done
        _collapsed=("${_tmp[@]}" "$_tok")
    else
        _collapsed+=("$_tok")
    fi
done
FF_CONFIGURE="${_collapsed[*]}"

FF_CONFIGURE="$(xargs <<< "$FF_CONFIGURE")"
FF_CFLAGS="$(xargs <<< "$FF_CFLAGS")"
FF_CXXFLAGS="$(xargs <<< "$FF_CXXFLAGS")"
FF_LDFLAGS="$(xargs <<< "$FF_LDFLAGS")"
FF_LDEXEFLAGS="$(xargs <<< "$FF_LDEXEFLAGS")"
FF_LIBS="$(xargs <<< "$FF_LIBS")"

to_df "ENV \\"
to_df "    FF_CONFIGURE=\"$FF_CONFIGURE\" \\"
to_df "    FF_CFLAGS=\"$FF_CFLAGS\" \\"
to_df "    FF_CXXFLAGS=\"$FF_CXXFLAGS\" \\"
to_df "    FF_LDFLAGS=\"$FF_LDFLAGS\" \\"
to_df "    FF_LDEXEFLAGS=\"$FF_LDEXEFLAGS\" \\"
to_df "    FF_LIBS=\"$FF_LIBS\""
