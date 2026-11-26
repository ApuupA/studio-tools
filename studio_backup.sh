#!/bin/bash
# End-of-session backup: incremental 1:1 copy of the Studio folder to the SSD.
# Usually started by double-clicking End_Session.command in the Studio folder.
#
#   <SSD>/Studio_Mirror/<this Mac>/   exact copy of Studio (only new/changed files are copied,
#                          files deleted in Studio are deleted here too)
#
# Version history (going back in time) comes from Time Machine, not from this copy.

source "$(dirname "$0")/_common.sh"

MIRROR="$MIRROR_DIR"
EXCLUDES="$SCRIPT_DIR/backup_excludes.txt"
# .last_backup lives only on the SSD; excluding it also protects it from --delete
RSYNC_OPTS=(-a --delete --exclude-from="$EXCLUDES" --exclude=/.last_backup)
INTERACTIVE=0
[ -t 0 ] && INTERACTIVE=1

ask() {  # ask "question" -> returns 0 on y
    [ $INTERACTIVE -eq 1 ] || return 1
    local a; read -r -p "$1 [y/N] " a; [ "$a" = "y" ] || [ "$a" = "Y" ]
}

# --- 1. DAWs must be closed ------------------------------------------------
if daw_running; then
    [ $INTERACTIVE -eq 1 ] || die "Pro Tools / Cubase is open – backup not started."
    echo "Please SAVE and QUIT Pro Tools / Cubase.  Waiting…  (Ctrl+C to cancel)"
    while daw_running; do sleep 3; done
    echo "DAW closed."
fi

# --- 2. SSD connected? -----------------------------------------------------
while ! volume_mounted "$ARCHIVE_VOLUME"; do
    [ $INTERACTIVE -eq 1 ] || die "SSD not connected ($ARCHIVE_VOLUME)."
    read -r -p "SSD '$(basename "$ARCHIVE_VOLUME")' not found. Connect it and press Enter (Ctrl+C to cancel) "
done

free_gb=$(( $(df -k "$ARCHIVE_VOLUME" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
[ "$free_gb" -lt "$MIN_FREE_GB" ] && die "Only ${free_gb} GB free on the SSD (minimum ${MIN_FREE_GB} GB)."

# --- Older layout: one mirror directly in Studio_Mirror/ -> move it into this Mac's folder
OLD="$ARCHIVE_VOLUME/Studio_Mirror"
if [ ! -d "$MIRROR" ] && { [ -e "$OLD/.last_backup" ] || [ -d "$OLD/01_PROJECTS" ]; }; then
    echo
    echo "The backup on the drive is directly in Studio_Mirror/. Now every Mac has its own folder:"
    echo "  Studio_Mirror/$MACHINE_NAME/   (this Mac)"
    if ask "Is the existing backup the one of THIS Mac – move it into Studio_Mirror/$MACHINE_NAME/? (nothing is copied or deleted)"; then
        mkdir -p "$MIRROR" || die "Cannot write to $MIRROR"
        find "$OLD" -mindepth 1 -maxdepth 1 | while IFS= read -r e; do
            [ "$e" = "$MIRROR" ] && continue
            [ -d "$e" ] && [ -e "$e/.last_backup" ] && continue        # another Mac's mirror
            mv "$e" "$MIRROR/" || die "Could not move $(basename "$e") – nothing else was changed."
        done
        log "Moved the existing backup into Studio_Mirror/$MACHINE_NAME/"
    else
        echo "  Left as it is. This Mac gets its own, new backup in Studio_Mirror/$MACHINE_NAME/."
    fi
fi

mkdir -p "$MIRROR" || die "Cannot write to $MIRROR"

# --- 3. Dry run: what would change? ----------------------------------------
echo "Checking for changes…"
changes="$(rsync "${RSYNC_OPTS[@]}" -n --out-format='%i %n' "$STUDIO_ROOT/" "$MIRROR/" 2>&1)" \
    || die "Check failed: $changes"
# Our own log files always change - don't count them
changes="$(echo "$changes" | grep -v ' 99_SYSTEM/Logs/')"
n_copy=$(echo "$changes" | grep -c '^>f')
n_del=$(echo "$changes"  | grep '^\*deleting' | grep -vc '/$')

if [ "$n_copy" -eq 0 ] && [ "$n_del" -eq 0 ]; then
    log "Nothing changed – SSD copy is already up to date."
    notify "Studio Backup" "Already up to date"
    exit 0
fi

if [ "$n_del" -gt "$MAX_DELETE_FILES" ]; then
    echo
    echo "WARNING: this backup would DELETE $n_del files from the SSD copy, e.g.:"
    echo "$changes" | grep '^\*deleting' | sed 's/^\*deleting /   /' | head -15
    echo
    ask "Is that intended (did you delete/move these yourself)?" \
        || die "Stopped: $n_del deletions not confirmed. Nothing was changed."
fi

# --- 4. Copy ---------------------------------------------------------------
START=$(date +%s)
log "Backup started: $n_copy files to copy, $n_del to remove -> $MIRROR"

rsync "${RSYNC_OPTS[@]}" "$STUDIO_ROOT/" "$MIRROR/" >> "$LOG_FILE" 2>&1
rc=$?
# 24 = some files vanished during transfer (harmless)
[ $rc -eq 0 ] || [ $rc -eq 24 ] || die "Copy failed (code $rc). See $LOG_FILE"

date '+%Y-%m-%d %H:%M:%S' > "$MIRROR/.last_backup"

secs=$(( $(date +%s) - START ))
log "Backup finished in $((secs / 60))m $((secs % 60))s ($n_copy copied, $n_del removed, ${free_gb} GB were free)."
notify "Studio Backup" "Finished – $n_copy files copied"
