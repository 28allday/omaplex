#!/bin/bash
# omaplex-spindown — put idle media disks to sleep.
#
# Installed by OmaPlex as /usr/local/lib/omaplex/omaplex-spindown and run as
# root by omaplex-spindown.service. Reads /etc/omaplex/spindown.conf, one
# disk per line:
#
#   /dev/disk/by-id/<disk>  <idle minutes>
#
# Why a watcher rather than the disk's own standby timer: common NAS drives
# (the 10 TB helium WD Reds among them) accept the timer and then ignore it.
# Sending "sleep now" from outside works on every drive that hdparm -y does.
#
# Nothing here touches the platters while watching: /proc/diskstats is kernel
# memory, and hdparm -C (CHECK POWER MODE) neither wakes a sleeping disk nor
# resets its idle state.

set -u

CONF=/etc/omaplex/spindown.conf
INTERVAL=30

declare -A sig_seen last_change

# Reads, sectors read, writes, sectors written: the counters that move only
# on real I/O (io_ticks and in_flight churn by themselves).
io_signature() {
  awk -v d="$1" '$3 == d { print $4, $6, $8, $10; exit }' /proc/diskstats
}

spinning() {
  # Anything we can't read counts as not spinning: never send a sleep
  # command to a disk whose state is unknown.
  hdparm -C "$1" 2>/dev/null | grep -q 'active'
}

echo "watching $CONF every ${INTERVAL}s"
while true; do
  now=$(date +%s)
  if [[ -r $CONF ]]; then
    while read -r id minutes _; do
      [[ $id == /dev/disk/by-id/* && $minutes =~ ^[0-9]+$ && $minutes -gt 0 ]] || continue
      dev=$(readlink -f "$id" 2>/dev/null) || continue
      [[ -b $dev ]] || continue
      name=${dev##*/}
      sig=$(io_signature "$name")
      [[ -n $sig ]] || continue
      if [[ ${sig_seen[$name]:-} != "$sig" ]]; then
        sig_seen[$name]=$sig
        last_change[$name]=$now
        continue
      fi
      ((now - ${last_change[$name]} >= minutes * 60)) || continue
      spinning "$dev" || continue
      if hdparm -y "$dev" >/dev/null 2>&1; then
        echo "$dev ($id) asleep after $minutes min with nothing to do"
      else
        echo "couldn't put $dev to sleep; trying again after another $minutes min"
      fi
      # Either way, start the idle count again from here.
      last_change[$name]=$now
    done <"$CONF"
  fi
  sleep "$INTERVAL"
done
