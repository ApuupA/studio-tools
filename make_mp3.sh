#!/bin/bash
# MP3 copies of your bounces (client previews).
#
#   studio mp3 [PROJECT]            final version of every mix / demo / master of the project
#   studio mp3 --all [PROJECT]      every version, not only the final ones
#   studio mp3 file.wav [more …]    just these files (MP3 lands next to each file)
#
# For a project the MP3s go into an "MP3" subfolder next to the WAVs:
#   03_Mixes/NIGHT_01_Song_Mix_v03.wav  ->  03_Mixes/MP3/NIGHT_01_Song_Mix_v03.mp3
# Files that already have an up-to-date MP3 are skipped.
# Bitrate: MP3_BITRATE in studio.conf. Needs ffmpeg or lame (brew install lame).

source "$(dirname "$0")/_common.sh"

MODE=""
[ "$1" = "--all" ] && { MODE="all"; shift; }

if ! find_tool ffmpeg >/dev/null && ! find_tool lame >/dev/null; then
    die "No MP3 encoder found. Install one once with:  brew install lame   (macOS itself cannot write MP3s)"
fi

made=0; skipped=0; failed=0

# convert <source> <target.mp3> <artist> <album> <code>
convert() {
    local src="$1" dst="$2"
    if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then skipped=$((skipped + 1)); return; fi
    nice_title "$(basename "${src%.*}")" "$5"
    mkdir -p "$(dirname "$dst")"
    if encode_mp3 "$src" "$dst" "$TRACK_TITLE" "$3" "$4" "$TRACK_NO"; then
        echo "  ✅ $(basename "$dst")"
        made=$((made + 1))
    else
        echo "  ❌ $(basename "$src") – could not be converted"
        rm -f "$dst"
        failed=$((failed + 1))
    fi
}

if [ -n "$1" ] && [ -f "$1" ]; then
    # --- single files -----------------------------------------------------------
    for f in "$@"; do
        [ -f "$f" ] || { echo "  ❌ not a file: $f"; failed=$((failed + 1)); continue; }
        convert "$f" "${f%.*}.mp3" "" "" ""
    done
else
    # --- a project ----------------------------------------------------------------
    PROJECT="$(resolve_project "$1")" || exit 1
    echo "Project: $(basename "$PROJECT")"
    ARTIST="$(log_field "$PROJECT" ARTIST)"; ALBUM="$(log_field "$PROJECT" TITLE)"; CODE="$(log_field "$PROJECT" CODE)"
    for folder in $BOUNCE_FOLDERS; do
        [ -d "$PROJECT/$folder" ] || continue
        while IFS= read -r f; do
            case "$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')" in wav|aif|aiff|flac) ;; *) continue ;; esac
            case "$f" in */MP3/*) continue ;; esac
            convert "$f" "$(dirname "$f")/MP3/$(basename "${f%.*}").mp3" "$ARTIST" "$ALBUM" "$CODE"
        done < <(pick_finals "$PROJECT/$folder" $MODE)
    done
fi

echo
echo "$made MP3(s) created, $skipped already up to date${failed:+, $failed failed}." | sed 's/, 0 failed//'
[ $failed -eq 0 ]
