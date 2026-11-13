#!/bin/bash
# Start a studio session ("Studio Mode"). Usually started by double-clicking
# Start_Session.command in the Studio folder.
#
#   1. Focus mode on (via a Shortcut, see studio.conf)
#   2. quits distracting apps (QUIT_APPS)
#   3. keeps the Mac awake until End_Session (caffeinate)
#   4. checks disk space, SSD and the last backup
#   5. lets you pick a project + session and opens it
#
# End_Session.command undoes 1+3, asks for a note for the session log and runs the backup.

source "$(dirname "$0")/_common.sh"

STATE="${TMPDIR:-/tmp}/studio_session.state"
ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; }

echo "Studio Mode"
echo "-----------"

# --- 1. Focus ----------------------------------------------------------------
if shortcuts list </dev/null 2>/dev/null | grep -qxF "$FOCUS_ON_SHORTCUT"; then
    shortcuts run "$FOCUS_ON_SHORTCUT" </dev/null >/dev/null 2>&1 && ok "Focus mode on" || warn "Focus shortcut failed"
else
    warn "No shortcut '$FOCUS_ON_SHORTCUT' – Focus not changed (see README)"
fi

# --- 2. Quit distractions ----------------------------------------------------
quit=""
IFS='|' read -r -a apps <<< "$QUIT_APPS"
for a in "${apps[@]}"; do
    quit_app "$a" && quit="$quit, $a"
done
[ -n "$quit" ] && ok "Closed: ${quit#, }" || ok "No distracting apps open"

# --- 3. Keep awake -----------------------------------------------------------
[ -f "$STATE" ] && OLD_PID="$(sed -n 's/^CAFF_PID=//p' "$STATE")" && [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null
nohup caffeinate -dims -t $((KEEP_AWAKE_HOURS * 3600)) </dev/null >/dev/null 2>&1 &
CAFF_PID=$!
disown
ok "Mac stays awake (until End_Session, max ${KEEP_AWAKE_HOURS}h)"

# --- 4. Checks ---------------------------------------------------------------
free_gb=$(( $(df -k "$STUDIO_ROOT" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
if [ "$free_gb" -lt "$MIN_FREE_INTERNAL_GB" ]; then
    warn "Only ${free_gb} GB free on the Mac – think about archiving a project"
else
    ok "${free_gb} GB free on the Mac"
fi

if volume_mounted "$ARCHIVE_VOLUME"; then
    last="$(cat "$ARCHIVE_VOLUME/Studio_Mirror/.last_backup" 2>/dev/null)"
    if [ -z "$last" ]; then
        warn "SSD connected, but no backup on it yet"
    else
        age_d=$(( ($(date +%s) - $(date -j -f '%Y-%m-%d %H:%M:%S' "$last" +%s)) / 86400 ))
        if [ $age_d -gt "$BACKUP_WARN_DAYS" ]; then warn "Last backup is $age_d days old ($last)"
        else ok "SSD connected – last backup $last"; fi
    fi
else
    warn "Backup SSD '$(basename "$ARCHIVE_VOLUME")' not connected – plug it in before End_Session"
fi

# --- 5. Pick project + session -----------------------------------------------
PROJECT=""
if [ -t 0 ]; then
    projects=()
    while IFS= read -r p; do projects+=("$p"); done < <(list_projects | head -9)
    if [ ${#projects[@]} -gt 0 ]; then
        echo
        echo "Which project? (Enter = none)"
        i=1
        for p in "${projects[@]}"; do
            t="$(log_field "$p" TYPE | sed 's/^[a-z]* (\(.*\))$/\1/')"
            printf "  %d) %s   [%s]\n" $i "$(basename "$p")" "${t:-Full production}"
            i=$((i + 1))
        done
        read -r -p "> " pick
        if [[ "$pick" =~ ^[1-9]$ ]] && [ "$pick" -le ${#projects[@]} ]; then
            PROJECT="${projects[$((pick - 1))]}"
        fi
    fi

    if [ -n "$PROJECT" ]; then
        # newest session file per session folder
        sessions=()
        for d in "$PROJECT"/02_Sessions/PT/*/ "$PROJECT"/02_Sessions/CB/*/; do
            [ -d "$d" ] || continue
            f="$(find "$d" -maxdepth 1 \( -name '*.ptx' -o -name '*.cpr' \) -exec stat -f '%m	%N' {} + 2>/dev/null \
                 | sort -rn | head -1 | cut -f2-)"
            [ -n "$f" ] && sessions+=("$f")
        done
        if [ ${#sessions[@]} -gt 0 ]; then
            echo
            echo "Open which session? (Enter = just open the project folder)"
            i=1
            for f in "${sessions[@]}"; do
                printf "  %2d) %s\n" $i "$(basename "$f")"
                i=$((i + 1))
            done
            read -r -p "> " pick
            if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#sessions[@]} ]; then
                open "${sessions[$((pick - 1))]}" && ok "Opening $(basename "${sessions[$((pick - 1))]}")"
            else
                open "$PROJECT"
            fi
        else
            open "$PROJECT"
        fi
    fi
fi

# --- Remember for End_Session --------------------------------------------------
{
    echo "START=$(date +%s)"
    echo "CAFF_PID=$CAFF_PID"
    echo "PROJECT=$PROJECT"
} > "$STATE"

log "Session started${PROJECT:+: $(basename "$PROJECT")}"
echo
echo "🎙  Studio Mode is ON – have a good session."
