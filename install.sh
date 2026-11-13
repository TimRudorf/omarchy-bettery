#!/bin/bash

# One-time system setup for the omarchy-bettery plugin. Run with sudo.
#
#   sudo ./install.sh            lets the wheel group set charge limits and
#                                charge behaviour, and stops a forced discharge
#                                before suspend
#   sudo ./install.sh --remove   undoes both
#
# The rule gives every member of wheel write access to these battery files:
# charge_control_start_threshold, charge_control_end_threshold,
# charge_behaviour, charge_types. Nothing else.

set -euo pipefail

RULE=/etc/udev/rules.d/90-omarchy-bettery.rules
HOOK=/usr/lib/systemd/system-sleep/omarchy-bettery
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

(( EUID == 0 )) || { echo "Run with sudo: sudo $0 ${*:-}" >&2; exit 1; }

reload_rules() {
  udevadm control --reload
  udevadm trigger --subsystem-match=power_supply --action=change
  udevadm settle
}

if [[ ${1:-} == "--remove" ]]; then
  rm -f "$RULE" "$HOOK"
  reload_rules
  for f in /sys/class/power_supply/*/{charge_control_start_threshold,charge_control_end_threshold,charge_behaviour,charge_types}; do
    [[ -e $f ]] || continue
    chgrp root "$f" && chmod g-w "$f"
  done
  echo "Removed. The charge limit stays at its last value until you change it or the firmware resets it."
  exit 0
fi

install -Dm644 "$SRC/system/90-omarchy-bettery.rules" "$RULE"
install -Dm755 "$SRC/system/omarchy-bettery.sleep" "$HOOK"
reload_rules

if [[ $("$SRC/bin/bettery-hw" status) == *"supported	1"* ]]; then
  echo "Done. Battery care is ready in the power panel."
else
  echo "Installed, but no battery with a kernel charge limit was found on this machine." >&2
fi
