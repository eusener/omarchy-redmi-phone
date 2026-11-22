#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Run: bash tests/test_ctl.sh
# Exercises bin/headphones-ctl against stub pactl/wpctl/systemctl/bluetoothctl.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CTL="$ROOT/bin/headphones-ctl"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STUBS="$WORK/bin"
LOG="$WORK/calls.log"
mkdir -p "$STUBS"
MAC="AA:BB:CC:DD:EE:FF"
fail=0

# Each stub records its name and every argument on its own line, so the test
# can tell "two separate words" from "one word containing a space".
make_stub() {
  local name=$1 body=$2
  cat >"$STUBS/$name" <<EOF
#!/usr/bin/env bash
{ echo "== $name"; for a in "\$@"; do echo "[\$a]"; done; } >>"$LOG"
$body
EOF
  chmod +x "$STUBS/$name"
}

make_stub pactl '
case "$*" in
  "--format=json list cards") cat <<JSON
[{"name":"bluez_card.AA_BB_CC_DD_EE_FF","active_profile":"a2dp-sink","driver":"x",
  "profiles":{"off":{"description":"Off","priority":0,"available":true},
              "a2dp-sink":{"description":"High Fidelity Playback (A2DP Sink, codec SBC)","priority":132,"available":true},
              "a2dp-sink-sbc_xq":{"description":"High Fidelity Playback (A2DP Sink, codec SBC-XQ)","priority":131,"available":true},
              "headset-head-unit":{"description":"Headset Head Unit (HSP/HFP, codec MSBC)","priority":5,"available":true}}}]
JSON
  ;;
  "get-default-sink") echo "bluez_output.AA_BB_CC_DD_EE_FF.1" ;;
  "list sinks short") printf "69\talsa_output.speaker\tPipeWire\n90\tbluez_output.AA_BB_CC_DD_EE_FF.1\tPipeWire\n" ;;
esac
exit 0'
# --save mimics WirePlumber persisting to $XDG_STATE_HOME unless NO_PERSIST is set.
make_stub wpctl '
if [[ ${1:-} == settings && ${2:-} == --save && -z ${NO_PERSIST:-} ]]; then
  mkdir -p "$XDG_STATE_HOME/wireplumber"
  printf "[sm-settings]\n%s=%s\n" "$3" "$4" >"$XDG_STATE_HOME/wireplumber/sm-settings"
fi
echo "Value: false"; exit 0'
make_stub systemctl 'case "$*" in *is-active*|*is-enabled*) exit 1 ;; esac; exit 0'
make_stub bluetoothctl 'echo "	UUID: Vendor specific           (0000fd2d-0000-1000-8000-00805f9b34fb)"'
make_stub omarchy-bluetooth-device 'exit 0'

export XDG_STATE_HOME="$WORK/state"
run() { : >"$LOG"; PATH="$STUBS:$PATH" "$CTL" "$@"; }
check() {
  local label=$1; shift
  if "$@"; then echo "ok   $label"; else echo "FAIL $label"; fail=1; fi
}
jqe() { jq -e "$@" >/dev/null; }
called() { grep -q "^== $1$" "$LOG"; }
nothing_called() { [[ ! -s $LOG ]] || ! grep -q '^== ' "$LOG"; }

# ---- injection attempts are refused before any command runs ----
out=$(run set-profile "$MAC" 'a2dp-sink; rm -rf ~'); rc=$?
check "malicious profile rejected (rc=$rc)" test "$rc" -ne 0
check "malicious profile: error code" grep -q '"invalid_profile"' <<<"$out"
check "malicious profile: no stub called" nothing_called

out=$(run set-profile 'AA:BB:CC:DD:EE:FF; reboot' a2dp-sink); rc=$?
check "invalid MAC rejected (rc=$rc)" test "$rc" -ne 0
check "invalid MAC: no stub called" nothing_called

out=$(run status '$(touch /tmp/pwned)'); rc=$?
check "status rejects shell syntax" test "$rc" -ne 0
check "status: no stub called" nothing_called

out=$(run set-profile "$MAC" a2dp-sink-ldac); rc=$?
check "profile not on the card is refused" grep -q '"unknown_profile"' <<<"$out"
check "unknown profile: set-card-profile never sent" bash -c "! grep -q '\[set-card-profile\]' '$LOG'"

out=$(run autoswitch maybe); rc=$?
check "bad switch value refused" grep -q '"invalid_switch"' <<<"$out"

# ---- valid calls pass arguments as separate words ----
out=$(run set-profile "$MAC" a2dp-sink-sbc_xq); rc=$?
check "valid profile accepted" test "$rc" -eq 0
check "set-card-profile args separate" bash -c "grep -A3 '^== pactl' '$LOG' | tr '\n' ' ' | grep -q '\[set-card-profile\] \[bluez_card.AA_BB_CC_DD_EE_FF\] \[a2dp-sink-sbc_xq\]'"

out=$(run set-default "$MAC"); rc=$?
check "set-default picks the bluez sink" grep -q 'bluez_output.AA_BB_CC_DD_EE_FF.1' <<<"$out"

out=$(run status "$MAC"); rc=$?
check "status is valid JSON" jqe '.ok == true and .isDefaultSink == true and .autoswitch == false' <<<"$out"
check "status lists vendor UUID" jqe '.uuids | index("0000fd2d-0000-1000-8000-00805f9b34fb")' <<<"$out"
check "status card profiles" jqe '.card.profiles | has("a2dp-sink-sbc_xq")' <<<"$out"

out=$(run autoswitch off); rc=$?
check "autoswitch off persists with --save" bash -c "grep -A4 '^== wpctl' '$LOG' | tr '\n' ' ' | grep -q '\[settings\] \[--save\] \[bluetooth.autoswitch-to-headset-profile\] \[false\]'"

check "autoswitch off succeeds once persisted (rc=$rc)" test "$rc" -eq 0

out=$(NO_PERSIST=1 run autoswitch on); rc=$?
check "autoswitch reports a save that never reached disk" grep -q '"autoswitch_not_persisted"' <<<"$out"

out=$(run media-buttons on); rc=$?
check "media-buttons on enables the unit" bash -c "tr '\n' ' ' <'$LOG' | grep -q '\[--user\] \[enable\] \[--now\] \[mpris-proxy.service\]'"

out=$(run connect "$MAC"); rc=$?
check "connect delegates to omarchy-bluetooth-device" called omarchy-bluetooth-device

exit $fail
