#!/bin/bash
# Install OmaPlex and Plex Media Server in one go:
#   git clone <this repo> && cd omaplex && ./install.sh
#
# Adds the plugin the supported way (omarchy plugin add, so `omarchy plugin
# update` keeps working), then installs Plex and sets it to start at boot.

set -euo pipefail

ID="nosignal.plex"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"

command -v omarchy >/dev/null || {
  echo "OmaPlex needs Omarchy 4." >&2
  exit 1
}

if [[ -e "$PLUGINS/$ID" ]]; then
  echo "OmaPlex is already installed."
else
  source_url=$(git -C "$HERE" remote get-url origin 2>/dev/null || true)
  source_url="${source_url:-$HERE}"
  # Only skip the prompts (including where the icon goes) without a terminal.
  if [[ -t 0 && -t 1 ]]; then
    omarchy plugin add "$source_url" --enable
  else
    omarchy plugin add "$source_url" --enable --yes
  fi
fi

exec "$PLUGINS/$ID/lib/setup.sh" install
