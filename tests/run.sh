#!/bin/sh
# Unit tests for consuela. Run from anywhere: ./tests/run.sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURES="$ROOT/tests/fixtures"
failed=0

assert_eq() {
  got=$1
  want=$2
  msg=$3
  if [ "$got" != "$want" ]; then
    echo "FAIL: $msg (got '$got', want '$want')" >&2
    failed=$((failed + 1))
  fi
}

assert_ok() {
  msg=$1
  st=$2
  if [ "$st" -ne 0 ]; then
    echo "FAIL: $msg" >&2
    failed=$((failed + 1))
  fi
}

assert_fail() {
  msg=$1
  st=$2
  if [ "$st" -eq 0 ]; then
    echo "FAIL: $msg (expected non-zero exit)" >&2
    failed=$((failed + 1))
  fi
}

status_of() {
  set +e
  "$@"
  st=$?
  set -e
  echo "$st"
}

has_re() {
  printf '%s\n' "$1" | grep -qE -- "$2"
}

has_str() {
  printf '%s\n' "$1" | grep -Fq -- "$2"
}

echo "== shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -s sh "$ROOT/consuela" "$ROOT/install.sh" "$ROOT/tests/run.sh"; then
    echo "ok shellcheck"
  else
    echo "FAIL: shellcheck" >&2
    failed=$((failed + 1))
  fi
else
  echo "FAIL: shellcheck is not installed" >&2
  failed=$((failed + 1))
fi

echo "== fmt_kb, plan, clear_dir"
# shellcheck source=../consuela disable=SC1091
. "$ROOT/consuela"

assert_eq "$(fmt_kb 0)" "0B" "fmt_kb 0"
assert_eq "$(fmt_kb 1)" "1K" "fmt_kb 1K"
assert_eq "$(fmt_kb 1024)" "1.0M" "fmt_kb 1.0M"
assert_eq "$(fmt_kb 1048576)" "1.0G" "fmt_kb 1.0G"

plan_init
add xcode 1024 "DerivedData" clear_dir "/tmp/does-not-matter"
add xcode 10 "Unavailable runtime iOS-16-0" runtime_unavailable "id,with,commas"
add cache 0 "skip me" clear_dir "$HOME"
assert_eq "$PLAN_COUNT" "2" "add skips 0 kb"
assert_eq "$(sed -n '1p' "$(plan_rec 1)/size")" "$(fmt_kb 1024)" "plan stores fmt_kb size"
assert_eq "$(cat "$(plan_rec 2)/arg")" "id,with,commas" "runtime id is not comma-split"
assert_eq "$(sum_plan_kb)" "1034" "sum_plan_kb"
rm -rf "$PLAN_DIR"

err=$(mktemp)
st=$(status_of clear_dir "$HOME" 2>"$err")
assert_fail "clear_dir refuses \$HOME" "$st"
st=$(status_of grep -q "unsafe path" "$err")
assert_ok "clear_dir \$HOME prints refusal" "$st"

st=$(status_of clear_dir / 2>"$err")
assert_fail "clear_dir refuses /" "$st"

st=$(status_of path_is_allowed "$HOME")
assert_fail "path_is_allowed refuses \$HOME" "$st"

st=$(status_of path_is_allowed /)
assert_fail "path_is_allowed refuses /" "$st"

safe="$HOME/Library/Caches/consuela-test-$$"
mkdir -p "$safe/sub"
echo keep-dir >"$safe/sub/file"
st=$(status_of clear_dir "$safe")
assert_ok "clear_dir allowlisted cache" "$st"
if [ ! -d "$safe" ]; then
  echo "FAIL: clear_dir removed the allowlisted directory" >&2
  failed=$((failed + 1))
fi
if [ -e "$safe/sub" ]; then
  echo "FAIL: clear_dir left contents in allowlisted dir" >&2
  failed=$((failed + 1))
fi
rmdir "$safe" 2>/dev/null || rm -rf "$safe"

link="$HOME/Library/Caches/consuela-symlink-test-$$"
ln -s "$HOME" "$link"
st=$(status_of clear_dir "$link" 2>"$err")
assert_fail "clear_dir refuses symlink to \$HOME" "$st"
rm -f "$link"

echo "== simctl fixtures"
export CONSUELA_FIXTURE_DEVICES="$FIXTURES/simctl_devices.json"
export CONSUELA_FIXTURE_RUNTIME_IMAGES="$FIXTURES/simctl_runtime_images.json"
export CONSUELA_FIXTURE_RUNTIMES="$FIXTURES/simctl_runtimes.json"
scan=$(run_simctl_scan 2>"$err")
assert_eq "$(printf '%s\n' "$scan" | sed -n '1p')" "unavailable_devices 1024" "devices kb from dataPathSize"
assert_eq "$(printf '%s\n' "$scan" | sed -n '2p')" \
  "unavailable_runtime 2097152 AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" \
  "runtime id is a single field, not comma-joined"
if [ -s "$err" ]; then
  echo "FAIL: good fixtures wrote stderr: $(cat "$err")" >&2
  failed=$((failed + 1))
fi

CONSUELA_FIXTURE_DEVICES="$FIXTURES/simctl_devices_wrong_shape.json"
scan=$(run_simctl_scan 2>"$err")
st=$(status_of has_re "$scan" '^unavailable_devices ')
assert_fail "wrong-shape devices are not a successful empty scan" "$st"
st=$(status_of grep -q "warning: could not scan unavailable simulators" "$err")
assert_ok "wrong-shape devices warns" "$st"
st=$(status_of has_re "$scan" '^unavailable_runtime ')
assert_ok "runtime scan continues after device failure" "$st"

CONSUELA_FIXTURE_DEVICES="$FIXTURES/simctl_invalid.json"
scan=$(run_simctl_scan 2>"$err")
st=$(status_of has_re "$scan" '^unavailable_devices ')
assert_fail "invalid JSON is not a successful empty scan" "$st"
st=$(status_of grep -q "warning: could not scan unavailable simulators" "$err")
assert_ok "invalid JSON warns" "$st"
unset CONSUELA_FIXTURE_DEVICES CONSUELA_FIXTURE_RUNTIME_IMAGES CONSUELA_FIXTURE_RUNTIMES

echo "== install.sh verify and PATH hint"
# shellcheck source=../install.sh disable=SC1091
. "$ROOT/install.sh"

html=$(mktemp)
printf '%s\n' '<!DOCTYPE html>' '<html><body>not found</body></html>' >"$html"
st=$(status_of verify_downloaded_script "$html" 2>"$err")
assert_fail "verify rejects HTML" "$st"
rm -f "$html"

empty=$(mktemp)
: >"$empty"
st=$(status_of verify_downloaded_script "$empty" 2>"$err")
assert_fail "verify rejects empty file" "$st"
rm -f "$empty"

st=$(status_of verify_downloaded_script "$ROOT/consuela")
assert_ok "verify accepts consuela" "$st"

tmpbin=$(mktemp -d)
out=$(CONSUELA_BIN="$tmpbin" "$ROOT/install.sh")
assert_eq "$(sed -n '1p' "$tmpbin/consuela")" "#!/bin/sh" "install copies shebang"
st=$(status_of has_str "$out" "export PATH=\"$tmpbin:\$PATH\"")
assert_ok "PATH hint uses BIN_DIR" "$st"
rm -rf "$tmpbin"

echo "== CLI dry-run (mock docker, no deletes)"
mocks=$(mktemp -d)
cat >"$mocks/docker" <<EOF
#!/bin/sh
echo "\$@" >>"$mocks/log"
if [ "\$1" = system ] && [ "\$2" = df ]; then
  printf '%s\t%s\n' "Images" "1GB"
  printf '%s\t%s\n' "Containers" "100MB"
  printf '%s\t%s\n' "Local Volumes" "5GB"
  printf '%s\t%s\n' "Build Cache" "2GB"
  exit 0
fi
if [ "\$1" = system ] && [ "\$2" = prune ]; then
  echo prune >>"$mocks/prune"
  exit 1
fi
exit 0
EOF
chmod +x "$mocks/docker"

set +e
out=$(PATH="$mocks:$PATH" "$ROOT/consuela" --dry-run --docker 2>"$err")
st=$?
set -e
assert_eq "$st" "0" "dry-run --docker exits 0"
st=$(status_of has_re "$out" "Dry run: nothing deleted")
assert_ok "dry-run prints that nothing was deleted" "$st"
st=$(status_of has_re "$out" "unused images \\(including tagged\\)")
assert_ok "docker-all prompt names tagged unused images" "$st"
if [ -e "$mocks/prune" ]; then
  echo "FAIL: dry-run called docker system prune" >&2
  failed=$((failed + 1))
fi

set +e
out=$(PATH="$mocks:$PATH" "$ROOT/consuela" --dry-run --docker-dangling 2>"$err")
st=$?
set -e
assert_eq "$st" "0" "dry-run --docker-dangling exits 0"
st=$(status_of has_re "$out" "dangling images")
assert_ok "docker-dangling prompt names dangling images" "$st"

set +e
out=$(PATH="$mocks:$PATH" DOCKER_HOST="ssh://example" "$ROOT/consuela" --dry-run --docker 2>"$err")
st=$?
set -e
assert_eq "$st" "0" "dry-run with DOCKER_HOST exits 0"
st=$(status_of has_re "$out" "DOCKER_HOST=ssh://example")
assert_ok "prints DOCKER_HOST" "$st"

rm -f "$mocks/log" "$mocks/prune"
set +e
out=$(PATH="$mocks:$PATH" "$ROOT/consuela" --dry-run --cache 2>"$err")
st=$?
set -e
assert_eq "$st" "0" "dry-run --cache exits 0"
if [ -e "$mocks/log" ]; then
  echo "FAIL: --cache invoked docker" >&2
  failed=$((failed + 1))
fi

rm -f "$mocks/prune"
set +e
out=$(printf 'n\n' | PATH="$mocks:$PATH" DOCKER_HOST="ssh://example" "$ROOT/consuela" -y --docker 2>"$err")
st=$?
set -e
assert_eq "$st" "0" "DOCKER_HOST confirm abort exits 0"
st=$(status_of has_re "$out" "Aborted")
assert_ok "DOCKER_HOST still requires confirmation with -y" "$st"
if [ -e "$mocks/prune" ]; then
  echo "FAIL: DOCKER_HOST n-confirm called docker system prune" >&2
  failed=$((failed + 1))
fi

set +e
"$ROOT/consuela" --not-a-flag >/dev/null 2>&1
st=$?
set -e
assert_fail "unknown flag exits non-zero" "$st"

help=$("$ROOT/consuela" --help)
st=$(status_of has_re "$help" "--dry-run")
assert_ok "usage mentions --dry-run" "$st"

rm -rf "$mocks"
rm -f "$err"

echo
if [ "$failed" -ne 0 ]; then
  echo "$failed test(s) failed" >&2
  exit 1
fi
echo "All tests passed."
