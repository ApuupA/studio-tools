#!/bin/bash
# Move a finished project to the archive SSD – safely.
#
#   ./archive_project.sh [--no-keep] [PROJECT]
#   PROJECT: the project folder, any part of its name ("night"), or nothing -> choose from a list
#
# 1. copies the project to  <backup drive>/<ARCHIVE_FOLDER>/<year>/<project>  (default: Studio_Archive)
# 2. verifies every file by checksum
# 3. keeps the final mixes / demos / masters on the Mac in 03_LIBRARY/Portfolio/<project>
#    (folders: ARCHIVE_KEEP_FOLDERS, newest version only: ARCHIVE_KEEP_LATEST_ONLY)
#    --no-keep skips this step
# 4. only then asks whether to move the local copy to the Trash
#
# Archived projects exist only on the SSD afterwards – include the SSD in
# Time Machine so there is a second copy (see README).

source "$(dirname "$0")/_common.sh"

KEEP=1
[ "$1" = "--no-keep" ] && { KEEP=0; shift; }
[ $# -le 1 ] || { echo "Usage: $0 [--no-keep] [PROJECT]   (folder, part of the name, or nothing = list)"; exit 1; }
SRC="$(resolve_project "$1")" || exit 1
[ -d "$SRC" ] || die "Not a folder: $SRC"
echo "Project: $(basename "$SRC")"
volume_mounted "$ARCHIVE_VOLUME" || die "Archive SSD not connected ($ARCHIVE_VOLUME)."

source "$SCRIPT_DIR/_sync_lib.sh"
OUTSONGS="$(rec_units "${SRC#"$STUDIO_ROOT"/}" lent | /usr/bin/grep '/02_Sessions/' | sed 's|.*/||' | tr '\n' ' ')"
if [ -n "$OUTSONGS" ]; then
    echo "⚠️  Songs of this project are still on the drive / at the laptop: $OUTSONGS"
    read -r -p "Archive anyway? Bring them back first with 'studio sync'. [y/N] " a
    [ "$a" = "y" ] || exit 1
fi

if daw_running; then
    echo "A DAW is open. Please close all sessions of this project first."
    read -r -p "Continue anyway? [y/N] " a
    [ "$a" = "y" ] || exit 1
fi

PROJECT="$(basename "$SRC")"
YEAR="$(echo "$PROJECT" | grep -oE '^[0-9]{4}' || date +%Y)"
DEST="$ARCHIVE_VOLUME/${ARCHIVE_FOLDER:-Studio_Archive}/$YEAR/$PROJECT"

size_kb=$(du -sk "$SRC" | awk '{print $1}')
free_kb=$(df -k "$ARCHIVE_VOLUME" | awk 'NR==2 {print $4}')
[ "$size_kb" -lt "$free_kb" ] || die "Not enough space on archive SSD ($((size_kb/1024/1024)) GB needed)."

log "Archiving $PROJECT ($((size_kb/1024)) MB) -> $DEST"
mkdir -p "$DEST"
rsync -a --exclude-from="$SCRIPT_DIR/backup_excludes.txt" "$SRC/" "$DEST/" >> "$LOG_FILE" 2>&1 \
    || die "Copy failed. Local project untouched."

echo "Verifying copy (checksums)…"
diffs="$(rsync -a -c -n -i --exclude-from="$SCRIPT_DIR/backup_excludes.txt" "$SRC/" "$DEST/" 2>&1)"
if [ -n "$diffs" ]; then
    echo "$diffs" >> "$LOG_FILE"
    die "Verification FAILED for $PROJECT. Local project untouched. See $LOG_FILE"
fi
log "Verified OK: $DEST"

# Note in the project's session log
LOGTXT="$DEST/00_Admin/Session_Log.txt"
[ -f "$LOGTXT" ] && echo "$(date +%Y-%m-%d)  Archived to $DEST" >> "$LOGTXT"

# --- Keep finals on the Mac ---------------------------------------------------
# pick_finals (in _common.sh) chooses the approved or highest version per song.
[ "$ARCHIVE_KEEP_LATEST_ONLY" = "yes" ] && KEEP_MODE="" || KEEP_MODE="all"

if [ $KEEP -eq 1 ]; then
    KEEP_DIR="$STUDIO_ROOT/03_LIBRARY/Portfolio/$PROJECT"
    kept=0
    for folder in $ARCHIVE_KEEP_FOLDERS; do
        [ -d "$SRC/$folder" ] || continue
        while IFS= read -r f; do
            rel="${f#"$SRC"/}"
            mkdir -p "$KEEP_DIR/$(dirname "$rel")"
            cp -p "$f" "$KEEP_DIR/$rel" && kept=$((kept + 1))
        done < <(pick_finals "$SRC/$folder" $KEEP_MODE)
    done
    if [ $kept -gt 0 ]; then
        log "Kept $kept final file(s) on the Mac: $KEEP_DIR ($(du -sh "$KEEP_DIR" | cut -f1))"
    else
        log "No mixes/masters found to keep on the Mac."
    fi
fi

echo
echo "Archive copy verified: $DEST"
read -r -p "Move the local copy to the Trash now? [y/N] " a
if [ "$a" = "y" ]; then
    mv "$SRC" "$HOME/.Trash/$PROJECT-$(date +%H%M%S)" && log "Local copy moved to Trash: $SRC"
    # Its copy in Studio_Mirror is now redundant (verified archive copy exists)
    case "$SRC" in
        "$STUDIO_ROOT"/*)
            OLD_MIRROR="$MIRROR_DIR/${SRC#"$STUDIO_ROOT"/}"
            [ -d "$OLD_MIRROR" ] && rm -rf "$OLD_MIRROR" && log "Removed redundant mirror copy: $OLD_MIRROR"
            ;;
    esac
    echo "Done. Empty the Trash yourself once you're happy."
else
    log "Local copy kept: $SRC"
fi
notify "Studio Archive" "$PROJECT archived and verified"
