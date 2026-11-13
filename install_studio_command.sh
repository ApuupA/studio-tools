#!/bin/bash
# Installs the "studio" command (with Tab completion) into your zsh.
#
#   ./install_studio_command.sh            install / update (run again after moving the Studio folder)
#   ./install_studio_command.sh --remove   uninstall
#
# It adds ONE line to ~/.zshrc that loads studio.zsh from this folder.

D="$(cd "$(dirname "$0")" && pwd)"
RC="$HOME/.zshrc"
MARK="# studio-command"

touch "$RC"
# remove an older line (e.g. from before the Studio folder was moved)
sed -i '' "/$MARK\$/d" "$RC"

if [ "$1" = "--remove" ]; then
    echo "Removed the studio command from $RC. Open a new Terminal window."
    exit 0
fi

chmod +x "$D/studio" "$D"/*.sh
echo "source \"$D/studio.zsh\"  $MARK" >> "$RC"

cat <<EOF
Installed. Open a NEW Terminal window (or run: source ~/.zshrc), then try:

  studio <Tab>
  studio add night<Tab>
  studio list
EOF
