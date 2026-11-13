#!/bin/bash
# End a studio session. Usually started by double-clicking End_Session.command.
#
#   1. waits until Pro Tools / Cubase are closed
#   2. asks for a short note → project's Session_Log.txt (if a project was picked at start)
#   3. backup to the SSD (studio_backup.sh)
#   4. Focus off, Mac may sleep again

source "$(dirname "$0")/_common.sh"

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
/bin/bash "$SCRIPT_DIR/studio_backup.sh"
rc=$?

# --- 4. Studio Mode off ----------------------------------------------------------
echo
if shortcuts list </dev/null 2>/dev/null | grep -qxF "$FOCUS_OFF_SHORTCUT"; then
    shortcuts run "$FOCUS_OFF_SHORTCUT" </dev/null >/dev/null 2>&1 && echo "  ✅ Focus mode off"
fi
if [ -n "$CAFF_PID" ] && kill "$CAFF_PID" 2>/dev/null; then
    echo "  ✅ Mac may sleep again"
fi
rm -f "$STATE"
log "Session ended${PROJECT:+: $(basename "$PROJECT")} (backup rc=$rc)"

exit $rc
