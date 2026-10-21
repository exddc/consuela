#!/bin/sh
# Tests for consuela. Run from anywhere: ./tests/run.sh
#
# Every case runs consuela with HOME, TMPDIR, and PATH pointing into a
# disposable fixture. Tools that could change data (xcrun, docker, npm,
# poetry, ...) are stubs that record their arguments and exit; they never
# run the real tool.
# ok() takes shell expressions in single quotes on purpose.
# shellcheck disable=SC2016
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
REAL_HOME=$(CDPATH='' cd -P -- "$HOME" && pwd -P)
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/consuela-tests.XXXXXX")
SCRATCH=$(CDPATH='' cd -P -- "$SCRATCH" && pwd -P)
trap 'chmod -R u+rwx "$SCRATCH" 2>/dev/null; rm -rf "$SCRATCH"' EXIT
failed=0
passed=0

fail() {
  echo "FAIL: $*" >&2
  failed=$((failed + 1))
}

pass() {
  passed=$((passed + 1))
}

check() {
  msg=$1
  shift
  if "$@"; then pass; else fail "$msg"; fi
}

contains() {
  printf '%s\n' "$1" | grep -Fq -- "$2"
}

lacks() {
  ! contains "$1" "$2"
}

# Usage: ok <message> <shell expression>, evaluated when called.
ok() {
  msg=$1
  if eval "$2"; then pass; else fail "$msg"; fi
}

# ---- fixture ----------------------------------------------------------

stub() {
  cat >"$T/bin/$1"
  chmod +x "$T/bin/$1"
}

write_stubs() {
  stub xcrun <<'EOF'
#!/bin/sh
S=$CONSUELA_TEST_STATE
echo "xcrun $*" >>"$S/calls"
if [ "$1" = --find ]; then echo /usr/bin/simctl; exit 0; fi
case "$*" in
  *delete*|*erase*)
    echo "xcrun $*" >>"$S/mutations"
    [ ! -f "$S/xcrun_fail" ] || exit 1
    exit 0
    ;;
esac
exit 1
EOF
  stub xcode-select <<'EOF'
#!/bin/sh
echo /Applications/Xcode.app/Contents/Developer
EOF
  stub python3 <<'EOF'
#!/bin/sh
S=$CONSUELA_TEST_STATE
if [ "${1-}" = -m ] && [ "${2-}" = pip ]; then
  echo "python3 $*" >>"$S/calls"
  if [ "${4-}" = dir ]; then echo "$HOME/Library/Caches/pip"; else echo "python3 $*" >>"$S/mutations"; fi
  exit 0
fi
exec /usr/bin/python3 "$@"
EOF
  stub mdfind <<'EOF'
#!/bin/sh
S=$CONSUELA_TEST_STATE
echo "mdfind $*" >>"$S/calls"
[ ! -f "$S/mdfind_fail" ] || exit 1
cat "$S/mdfind" 2>/dev/null
exit 0
EOF
  # Process table: lines of "PID NAME FULL-COMMAND" in $S/procs.
  stub pgrep <<'EOF'
#!/bin/sh
S=$CONSUELA_TEST_STATE
echo "pgrep $*" >>"$S/calls"
[ ! -f "$S/pgrep_fail" ] || exit 3
l=0 x=0 f=0 i=0
while [ $# -gt 1 ]; do
  case "$1" in
    -u) shift ;;
    -*)
      case "$1" in *l*) l=1 ;; esac
      case "$1" in *x*) x=1 ;; esac
      case "$1" in *f*) f=1 ;; esac
      case "$1" in *i*) i=1 ;; esac
      ;;
  esac
  shift
done
pat=$1
[ "$x" = 0 ] || pat="^($pat)\$"
opt=-qE
[ "$i" = 0 ] || opt=-qiE
rc=1
[ -f "$S/procs" ] || exit 1
while read -r pid name args; do
  subj=$name
  [ "$f" = 0 ] || subj=$args
  printf '%s\n' "$subj" | grep "$opt" -- "$pat" || continue
  rc=0
  if [ "$l" = 1 ]; then echo "$pid $subj"; else echo "$pid"; fi
done <"$S/procs"
exit $rc
EOF
  stub docker <<'EOF'
#!/bin/sh
S=$CONSUELA_TEST_STATE
echo "docker $*" >>"$S/calls"
ctx=
if [ "$1" = --context ]; then ctx=$2; shift 2; fi
case "$1 $2" in
  "context inspect")
    [ -f "$S/docker_context" ] || exit 1
    line=$(cat "$S/docker_context")
    if [ $# -ge 5 ]; then
      ep=${line#* }
      [ ! -f "$S/docker_endpoint_later" ] || ep=$(cat "$S/docker_endpoint_later")
      echo "$ep"
    else
      echo "$line"
    fi
    exit 0
    ;;
  "system df")
    [ ! -f "$S/docker_down" ] || { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
    case "$*" in
      *" -v "*) cat "$S/docker_volumes" 2>/dev/null ;;
      *) cat "$S/docker_df" ;;
    esac
    exit 0
    ;;
  "volume inspect")
    for name; do :; done
    awk -F '\t' -v n="$name" '$1 == n { found = 1 } END { exit !found }' "$S/docker_volumes" || exit 1
    echo "$name"
    exit 0
    ;;
  "ps -a")
    [ ! -f "$S/docker_ps_fail" ] || exit 1
    name=
    for a; do case "$a" in volume=*) name=${a#volume=} ;; esac; done
    n=$(($(cat "$S/ps_count_$name" 2>/dev/null || echo 0) + 1))
    echo "$n" >"$S/ps_count_$name"
    cat "$S/docker_users_$name" 2>/dev/null
    if [ "$n" -ge 2 ] && [ -f "$S/docker_users_later_$name" ]; then
      cat "$S/docker_users_later_$name"
    fi
    exit 0
    ;;
esac
echo "docker --context $ctx $*" >>"$S/mutations"
exit 0
EOF
}

# Optional stubs for tools a case wants "installed".
stub_poetry() {
  stub poetry <<'EOF'
#!/bin/sh
S=$CONSUELA_TEST_STATE
echo "poetry $*" >>"$S/calls"
case "$*" in
  "config cache-dir") cat "$S/poetry_cache_dir" ;;
  "config virtualenvs.path") cat "$S/poetry_venvs" ;;
  *) echo "poetry $*" >>"$S/mutations" ;;
esac
EOF
}

stub_npm() {
  stub npm <<'EOF'
#!/bin/sh
S=$CONSUELA_TEST_STATE
echo "npm $*" >>"$S/calls"
case "$*" in
  "config get cache") cat "$S/npm_cache" ;;
  *) echo "npm $*" >>"$S/mutations" ;;
esac
EOF
}

stub_brew() {
  stub brew <<'EOF'
#!/bin/sh
S=$CONSUELA_TEST_STATE
echo "brew $*" >>"$S/calls"
case "$*" in
  --cache) cat "$S/brew_cache" ;;
  *) echo "brew $*" >>"$S/mutations" ;;
esac
EOF
}

mkfile_kb() {
  mkdir -p "${1%/*}"
  dd if=/dev/zero of="$1" bs=1024 count="$2" 2>/dev/null
}

# Builds the fake home. Sizes are small; names match what consuela looks for.
build_home() {
  L=$H/Library
  mkfile_kb "$L/Developer/XCTestDevices/AAAA/data/blob" 64
  printf 'x' >"$L/Developer/XCTestDevices/AAAA/device.plist"
  mkfile_kb "$L/Developer/Xcode/DerivedData/App-abc/Build/blob" 32
  mkfile_kb "$L/Developer/Xcode/UserData/KeyBindings/custom.idekeybindings" 1

  P="$L/Developer/Xcode/UserData/Previews"
  mkfile_kb "$P/Simulator Devices/6DB69134/data/blob" 128
  printf 'x' >"$P/Simulator Devices/6DB69134/device.plist"
  mkfile_kb "$P/Simulator Devices/1B35F9D4/data/orphan" 256
  mkfile_kb "$P/Simulator%20Devices/6DB69134/data/blob" 8

  W="$L/Developer/XcodeBuildMCP/workspaces"
  ws="$W/Proj One-aaaa"
  mkfile_kb "$ws/DerivedData/Proj-hash/Build/blob" 96
  printf 'plist' >"$ws/DerivedData/Proj-hash/info.plist"
  mkfile_kb "$ws/DerivedData/ModuleCache.noindex/m" 16
  mkdir -p "$ws/locks"
  mkfile_kb "$ws/state/daemon/state.json" 1
  mkfile_kb "$ws/logs/build.log" 1
  mkfile_kb "$ws/result-bundles/r.xcresult/x" 1
  mkfile_kb "$ws/Sources/main.swift" 1
  tp="$ws/test-products"
  done_tp="$tp/test_sim_2026-07-27T19-50-41-066Z_pid99999999_e9554cbb.xctestproducts"
  mkfile_kb "$done_tp/Tests.xctestrun" 40
  echo 1785181965827 >"$done_tp.xcodebuildmcp-completed"
  dead_tp="$tp/test_sim_2026-07-27T20-09-59-932Z_pid99999998_7fef48b3.xctestproducts"
  mkfile_kb "$dead_tp/Tests.xctestrun" 24
  live_tp="$tp/test_sim_2026-07-27T20-10-07-440Z_pid$$_423bceb5.xctestproducts"
  mkfile_kb "$live_tp/Tests.xctestrun" 24
  mkfile_kb "$tp/notes.txt" 1
  mkfile_kb "$tp/odd name.xctestproducts/x" 4

  locked="$W/Locked-bbbb"
  mkfile_kb "$locked/DerivedData/P-hash/Build/blob" 16
  printf 'plist' >"$locked/DerivedData/P-hash/info.plist"
  mkfile_kb "$locked/locks/filesystem-lifecycle.lock/owner.json" 1

  weird="$W/Weird-cccc"
  mkfile_kb "$weird/DerivedData/random-user-file.txt" 8

  esc="$W/Escape-dddd"
  mkdir -p "$esc"
  mkfile_kb "$T/outside/dd/P-hash/Build/blob" 16
  printf 'plist' >"$T/outside/dd/P-hash/info.plist"
  ln -s "$T/outside/dd" "$esc/DerivedData"
  mkfile_kb "$T/outside/tp/test_sim_2026-07-27T21-00-00-000Z_pid99999997_aaaaaaaa.xctestproducts/x" 8
  ln -s "$T/outside/tp" "$esc/test-products"

  C=$L/Caches
  mkfile_kb "$C/pypoetry/cache/repositories/PyPI/_http/blob" 40
  mkfile_kb "$C/pypoetry/artifacts/ab/cd/pkg.whl" 40
  mkfile_kb "$C/pypoetry/virtualenvs/proj-py3.12/bin/python" 12

  O="$C/com.electron.ollama.ShipIt"
  mkfile_kb "$O/update.0MmZxDP/Ollama.app/Contents/blob" 64
  mkfile_kb "$O/update.2hlOt45/Ollama.app/Contents/blob" 64
  printf '%s' '{"launchAfterInstallation":false,"updateBundleURL":"file:\/\/\/x\/update.IExnDor\/Ollama.app\/","useUpdateBundleName":true,"bundleIdentifier":"com.electron.ollama","targetBundleURL":"file:\/\/\/Applications\/Ollama.app\/"}' >"$O/ShipItState.plist"

  CU="$C/com.todesktop.230313mzl4w4u92.ShipIt"
  mkfile_kb "$CU/update.I0j8oPc/Cursor.app/Contents/blob" 48
  mkfile_kb "$CU/update.9ZXKO8n/Cursor.app/Contents/blob" 48
  printf '{"launchAfterInstallation":false,"updateBundleURL":"file:\\/\\/%s\\/update.I0j8oPc\\/Cursor.app\\/","useUpdateBundleName":true,"bundleIdentifier":"com.todesktop.230313mzl4w4u92","targetBundleURL":"file:\\/\\/\\/Applications\\/Cursor.app\\/"}' \
    "$(printf '%s' "$CU" | sed 's:/:\\/:g')" >"$CU/ShipItState.plist"

  R="$C/Raspberry Pi/Imager"
  mkfile_kb "$R/lastdownload.cache" 72
  mkfile_kb "$R/qmlcache/a.qmlc" 2
  mkfile_kb "$R/oslistcache0/list.json" 1

  mkfile_kb "$C/ms-playwright/chromium-1228/blob" 8
  mkfile_kb "$H/.npm/_cacache/blob" 16
  mkfile_kb "$L/Application Support/Notion/Partitions/notion/Cache/blob" 8
  mkfile_kb "$L/Application Support/Autodesk/webdeploy/production/024afa2c/Autodesk Fusion.app/x" 8
  mkfile_kb "$L/Application Support/Autodesk/webdeploy/production/bb8a77c5/Autodesk Fusion.app/x" 8
  ln -s "$L/Application Support/Autodesk/webdeploy/production/024afa2c/Autodesk Fusion.app" \
    "$L/Application Support/Autodesk/webdeploy/production/Autodesk Fusion.app"
  mkfile_kb "$H/Projects/openchime/scripts/buildroot_chime.sh" 1
}

# The exact Docker state observed on the developer Mac.
docker_observed() {
  echo "desktop-linux unix://$H/.docker/run/docker.sock" >"$S/docker_context"
  printf 'Images\t563.1MB\t0B (0%%)\nContainers\t0B\t0B\nLocal Volumes\t6.844GB\t6.844GB (100%%)\nBuild Cache\t4.503GB\t4.009GB\n' >"$S/docker_df"
  printf 'openchime-buildroot-cache\t0\t6.844GB\n' >"$S/docker_volumes"
}

setup() {
  T=$(mktemp -d "$SCRATCH/case.XXXXXX")
  H=$T/home
  S=$T/state
  mkdir -p "$H" "$S" "$T/bin" "$T/tmp" "$T/apps/Xcode.app/Contents/Developer"
  : >"$S/calls"
  if [ "$H" = "$REAL_HOME" ] || [ "${H#"$REAL_HOME"/}" != "$H" ]; then
    echo "refusing to run: fixture HOME is inside the real HOME" >&2
    exit 2
  fi
  printf '{"devices": {}}' >"$S/devices.json"
  printf '{}' >"$S/runtime_images.json"
  printf '{"runtimes": []}' >"$S/runtimes.json"
  write_stubs
  build_home
  docker_observed
}

# Usage: run [consuela args...]. Stdin comes from $STDIN (default /dev/null).
run() {
  env -i HOME="$H" TMPDIR="$T/tmp" PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin" LANG=C \
    CONSUELA_TEST_STATE="$S" \
    CONSUELA_FIXTURE_XCODE_APPS="${XCODE_APPS:-$T/apps/Xcode.app}" \
    CONSUELA_FIXTURE_DEVICES="$S/devices.json" \
    CONSUELA_FIXTURE_RUNTIME_IMAGES="$S/runtime_images.json" \
    CONSUELA_FIXTURE_RUNTIMES="$S/runtimes.json" \
    "$ROOT/consuela" "$@" <"${STDIN:-/dev/null}" >"$S/out" 2>"$S/err"
  ST=$?
  OUT=$(cat "$S/out")
  ERR=$(cat "$S/err")
}

# Like run, on a terminal, answering prompts. Usage: run_tty 'PROMPT=ANSWER'... -- args
run_tty() {
  answers=
  while [ "$1" != -- ]; do
    answers="$answers$1$TABSEP"
    shift
  done
  shift
  old_ifs=$IFS
  IFS=$TABSEP
  # shellcheck disable=SC2086
  set -- $answers -- env -i HOME="$H" TMPDIR="$T/tmp" PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin" LANG=C \
    CONSUELA_TEST_STATE="$S" \
    CONSUELA_FIXTURE_XCODE_APPS="$T/apps/Xcode.app" CONSUELA_FIXTURE_DEVICES="$S/devices.json" \
    CONSUELA_FIXTURE_RUNTIME_IMAGES="$S/runtime_images.json" CONSUELA_FIXTURE_RUNTIMES="$S/runtimes.json" \
    "$ROOT/consuela" "$@"
  IFS=$old_ifs
  OUT=$(/usr/bin/python3 "$ROOT/tests/pty_drive.py" "$@" </dev/null 2>&1)
  ST=$?
  ERR=$OUT
}
TABSEP=$(printf '\t')

# Paths, types, symlink targets, and content hashes under $T, except state.
inventory() {
  (
    cd "$T" || exit 1
    find home outside apps 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then
        printf '%s L %s\n' "$p" "$(readlink "$p")"
      elif [ -f "$p" ]; then
        printf '%s F %s\n' "$p" "$(shasum -a 256 <"$p" | cut -c1-16)"
      else
        printf '%s D\n' "$p"
      fi
    done
  )
}

mutations() {
  cat "$S/mutations" 2>/dev/null
}

# Fails if any docker call could change state.
docker_read_only() {
  ! grep '^docker ' "$S/calls" |
    grep -vE '^docker (context inspect|--context [^ ]+ (system df|volume inspect|ps -a))' |
    grep -q .
}

# ---- cases ------------------------------------------------------------

echo "== lint"
for f in "$ROOT/consuela" "$ROOT/install.sh" "$ROOT/tests/run.sh"; do
  check "sh -n $f" sh -n "$f"
done
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck" shellcheck -s sh "$ROOT/consuela" "$ROOT/install.sh" "$ROOT/tests/run.sh"
else
  echo "shellcheck not installed; skipped"
fi

echo "== dry run and report change nothing"
setup
before=$(inventory)
for args in "--dry-run" "--dry-run --xcode" "--dry-run --cache" "--dry-run --docker" \
  "--dry-run --docker-dangling" "--dry-run --xcode-previews" "--dry-run --xcodebuildmcp" \
  "--dry-run --docker-volume openchime-buildroot-cache" \
  "--dry-run -y --xcode-previews --xcodebuildmcp --cache --xcode --docker" \
  "--report" "--report -y"; do
  # shellcheck disable=SC2086
  run $args
  check "$args exits 0 (got $ST: $ERR)" [ "$ST" -eq 0 ]
  check "$args never prompts" lacks "$OUT" "Proceed?"
  check "$args runs no cleanup command: $(mutations)" [ -z "$(mutations)" ]
  check "$args uses only read-only docker commands" docker_read_only
  case "$args" in
    --report*) check "$args says nothing deleted" contains "$OUT" "Report only: nothing deleted." ;;
    *) check "$args says nothing deleted" contains "$OUT" "Dry run: nothing deleted." ;;
  esac
done
check "dry runs and reports leave every fixture file unchanged" [ "$before" = "$(inventory)" ]

run --dry-run
for optin in "Xcode Previews" XcodeBuildMCP "Docker volume openchime"; do
  check "default run leaves out opt-in $optin" lacks "$OUT" "$optin"
done
check "default run still lists the existing groups" contains "$OUT" "XCTestDevices"

echo "== report contents"
run --report -y
check "report lists opt-in previews with its flag" contains "$OUT" "--xcode-previews"
check "report lists the volume as kept" contains "$OUT" "openchime-buildroot-cache  (no containers use it)"
check "report shows Cursor's pending update" contains "$OUT" "pending install: update.I0j8oPc"
check "report marks the active Fusion install" contains "$OUT" "active Fusion install"
check "report lists the dyld cache only for review" contains "$OUT" "no supported cleanup"
check "report shows Docker df rows unsummed" contains "$OUT" "Build Cache: 4.503GB total, 4.009GB reclaimable"
check "report lists Poetry virtualenvs as kept" contains "$OUT" "--cache keeps them"
default_line=$(printf '%s\n' "$OUT" | grep '^Default run')
check "default total holds Docker's ~3.7G estimate, not the volume: $default_line" contains "$default_line" "~3.7G estimated"
check "default total leaves out the 6.4G volume" lacks "$default_line" "6.4G"
run --report --xcode
check "--report rejects group flags" [ "$ST" -eq 1 ]

echo "== XcodeBuildMCP keeps state, locks, sources, active runs"
setup
outside_before=$(cd "$T" && find outside | LC_ALL=C sort)
run -y --xcodebuildmcp
check "xcodebuildmcp run exits 0 ($ST: $ERR)" [ "$ST" -eq 0 ]
ws="$H/Library/Developer/XcodeBuildMCP/workspaces/Proj One-aaaa"
ok "DerivedData contents removed" '[ -d "$ws/DerivedData" ] && [ -z "$(ls -A "$ws/DerivedData")" ]'
ok "completed test products removed" '[ ! -e "$done_tp" ] && [ ! -e "$done_tp.xcodebuildmcp-completed" ]'
check "dead-owner test products removed" [ ! -e "$dead_tp" ]
check "live-owner test products kept" [ -d "$live_tp" ]
ok "unrecognized test-products entries kept" '[ -f "$tp/notes.txt" ] && [ -d "$tp/odd name.xctestproducts" ]'
for keep in state/daemon/state.json logs/build.log result-bundles/r.xcresult/x Sources/main.swift; do
  check "workspace keeps $keep" [ -f "$ws/$keep" ]
done
check "locks folder kept" [ -d "$ws/locks" ]
check "locked workspace untouched" [ -f "$locked/DerivedData/P-hash/Build/blob" ]
check "unrecognized DerivedData untouched" [ -f "$weird/DerivedData/random-user-file.txt" ]
check "symlinked DerivedData target untouched" [ "$outside_before" = "$(cd "$T" && find outside | LC_ALL=C sort)" ]
check "symlink escape warned" contains "$ERR" "skipping unsafe path: $H/Library/Developer/XcodeBuildMCP/workspaces/Escape-dddd"
check "Xcode user data untouched" [ -f "$H/Library/Developer/Xcode/UserData/KeyBindings/custom.idekeybindings" ]

echo "== XcodeBuildMCP process forces the prompt even with -y"
setup
echo "4242 node node $T/lib/node_modules/xcodebuildmcp/build/cli.js mcp" >"$S/procs"
before=$(inventory)
STDIN=$S/no; echo n >"$STDIN"
run -y --xcodebuildmcp
STDIN=
check "prompt shown with -y while XcodeBuildMCP runs" contains "$OUT" "Xcode tools running: XcodeBuildMCP"
check "declined prompt exits 1" [ "$ST" -eq 1 ]
check "declined prompt deletes nothing" [ "$before" = "$(inventory)" ]

echo "== Xcode Previews use simctl on the exact set"
setup
run -y --xcode-previews
check "previews run exits 0 ($ERR)" [ "$ST" -eq 0 ]
check "previews deleted through simctl --set" contains "$(mutations)" "xcrun simctl --set $H/Library/Developer/Xcode/UserData/Previews/Simulator Devices delete all"
previews_kb=$(printf '%s\n' "$OUT" | awk '/K  Xcode Previews simulators/ { sub(/K$/, "", $1); print $1 }')
ok "previews size counts registered devices only (got ${previews_kb}K)" '[ "${previews_kb:-0}" -ge 128 ] && [ "$previews_kb" -lt 256 ]'
check "Simulator%20Devices left alone" [ -f "$P/Simulator%20Devices/6DB69134/data/blob" ]
setup
rm -rf "$P/Simulator Devices"
mkdir -p "$T/outside/set/D/data"
ln -s "$T/outside/set" "$P/Simulator Devices"
run -y --xcode-previews
check "symlinked Previews set rejected" contains "$ERR" "skipping unsafe path"
check "symlinked Previews set not deleted" [ -z "$(mutations)" ]

echo "== Poetry keeps virtualenvs"
setup
run -y --cache
check "cache run exits 0 ($ERR)" [ "$ST" -eq 0 ]
check "Poetry cache emptied" [ -z "$(ls -A "$C/pypoetry/cache")" ]
check "Poetry artifacts emptied" [ -z "$(ls -A "$C/pypoetry/artifacts")" ]
check "Poetry virtualenvs kept" [ -f "$C/pypoetry/virtualenvs/proj-py3.12/bin/python" ]
setup
stub_poetry
echo "$C/pypoetry" >"$S/poetry_cache_dir"
echo "$C/pypoetry/cache/virtualenvs" >"$S/poetry_venvs"
mkfile_kb "$C/pypoetry/cache/virtualenvs/env/bin/python" 4
run -y --cache
check "virtualenvs inside Poetry cache stops that wipe" contains "$ERR" "skipping Poetry cache: virtualenvs.path"
check "virtualenv inside cache kept" [ -f "$C/pypoetry/cache/virtualenvs/env/bin/python" ]
check "Poetry artifacts still cleaned" [ -z "$(ls -A "$C/pypoetry/artifacts")" ]
check "no poetry cache command ran" [ -z "$(mutations | grep poetry)" ]

echo "== pending updates of installed apps are never planned"
setup
app_caches() {
  (cd "$T" && find home/Library/Caches/*.ShipIt "home/Library/Caches/Raspberry Pi" | LC_ALL=C sort)
}
app_before=$(app_caches)
run -y --xcode --cache --xcode-previews --xcodebuildmcp
check "ShipIt and Imager caches untouched by every flag" [ "$app_before" = "$(app_caches)" ]
check "Cursor ShipIt never in a plan" lacks "$OUT" "todesktop"
check "Ollama ShipIt never in a plan" lacks "$OUT" "ollama"
check "Imager cache never in a plan" lacks "$OUT" "Raspberry Pi"
run --report
check "report lists Ollama's staged updates for review" contains "$OUT" "com.electron.ollama.ShipIt"
setup
printf 'garbage' >"$CU/ShipItState.plist"
run --report
check "malformed Cursor state reported, not guessed" contains "$OUT" "ShipItState.plist unreadable"

echo "== Docker: observed state"
setup
run --dry-run --docker
check "docker estimate ~3.7G from reclaimable rows" contains "$OUT" "3.7G  Docker unused images"
check "This run excludes the volume" contains "$OUT" "This run:   ~3.7G estimated"
check "volume reported as kept" contains "$OUT" "6.4G  openchime-buildroot-cache  (no containers use it)"
check "volume report names the context" contains "$OUT" "context desktop-linux, unix://$H/.docker/run/docker.sock"
setup
run -y --docker
check "--docker prunes with pinned context" contains "$(mutations)" "docker --context desktop-linux system prune -af"
check "--docker never removes volumes" lacks "$(mutations)" "volume"

echo "== Docker: volume-only mode"
setup
run --dry-run --docker-volume openchime-buildroot-cache
check "volume-only plan lists the volume" contains "$OUT" "6.4G  Docker volume openchime-buildroot-cache"
check "volume-only does not scan Xcode" lacks "$(cat "$S/calls")" "xcrun"
check "volume-only does not scan caches" lacks "$OUT" "Poetry"
check "volume-only does not prune" lacks "$(cat "$S/calls")" "system df --format {{.Type}}"
run -y --docker-volume openchime-buildroot-cache
check "-y without a terminal keeps the volume" [ -z "$(mutations)" ]
check "-y without a terminal exits 1" [ "$ST" -eq 1 ]
check "-y without a terminal says why" contains "$ERR" "needs its name typed at a terminal"
setup
run_tty 'Type the volume name to delete it: =openchime-buildroot-cache' -- -y --docker-volume openchime-buildroot-cache
check "typed name deletes the volume ($OUT)" [ "$(mutations)" = "docker --context desktop-linux volume rm openchime-buildroot-cache" ]
check "typed name exits 0" [ "$ST" -eq 0 ]
setup
run_tty 'Type the volume name to delete it: =yes' -- -y --docker-volume openchime-buildroot-cache
check "wrong typed answer keeps the volume" [ -z "$(mutations)" ]
setup
echo abc123 >"$S/docker_users_later_openchime-buildroot-cache"
run_tty 'Type the volume name to delete it: =openchime-buildroot-cache' -- -y --docker-volume openchime-buildroot-cache
check "volume used after the scan is kept" [ -z "$(mutations)" ]
check "volume used after the scan fails the run" [ "$ST" -eq 1 ]
setup
echo "unix:///other.sock" >"$S/docker_endpoint_later"
run_tty 'Type the volume name to delete it: =openchime-buildroot-cache' -- -y --docker-volume openchime-buildroot-cache
check "changed context endpoint keeps the volume" [ -z "$(mutations)" ]
setup
printf 'openchime-buildroot-cache\t1\t6.844GB\n' >"$S/docker_volumes"
run --dry-run --docker-volume openchime-buildroot-cache
check "linked volume refused" contains "$ERR" "is used by a container"
check "linked volume not planned" contains "$OUT" "Nothing to clean."
setup
echo abc >"$S/docker_users_openchime-buildroot-cache"
run --dry-run --docker-volume openchime-buildroot-cache
check "volume with a stopped container refused" contains "$OUT" "Nothing to clean."
setup
: >"$S/docker_ps_fail"
run --dry-run --docker-volume openchime-buildroot-cache
check "usage query failure keeps the volume" contains "$ERR" "cannot list containers"
setup
printf 'openchime-buildroot-cache\t0\t6.844GB\nother-vol\t0\tN/A\n' >"$S/docker_volumes"
run --dry-run --docker-volume openchime-buildroot-cache --docker-volume other-vol --docker-volume other-vol
check "two named volumes planned once each" [ "$(printf '%s\n' "$OUT" | grep -c 'Docker volume [a-z-]* (docker volume rm')" -eq 2 ]
check "unknown size is not counted as zero" contains "$OUT" "plus 1 item(s) of unknown size"
check "unknown size marked ?" contains "$OUT" "?  Docker volume other-vol"
run --dry-run --docker-volume -rf
check "invalid volume name is a usage error" [ "$ST" -eq 1 ]
run --dry-run --docker-volume missing-vol
check "missing volume skipped" contains "$ERR" "missing-vol not found"

echo "== Docker: contexts"
setup
: >"$S/docker_down"
run --dry-run --docker
ok "stopped Docker warns and exits 0" '[ "$ST" -eq 0 ] && contains "$ERR" "docker is not reachable"'
setup
echo "orbstack unix://$H/.orbstack/run/docker.sock" >"$S/docker_context"
run -y --docker
check "OrbStack local context pruned with its name" contains "$(mutations)" "docker --context orbstack system prune -af"
setup
echo "remote ssh://build@example" >"$S/docker_context"
run -y --docker
ok "-y skips a remote endpoint" 'contains "$ERR" "is not a local unix:// socket" && [ -z "$(mutations)" ]'
run_tty 'Proceed? [y/N] =y' 'Type the volume name to delete it: =openchime-buildroot-cache' -- --docker-volume openchime-buildroot-cache
ok "volume deletion refused on a remote endpoint" 'contains "$OUT" "refusing to delete Docker volumes" && [ -z "$(mutations)" ]'
setup
echo "weird <no value>" >"$S/docker_context"
run -y --docker
ok "-y skips an unknown endpoint" 'contains "$ERR" "docker endpoint unknown" && [ -z "$(mutations)" ]'

echo "== totals and overlap"
setup
stub_npm
echo "$C/pypoetry/cache" >"$S/npm_cache"
run --dry-run --cache
check "overlapping cache paths warned" contains "$ERR" "skipping $C/pypoetry/cache: overlaps $C/pypoetry/cache/"

echo "== npm and npx"
setup
stub_npm
echo "$H/.npm" >"$S/npm_cache"
mkfile_kb "$H/.npm/_npx/0a1b/node_modules/pkg/index.js" 300
mkfile_kb "$H/.npm/_logs/debug.log" 200
run --dry-run --cache
check "npm line counts only _cacache" contains "$OUT" "16K  npm cache clean --force"
check "npx cache planned separately" contains "$OUT" "300K  npx package cache"
run -y --cache
check "npm cache clean ran" contains "$(mutations)" "npm cache clean --force"
check "npx cache emptied" [ -z "$(ls -A "$H/.npm/_npx")" ]
check "npm logs kept" [ -f "$H/.npm/_logs/debug.log" ]

echo "== unsafe paths"
setup
stub_brew
echo "$H" >"$S/brew_cache"
before=$(inventory)
run -y --cache
check "brew cache at HOME refused" contains "$ERR" "skipping unsafe path: $H"
check "HOME left intact" [ -f "$H/Projects/openchime/scripts/buildroot_chime.sh" ]
echo / >"$S/brew_cache"
run --dry-run --cache
check "brew cache at / refused" contains "$ERR" "skipping unsafe path: /"
(
  HOME=$H
  # shellcheck source=../consuela disable=SC1091
  . "$ROOT/consuela"
  w="$HOME_REAL/$MCP_WORKSPACES_REL"
  mcp_generated_path "$w/a/DerivedData" DerivedData || exit 1
  ! mcp_generated_path "$w/a/b/DerivedData" DerivedData || exit 2
  ! mcp_generated_path "$w/DerivedData" DerivedData || exit 3
  ! mcp_generated_path "$w/../DerivedData" DerivedData || exit 4
  ! path_is_allowed "$HOME" || exit 5
  ! path_is_allowed / || exit 6
  ! path_is_allowed_real "$HOME_REAL/Library/Developer/Xcode/UserData" || exit 7
  ! path_is_allowed_real "$HOME_REAL/Library/Developer/Xcode/UserData/Previews" || exit 8
)
check "allowlist accepts only exact generated paths (case $?)" [ $? -eq 0 ]

echo "== paths swapped for symlinks between plan and action"
setup
mkfile_kb "$T/outside/victim/keep" 4
swap_dd="$ws/DerivedData"
swap_tp=$done_tp
(
  HOME=$H TMPDIR=$T/tmp PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin" CONSUELA_TEST_STATE=$S
  export HOME TMPDIR PATH CONSUELA_TEST_STATE
  # shellcheck source=../consuela disable=SC1091
  . "$ROOT/consuela"
  plan_init
  scan_xcodebuildmcp 2>/dev/null
  mv "$swap_dd" "$T/moved-dd"
  ln -s "$T/outside/victim" "$swap_dd"
  mv "$swap_tp" "$T/moved-tp"
  ln -s "$T/outside/victim" "$swap_tp"
  run_plan >/dev/null 2>&1
  rm -rf "$PLAN_DIR"
  [ "$FAIL_COUNT" -ge 2 ] || exit 1
)
check "swapped paths fail their steps" [ $? -eq 0 ]
check "symlink targets untouched after swap" [ -f "$T/outside/victim/keep" ]
ok "swapped links themselves left in place" '[ -L "$ws/DerivedData" ] && [ -L "$done_tp" ]'

echo "== permission failure and missing paths"
setup
mkfile_kb "$C/pypoetry/artifacts/locked/inner/x" 4
chmod 000 "$C/pypoetry/artifacts/locked"
run -y --cache
chmod -R u+rwx "$C/pypoetry/artifacts/locked" 2>/dev/null
check "permission failure exits 1" [ "$ST" -eq 1 ]
check "permission failure names the step" contains "$ERR" "failed: Poetry cache and artifacts"
setup
rm -rf "$H/Library" "$H/.npm"
mkdir -p "$H/Library"
for flag in --xcode-previews --xcodebuildmcp --cache; do
  run -y "$flag"
  check "$flag with missing paths: nothing to clean ($ERR)" contains "$OUT" "Nothing to clean."
done

echo "== existing guards"
setup
printf '{"devices": {"r": [{"isAvailable": false, "dataPathSize": 1048576}]}}' >"$S/devices.json"
mkdir -p "$T/apps/Xcode-beta.app/Contents/Developer"
NL='
'
XCODE_APPS="$T/apps/Xcode.app$NL$T/apps/Xcode-beta.app"
run --dry-run --xcode
XCODE_APPS=
ok "multiple Xcodes skip unavailable simulators" 'contains "$ERR" "found 2 Xcodes" && lacks "$OUT" "Unavailable simulators"'
setup
echo "55 xcodebuild /usr/bin/xcodebuild test" >"$S/procs"
STDIN=$S/no; echo n >"$STDIN"
before=$(inventory)
run -y --xcode
STDIN=
check "running xcodebuild forces the prompt" contains "$OUT" "Xcode tools running: xcodebuild"
ok "declining keeps Xcode data" '[ "$before" = "$(inventory)" ] && [ "$ST" -eq 1 ]'
setup
: >"$S/xcrun_fail"
run -y --xcode
ok "failed simctl step exits 1" '[ "$ST" -eq 1 ] && contains "$ERR" "failed: XCTestDevices"'
run --update --dry-run
ok "--update rejects other arguments" '[ "$ST" -eq 1 ] && contains "$ERR" "--update must be the only argument"'

echo "== version and Homebrew installs"
run --version
ok "--version prints the version" '[ "$ST" -eq 0 ] && [ "$OUT" = "consuela $(sed -n "s/^VERSION=//p" "$ROOT/consuela")" ]'
run --version --dry-run
ok "--version rejects other arguments" '[ "$ST" -eq 1 ] && contains "$ERR" "--version must be the only argument"'
setup
stub curl <<'EOF'
#!/bin/sh
echo called >>"$CONSUELA_TEST_STATE/curl"
exit 1
EOF
mkdir -p "$T/cellar/bin"
sed 's/^INSTALL_METHOD=script$/INSTALL_METHOD=brew/' "$ROOT/consuela" >"$T/cellar/bin/consuela"
chmod +x "$T/cellar/bin/consuela"
ln -s "$T/cellar/bin/consuela" "$T/bin/consuela"
brew_before=$(cksum <"$T/cellar/bin/consuela")
env -i HOME="$H" TMPDIR="$T/tmp" PATH="$T/bin:/usr/bin:/bin" LANG=C CONSUELA_TEST_STATE="$S" \
  consuela --update >"$S/out" 2>"$S/err"
ST=$?
OUT=$(cat "$S/out")
check "brew --update exits 0 ($ST: $(cat "$S/err"))" [ "$ST" -eq 0 ]
check "brew --update points to brew upgrade" contains "$OUT" "brew upgrade consuela"
check "brew --update leaves the install alone" [ "$brew_before" = "$(cksum <"$T/cellar/bin/consuela")" ]
check "brew --update downloads nothing" [ ! -e "$S/curl" ]
rm "$T/bin/consuela"
cp "$ROOT/consuela" "$T/bin/consuela"
env -i HOME="$H" TMPDIR="$T/tmp" PATH="$T/bin:/usr/bin:/bin" LANG=C CONSUELA_TEST_STATE="$S" \
  consuela --update >"$S/out" 2>"$S/err"
ST=$?
check "script --update downloads the installer" [ -e "$S/curl" ]
check "failed download fails the update" [ "$ST" -eq 1 ]

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
