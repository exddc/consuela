#!/bin/sh
# Install consuela to ~/.local/bin (or $CONSUELA_BIN)
set -eu

usage() {
  cat <<'EOF'
usage: install.sh [script-url]

Installs consuela into CONSUELA_BIN (default: ~/.local/bin).

The script-url argument wins over CONSUELA_URL. With neither, a run
from a clone copies the consuela file next to install.sh. Otherwise
it downloads from GitHub (exddc/consuela).

Environment:
  CONSUELA_BIN      install directory
  CONSUELA_URL      script URL (overridden by the first argument)
  CONSUELA_SHA256   optional hex digest; the download must match
EOF
}

verify_downloaded_script() {
  file=$1
  if [ ! -s "$file" ]; then
    echo "error: download is empty" >&2
    return 1
  fi
  first=$(sed -n '1p' "$file")
  case "$first" in
    '#!'*) ;;
    *)
      echo "error: download is not a script (missing shebang)" >&2
      return 1
      ;;
  esac
  if awk 'NR<=8 {print} NR==8 {exit}' "$file" | grep -qiE '<(!DOCTYPE[[:space:]]+html|html)[[:space:]>]'; then
    echo "error: download looks like HTML" >&2
    return 1
  fi
  if [ -n "${CONSUELA_SHA256:-}" ]; then
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
    if [ "$actual" != "$CONSUELA_SHA256" ]; then
      echo "error: SHA-256 mismatch (got $actual)" >&2
      return 1
    fi
  fi
  return 0
}

consuela_install_main() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "consuela only runs on macOS." >&2
    exit 1
  fi

  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  BIN_DIR="${CONSUELA_BIN:-$HOME/.local/bin}"
  DEFAULT_URL="https://raw.githubusercontent.com/exddc/consuela/main/consuela"
  URL_OVERRIDE="${1:-${CONSUELA_URL:-}}"
  LOCAL_SCRIPT="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/consuela"
  DEST="$BIN_DIR/consuela"

  mkdir -p "$BIN_DIR"
  tmp=$(mktemp "${TMPDIR:-/tmp}/consuela.XXXXXX")
  trap 'rm -f "$tmp"' EXIT

  # `curl | sh` sets $0 to sh.
  if [ -z "$URL_OVERRIDE" ] && [ "${0##*/}" = "install.sh" ] && [ -f "$LOCAL_SCRIPT" ]; then
    SOURCE=$LOCAL_SCRIPT
    cp "$SOURCE" "$tmp"
  else
    SOURCE="${URL_OVERRIDE:-$DEFAULT_URL}"
    curl -fsSL "$SOURCE" -o "$tmp"
  fi

  verify_downloaded_script "$tmp"
  mv -f "$tmp" "$DEST"
  trap - EXIT
  chmod +x "$DEST"

  echo "Installed $DEST from $SOURCE"

  case ":$PATH:" in
    *":$BIN_DIR:"*)
      ;;
    *)
      echo
      echo "Add this to your shell config so the command is on PATH:"
      echo "  export PATH=\"$BIN_DIR:\$PATH\""
      ;;
  esac

  echo
  echo "Run:  consuela"
}

# Sourced by tests: return. Executed: run install. SC2317 is a false positive.
# shellcheck disable=SC2317
return 0 2>/dev/null || consuela_install_main "$@"
