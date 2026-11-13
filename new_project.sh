#!/bin/bash
# Create a new project folder with the standard structure.
#
#   ./new_project.sh [options] "Artist" "Project Title" ["Song 1" "Song 2" ...]
#
#   --type TYPE       full | rec | mix | write | master   (default: full)
#                       full    full production: recording → mix → master
#                       rec     recording only (roughs + multitrack delivery)
#                       mix     mixing received multitracks
#                       write   songwriting (Cubase), created in 02_WRITING/<NN_ARTIST>/
#                               with 03_Demos, 04_Ideas (memos) and 05_Songs (final songs)
#                       master  mastering: ONE session for all songs, songs = tracklist
#   --code NIGHT      artist code for file names (default: first 5 letters of the artist)
#   --pt TEMPLATE     Pro Tools template from 03_LIBRARY/Templates/ProTools (default: studio.conf)
#   --cb TEMPLATE     Cubase template from 03_LIBRARY/Templates/Cubase (default: studio.conf)
#   --daw pt|cb|both  which DAW gets folders + sessions (default depends on the type:
#                     write = cb, all others = pt)
#
# Each song gets a folder for the chosen DAW (01_Song_PT and/or 01_Song_CB) with a
# copy of the template session, already named:
#   NIGHT_01_Song_TRK_v01.ptx  (full/rec)  ·  NIGHT_01_Song_MIX_v01.ptx  (mix)
#   NIGHT_01_Song_v01.cpr      (write)     ·  NIGHT_MASTER_Title_v01.ptx (master)
# Add songs later with add_songs.sh.
#
# Without any arguments it asks for everything step by step (guided mode).

source "$(dirname "$0")/_common.sh"

# --- Guided mode: no arguments -> ask step by step ------------------------------
if [ $# -eq 0 ] && [ -t 0 ]; then
    echo "NEW PROJECT  –  Enter = take the default / skip,  Ctrl+C = cancel"

    choose "What kind of project?" 1 "Full production" "Recording" "Mixing" "Songwriting" "Mastering"
    W_TYPE="$(echo full rec mix write master | cut -d' ' -f"$CHOICE")"
    set_project_type "$W_TYPE"

    ask_required "Artist / band";                        W_ARTIST="$ANSWER"
    ask_required "Project title (album, EP, song …)";    W_TITLE="$ANSWER"
    ask "Short code for file names" "$(make_code "$W_ARTIST")"
    W_CODE="$(make_code "$ANSWER")"

    case "$TYPE_DAW" in pt) d=1 ;; cb) d=2 ;; *) d=3 ;; esac
    choose "Which DAW?" $d "Pro Tools" "Cubase" "both"
    W_DAW="$(echo pt cb both | cut -d' ' -f"$CHOICE")"

    W_PT="$PT_TEMPLATE"; W_CB="$CB_TEMPLATE"
    [ "$W_DAW" != "cb" ] && { choose_template pt "$PT_TEMPLATE"; W_PT="$ANSWER"; }
    [ "$W_DAW" != "pt" ] && { choose_template cb "$CB_TEMPLATE"; W_CB="$ANSWER"; }

    if [ "$W_TYPE" = "master" ]; then
        ask "Tracklist – songs in order, separated by ;  (Enter = none)"
    else
        ask "Songs, separated by ;  (Enter = none – add later with: studio add)"
    fi
    split_songs "$ANSWER"

    echo
    echo "------------------------------------------------------------"
    echo "  Type:     $TYPE_LABEL"
    echo "  Artist:   $W_ARTIST"
    echo "  Title:    $W_TITLE"
    echo "  Code:     $W_CODE"
    echo "  DAW:      $W_DAW"
    [ "$W_DAW" != "cb" ] && echo "  PT template:      $W_PT"
    [ "$W_DAW" != "pt" ] && echo "  Cubase template:  $W_CB"
    if [ ${#SONGS[@]} -gt 0 ]; then
        echo "  Songs:    ${#SONGS[@]}"
        n=1; for s in "${SONGS[@]}"; do printf "              %02d  %s\n" $n "$s"; n=$((n + 1)); done
    else
        echo "  Songs:    none yet"
    fi
    echo "------------------------------------------------------------"
    read -r -p "Create it? [Y/n] " a
    case "$a" in n|N|no|nein) echo "Cancelled – nothing created."; exit 0 ;; esac

    # the same as a one-line command, for next time
    cmdline="studio new --type $W_TYPE --code $W_CODE --daw $W_DAW"
    [ "$W_DAW" != "cb" ] && cmdline="$cmdline --pt $W_PT"
    [ "$W_DAW" != "pt" ] && cmdline="$cmdline --cb $W_CB"
    cmdline="$cmdline \"$W_ARTIST\" \"$W_TITLE\""
    for s in "${SONGS[@]}"; do cmdline="$cmdline \"$s\""; done
    echo
    echo "Shortcut for next time:"
    echo "  $cmdline"
    echo

    set -- --type "$W_TYPE" --code "$W_CODE" --daw "$W_DAW" --pt "$W_PT" --cb "$W_CB" \
           "$W_ARTIST" "$W_TITLE" "${SONGS[@]}"
fi

CODE=""; PT="$PT_TEMPLATE"; CB="$CB_TEMPLATE"; DAW=""; TYPE="full"
while [ $# -gt 0 ]; do
    case "$1" in
        --type) TYPE="$2"; shift 2 ;;
        --code) CODE="$(make_code "$2")"; shift 2 ;;
        --pt)   PT="$2"; shift 2 ;;
        --cb)   CB="$2"; shift 2 ;;
        --daw)  DAW="$2"; shift 2 ;;
        --*)    die "Unknown option $1" ;;
        *)      break ;;
    esac
done
set_project_type "$TYPE"
DAW="${DAW:-$TYPE_DAW}"
apply_daw "$DAW"

if [ $# -lt 2 ]; then
    echo "Usage: $0 [--type full|rec|mix|write|master] [--code NIGHT] [--daw pt|cb|both]"
    echo "          [--pt TEMPLATE] [--cb TEMPLATE] \"Artist\" \"Project Title\" [\"Song 1\" ...]"
    exit 1
fi

ARTIST_RAW="$1"; TITLE_RAW="$2"
ARTIST="$(sanitize "$1")"
TITLE="$(sanitize "$2")"
[ -n "$CODE" ] || CODE="$(make_code "$ARTIST_RAW")"
shift 2

NAME="$(date +%Y-%m)_${ARTIST}_${TITLE}"

if [ "$TYPE" = "write" ]; then
    # Songwriting lives with the band in 02_WRITING/<NN_ARTIST>/ (e.g. 01_NIGHTFALL)
    UPPER="$(echo "$ARTIST" | tr '[:lower:]' '[:upper:]')"
    BAND_DIR=""
    for d in "$STUDIO_ROOT"/02_WRITING/[0-9][0-9]_*; do
        [ -d "$d" ] || continue
        b="$(basename "$d")"
        [ "$(echo "${b#*_}" | tr '[:lower:]' '[:upper:]')" = "$UPPER" ] && BAND_DIR="$d" && break
    done
    if [ -z "$BAND_DIR" ]; then
        last=0
        for d in "$STUDIO_ROOT"/02_WRITING/[0-9][0-9]_*; do
            [ -d "$d" ] && n=$((10#$(basename "$d" | cut -c1-2))) && [ $n -gt $last ] && last=$n
        done
        BAND_DIR="$STUDIO_ROOT/02_WRITING/$(printf '%02d' $((last + 1)))_$UPPER"
        mkdir -p "$BAND_DIR"
        log "Created band folder $(basename "$BAND_DIR")"
    fi
    PROJECT="$BAND_DIR/$NAME"
else
    PROJECT="$STUDIO_ROOT/01_PROJECTS/$(date +%Y)/$NAME"
fi

[ -e "$PROJECT" ] && die "Project already exists: $(basename "$PROJECT") – add songs to it with: studio add"

for f in $TYPE_FOLDERS; do mkdir -p "$PROJECT/$f"; done

# --- Session_Log.txt -----------------------------------------------------------
case "$TYPE" in
    full)   HINTS="Song sessions:  02_Sessions/PT/01_..89_   (tracking + editing, one per song)
Mix session:    02_Sessions/PT/90_MIX_${TITLE}_PT   (import with \"Copy from source media\"!)
File names:     ${CODE}_01_Song_TRK_v01.ptx -> _EDT_v01 -> ...   (new version = Save As)" ;;
    rec)    HINTS="Song sessions:  02_Sessions/PT/01_..89_   (tracking + editing, one per song)
Roughs:         03_Mixes      Multitrack delivery (consolidated, from bar 1): 06_Deliverables
File names:     ${CODE}_01_Song_TRK_v01.ptx -> _EDT_v01 -> ...   (new version = Save As)" ;;
    mix)    HINTS="Received:       07_Received   (client files exactly as delivered – never edit here)
Mix sessions:   02_Sessions/PT/01_..89_   (one per song, import audio from 07_Received)
File names:     ${CODE}_01_Song_MIX_v01.ptx  ->  bounce ${CODE}_01_Song_Mix_v01.wav" ;;
    write)  HINTS="Song sessions:  02_Sessions/CB/01_..89_   (one per song)
Demos:          03_Demos   (${CODE}_01_Song_Demo_v01.wav)
Ideas:          04_Ideas   (memos, voice notes, riffs)
Songs:          05_Songs   (final songs from the writing)" ;;
    master) HINTS="Received:       07_Received   (premasters exactly as delivered – never edit here)
Master session: 02_Sessions/PT/95_MASTER_${TITLE}_PT   (ONE session for all songs)
Masters:        05_Masters  (${CODE}_01_Song_Master_v01.wav)   DDP / MP3 / client package: 06_Deliverables" ;;
esac

{
    echo "PROJECT:  $NAME"
    echo "TYPE:     $TYPE ($TYPE_LABEL)"
    echo "ARTIST:   $ARTIST_RAW"
    echo "TITLE:    $TITLE_RAW"
    echo "CODE:     $CODE"
    echo "CREATED:  $(date +%Y-%m-%d)"
    echo
    echo "$HINTS"
    if [ "$TYPE" = "master" ] && [ $# -gt 0 ]; then
        echo
        echo "TRACKLIST:"
        n=1; for song in "$@"; do printf '  %02d  %s\n' $n "$song"; n=$((n + 1)); done
    fi
    echo
    echo "------------------------------------------------------------"
    echo "DATE        NOTE"
    echo "------------------------------------------------------------"
    echo "$(date +%Y-%m-%d)  Project created ($TYPE_LABEL)"
} > "$PROJECT/00_Admin/Session_Log.txt"

log "Created project $NAME ($TYPE_LABEL, code $CODE)"
set_type_tag "$PROJECT" "$TYPE_LABEL"     # coloured Finder tag for the project type

# --- Sessions ------------------------------------------------------------------
if [ "$TYPE" = "master" ]; then
    # One session for the whole release
    if [ -n "$PT" ]; then
        mkdir -p "$PROJECT/02_Sessions/PT/95_MASTER_${TITLE}_PT"
        copy_template PT "$PT" "$PROJECT/02_Sessions/PT/95_MASTER_${TITLE}_PT" "${CODE}_MASTER_${TITLE}_v01"
    fi
    if [ -n "$CB" ]; then
        mkdir -p "$PROJECT/02_Sessions/CB/95_MASTER_${TITLE}_CB"
        copy_template CB "$CB" "$PROJECT/02_Sessions/CB/95_MASTER_${TITLE}_CB" "${CODE}_MASTER_${TITLE}_v01"
    fi
else
    n=1
    for song in "$@"; do
        num="$(printf '%02d' "$n")"
        s="$(sanitize "$song")"
        make_song_folders "$PROJECT" "${num}_${s}"
        n=$((n + 1))
    done
    fill_song_folders "$PROJECT" "$CODE" "$PT" "$CB" "$PT_STAGE" "$CB_STAGE"
fi

echo "$PROJECT"
[ -z "$NO_OPEN" ] && open "$PROJECT" 2>/dev/null || true
