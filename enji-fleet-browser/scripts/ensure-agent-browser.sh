#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: ensure-agent-browser.sh [--check-only] [--print-export]

Resolve an agent-browser binary. If none is installed, download the latest
prebuilt release into a task-local cache.

Environment:
  ENJI_AGENT_BROWSER_BIN   Absolute path to an existing agent-browser binary.
  ENJI_AGENT_BROWSER_HOME  Cache root. Default: /tmp/enji-fleet-browser/agent-browser
USAGE
}

check_only=0
print_export=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-only) check_only=1 ;;
    --print-export) print_export=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

emit_path() {
  if [ "$print_export" -eq 1 ]; then
    printf "export ENJI_AGENT_BROWSER_BIN=%q\n" "$1"
  else
    printf "%s\n" "$1"
  fi
}

resolve_existing() {
  if [ -n "${ENJI_AGENT_BROWSER_BIN:-}" ] && [ -x "$ENJI_AGENT_BROWSER_BIN" ]; then
    printf "%s\n" "$ENJI_AGENT_BROWSER_BIN"
    return 0
  fi

  if command -v agent-browser >/dev/null 2>&1; then
    command -v agent-browser
    return 0
  fi

  local cache_root="${ENJI_AGENT_BROWSER_HOME:-/tmp/enji-fleet-browser/agent-browser}"
  local cached="$cache_root/bin/agent-browser"
  if [ -x "$cached" ]; then
    printf "%s\n" "$cached"
    return 0
  fi

  return 1
}

detect_platform_key() {
  local os arch libc
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "Unsupported architecture for agent-browser: $arch" >&2; return 1 ;;
  esac

  case "$os" in
    Linux)
      libc="linux"
      if ldd --version 2>&1 | grep -qi musl; then
        libc="linux-musl"
      fi
      printf "%s-%s\n" "$libc" "$arch"
      ;;
    Darwin) printf "darwin-%s\n" "$arch" ;;
    MINGW*|MSYS*|CYGWIN*) printf "win32-%s\n" "$arch" ;;
    *) echo "Unsupported OS for agent-browser: $os" >&2; return 1 ;;
  esac
}

download_with_gh() {
  local repo="$1" asset="$2" dest_dir="$3"
  gh release view --repo "$repo" --json tagName,assets \
    --jq '{tagName,assets:[.assets[].name]}' >&2
  gh release download --repo "$repo" --pattern "$asset" --dir "$dest_dir" --clobber >&2
}

download_with_curl() {
  local repo="$1" asset="$2" dest="$3" tag
  tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1)"
  if [ -z "$tag" ]; then
    echo "Could not determine latest $repo release tag with curl" >&2
    return 1
  fi
  curl -fL "https://github.com/$repo/releases/download/$tag/$asset" -o "$dest" >&2
}

download_agent_browser() {
  local repo="vercel-labs/agent-browser"
  local cache_root="${ENJI_AGENT_BROWSER_HOME:-/tmp/enji-fleet-browser/agent-browser}"
  local bin_dir="$cache_root/bin"
  local platform_key asset ext downloaded target

  platform_key="$(detect_platform_key)"
  ext=""
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ext=".exe" ;;
  esac
  asset="agent-browser-$platform_key$ext"
  target="$bin_dir/agent-browser$ext"

  mkdir -p "$bin_dir"
  downloaded="$bin_dir/$asset"

  echo "agent-browser not found; downloading $asset from $repo latest release" >&2
  if command -v gh >/dev/null 2>&1; then
    download_with_gh "$repo" "$asset" "$bin_dir"
  elif command -v curl >/dev/null 2>&1; then
    download_with_curl "$repo" "$asset" "$downloaded"
  else
    echo "Need gh or curl to download agent-browser" >&2
    return 1
  fi

  if [ ! -f "$downloaded" ]; then
    echo "Downloaded release did not create expected asset: $downloaded" >&2
    return 1
  fi

  chmod +x "$downloaded" 2>/dev/null || true
  if [ "$downloaded" != "$target" ]; then
    cp "$downloaded" "$target"
    chmod +x "$target" 2>/dev/null || true
  fi

  "$target" --version >&2
  printf "%s\n" "$target"
}

if existing="$(resolve_existing)"; then
  emit_path "$existing"
  exit 0
fi

if [ "$check_only" -eq 1 ]; then
  echo "agent-browser not found. Run without --check-only to download it." >&2
  exit 1
fi

downloaded="$(download_agent_browser)"
emit_path "$downloaded"
