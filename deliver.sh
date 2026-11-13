#!/bin/bash
# Build the delivery package for the client.
#
#   studio deliver [--masters] [--mixes] [--stems] [--demos] [--songs] [--all]
#                  [--no-mp3] [--no-zip] [PROJECT]
#
# You can deliver any combination: masters, mixes, stems … Without options it
# asks, and you type one or more numbers ("1 2", "1;3", a = all).
#
# Masters / mixes / demos / songs: the FINAL version of every song (approved
# version, otherwise the highest _v## – see "studio approve"), as WAV + MP3.
# Stems: the final version of every stem, folders kept as they are, WAV only.
#
# One part:                                Several parts:
#   2026-11-13_NIGHT_Title_Masters/          2026-11-13_NIGHT_Title_Masters_Mixes_Stems/
#   ├── WAV/                                 ├── Masters/WAV/  Masters/MP3/
#   ├── MP3/                                 ├── Mixes/WAV/    Mixes/MP3/
#   └── Tracklist.txt                        ├── Stems/…
#   + .zip                                   └── Tracklist.txt          + .zip

source "$(dirname "$0")/_common.sh"

# label:folder – in the order they are offered
PARTS="Masters:05_Masters Mixes:03_Mixes Stems:04_Stems Songs:05_Songs Demos:03_Demos"

WANT=""; ALL=0; MP3=1; ZIP=1
while [ $# -gt 0 ]; do
    case "$1" in
        --masters) WANT="$WANT Masters"; shift ;;
        --mixes)   WANT="$WANT Mixes";   shift ;;
        --stems)   WANT="$WANT Stems";   shift ;;
        --songs)   WANT="$WANT Songs";   shift ;;
        --demos)   WANT="$WANT Demos";   shift ;;
        --all)     ALL=1; shift ;;
        --no-mp3)  MP3=0; shift ;;
        --no-zip)  ZIP=0; shift ;;
        --*)       die "Unknown option $1" ;;
        *)         break ;;
    esac
done

PROJECT="$(resolve_project "$1")" || exit 1
echo "Project: $(basename "$PROJECT")"

part_folder() { local p; for p in $PARTS; do [ "${p%%:*}" = "$1" ] && echo "${p#*:}"; done; }
has_audio() {
    [ -d "$1" ] && [ -n "$(find "$1" -type f \( -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' -o -iname '*.flac' \) \
                            -not -path '*/MP3/*' -print -quit)" ]
}

# --- What is there, and what to deliver? ------------------------------------------
found=()
for p in $PARTS; do has_audio "$PROJECT/${p#*:}" && found+=("${p%%:*}"); done
[ ${#found[@]} -gt 0 ] || die "No mixes, masters or stems found in this project yet."

chosen=()
if [ $ALL -eq 1 ]; then
    chosen=("${found[@]}")
elif [ -n "$WANT" ]; then
    for w in $WANT; do
        case " ${found[*]} " in *" $w "*) ;; *) die "No audio files in $(part_folder "$w") ($w)." ;; esac
    done
    # always the same order: Masters, Mixes, Stems …
    for w in "${found[@]}"; do
        case " $WANT " in *" $w "*) chosen+=("$w") ;; esac
    done
elif [ ${#found[@]} -eq 1 ] || [ ! -t 0 ]; then
    chosen=("${found[0]}")
else
    choose_many "What to deliver?" 1 "${found[@]}"
    for n in $(printf '%s\n' "${CHOICES[@]}" | sort -n); do chosen+=("${found[$((n - 1))]}"); done
fi

# final files of one part
part_files() {
    pick_finals "$PROJECT/$(part_folder "$1")" | while IFS= read -r f; do
        case "$(echo "${f##*.}" | tr '[:upper:]' '[:lower:]')" in wav|aif|aiff|flac) ;; *) continue ;; esac
        case "$f" in */MP3/*) continue ;; esac
        echo "$f"
    done
}

echo
for part in "${chosen[@]}"; do
    src="$PROJECT/$(part_folder "$part")"
    echo "$part:"
    part_files "$part" | while IFS= read -r f; do echo "    ${f#"$src"/}"; done
done
if [ -t 0 ]; then
    echo
    read -r -p "Build the package? [Y/n]  (wrong version? -> n, then: studio approve) " a
    case "$a" in n|N|no|nein) echo "Cancelled – nothing created."; exit 0 ;; esac
fi

ARTIST="$(log_field "$PROJECT" ARTIST)"; ALBUM="$(log_field "$PROJECT" TITLE)"; CODE="$(log_field "$PROJECT" CODE)"
NAME="$(date +%Y-%m-%d)_${CODE:+${CODE}_}$(sanitize "$ALBUM")_$(IFS=_; echo "${chosen[*]}")"
OUT_ROOT="$PROJECT/06_Deliverables"
mkdir -p "$OUT_ROOT"
[ -e "$OUT_ROOT/$NAME" ] && NAME="${NAME}_$(date +%H%M)"
PKG="$OUT_ROOT/$NAME"
mkdir -p "$PKG"

if [ $MP3 -eq 1 ] && ! find_tool ffmpeg >/dev/null && ! find_tool lame >/dev/null; then
    echo "  ⚠️  No MP3 encoder (brew install lame) – package is built without MP3s."
    MP3=0
fi

# --- Copy, convert, tracklist -----------------------------------------------------
LIST="$PKG/Tracklist.txt"
{
    echo "$ARTIST – $ALBUM"
    echo "$(IFS=,; echo "${chosen[*]}" | sed 's/,/ + /g') · delivered $(date +%Y-%m-%d)"
} > "$LIST"

echo
files_total=0
for part in "${chosen[@]}"; do
    src="$PROJECT/$(part_folder "$part")"
    # one part: WAV/ MP3/ directly in the package – several parts: one folder each
    if [ ${#chosen[@]} -eq 1 ]; then base="$PKG"; else base="$PKG/$part"; fi
    if [ "$part" = "Stems" ]; then wavdir="$base"; [ ${#chosen[@]} -eq 1 ] && wavdir="$PKG/Stems"; else wavdir="$base/WAV"; fi

    { echo; echo "$part"; printf '%-3s %-58s %8s   %s\n' "#" "FILE" "LENGTH" "FORMAT"; } >> "$LIST"
    echo "$part"
    n=0; total=0
    while IFS= read -r f; do
        n=$((n + 1))
        rel="${f#"$src"/}"; b="$(basename "$f")"
        mkdir -p "$wavdir/$(dirname "$rel")"
        cp -p "$f" "$wavdir/$rel" || die "Could not copy $rel"
        IFS=$'\t' read -r ch rate bits dur <<< "$(audio_info "$f")"
        total="$(awk -v a="$total" -v b="${dur:-0}" 'BEGIN { print a + b }')"
        printf '%-3s %-58s %8s   %s Hz / %s bit / %s\n' "$n" "$rel" "$(fmt_time "${dur:-0}")" "$rate" "$bits" \
            "$([ "$ch" = 1 ] && echo mono || echo stereo)" >> "$LIST"
        if [ $MP3 -eq 1 ] && [ "$part" != "Stems" ]; then
            nice_title "${b%.*}" "$CODE"
            mkdir -p "$base/MP3/$(dirname "$rel")"
            encode_mp3 "$f" "$base/MP3/${rel%.*}.mp3" "$TRACK_TITLE" "$ARTIST" "$ALBUM" "$TRACK_NO" \
                || echo "  ⚠️  MP3 failed for $b"
        fi
        echo "  ✅ $rel"
    done < <(part_files "$part")
    echo "    $n file(s), $(fmt_time "$total")" >> "$LIST"
    files_total=$((files_total + n))
done

# --- Zip ----------------------------------------------------------------------------
if [ $ZIP -eq 1 ]; then
    (cd "$OUT_ROOT" && zip -rqX "$NAME.zip" "$NAME" -x '*.DS_Store') \
        && echo "  ✅ $NAME.zip ($(du -h "$OUT_ROOT/$NAME.zip" | cut -f1 | tr -d ' '))"
fi

echo "$(date +%Y-%m-%d)  Delivery package built: $NAME ($files_total files)" >> "$PROJECT/00_Admin/Session_Log.txt"
log "Delivery package $NAME ($files_total files) in $(basename "$PROJECT")"
echo
echo "Package: ${PKG#"$STUDIO_ROOT"/}"
[ -z "$NO_OPEN" ] && open "$OUT_ROOT" 2>/dev/null || true
