#!/bin/bash
# End a studio session. Usually started by double-clicking End_Session.command.
#
#   1. waits until Pro Tools / Cubase are closed
#   2. asks for a short note → project's Session_Log.txt (if a project was picked at start)
#   3. backup to the SSD (studio_backup.sh)
#   4. Focus off, Mac may sleep again
#
#   studio end               backup included; if the drive is missing it asks: wait or skip
#   studio end --no-backup   end the session without a backup (drive at home …)

source "$(dirname "$0")/_common.sh"

DO_BACKUP=1
[ "$1" = "--no-backup" ] && DO_BACKUP=0

STATE="${TMPDIR:-/tmp}/studio_session.state"
START=""; CAFF_PID=""; PROJECT=""
if [ -f "$STATE" ]; then
    START="$(sed -n 's/^START=//p' "$STATE")"
    CAFF_PID="$(sed -n 's/^CAFF_PID=//p' "$STATE")"
    PROJECT="$(sed -n 's/^PROJECT=//p' "$STATE")"
fi

# --- 1. DAWs closed ------------------------------------------------------------
if daw_running && [ -t 0 ]; then
    echo "Please SAVE and QUIT Pro Tools / Cubase.  Waiting…  (Ctrl+C to cancel)"
    while daw_running; do sleep 3; done
    echo "DAW closed."
    echo
fi

# --- 2. Note for the session log ----------------------------------------------
if [ -n "$PROJECT" ] && [ -d "$PROJECT" ] && [ -t 0 ]; then
    dur=""
    if [ -n "$START" ]; then
        m=$(( ($(date +%s) - START) / 60 ))
        dur="$((m / 60))h $((m % 60))m"
    fi
    echo "Project: $(basename "$PROJECT")${dur:+  –  session time $dur}"
    read -r -p "What did you do today? (Enter = skip) > " note
    if [ -n "$note" ]; then
        echo "$(date +%Y-%m-%d)  ${note}${dur:+  [$dur]}" >> "$PROJECT/00_Admin/Session_Log.txt"
        echo "  ✅ Added to Session_Log.txt"
    fi
    echo
fi

# --- 3. Backup -------------------------------------------------------------------
# Drive not connected: wait for it, or skip the backup this time
if [ $DO_BACKUP -eq 1 ] && ! volume_mounted "$ARCHIVE_VOLUME"; then
    DRIVE="$(basename "$ARCHIVE_VOLUME")"
    if [ -t 0 ]; then
        choose "Backup drive '$DRIVE' is not connected." 1 "Wait – I'll connect it now" "Skip the backup this time"
        if [ "$CHOICE" = 1 ]; then
            while ! volume_mounted "$ARCHIVE_VOLUME"; do
                read -r -p "Connect '$DRIVE', then press Enter  (s = skip the backup) " a
                case "$a" in s|S|skip) DO_BACKUP=0; break ;; esac
            done
        else
            DO_BACKUP=0
        fi
    else
        DO_BACKUP=0                                     # nobody to ask (e.g. scripted run)
    fi
fi

# Laptop: work on songs from the main Mac goes to the drive first (asks before sending)
if [ "$MACHINE_ROLE" = "portable" ] && [ -t 0 ] && volume_mounted "$ARCHIVE_VOLUME"; then
    /bin/bash "$SCRIPT_DIR/sync.sh" --send
fi

if [ $DO_BACKUP -eq 1 ]; then
    /bin/bash "$SCRIPT_DIR/studio_backup.sh"
    rc=$?
else
    rc=0
    echo
    echo "  ⚠️  No backup this time. Back up later with:  studio backup"
    log "Backup skipped"
fi

# --- 4. Studio Mode off ----------------------------------------------------------
echo
if shortcuts list </dev/null 2>/dev/null | grep -qxF "$FOCUS_OFF_SHORTCUT"; then
    shortcuts run "$FOCUS_OFF_SHORTCUT" </dev/null >/dev/null 2>&1 && echo "  ✅ Focus mode off"
fi
if [ -n "$CAFF_PID" ] && kill "$CAFF_PID" 2>/dev/null; then
    echo "  ✅ Mac may sleep again"
fi
rm -f "$STATE"
log "Session ended${PROJECT:+: $(basename "$PROJECT")} ($([ $DO_BACKUP -eq 1 ] && echo "backup rc=$rc" || echo "no backup"))"

exit $rc
