#!/bin/bash
# Shared helpers for the studio scripts. Sourced, not run directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Settings: studio.conf holds the defaults (tracked in git). Your own values go
# into studio.local.conf next to it (not tracked – "studio init" creates it).
# shellcheck source=studio.conf
source "$SCRIPT_DIR/studio.conf"
[ -f "$SCRIPT_DIR/studio.local.conf" ] && source "$SCRIPT_DIR/studio.local.conf"

# Environment variables override the config (used for testing).
STUDIO_ROOT="${STUDIO_ROOT_OVERRIDE:-$STUDIO_ROOT}"
ARCHIVE_VOLUME="${ARCHIVE_VOLUME_OVERRIDE:-$ARCHIVE_VOLUME}"

# No STUDIO_ROOT set: the tools may sit inside the Studio folder (Studio/99_SYSTEM/Scripts)
if [ -z "$STUDIO_ROOT" ]; then
    _cand="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)"
    [ "$(basename "$(dirname "$SCRIPT_DIR")")" = "99_SYSTEM" ] && [ -d "$_cand/01_PROJECTS" ] && STUDIO_ROOT="$_cand"
fi

if [ -n "$STUDIO_ROOT" ] && [ -d "$STUDIO_ROOT" ]; then
    LOG_DIR="$STUDIO_ROOT/99_SYSTEM/Logs"
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/studio_$(date +%Y-%m).log"
elif [ -n "$STUDIO_NO_ROOT_OK" ]; then
    LOG_DIR=""; LOG_FILE="/dev/null"            # only "studio init" and "studio help" run without a Studio folder
else
    echo "No Studio folder is set up yet${STUDIO_ROOT:+ (not found: $STUDIO_ROOT)}." >&2
    echo "Create one with:   $SCRIPT_DIR/studio init" >&2
    exit 1
fi

log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S')  [$(basename "$0")]  $*"
    echo "$msg" >&2
    echo "$msg" >> "$LOG_FILE"
}

notify() {
    # macOS notification; silently ignored if not possible.
    local title="$1" text="$2"
    /usr/bin/osascript -e "display notification \"${text//\"/\'}\" with title \"${title//\"/\'}\"" >/dev/null 2>&1 || true
}

die() {
    log "ERROR: $*"
    notify "Studio – Error" "$*"
    exit 1
}

# Turn "Müller & Söhne / Live!" into "Mueller_Soehne_Live"
sanitize() {
    echo "$1" \
        | sed -e 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/Ä/Ae/g; s/Ö/Oe/g; s/Ü/Ue/g; s/ß/ss/g' \
        | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
        | sed -e 's/[^A-Za-z0-9_-]/_/g; s/__*/_/g; s/^_//; s/_$//'
}

volume_mounted() {
    [ -d "$1" ] && [ -w "$1" ]
}

daw_running() {
    pgrep -i "$DAW_APPS" >/dev/null 2>&1
}

# --- Session templates -------------------------------------------------------

TEMPLATE_DIR="$STUDIO_ROOT/03_LIBRARY/Templates"

# Short artist code for file names: "Nightfall" -> "NIGHT"
make_code() {
    sanitize "$1" | tr -d '_-' | cut -c1-5 | tr '[:lower:]' '[:upper:]'
}

folder_is_empty() {
    [ -z "$(find "$1" -mindepth 1 -not -name .DS_Store -print -quit 2>/dev/null)" ]
}

# copy_template <PT|CB> <template-name> <target-folder> <new-session-name>
# Copies the template session into an EMPTY folder and renames the session file.
copy_template() {
    local kind="$1" tpl="$2" target="$3" newname="$4" sub ext
    case "$kind" in
        PT) sub="ProTools"; ext="ptx" ;;
        CB) sub="Cubase";   ext="cpr" ;;
    esac
    local src="$TEMPLATE_DIR/$sub/$tpl"

    if [ ! -d "$src" ]; then
        # warn once per template, not for every song
        case " $WARNED_TEMPLATES " in *" $sub/$tpl "*) ;; *)
            log "No $sub template '$tpl' in 03_LIBRARY/Templates/$sub – song folders stay empty."
            WARNED_TEMPLATES="$WARNED_TEMPLATES $sub/$tpl" ;;
        esac
        return 1
    fi
    folder_is_empty "$target" || { log "Skipped $(basename "$target"): not empty."; return 1; }

    local session
    session="$(find "$src" -maxdepth 1 -name "*.$ext" | head -1)"
    [ -n "$session" ] || { log "Template '$tpl' contains no .$ext file."; return 1; }

    rsync -a --exclude-from="$SCRIPT_DIR/backup_excludes.txt" \
        --exclude='Session File Backups/*' --exclude='Auto Saves/*' \
        "$src/" "$target/" || return 1
    mv "$target/$(basename "$session")" "$target/$newname.$ext"
    log "  $sub session: $(basename "$target")/$newname.$ext"
}

# fill_song_folders <project> <code> <pt-template> <cb-template> [pt-stage] [cb-stage]
# Puts a template session into every empty song folder (01_..89_).
# Stage is part of the file name: NIGHT_01_Song_TRK_v01 (empty stage: NIGHT_01_Song_v01).
fill_song_folders() {
    local project="$1" code="$2" pt="$3" cb="$4" pts="${5-TRK}" cbs="${6-}" d base num song
    for d in "$project"/02_Sessions/PT/[0-8][0-9]_*_PT "$project"/02_Sessions/CB/[0-8][0-9]_*_CB; do
        [ -d "$d" ] && folder_is_empty "$d" || continue
        base="$(basename "$d")"
        num="${base%%_*}"
        song="${base#*_}"; song="${song%_??}"
        case "$base" in
            *_PT) [ -n "$pt" ] && copy_template PT "$pt" "$d" "${code}_${num}_${song}${pts:+_$pts}_v01" ;;
            *_CB) [ -n "$cb" ] && copy_template CB "$cb" "$d" "${code}_${num}_${song}${cbs:+_$cbs}_v01" ;;
        esac
    done
}

# --- Project types -----------------------------------------------------------
#
#   type     folders (numbers stay the same in every type)          sessions
#   full     00 01 02 03_Mixes 04_Stems 05_Masters 06_Deliverables  one per song, PT: TRK
#   rec      00 01 02 03_Mixes 06_Deliverables                      one per song, TRK
#   mix      00 01 02 03_Mixes 04_Stems 06_Deliverables 07_Received one per song, MIX
#   write    00 01 02 03_Demos 04_Ideas 05_Songs                    one per song, Cubase
#   master   00 01 02 05_Masters 06_Deliverables 07_Received        ONE session for all songs
#
# set_project_type <type>  ->  TYPE_LABEL, TYPE_FOLDERS, PT_STAGE, CB_STAGE, TYPE_DAW
set_project_type() {
    case "$1" in
        full)   TYPE_LABEL="Full production"
                TYPE_FOLDERS="03_Mixes 04_Stems 05_Masters 06_Deliverables"
                PT_STAGE="TRK"; CB_STAGE="";    TYPE_DAW="$FILL_DAW" ;;
        rec)    TYPE_LABEL="Recording"
                TYPE_FOLDERS="03_Mixes 06_Deliverables"
                PT_STAGE="TRK"; CB_STAGE="TRK"; TYPE_DAW="pt" ;;
        mix)    TYPE_LABEL="Mixing"
                TYPE_FOLDERS="03_Mixes 04_Stems 06_Deliverables 07_Received"
                PT_STAGE="MIX"; CB_STAGE="MIX"; TYPE_DAW="pt" ;;
        write)  TYPE_LABEL="Songwriting"
                TYPE_FOLDERS="03_Demos 04_Ideas 05_Songs"
                PT_STAGE="";    CB_STAGE="";    TYPE_DAW="cb" ;;
        master) TYPE_LABEL="Mastering"
                TYPE_FOLDERS="05_Masters 06_Deliverables 07_Received"
                PT_STAGE="";    CB_STAGE="";    TYPE_DAW="pt" ;;
        *)      die "--type must be full, rec, mix, write or master (got '$1')" ;;
    esac
    # every type has these
    TYPE_FOLDERS="00_Admin 01_Reference 02_Sessions $TYPE_FOLDERS"
}

# All project folders (anything with 00_Admin/Session_Log.txt), newest activity first
list_projects() { list_projects_t | cut -f2-; }

# … the same with the time of the last activity in front: "<epoch><TAB><path>"
list_projects_t() {
    find "$STUDIO_ROOT/01_PROJECTS" "$STUDIO_ROOT/02_WRITING" -maxdepth 4 \
         -path '*/00_Admin/Session_Log.txt' 2>/dev/null \
    | while IFS= read -r f; do
        p="${f%/00_Admin/Session_Log.txt}"
        # last activity = newest session file or log entry
        t="$(find "$p" \( -name '*.ptx' -o -name '*.cpr' -o -name Session_Log.txt \) \
                -not -path '*/Session File Backups/*' -not -path '*/Auto Saves/*' \
                -exec stat -f %m {} + 2>/dev/null | sort -n | tail -1)"
        echo "${t:-0}	$p"
      done | sort -rn
}

# pick_project [search]: prints the path of a project.
#   search given + exactly one match  -> that project
#   otherwise (several / no search)   -> numbered list to choose from (newest first)
# Search is case-insensitive and matches any part of the path below the Studio
# folder, e.g. "night", "album", "demo", "2026-11".
pick_project() {
    local search="$1" p rel t matches=() i pick
    while IFS= read -r p; do
        rel="${p#"$STUDIO_ROOT"/}"
        if [ -n "$search" ] && ! echo "$rel" | tr '_' ' ' | grep -qiF -- "$(echo "$search" | tr '_' ' ')"; then
            continue
        fi
        matches+=("$p")
    done < <(list_projects)

    if [ ${#matches[@]} -eq 0 ]; then
        log "No project found${search:+ matching '$search'}."; return 1
    fi
    if [ -n "$search" ] && [ ${#matches[@]} -eq 1 ]; then
        echo "${matches[0]}"; return 0
    fi
    [ -t 0 ] || { log "'$search' matches ${#matches[@]} projects – be more specific."; return 1; }

    echo "Which project?" >&2
    i=1
    for p in "${matches[@]:0:20}"; do
        t="$(log_field "$p" TYPE | sed 's/^[a-z]* (\(.*\))$/\1/')"
        printf "  %2d) %s   [%s]\n" $i "$(basename "$p")" "${t:-Full production}" >&2
        i=$((i + 1))
    done
    read -r -p "> " pick
    if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -lt $i ]; then
        echo "${matches[$((pick - 1))]}"; return 0
    fi
    return 1
}

# resolve_project <path-or-search>: a real project folder is used as is,
# anything else goes through pick_project.
resolve_project() {
    if [ -n "$1" ] && [ -f "${1%/}/00_Admin/Session_Log.txt" ]; then
        (cd "${1%/}" && pwd)
    else
        pick_project "$1"
    fi
}

# Quit a running app gracefully by its process name (e.g. "Mail", "MSTeams")
quit_app() {
    local pid app bid
    pid="$(pgrep -x "$1" | head -1)"; [ -n "$pid" ] || return 1
    app="$(ps -o comm= -p "$pid" | sed -n 's|^\(.*\.app\)/Contents/.*|\1|p')"
    bid="$(defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null)"
    [ -n "$bid" ] || return 1
    osascript -e "tell application id \"$bid\" to quit" </dev/null >/dev/null 2>&1
}

# apply_daw <pt|cb|both>: sets USE_PT / USE_CB and clears the template of the
# DAW that is not used – only the chosen DAW gets folders and sessions.
apply_daw() {
    USE_PT=1; USE_CB=1
    case "$1" in
        pt)   CB=""; USE_CB=0 ;;
        cb)   PT=""; USE_PT=0 ;;
        both) ;;
        *)    die "--daw must be pt, cb or both (got '$1')" ;;
    esac
}

# make_song_folders <project> <NN_Song>: creates the song folder for each used DAW
make_song_folders() {
    [ $USE_PT -eq 1 ] && mkdir -p "$1/02_Sessions/PT/${2}_PT"
    [ $USE_CB -eq 1 ] && mkdir -p "$1/02_Sessions/CB/${2}_CB"
    return 0
}

# complete_song_folders <project>: songs that exist for one DAW also get a folder
# for the other DAW if it is used now (e.g. add_songs.sh --daw cb on a PT project)
complete_song_folders() {
    local d b
    for d in "$1"/02_Sessions/PT/[0-8][0-9]_*_PT "$1"/02_Sessions/CB/[0-8][0-9]_*_CB; do
        [ -d "$d" ] || continue
        b="$(basename "$d")"
        make_song_folders "$1" "${b%_??}"
    done
}

# Read a field ("CODE", "ARTIST" ...) from a project's Session_Log.txt
log_field() {
    sed -n "s/^$2: *//p" "$1/00_Admin/Session_Log.txt" 2>/dev/null | head -1
}

# --- Guided mode (questions in the Terminal) -----------------------------------

# choose "Question" <default-number> "Option 1" "Option 2" …   -> sets CHOICE (1-based)
# Enter = default. Short lists are shown on one line, long ones one per line.
choose() {
    local q="$1" def="$2" i=1 line="" o pick
    shift 2
    echo >&2
    echo "$q" >&2
    for o in "$@"; do line="$line  $i) $o"; i=$((i + 1)); done
    if [ ${#line} -le 76 ]; then
        echo "$line" >&2
    else
        i=1; for o in "$@"; do printf "  %d) %s\n" $i "$o" >&2; i=$((i + 1)); done
    fi
    while :; do
        read -r -p "> [Enter = $def] " pick || exit 1
        pick="${pick:-$def}"
        [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le $# ] && break
        echo "  Please type a number from 1 to $#." >&2
    done
    CHOICE=$pick
}

# choose_many "Question" <default> "Option 1" "Option 2" …   -> sets CHOICES (array of numbers)
# Several numbers can be typed in any way: "1 3", "1;3", "1,3", "1+3".  a = all.  Enter = default.
choose_many() {
    local q="$1" def="$2" i=1 line="" o pick n ok
    shift 2
    echo >&2
    echo "$q" >&2
    for o in "$@"; do line="$line  $i) $o"; i=$((i + 1)); done
    echo "$line" >&2
    while :; do
        read -r -p "> one or more numbers, a = all [Enter = $def] " pick || exit 1
        pick="${pick:-$def}"
        CHOICES=(); ok=1
        case "$pick" in
            a|A|all|alle) i=1; for o in "$@"; do CHOICES+=($i); i=$((i + 1)); done ;;
            *)  for n in $(echo "$pick" | tr ';,+/&' '     '); do
                    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le $# ]; then
                        case " ${CHOICES[*]} " in *" $n "*) ;; *) CHOICES+=("$n") ;; esac
                    else
                        ok=0
                    fi
                done ;;
        esac
        [ $ok -eq 1 ] && [ ${#CHOICES[@]} -gt 0 ] && break
        echo "  Please type numbers from 1 to $# (e.g. 1 2), or a for all." >&2
    done
}

# ask "Question" [default]   -> sets ANSWER (Enter = default / empty)
ask() {
    local q="$1" def="$2"
    echo >&2
    read -r -p "$q${def:+ [Enter = $def]}: " ANSWER || exit 1
    ANSWER="$(echo "${ANSWER:-$def}" | sed 's/^ *//; s/ *$//')"
}

# ask_required "Question"   -> sets ANSWER, repeats until something is typed
ask_required() {
    while :; do
        ask "$1"
        [ -n "$ANSWER" ] && break
        echo "  This one is needed." >&2
    done
}

# split_songs "Song 1; Song 2"  -> sets SONGS array.
# Separator is ";" – if there is none, commas are used instead.
split_songs() {
    local line="$1" sep=';' parts s
    SONGS=()
    case "$line" in *\;*) ;; *) sep=',' ;; esac
    IFS="$sep" read -r -a parts <<< "$line"
    for s in "${parts[@]}"; do
        s="$(echo "$s" | sed 's/^ *//; s/ *$//')"
        [ -n "$s" ] && SONGS+=("$s")
    done
}

# list_templates <pt|cb>: template folder names, one per line
list_templates() {
    local sub="ProTools"; [ "$1" = "cb" ] && sub="Cubase"
    find "$TEMPLATE_DIR/$sub" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|.*/||' | sort
}

# choose_template <pt|cb> <current-default>  -> sets ANSWER to the template name.
# No question if there is no template, or only one.
choose_template() {
    local kind="$1" def="$2" label="Pro Tools" names=() n i defnum=1
    [ "$kind" = "cb" ] && label="Cubase"
    while IFS= read -r n; do names+=("$n"); done < <(list_templates "$kind")
    ANSWER="$def"
    if [ ${#names[@]} -eq 0 ]; then
        echo >&2
        echo "No $label template yet – song folders will be created empty." >&2
        return
    fi
    if [ ${#names[@]} -eq 1 ]; then
        ANSWER="${names[0]}"
        echo >&2
        echo "$label template: $ANSWER (the only one)" >&2
        return
    fi
    i=1; for n in "${names[@]}"; do [ "$n" = "$def" ] && defnum=$i; i=$((i + 1)); done
    choose "Which $label template?" $defnum "${names[@]}"
    ANSWER="${names[$((CHOICE - 1))]}"
}

# --- Finder tags ---------------------------------------------------------------
# One coloured Finder tag per project type, so the type is visible at a glance.
#   Full production = red · Recording = orange · Mixing = blue
#   Mastering = purple · Songwriting = green
STUDIO_TAGS="Full production|Recording|Mixing|Mastering|Songwriting"

tag_color() {   # Finder colour numbers: 1 grey 2 green 3 purple 4 blue 5 yellow 6 red 7 orange
    case "$1" in
        "Full production") echo 6 ;;  "Recording") echo 7 ;;  "Mixing") echo 4 ;;
        "Mastering") echo 3 ;;        "Songwriting") echo 2 ;; *) echo 0 ;;
    esac
}

# set_type_tag <folder> <type label>: replaces an older studio tag, keeps your other tags
set_type_tag() {
    local dir="$1" label="$2" attr="com.apple.metadata:_kMDItemUserTags" tmp old t keep=""
    [ -d "$dir" ] && [ "$(tag_color "$label")" != 0 ] || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/studiotag.XXXXXX")" || return 1

    # existing tags that are not ours (a tag is "Name<newline>Colour"; newline shown as TAB here)
    old="$(xattr -px "$attr" "$dir" 2>/dev/null | xxd -r -p | plutil -convert xml1 -o - - 2>/dev/null \
           | awk 'BEGIN { RS = "</string>" }
                  { i = index($0, "<string>"); if (i) { v = substr($0, i + 8); gsub(/\n/, "\t", v); print v } }')"
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        case "|$STUDIO_TAGS|" in *"|${t%%$'\t'*}|"*) continue ;; esac
        keep="$keep<string>$(printf '%s' "$t" | tr '\t' '\n')</string>"
    done <<< "$old"

    printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><array>%s<string>%s\n%s</string></array></plist>' \
        "$keep" "$label" "$(tag_color "$label")" > "$tmp"
    plutil -convert binary1 "$tmp" 2>/dev/null \
        && xattr -wx "$attr" "$(xxd -p "$tmp" | tr -d '\n')" "$dir"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# type label of a project ("Mixing", "Full production" …)
project_label() {
    local t; t="$(log_field "$1" TYPE | sed 's/^[a-z]* (\(.*\))$/\1/')"
    echo "${t:-Full production}"
}

# --- Audio helpers -------------------------------------------------------------

# find_tool <name>: full path of a command line tool (also looks in Homebrew folders)
find_tool() {
    local t
    for t in "$(command -v "$1" 2>/dev/null)" "/opt/homebrew/bin/$1" "/usr/local/bin/$1"; do
        [ -n "$t" ] && [ -x "$t" ] && { echo "$t"; return 0; }
    done
    return 1
}

# audio_info <file>  ->  "channels<TAB>rate<TAB>bits<TAB>seconds"   (bits: 16, 24, 32f, - for lossy)
audio_info() {
    afinfo "$1" 2>/dev/null | awk '
        /^Data format:/ {
            ch = $3; rate = $5
            bits = "-"
            # afinfo writes either "24-bit … signed integer" / "32-bit … float" or "Int16" / "Float32"
            if (match($0, /[0-9]+-bit/))        { bits = substr($0, RSTART, RLENGTH - 4); if ($0 ~ /float/) bits = bits "f" }
            else if (match($0, /Int[0-9]+/))    { bits = substr($0, RSTART + 3, RLENGTH - 3) }
            else if (match($0, /Float[0-9]+/))  { bits = substr($0, RSTART + 5, RLENGTH - 5) "f" }
        }
        /^estimated duration:/ { dur = $3 }
        END { if (rate != "") printf "%s\t%s\t%s\t%s\n", ch, rate, bits, dur; else exit 1 }'
}

# fmt_time <seconds>  ->  3:45.2
fmt_time() { awk -v s="$1" 'BEGIN { printf "%d:%04.1f", int(s / 60), s - 60 * int(s / 60) }'; }

# --- Which version is the final one? -------------------------------------------
# File names:  CODE_01_Song_Mix_v03.wav  /  CODE_01_Song_Mix_v03_Instr.wav
#   - by default the HIGHEST _v## of each name is the final one (incl. its variants)
#   - "studio approve" can mark another version as approved; that is stored in
#     <folder>/_approved.txt and wins over the highest number.
#   - files without _v## always count.
#
# pick_finals <folder> [all]  ->  prints the final files (with "all": every file)
pick_finals() {
    local root="${1%/}" mode="$2"
    find "$root" -type f \( -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' -o -iname '*.flac' \
         -o -iname '*.mp3' -o -iname '*.m4a' \) -not -name '._*' \
    | while IFS= read -r f; do
        # versions are compared per subfolder (Song A/Drums_v01 and Song B/Drums_v02 are different things);
        # an MP3 subfolder counts as its parent folder
        rel="${f#"$root"/}"; b="${rel##*/}"; d="${rel%/*}"; [ "$d" = "$rel" ] && d=""
        d="${d%/MP3}"; [ "$d" = "MP3" ] && d=""
        if [ "$mode" != "all" ] && [[ "$b" =~ ^(.*)_[vV]([0-9]+)(_[^.]*)?\.[^.]+$ ]]; then
            printf '%s\t%d\t%s\n' "${d:+$d/}${BASH_REMATCH[1]}" "$((10#${BASH_REMATCH[2]}))" "$f"
        else
            printf '%s\t%d\t%s\n' "$f" 0 "$f"
        fi
      done \
    | awk -F'\t' -v apf="$root/_approved.txt" '
        BEGIN { while ((getline line < apf) > 0) { split(line, a, "\t"); if (a[1] != "") appr[a[1]] = a[2] + 0 } }
        { key[NR] = $1; ver[NR] = $2; path[NR] = $3; has[$1, $2] = 1; if ($2 > max[$1]) max[$1] = $2 }
        END {
            for (i = 1; i <= NR; i++) {
                want = max[key[i]]
                if ((key[i] in appr) && ((key[i], appr[key[i]]) in has)) want = appr[key[i]]
                if (ver[i] == want) print path[i]
            }
        }' | sort
}

# list_versions <folder>  ->  "name<TAB>v01 v02 v03" for every versioned name in the folder
list_versions() {
    find "${1%/}" -type f \( -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' -o -iname '*.flac' \) \
         -not -name '._*' -not -path '*/MP3/*' \
    | while IFS= read -r f; do
        rel="${f#"${1%/}"/}"; b="${rel##*/}"; d="${rel%/*}"; [ "$d" = "$rel" ] && d=""
        [[ "$b" =~ ^(.*)_[vV]([0-9]+)(_[^.]*)?\.[^.]+$ ]] && printf '%s\t%02d\n' "${d:+$d/}${BASH_REMATCH[1]}" "$((10#${BASH_REMATCH[2]}))"
      done | sort -u \
    | awk -F'\t' '{ if ($1 != k) { if (k != "") print k "\t" l; k = $1; l = "v" $2 } else l = l " v" $2 }
                  END { if (k != "") print k "\t" l }'
}

# --- MP3 -----------------------------------------------------------------------
# encode_mp3 <source> <target.mp3> [title] [artist] [album] [track]
# Uses ffmpeg or lame. Returns 2 if neither is installed.
encode_mp3() {
    local src="$1" dst="$2" title="$3" artist="$4" album="$5" track="$6" ff la
    local br="${MP3_BITRATE:-320}"
    if ff="$(find_tool ffmpeg)"; then
        "$ff" -v error -y -i "$src" -vn -codec:a libmp3lame -b:a "${br}k" -id3v2_version 3 \
            -metadata title="$title" -metadata artist="$artist" -metadata album="$album" \
            -metadata track="$track" "$dst" </dev/null
    elif la="$(find_tool lame)"; then
        "$la" --quiet -b "$br" --tt "$title" --ta "$artist" --tl "$album" ${track:+--tn "$track"} "$src" "$dst"
    else
        return 2
    fi
}

# nice_title "NIGHT_01_Opener_Mix_v03" "NIGHT"  ->  sets TRACK_TITLE="Opener Mix v03", TRACK_NO="01"
nice_title() {
    local n="$1" code="$2"
    TRACK_NO=""
    [ -n "$code" ] && n="${n#"${code}"_}"
    if [[ "$n" =~ ^([0-9][0-9])_(.*)$ ]]; then TRACK_NO="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[2]}"; fi
    TRACK_TITLE="$(echo "$n" | tr '_' ' ')"
}
