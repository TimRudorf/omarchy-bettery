#!/bin/bash
# Runs bettery-hw against a fake sysfs tree.
set -u
HW="$(cd "$(dirname "$0")/.." && pwd)/bin/bettery-hw"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export BETTERY_POWER_SUPPLY_PATH=$root
failures=0

check() {
  local name=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then echo "ok - $name"; else echo "not ok - $name: expected '$expected', got '$actual'"; failures=$((failures + 1)); fi
}

mkdir -p "$root/hidpp_battery_0" "$root/BAT0" "$root/AC"
echo Battery >"$root/hidpp_battery_0/type"; echo Device >"$root/hidpp_battery_0/scope"
echo 100 >"$root/hidpp_battery_0/charge_control_end_threshold"
echo Mains >"$root/AC/type"
echo Battery >"$root/BAT0/type"
echo 0 >"$root/BAT0/charge_control_start_threshold"
echo 100 >"$root/BAT0/charge_control_end_threshold"
echo "[auto] inhibit-charge force-discharge" >"$root/BAT0/charge_behaviour"
echo 45000000 >"$root/BAT0/energy_full"; echo 52000000 >"$root/BAT0/energy_full_design"
echo 99 >"$root/BAT0/capacity"; echo "Not charging" >"$root/BAT0/status"

out=$("$HW" status)
check "skips device batteries" "BAT0" "$(awk -F'\t' '$1=="battery"{print $2}' <<<"$out")"
check "health" "87" "$(awk -F'\t' '$1=="health"{print $2}' <<<"$out")"

"$HW" set-thresholds 75 80
check "start written" "75" "$(<"$root/BAT0/charge_control_start_threshold")"
check "end written" "80" "$(<"$root/BAT0/charge_control_end_threshold")"

"$HW" set-thresholds 85 90
check "raising start above old end writes end first" "85 90" "$(<"$root/BAT0/charge_control_start_threshold") $(<"$root/BAT0/charge_control_end_threshold")"

"$HW" set-thresholds 80 75 2>/dev/null; check "start >= end refused" "2" "$?"
"$HW" set-thresholds 70 101 2>/dev/null; check "end > 100 refused" "2" "$?"
"$HW" set-thresholds '1;rm' 80 2>/dev/null; check "garbage refused" "2" "$?"
"$HW" set-behaviour bogus 2>/dev/null; check "unknown behaviour refused" "2" "$?"

# A real sysfs file shows "[mode]" after a write; the fake one keeps what was written.
"$HW" set-behaviour force-discharge
check "behaviour written" "force-discharge" "$(<"$root/BAT0/charge_behaviour")"

echo "auto inhibit-charge [force-discharge]" >"$root/BAT0/charge_behaviour"
out=$("$HW" apply 75 80 -)
check "apply reports behaviour" "force-discharge" "$(awk -F'\t' '$1=="behaviour"{print $2}' <<<"$out")"

chmod a-w "$root/BAT0/charge_control_end_threshold"
if [[ $EUID -ne 0 ]]; then
  "$HW" set-thresholds 70 75 2>/dev/null; check "no write access exits 4" "4" "$?"
  out=$("$HW" apply 70 75 -); code=$?
  check "apply exits 0 on failure" "0" "$code"
  check "apply reports error code" "4" "$(awk -F'\t' '$1=="errorCode"{print $2}' <<<"$out")"
fi

rm -rf "$root/BAT0"
"$HW" set-thresholds 75 80 2>/dev/null; check "no battery exits 3" "3" "$?"
check "unsupported status" "supported	0" "$("$HW" status)"

exit $(( failures > 0 ))
