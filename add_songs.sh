#!/bin/bash
# Add songs to an existing project, and fill empty song folders with template sessions.
#
#   ./add_songs.sh [options] [PROJECT] ["Song" "Song" ...]
#
#   PROJECT: a project folder, OR any part of its name ("night", "demo", "mix").
#   No arguments at all = guided mode: choose the project from a list, then DAW,
#   template and song names are asked step by step (Enter = default / skip).
#   e.g.  ./add_songs.sh night "Bonus Track"      ./add_songs.sh
#
#   --daw pt|cb|both  which DAW gets folders + sessions (default: depends on the project TYPE)
#                     e.g. --daw cb on a Pro Tools project adds Cubase folders for ALL songs
#
# The project type (TYPE: line in Session_Log.txt) decides the session names:
#   full/rec NIGHT_12_Song_TRK_v01 · mix NIGHT_12_Song_MIX_v01 · write NIGHT_12_Song_v01.cpr
#   master   no new sessions – songs are added to the tracklist in Session_Log.txt
#
# - New songs get the next free numbers (e.g. 12_, 13_ …).
# - Every EMPTY song folder (old or new) of the chosen DAW gets a copy of the template session.
#   Folders that already contain anything are never touched.
# - Without song names it only fills empty folders (e.g. after you made a template).

source "$(dirname "$0")/_common.sh"

PT="$PT_TEMPLATE"; CB="$CB_TEMPLATE"; DAW=""
while [ $# -gt 0 ]; do
    case "$1" in
        --pt) PT="$2"; shift 2 ;;
        --cb) CB="$2"; shift 2 ;;
        --daw) DAW="$2"; shift 2 ;;
        --*)  die "Unknown option $1" ;;
        *)    break ;;
    esac
done

ASK_SONGS=0
if [ $# -eq 0 ]; then
    [ -t 0 ] || { echo "Usage: $0 [--daw pt|cb|both] [--pt TEMPLATE] [--cb TEMPLATE] [PROJECT] [\"Song\" ...]"; exit 1; }
    ASK_SONGS=1
fi
PROJECT="$(resolve_project "$1")" || exit 1
[ $# -gt 0 ] && shift
[ -d "$PROJECT/02_Sessions" ] || die "Not a project folder: $PROJECT"
echo "Project: $(basename "$PROJECT")" >&2

# Project type from Session_Log.txt (older projects without TYPE = full)
TYPE="$(log_field "$PROJECT" TYPE | awk '{print $1}')"
set_project_type "${TYPE:-full}"

# --- Guided mode: no arguments -> ask step by step ------------------------------
if [ $ASK_SONGS -eq 1 ]; then
    echo "Type:    $TYPE_LABEL        (Enter = take the default / skip)" >&2
    if [ "$TYPE" = "master" ]; then
        ask "Songs to add to the tracklist, separated by ;"
    else
        # default: the DAW this project already uses
        has_pt=0; has_cb=0
        [ -n "$(find "$PROJECT/02_Sessions/PT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)" ] && has_pt=1
        [ -n "$(find "$PROJECT/02_Sessions/CB" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)" ] && has_cb=1
        if   [ $has_pt -eq 1 ] && [ $has_cb -eq 1 ]; then d=3
        elif [ $has_cb -eq 1 ]; then d=2
        elif [ $has_pt -eq 1 ]; then d=1
        else case "$TYPE_DAW" in pt) d=1 ;; cb) d=2 ;; *) d=3 ;; esac
        fi
        if [ -z "$DAW" ]; then      # not already given with --daw
            choose "Which DAW?" $d "Pro Tools" "Cubase" "both"
            DAW="$(echo pt cb both | cut -d' ' -f"$CHOICE")"
        fi
        [ "$DAW" != "cb" ] && { choose_template pt "$PT"; PT="$ANSWER"; }
        [ "$DAW" != "pt" ] && { choose_template cb "$CB"; CB="$ANSWER"; }
        ask "New songs, separated by ;  (Enter = none, only fill empty song folders)"
    fi
    split_songs "$ANSWER"
    set -- "${SONGS[@]}"
    echo >&2
fi

DAW="${DAW:-$TYPE_DAW}"
apply_daw "$DAW"

CODE="$(log_field "$PROJECT" CODE)"
if [ -z "$CODE" ]; then
    CODE="$(make_code "$(log_field "$PROJECT" ARTIST)")"
    [ -n "$CODE" ] || die "No CODE/ARTIST in Session_Log.txt – add a line 'CODE:     XXXXX'."
fi

# Next free song number (01..89)
last=0
for d in "$PROJECT"/02_Sessions/PT/[0-8][0-9]_* "$PROJECT"/02_Sessions/CB/[0-8][0-9]_*; do
    [ -d "$d" ] || continue
    n=$((10#$(basename "$d" | cut -c1-2)))
    [ $n -gt $last ] && last=$n
done

# Mastering: one session for everything – songs only go into the tracklist
if [ "$TYPE" = "master" ]; then
    for song in "$@"; do
        echo "$(date +%Y-%m-%d)  Added to tracklist: $song" >> "$PROJECT/00_Admin/Session_Log.txt"
        log "Added '$song' to the tracklist of $(basename "$PROJECT")"
    done
    exit 0
fi

for song in "$@"; do
    last=$((last + 1))
    [ $last -le 89 ] || die "Song numbers 01–89 are full."
    num="$(printf '%02d' $last)"
    s="$(sanitize "$song")"
    make_song_folders "$PROJECT" "${num}_${s}"
    echo "$(date +%Y-%m-%d)  Song added: ${num}_${s}" >> "$PROJECT/00_Admin/Session_Log.txt"
    log "Added song ${num}_${s} to $(basename "$PROJECT")"
done

complete_song_folders "$PROJECT"
fill_song_folders "$PROJECT" "$CODE" "$PT" "$CB" "$PT_STAGE" "$CB_STAGE"
log "Done ($(basename "$PROJECT"), code $CODE)."
