#!/bin/bash
# OmaPlex set-up steps. Run inside a floating terminal (omaplex setup <step>),
# as your normal user; sudo asks for the password when a step needs it.
#
#   setup.sh install     install Plex, start it now and at every boot
#   setup.sh drive       make a media drive always available to Plex
#   setup.sh uninstall   remove Plex and undo what install did
#
# Everything the user reads is plain English: no fstab, setfacl or AUR.

set -euo pipefail

SERVICE="plexmediaserver.service"
PACKAGES=(plex-media-server plex-media-server-plexpass)
WEB_URL="http://localhost:32400/web"
WEBAPP_NAME="Plex"
WEBAPP_ICON="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/plex.png"
UFW_COMMENT="omaplex"
PRIVATE_CIDRS=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16)
# 32400 is the server itself; the UDP ports let apps on the network find it.
TCP_PORTS=(32400)
UDP_PORTS=(32410 32412 32413 32414)
FSTAB_MARK="# OmaPlex media drive:"
PLEX_DATA="/var/lib/plex/Plex Media Server"
# Artwork and posters (Metadata) and video thumbnails and previews (Media):
# the parts of Plex's data that grow with the size of the collection.
ARTWORK_DIRS=(Metadata Media)
ARTWORK_FOLDER="Plex Artwork"
ARTWORK_DROPIN="/etc/systemd/system/plexmediaserver.service.d/omaplex-artwork.conf"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omaplex"
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

say() { gum style --foreground 4 --bold "▸ $1"; }
ok() { gum style "✓ $1"; }
note() { gum style --faint "  $1"; }
die() {
  gum style --foreground 1 --bold "Something went wrong"
  gum style --foreground 1 "$1"
  exit 1
}

need() { command -v "$1" >/dev/null 2>&1; }

installed_package() {
  local pkg
  for pkg in "${PACKAGES[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
      printf '%s\n' "$pkg"
      return 0
    fi
  done
  return 1
}

firewall_active() {
  need ufw && systemctl is-active --quiet ufw
}

firewall_rule() {
  # firewall_rule add|delete <ufw rule words...>. The comment only goes on an
  # add; ufw matches a delete on the rule itself.
  local action="$1"
  shift
  if [[ $action == add ]]; then
    sudo ufw allow "$@" comment "$UFW_COMMENT" >/dev/null || true
  else
    sudo ufw delete allow "$@" >/dev/null 2>&1 || true
  fi
}

firewall_rules() {
  local action="$1" port cidr
  for port in "${TCP_PORTS[@]}"; do
    for cidr in "${PRIVATE_CIDRS[@]}"; do
      firewall_rule "$action" in proto tcp from "$cidr" to any port "$port"
    done
    if ip link show tailscale0 >/dev/null 2>&1; then
      firewall_rule "$action" in on tailscale0 to any port "$port" proto tcp
    fi
  done
  for port in "${UDP_PORTS[@]}"; do
    for cidr in "${PRIVATE_CIDRS[@]}"; do
      firewall_rule "$action" in proto udp from "$cidr" to any port "$port"
    done
  done
  sudo ufw reload >/dev/null || true
}

# ---------- install ----------

# Plex needs a few seconds after it starts before it answers (and, the first
# time, before it has made its data folder).
wait_for_plex() {
  local tries=0
  until curl -fsS --max-time 2 -o /dev/null http://127.0.0.1:32400/identity 2>/dev/null; do
    tries=$((tries + 1))
    ((tries < 30)) || return 0
    sleep 1
  done
}

step_install() {
  say "Installing Plex Media Server"
  if pkg=$(installed_package); then
    ok "Plex is already installed ($pkg)."
  else
    note "This downloads Plex and builds the package. It can take a minute or two."
    omarchy-pkg-aur-add plex-media-server || die "Plex didn't install. The messages above say why."
    ok "Plex is installed."
  fi

  say "Starting Plex, now and every time the computer starts"
  sudo systemctl enable --now "$SERVICE" || die "Plex installed but wouldn't start."
  ok "Plex is running and will start by itself after a restart."

  say "Letting other devices on your network reach Plex"
  if firewall_active; then
    firewall_rules add
    ok "Your TVs, phones and other computers at home can now see Plex."
  else
    note "No firewall is running, so there's nothing to open."
  fi

  say "Adding Plex to your apps"
  if omarchy-webapp-install "$WEBAPP_NAME" "$WEB_URL" "$WEBAPP_ICON" >/dev/null 2>&1; then
    ok "Plex is in the app launcher."
  else
    note "Couldn't add the launcher. The OmaPlex panel can still open Plex."
  fi

  echo
  note "Waiting for Plex to finish starting…"
  wait_for_plex
  if gum confirm "Set up a drive for your movies, TV and music now?"; then
    step_drive
  else
    note "You can add a drive any time from the OmaPlex panel."
  fi

  echo
  say "One last step: claim your server"
  note "Plex opens in a moment. Sign in with your Plex account to claim this server"
  note "and add your libraries. Then click Connect in the OmaPlex panel to see"
  note "what's playing and scan your libraries from the bar."
  wait_for_plex
  setsid omarchy-launch-webapp "$WEB_URL" >/dev/null 2>&1 &
}

# ---------- artwork ----------

# The drive Plex's artwork lives on, if OmaPlex moved it there; else empty.
# The link reads <drive>/<ARTWORK_FOLDER>/Metadata.
artwork_home() {
  local target
  target=$(sudo readlink "$PLEX_DATA/${ARTWORK_DIRS[0]}" 2>/dev/null || true)
  [[ -n $target ]] || return 0
  dirname "$(dirname "$target")"
}

move_artwork() {
  local drive="$1" dest="$1/$ARTWORK_FOLDER" current d
  sudo test -d "$PLEX_DATA" || {
    note "Plex hasn't set itself up yet, so there's no artwork to move. Run this again once Plex has started."
    return 0
  }
  current=$(artwork_home)
  if [[ -n $current ]]; then
    note "Plex already keeps its artwork in $current/$ARTWORK_FOLDER."
    return 0
  fi

  echo
  note "Plex's artwork, posters and video previews can take many gigabytes for a big"
  note "collection. They can live on this drive instead of your computer's own drive."
  note "Plex's library database stays where it is, so it stays fast."
  gum confirm "Keep Plex's artwork on this drive?" || return 0

  sudo systemctl stop "$SERVICE"
  sudo install -d -o plex -g plex -m 750 "$dest"
  for d in "${ARTWORK_DIRS[@]}"; do
    if sudo test -d "$PLEX_DATA/$d" && ! sudo test -L "$PLEX_DATA/$d"; then
      gum spin --title "Moving Plex's $d to the drive…" -- \
        sudo cp -a "$PLEX_DATA/$d" "$dest/" || die "Couldn't copy Plex's $d to the drive. Nothing was changed."
      sudo rm -rf --one-file-system "$PLEX_DATA/$d"
    else
      sudo install -d -o plex -g plex -m 750 "$dest/$d"
    fi
    sudo ln -sfn "$dest/$d" "$PLEX_DATA/$d"
    sudo chown -h plex:plex "$PLEX_DATA/$d"
  done

  # Plex must never start without the drive: it would quietly start filling
  # an empty folder on the computer's own drive instead.
  sudo mkdir -p "$(dirname "$ARTWORK_DROPIN")"
  printf '%s\n' "# Plex keeps its artwork on this drive (set up by OmaPlex)." \
    "[Unit]" "RequiresMountsFor=\"$drive\"" | sudo tee "$ARTWORK_DROPIN" >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl start "$SERVICE"
  ok "Plex's artwork now lives in $dest"
  note "If this drive isn't plugged in, Plex waits for it instead of starting without it."
}

# ---------- drive ----------

pick_partition() {
  local rows=() labels=() choice i dev size fs label at uuid disks where
  mapfile -t rows < <(python3 -I "$HERE/drives.py")
  ((${#rows[@]} > 0)) || die "No drives found. Plug your media drive in and try again."
  for i in "${!rows[@]}"; do
    IFS=$'\t' read -r dev size fs label at uuid disks <<<"${rows[$i]}"
    [[ $label == - ]] && label="(no name)"
    where="not open"
    [[ $at != - ]] && where="open at $at"
    ((disks > 1)) && size="$size × $disks disks"
    labels+=("$(printf '%-16s  %-16s  %-6s  %s  [%s]' "$label" "$size" "$fs" "$where" "$dev")")
  done
  choice=$(printf '%s\n' "${labels[@]}" | gum choose --height 15 \
    --header "Pick the drive that holds (or will hold) your media")
  [[ -n $choice ]] || die "Nothing picked. Cancelled."
  for i in "${!labels[@]}"; do
    if [[ ${labels[$i]} == "$choice" ]]; then
      IFS=$'\t' read -r DEVICE _ _ _ _ _ DISKS <<<"${rows[$i]}"
    fi
  done
  [[ -b ${DEVICE:-} ]] || die "That doesn't look like a real drive."
}

# Close every other place the drive is open, by UUID and by device:
# close_other_mounts <UUID=… or device> <where it should stay open>
close_other_mounts() {
  # The file manager may already have opened the drive somewhere else
  # (/run/media/...), sometimes more than once: a pool of several disks gets
  # opened once per disk. Close every one so it opens in a single place.
  local spot
  while IFS= read -r spot; do
    [[ -n $spot && $spot != "$2" ]] || continue
    note "Closing the drive at $spot so it can open at $2 instead."
    sudo umount "$spot" ||
      die "Couldn't close the drive at $spot. Close any windows using it and try again."
  done < <(
    # set -e carries into this subshell, and a lookup that finds nothing
    # "fails" (by UUID it always does on a multi-disk pool), so neither may
    # end it early.
    {
      findmnt -rno TARGET -S "$1" 2>/dev/null || true
      findmnt -rno TARGET -S "$DEVICE" 2>/dev/null || true
    } | sort -u
  )
}

step_drive() {
  local DISKS=1 user="$USER" uid gid default_name base n pass mount_point name fs uuid ident opts line existing errfile
  uid=$(id -u)
  gid=$(id -g)

  say "Pick your media drive"
  pick_partition
  # Of every place the drive is open, the one OmaPlex set up (if any).
  # findmnt -r writes a space as \x20; printf %b turns it back.
  existing=$(findmnt -rno TARGET -S "$DEVICE" 2>/dev/null | grep "^/media/$user/" | head -n1 || true)
  existing=$(printf '%b' "$existing")
  if [[ -n $existing ]] && grep -qsF " ${existing// /\\040} " /etc/fstab; then
    ok "This drive is already set up at $existing."
    uuid=$(sudo blkid -s UUID -o value "$DEVICE" 2>/dev/null || true)
    close_other_mounts "${uuid:+UUID=$uuid}" "$existing"
    if pacman -Q plex-media-server >/dev/null 2>&1 || pacman -Q plex-media-server-plexpass >/dev/null 2>&1; then
      move_artwork "$existing"
    fi
    return 0
  fi
  ok "Picked $DEVICE"

  # Suggest the drive's own label when it makes a usable name.
  default_name=$(lsblk -no LABEL "$DEVICE" 2>/dev/null | head -n1 || true)
  [[ $default_name =~ ^[A-Za-z0-9._\ -]{1,40}$ && $default_name != .* ]] || default_name="MediaDrive"
  n=2
  base="$default_name"
  while [[ -e "/media/$user/$default_name" ]]; do
    default_name="$base$n"
    n=$((n + 1))
  done
  name=$(gum input --header "What should this drive be called in your file manager?" --value "$default_name")
  name="${name:-$default_name}"
  [[ $name =~ ^[A-Za-z0-9._\ -]{1,40}$ && $name != .* ]] || die "Use letters, numbers, spaces, dots, dashes or underscores (up to 40)."
  mount_point="/media/$user/$name"
  if mountpoint -q "$mount_point" 2>/dev/null; then
    die "Something else is already open at $mount_point. Pick another name."
  fi

  fs=$(lsblk -no FSTYPE "$DEVICE" 2>/dev/null | head -n1 || true)
  if [[ -z $fs ]] || ! gum confirm "The drive is formatted as $fs. Use that?"; then
    fs=$(printf '%s\n' ext4 btrfs xfs ntfs exfat | gum choose --header "What format is the drive?")
    [[ -n $fs ]] || die "Nothing picked. Cancelled."
  fi

  uuid=$(sudo blkid -s UUID -o value "$DEVICE" 2>/dev/null || true)
  ident="${uuid:+UUID=$uuid}"
  ident="${ident:-$DEVICE}"
  # nofail: a missing drive must never stop the computer from booting.
  opts="defaults,nofail,x-gvfs-show,x-gvfs-name=${name// /\\040}"
  # Windows-format drives have no owners, so open them as yours and readable
  # by everyone. Skip the boot-time check on them (pass 0): NTFS has no
  # checker here, and checking a big USB drive at every start only slows it.
  pass=2
  case $fs in
    exfat | ntfs)
      opts="uid=$uid,gid=$gid,umask=002,$opts"
      pass=0
      ;;
  esac
  line="$ident  ${mount_point// /\\040}  $fs  $opts  0  $pass"

  gum style --border normal --padding "0 1" \
    "Drive:        $DEVICE$( ((DISKS > 1)) && echo " (and $((DISKS - 1)) more disk(s) in the same pool)")" \
    "Opens at:     $mount_point" \
    "Called:       $name" \
    "Format:       $fs"
  gum confirm "Make this drive available every time the computer starts?" || die "Cancelled."

  close_other_mounts "$ident" "$mount_point"

  sudo mkdir -p "$mount_point"
  sudo cp -a /etc/fstab "/etc/fstab.bak.$(date +%s)"
  if ! grep -qsF "$line" /etc/fstab; then
    printf '%s %s\n%s\n' "$FSTAB_MARK" "$name" "$line" | sudo tee -a /etc/fstab >/dev/null
  fi
  sudo systemctl daemon-reload
  errfile=$(mktemp)
  if ! sudo mount "$mount_point" 2>"$errfile"; then
    local msg
    msg=$(head -c 2000 "$errfile")
    rm -f "$errfile"
    die "Couldn't open the drive: $msg"
  fi
  rm -f "$errfile"
  ok "The drive is open at $mount_point"

  say "Letting Plex read your media"
  if ! id -u plex >/dev/null 2>&1; then
    note "Plex isn't installed yet. Install it from the panel and it will be able to read this drive."
  else
    case $fs in
      ext4 | btrfs | xfs)
        note "On a big collection this takes a few minutes."
        # shellcheck disable=SC2016 # $1 expands in the inner shell
        if gum spin --title "Giving Plex permission to read your media…" -- \
          sudo bash -c 'setfacl -R -m u:plex:rX "$1" && setfacl -R -d -m u:plex:rX "$1"' _ "$mount_point"; then
          ok "Plex can read everything on this drive, including anything you add later."
        else
          note "Couldn't set that up automatically. Plex will use the files' own permissions."
        fi
        ;;
      *)
        # exFAT and NTFS have no owners; the umask above already lets everyone read.
        ok "This kind of drive is readable by Plex as it is."
        ;;
    esac
  fi

  if [[ -z $(find "$mount_point" -mindepth 1 -maxdepth 1 -not -name 'lost+found' -print -quit 2>/dev/null) ]]; then
    if gum confirm "The drive is empty. Make Movies, TV and Music folders on it?"; then
      sudo install -d -o "$uid" -g "$gid" -m 775 "$mount_point/Movies" "$mount_point/TV" "$mount_point/Music"
      if [[ $fs == ext4 || $fs == btrfs || $fs == xfs ]] && id -u plex >/dev/null 2>&1; then
        sudo setfacl -m u:plex:rX -d -m u:plex:rX "$mount_point/Movies" "$mount_point/TV" "$mount_point/Music" || true
      fi
      ok "Made Movies, TV and Music folders."
    fi
  fi

  if pacman -Q plex-media-server >/dev/null 2>&1 || pacman -Q plex-media-server-plexpass >/dev/null 2>&1; then
    move_artwork "$mount_point"
  fi

  echo
  ok "Done. In Plex, add a library and point it at $mount_point"
}

# ---------- uninstall ----------

step_uninstall() {
  local pkg drives=() picked line artwork
  say "Remove Plex Media Server"
  gum confirm "Remove Plex from this computer?" || exit 0

  # Read before anything is removed: the link is the only record of where.
  artwork=$(artwork_home)

  if systemctl list-unit-files "$SERVICE" >/dev/null 2>&1; then
    sudo systemctl disable --now "$SERVICE" 2>/dev/null || true
    ok "Plex is stopped and won't start with the computer."
  fi

  if pkg=$(installed_package); then
    sudo pacman -Rns --noconfirm "$pkg" || die "Couldn't remove $pkg."
    ok "Plex is removed."
  else
    note "Plex wasn't installed."
  fi

  sudo rm -f "$ARTWORK_DROPIN"
  sudo systemctl daemon-reload

  if [[ -d /var/lib/plex ]]; then
    note "Plex keeps its settings, watch history and artwork in /var/lib/plex."
    [[ -n $artwork ]] && note "Its artwork is on your drive, in $artwork/$ARTWORK_FOLDER."
    if gum confirm --default=false "Delete those too? Your media files are NOT touched."; then
      sudo rm -rf --one-file-system /var/lib/plex
      [[ -n $artwork ]] && sudo rm -rf --one-file-system "${artwork:?}/$ARTWORK_FOLDER"
      ok "Deleted Plex's settings, history and artwork."
    else
      note "Kept. Reinstalling Plex picks up where you left off."
    fi
  fi

  if firewall_active; then
    firewall_rules delete
    ok "Closed the network ports opened for Plex."
  fi

  omarchy-webapp-remove "$WEBAPP_NAME" >/dev/null 2>&1 || true
  rm -rf "$CONFIG_DIR"

  mapfile -t drives < <(grep -sh "^$FSTAB_MARK" /etc/fstab | sed "s/^$FSTAB_MARK //")
  if ((${#drives[@]} > 0)); then
    note "Your media drives still open automatically. Your files stay on them either way."
    picked=$(printf '%s\n' "${drives[@]}" | gum choose --no-limit \
      --header "Stop opening any of these automatically? (space to pick, enter to finish)" || true)
    if [[ -n $picked ]]; then
      sudo cp -a /etc/fstab "/etc/fstab.bak.$(date +%s)"
      while IFS= read -r line; do
        [[ -n $line ]] || continue
        # Drop the marker line and the mount line straight after it.
        sudo awk -v mark="$FSTAB_MARK $line" '
          skip { skip=0; next }
          $0 == mark { skip=1; next }
          { print }' /etc/fstab | sudo tee /etc/fstab.omaplex >/dev/null
        sudo mv -f /etc/fstab.omaplex /etc/fstab
        ok "$line won't open automatically any more."
      done <<<"$picked"
      sudo systemctl daemon-reload
    fi
  fi

  echo
  ok "Plex is gone. The OmaPlex panel stays in your bar; remove it with: omarchy plugin remove nosignal.plex"
}

case "${1:-}" in
  install) step_install ;;
  drive) step_drive ;;
  uninstall) step_uninstall ;;
  *)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
