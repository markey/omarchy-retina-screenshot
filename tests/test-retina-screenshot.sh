#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/retina-screenshot"
TEST_DIR=$(mktemp -d)
cleanup() {
  if [[ -f $TEST_DIR/wl-copy-child ]]; then
    while IFS= read -r pid; do kill "$pid" 2>/dev/null || true; done <"$TEST_DIR/wl-copy-child"
  fi
  if [[ -f $TEST_DIR/freeze-pids ]]; then
    while IFS= read -r pid; do kill "$pid" 2>/dev/null || true; done <"$TEST_DIR/freeze-pids"
  fi
  rm -rf -- "$TEST_DIR"
}
trap cleanup EXIT

BIN="$TEST_DIR/bin"
STATE="$TEST_DIR/state"
OUT="$TEST_DIR/output"
mkdir -p "$BIN" "$STATE" "$OUT"

cat >"$BIN/hyprctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
state=${MOCK_STATE:?}
log="$state/log"
printf 'hyprctl %s\n' "$*" >>"$log"

created=0; moved=0
[[ -f $state/created ]] && created=1
[[ -f $state/moved ]] && moved=1

if [[ ${1:-} == output && ${2:-} == create ]]; then
  printf '%s\n' "${4:-}" >"$state/output-name"; : >"$state/created"; exit 0
fi
if [[ ${1:-} == output && ${2:-} == remove ]]; then
  rm -f "$state/created" "$state/output-name"; exit 0
fi
if [[ ${1:-} == keyword && ${2:-} == monitor ]]; then exit 0; fi
if [[ ${1:-} == keyword && ${2:-} == cursor:no_hardware_cursors ]]; then exit 0; fi
if [[ ${1:-} == dispatch ]]; then
  if [[ ${2:-} == moveworkspacetomonitor ]]; then
    if [[ ${3:-} == *RETINA-* ]]; then
      : >"$state/moved"
      rm -f "$state/late-shift"
    else
      if [[ -f ${MOCK_TEST_DIR:?}/freeze-pids ]]; then
        freeze_pid=$(tail -n1 "${MOCK_TEST_DIR:?}/freeze-pids")
        if kill -0 "$freeze_pid" 2>/dev/null; then
          printf 'freeze alive during workspace restore\n' >>"$log"
        else
          printf 'freeze missing during workspace restore\n' >>"$log"
        fi
      fi
      rm -f "$state/moved" "$state/late-shift"
    fi
  fi
  exit 0
fi

if [[ ${1:-} == -j && ${2:-} == activewindow ]]; then
  cat <<JSON
{"address":"0xabc","mapped":true,"at":[100,50],"size":[800,600],"workspace":{"id":1,"name":"1"},"floating":false,"monitor":1,"class":"mock-app","xwayland":false,"pinned":false,"fullscreen":0,"fullscreenClient":0}
JSON
  exit 0
fi
if [[ ${1:-} == getoption && ${2:-} == cursor:no_hardware_cursors ]]; then
  printf '{"int":2}\n'
  exit 0
fi
if [[ ${1:-} == -j && ${2:-} == monitors ]]; then
  if ((created)); then
    output_name=$(cat "$state/output-name")
    cat <<JSON
[{"id":1,"name":"DP-1","width":1920,"height":1080,"x":0,"y":0,"scale":1,"transform":0},{"id":2,"name":"$output_name","width":3840,"height":2160,"x":1920,"y":0,"scale":2,"transform":0}]
JSON
  else
    printf '[{"id":1,"name":"DP-1","width":1920,"height":1080,"x":0,"y":0,"scale":1,"transform":0}]\n'
  fi
  exit 0
fi
if [[ ${1:-} == -j && ${2:-} == clients ]]; then
  target_y=100
  if ((moved)); then
    monitor=2; focused_x=2020; target_x=2920
    [[ -f $state/late-shift ]] && target_y=107
  else
    monitor=1; focused_x=100; target_x=1000
  fi
  printf '[{"address":"0xabc","mapped":true,"hidden":false,"at":[%s,50],"size":[800,600],"workspace":{"id":1,"name":"1"},"floating":false,"monitor":%s,"class":"focused-app","xwayland":false,"pinned":false,"fullscreen":0,"fullscreenClient":0,"focusHistoryID":0},{"address":"0xdef","mapped":true,"hidden":false,"at":[%s,%s],"size":[600,500],"workspace":{"id":1,"name":"1"},"floating":false,"monitor":%s,"class":"selected-app","xwayland":false,"pinned":false,"fullscreen":0,"fullscreenClient":0,"focusHistoryID":1}]\n' "$focused_x" "$monitor" "$target_x" "$target_y" "$monitor"
  exit 0
fi
if [[ ${1:-} == -j && ${2:-} == workspaces ]]; then
  if ((moved)); then monitor=$(cat "$state/output-name"); id=2; else monitor=DP-1; id=1; fi
  printf '[{"id":1,"name":"1","monitor":"%s","monitorID":%s}]\n' "$monitor" "$id"
  exit 0
fi
exit 1
MOCK

cat >"$BIN/sleep" <<'MOCK'
#!/usr/bin/env bash
if [[ ${MOCK_LATE_Y_SHIFT:-0} == 1 && ${1:-} == 0.5 ]]; then
  : >"${MOCK_STATE:?}/late-shift"
fi
exec /usr/bin/sleep "$@"
MOCK

cat >"$BIN/omarchy-capture-region" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'picker %s\n' "$*" >>"${MOCK_STATE:?}/log"
printf 'picker-stdin %s\n' "$(readlink /proc/$$/fd/0)" >>"${MOCK_STATE:?}/log"

keep_freeze=0
for arg in "$@"; do
  [[ $arg == --keep-freeze ]] && keep_freeze=1
done

if ((keep_freeze)); then
  /usr/bin/sleep 30 </dev/null >/dev/null 2>&1 &
  freeze_pid=$!
  printf '%s\n' "$freeze_pid" >>"${MOCK_TEST_DIR:?}/freeze-pids"
fi

if [[ ${MOCK_PICKER_HANG:-0} == 1 ]]; then
  printf '%s\n' "$$" >"${MOCK_STATE:?}/picker-pid"
  sleep 30
fi
((keep_freeze)) && printf '%s\n' "$freeze_pid"
[[ ${MOCK_PICKER_CANCEL:-0} == 0 ]] || exit 1
case ${1:-region} in
  region) printf '1100,200 200x150\n' ;;
  windows) printf '1000,100 600x500\n' ;;
  *) exit 1 ;;
esac
MOCK

cat >"$BIN/grim" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'grim %s\n' "$*" >>"${MOCK_STATE:?}/log"
[[ ${MOCK_GRIM_FAIL:-0} == 0 ]] || exit 1
printf 'PNG mock image' >"${@: -1}"
MOCK

cat >"$BIN/wl-copy" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null
printf 'wl-copy %s\n' "$*" >>"${MOCK_STATE:?}/log"
if [[ ${MOCK_WL_COPY_HOLD:-0} == 1 ]]; then
  sleep 30 </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!" >>"${MOCK_TEST_DIR:?}/wl-copy-child"
fi
MOCK

cat >"$BIN/omarchy-notification-send" <<'MOCK'
#!/usr/bin/env bash
printf 'notify %s\n' "$*" >>"${MOCK_STATE:?}/log"
MOCK

chmod +x "$BIN"/* "$SCRIPT"

run_capture() {
  PATH="$BIN:$PATH" \
  MOCK_STATE="$STATE" \
  MOCK_TEST_DIR="$TEST_DIR" \
  XDG_RUNTIME_DIR="$TEST_DIR" \
  RETINASHOT_SETTLE_DELAY="${RETINASHOT_SETTLE_DELAY_OVERRIDE:-0}" \
  RETINASHOT_HYPRCTL_BIN="$BIN/hyprctl" \
  RETINASHOT_GRIM_BIN="$BIN/grim" \
  RETINASHOT_WL_COPY_BIN="$BIN/wl-copy" \
  RETINASHOT_PICKER_BIN="$BIN/omarchy-capture-region" \
    "$SCRIPT" --output-dir "$OUT" "$@"
}

: >"$STATE/log"
result=$(MOCK_WL_COPY_HOLD=1 run_capture)
[[ -f $result ]]
grep -q 'picker region' "$STATE/log"
grep -q 'picker region --keep-freeze' "$STATE/log"
grep -q 'picker-stdin /dev/null' "$STATE/log"
grep -q 'keyword cursor:no_hardware_cursors 0' "$STATE/log"
grep -q 'output create headless RETINA-' "$STATE/log"
grep -q 'keyword monitor RETINA-.*3840x2160@60,auto,2' "$STATE/log"
grep -q 'moveworkspacetomonitor name:1 RETINA-' "$STATE/log"
grep -q 'grim -o RETINA-SCREENSHOT -g 3020,200 200x150' "$STATE/log"
grep -q 'moveworkspacetomonitor name:1 DP-1' "$STATE/log"
grep -q 'freeze alive during workspace restore' "$STATE/log"
grep -q 'output remove RETINA-' "$STATE/log"
grep -q 'focuswindow address:0xabc' "$STATE/log"
grep -q 'keyword cursor:no_hardware_cursors 2' "$STATE/log"
[[ ! -f $STATE/created && ! -f $STATE/moved ]]
freeze_pid=$(tail -n1 "$TEST_DIR/freeze-pids")
! kill -0 "$freeze_pid" 2>/dev/null
(
  exec 8>"$TEST_DIR/retina-screenshot.lock"
  flock -n 8
)

: >"$STATE/log"
result=$(run_capture --window)
[[ -f $result ]]
grep -q 'picker windows' "$STATE/log"
grep -q 'grim -o RETINA-SCREENSHOT -g 2920,100 600x500' "$STATE/log"
[[ ! -f $STATE/created && ! -f $STATE/moved ]]

: >"$STATE/log"
result=$(MOCK_LATE_Y_SHIFT=1 RETINASHOT_SETTLE_DELAY_OVERRIDE=0.5 run_capture)
[[ -f $result ]]
grep -q 'grim -o RETINA-SCREENSHOT -g 3020,207 200x150' "$STATE/log"
[[ ! -f $STATE/created && ! -f $STATE/moved ]]

: >"$STATE/log"
if MOCK_GRIM_FAIL=1 run_capture --window >/dev/null 2>&1; then
  echo "expected grim failure" >&2
  exit 1
fi
grep -q 'moveworkspacetomonitor name:1 DP-1' "$STATE/log"
grep -q 'freeze alive during workspace restore' "$STATE/log"
grep -q 'output remove RETINA-' "$STATE/log"
[[ ! -f $STATE/created && ! -f $STATE/moved ]]
freeze_pid=$(tail -n1 "$TEST_DIR/freeze-pids")
! kill -0 "$freeze_pid" 2>/dev/null

: >"$STATE/log"
result=$(MOCK_PICKER_CANCEL=1 run_capture)
[[ -z $result ]]
freeze_pid=$(tail -n1 "$TEST_DIR/freeze-pids")
! kill -0 "$freeze_pid" 2>/dev/null

: >"$STATE/log"
start_seconds=$SECONDS
result=$(MOCK_PICKER_HANG=1 RETINASHOT_PICKER_TIMEOUT=0.2 run_capture)
[[ -z $result ]]
((SECONDS - start_seconds < 3))
picker_pid=$(cat "$STATE/picker-pid")
! kill -0 "$picker_pid" 2>/dev/null
freeze_pid=$(tail -n1 "$TEST_DIR/freeze-pids")
! kill -0 "$freeze_pid" 2>/dev/null
grep -q 'picker-stdin /dev/null' "$STATE/log"
(
  exec 8>"$TEST_DIR/retina-screenshot.lock"
  flock -n 8
)

printf 'ok: frozen cover, region, late geometry, selected-window, cancellation, bounded picker, lock, and failure cleanup paths\n'
