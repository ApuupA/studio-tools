#!/bin/bash
# Set up a Studio folder: the complete folder structure, the double-click files
# and (if you want) the "studio" command for the Terminal.
#
#   studio init                asks where the Studio folder should be
#   studio init ~/Studio       no questions about the folder
#   studio init --no-command   don't touch ~/.zshrc
#
# Safe to run again at any time: existing folders and files are never changed
# or deleted, missing ones are added. Run it again after moving the Studio folder.

STUDIO_NO_ROOT_OK=1
source "$(dirname "$0")/_common.sh"

COMMAND=1
[ "$1" = "--no-command" ] && { COMMAND=0; shift; }
TARGET="$1"
LOCAL="$SCRIPT_DIR/studio.local.conf"

ok()   { echo "  ✅ $*"; }
todo() { echo "  ⬜ $*"; }

# set_local KEY VALUE: write a setting into studio.local.conf (replace or add)
set_local() {
    [ -f "$LOCAL" ] || echo "# Settings of THIS studio – overrides studio.conf. Not tracked in git." > "$LOCAL"
    if grep -q "^$1=" "$LOCAL"; then
        sed -i '' "s|^$1=.*|$1=\"$2\"|" "$LOCAL"
    else
        echo "$1=\"$2\"" >> "$LOCAL"
    fi
}

echo "STUDIO SETUP"

# --- 1. Where? -------------------------------------------------------------------
if [ -z "$TARGET" ]; then
    DEFAULT="${STUDIO_ROOT:-$HOME/Studio}"
    if [ -t 0 ]; then
        ask "Where should the Studio folder be?" "$DEFAULT"
        TARGET="$ANSWER"
    else
        TARGET="$DEFAULT"
    fi
fi
case "$TARGET" in "~"*) TARGET="$HOME${TARGET#\~}" ;; esac
mkdir -p "$TARGET" || { echo "Cannot create $TARGET"; exit 1; }
ROOT="$(cd "$TARGET" && pwd)"

# --- 2. Backup drive ---------------------------------------------------------------
DRIVE="$(basename "$ARCHIVE_VOLUME")"
if [ -t 0 ]; then
    ask "Name of your backup / archive drive (as shown in Finder)" "$DRIVE"
    DRIVE="$ANSWER"
fi

# --- 2b. This Mac: main studio Mac or laptop ---------------------------------------
ROLE="$MACHINE_ROLE"; NAME="$MACHINE_NAME"
if [ -t 0 ]; then
    d=1; [ "$MACHINE_ROLE" = "portable" ] && d=2
    choose "Which Mac is this?" $d "Main studio Mac (home of all projects)" "Laptop (you carry songs to it with studio sync)"
    [ "$CHOICE" = 1 ] && ROLE="main" || ROLE="portable"
    def="$MACHINE_NAME"
    [ "$ROLE" != "$MACHINE_ROLE" ] && { [ "$ROLE" = "main" ] && def="Main" || def="Portable"; }
    ask "Name of this Mac (its backup goes to Studio_Mirror/<name> on the drive)" "$def"
    NAME="$(sanitize "$ANSWER")"; NAME="${NAME:-$def}"
fi

# --- 3. Folder structure -----------------------------------------------------------
echo
echo "Studio folder: $ROOT"
created=0
for d in 00_INBOX "01_PROJECTS/$(date +%Y)" 02_WRITING \
         03_LIBRARY/Samples 03_LIBRARY/Impulse_Responses \
         03_LIBRARY/Presets/ProTools 03_LIBRARY/Presets/Cubase 03_LIBRARY/Presets/Plugins \
         03_LIBRARY/Templates/ProTools 03_LIBRARY/Templates/Cubase 03_LIBRARY/Portfolio \
         04_ARCHIVE 99_SYSTEM/Logs 99_SYSTEM/Studio_Docs; do
    [ -d "$ROOT/$d" ] || { mkdir -p "$ROOT/$d" && created=$((created + 1)); }
done
[ $created -gt 0 ] && ok "Folder structure: $created folder(s) created" || ok "Folder structure: complete, nothing to add"

# --- 4. Settings -------------------------------------------------------------------
INSIDE=0
[ "$SCRIPT_DIR" = "$ROOT/99_SYSTEM/Scripts" ] && INSIDE=1
if [ $INSIDE -eq 1 ]; then
    # tools live inside the Studio folder: it is found automatically, also after moving it
    [ -f "$LOCAL" ] && sed -i '' '/^STUDIO_ROOT=/d' "$LOCAL"
else
    set_local STUDIO_ROOT "$ROOT"
fi
[ "/Volumes/$DRIVE" != "$ARCHIVE_VOLUME" ] && set_local ARCHIVE_VOLUME "/Volumes/$DRIVE"
set_local MACHINE_ROLE "$ROLE"
set_local MACHINE_NAME "$NAME"
[ -f "$LOCAL" ] || echo "# Settings of THIS studio – overrides studio.conf. Not tracked in git." > "$LOCAL"
ok "Settings: studio.local.conf (your own values go there)"

# --- 5. Double-click files + docs in the Studio folder -------------------------------
# inside the Studio folder: relative paths, so the folder can be moved as a whole
if [ $INSIDE -eq 1 ]; then CALL='"$(dirname "$0")/99_SYSTEM/Scripts'; LINK="99_SYSTEM/Scripts"
else                       CALL="\"$SCRIPT_DIR";                      LINK="$SCRIPT_DIR"; fi

make_command() {   # make_command <file> <title> <script> <closing line>
    cat > "$ROOT/$1" <<EOF
#!/bin/bash
# $2 – double-click. (Created by "studio init"; run it again after moving folders.)
echo "=========================================="
echo "  $2"
echo "=========================================="
echo
/bin/bash $CALL/$3"
rc=\$?
echo
$4
read -n 1 -s -r -p "Press any key to close this window…"
echo
EOF
    chmod +x "$ROOT/$1"
}
make_command Start_Session.command "START SESSION" start_session.sh ':'
make_command End_Session.command   "END SESSION – backup" end_session.sh \
    '[ $rc -eq 0 ] && echo "✅  Done." || echo "❌  Backup NOT completed – see the message above."'
ok "Start_Session.command and End_Session.command"

for doc in README.md CHEATSHEET.md; do
    [ -f "$SCRIPT_DIR/$doc" ] || continue
    if [ -L "$ROOT/$doc" ] || [ ! -e "$ROOT/$doc" ]; then ln -sfn "$LINK/$doc" "$ROOT/$doc"; fi
done
ok "README.md and CHEATSHEET.md (links to the tools folder)"

# --- 6. The "studio" command ---------------------------------------------------------
chmod +x "$SCRIPT_DIR/studio" "$SCRIPT_DIR"/*.sh 2>/dev/null
if [ $COMMAND -eq 1 ] && [ -t 0 ]; then
    echo
    read -r -p "Install the 'studio' command for the Terminal (adds one line to ~/.zshrc)? [Y/n] " a
    case "$a" in n|N|no|nein) COMMAND=0 ;; esac
    [ $COMMAND -eq 1 ] && /bin/bash "$SCRIPT_DIR/install_studio_command.sh" >/dev/null && ok "'studio' command installed – open a new Terminal window"
else
    COMMAND=0
fi

# --- 7. What is still to do ------------------------------------------------------------
echo
echo "Still to do (once):"
if grep -qF "source \"$SCRIPT_DIR/studio.zsh\"" "$HOME/.zshrc" 2>/dev/null; then ok "'studio' command is installed in the Terminal"
else todo "Terminal command:  $SCRIPT_DIR/install_studio_command.sh"; fi
for k in ProTools Cubase; do
    if [ -n "$(find "$ROOT/03_LIBRARY/Templates/$k" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)" ]; then
        ok "$k template found"
    else
        todo "$k template: save an empty session as 03_LIBRARY/Templates/$k/TEMPLATE_48k  (see README)"
    fi
done
if find_tool ffmpeg >/dev/null && find_tool lame >/dev/null; then ok "ffmpeg + lame installed (MP3s, peak check)"
else todo "MP3s and peak check:  brew install lame ffmpeg"; fi
if shortcuts list </dev/null 2>/dev/null | grep -qxF "$FOCUS_ON_SHORTCUT"; then ok "Focus shortcuts found"
else todo "Focus mode: create the Shortcuts '$FOCUS_ON_SHORTCUT' and '$FOCUS_OFF_SHORTCUT' (see README)"; fi
if [ -d "/Volumes/$DRIVE" ]; then ok "Drive '$DRIVE' is connected"
else todo "Backup drive: name it '$DRIVE' and connect it before the first 'studio end'"; fi
todo "Time Machine: include the backup drive, so archived projects exist twice"

echo
echo "This Mac: $NAME ($([ "$ROLE" = main ] && echo "main studio Mac" || echo "laptop")) – carry songs between your Macs with: studio sync"
echo "Ready. First project:   studio new"
