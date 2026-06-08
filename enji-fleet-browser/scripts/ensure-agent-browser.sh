#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: ensure-agent-browser.sh [--check-only] [--print-export]

Resolve an agent-browser binary. If none is installed, download the pinned
prebuilt release into a per-user cache and verify its SHA256.

Environment:
  ENJI_AGENT_BROWSER_BIN   Absolute path to an existing agent-browser binary.
  ENJI_AGENT_BROWSER_HOME  Cache root. Default: $XDG_CACHE_HOME/enji-fleet-browser/agent-browser
USAGE
}

AGENT_BROWSER_REPO="vercel-labs/agent-browser"
AGENT_BROWSER_VERSION="v0.27.1"

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

  local cache_root cached platform_key ext asset
  cache_root="$(default_cache_root)" || return 1
  platform_key="$(detect_platform_key)" || return 1
  ext=""
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ext=".exe" ;;
  esac
  asset="agent-browser-$platform_key$ext"
  cached="$cache_root/bin/agent-browser$ext"
  if cached_agent_browser_valid "$cached" "$asset"; then
    printf "%s\n" "$cached"
    return 0
  fi

  return 1
}

default_cache_root() {
  if [ -n "${ENJI_AGENT_BROWSER_HOME:-}" ]; then
    printf "%s\n" "$ENJI_AGENT_BROWSER_HOME"
  elif [ -n "${XDG_CACHE_HOME:-}" ]; then
    printf "%s/enji-fleet-browser/agent-browser\n" "$XDG_CACHE_HOME"
  elif [ -n "${HOME:-}" ]; then
    printf "%s/.cache/enji-fleet-browser/agent-browser\n" "$HOME"
  else
    echo "Could not determine a per-user cache root; set ENJI_AGENT_BROWSER_HOME" >&2
    return 1
  fi
}

ensure_private_cache_root() {
  local dir="$1" owner
  umask 077
  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  owner="$(stat -c '%u' "$dir" 2>/dev/null || stat -f '%u' "$dir" 2>/dev/null || true)"
  if [ -n "$owner" ] && [ "$owner" != "$(id -u)" ]; then
    echo "Refusing cache root not owned by current user: $dir" >&2
    return 1
  fi
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

agent_browser_sha256() {
  case "$1" in
    agent-browser-darwin-arm64) printf "5ff18a2f0c7d4c662d638b8ac5ce434b589be5f6bde8b8fe7e25c3658e2bcbf9\n" ;;
    agent-browser-darwin-x64) printf "de70b31d7dc86f3ad2f9df016b5109306079569de61c8825f836c12a34d4f1d7\n" ;;
    agent-browser-linux-arm64) printf "ab93f04ca217e6ff73832c900a43c4b88f14239d6bf11fb8ba90478d99b84b3d\n" ;;
    agent-browser-linux-musl-arm64) printf "807c1c386e4cc21dc4e1f8ee747a40650a5f560ed21dc25054464bc2f6fb52df\n" ;;
    agent-browser-linux-musl-x64) printf "7fb2f2cb1d503b4af55b337af2bf379da0c85655aa0ea3685e80c39bd0aaf1fd\n" ;;
    agent-browser-linux-x64) printf "95ff8224a971698d9df8add26f1f571027c35f9003e3067c53e54d154b5b1ea1\n" ;;
    agent-browser-win32-x64.exe) printf "ac88ef4261ccae30d047506a8c45d465f6c7b7a96743189131e6fb0b841bc3b1\n" ;;
    *) echo "No pinned SHA256 for agent-browser asset: $1" >&2; return 1 ;;
  esac
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "Need sha256sum or shasum to verify downloads" >&2
    return 1
  fi
}

verify_sha256() {
  local file="$1" expected="$2" label="$3" actual
  actual="$(sha256_file "$file")" || return 1
  if [ "$actual" != "$expected" ]; then
    echo "SHA256 mismatch for $label: expected $expected, got $actual" >&2
    return 1
  fi
}

cached_agent_browser_valid() {
  local target="$1" asset="$2" expected cache_root
  [ -x "$target" ] || return 1
  cache_root="$(dirname "$(dirname "$target")")"
  ensure_private_cache_root "$cache_root" || return 1
  expected="$(agent_browser_sha256 "$asset")" || return 1
  verify_sha256 "$target" "$expected" "$asset" >/dev/null 2>&1
}

download_with_gh() {
  local repo="$1" tag="$2" asset="$3" dest_dir="$4"
  gh release view "$tag" --repo "$repo" --json tagName,assets \
    --jq '{tagName,assets:[.assets[].name]}' >&2
  gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$dest_dir" --clobber >&2
}

download_with_curl() {
  local repo="$1" tag="$2" asset="$3" dest="$4"
  curl -fL "https://github.com/$repo/releases/download/$tag/$asset" -o "$dest" >&2
}

download_agent_browser() {
  local repo="$AGENT_BROWSER_REPO"
  local tag="$AGENT_BROWSER_VERSION"
  local cache_root
  cache_root="$(default_cache_root)"
  local bin_dir="$cache_root/bin"
  local platform_key asset ext downloaded target lock_dir waited expected

  platform_key="$(detect_platform_key)"
  ext=""
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ext=".exe" ;;
  esac
  asset="agent-browser-$platform_key$ext"
  target="$bin_dir/agent-browser$ext"
  expected="$(agent_browser_sha256 "$asset")"

  ensure_private_cache_root "$cache_root"
  mkdir -p "$bin_dir"
  downloaded="$bin_dir/$asset"
  lock_dir="$cache_root/.download.lock"
  waited=0

  while ! mkdir "$lock_dir" 2>/dev/null; do
    if cached_agent_browser_valid "$target" "$asset"; then
      "$target" --version >&2
      printf "%s\n" "$target"
      return 0
    fi
    if [ "$waited" -ge 180 ]; then
      echo "Timed out waiting for agent-browser download lock: $lock_dir" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  cleanup_lock() {
    rmdir "$lock_dir" 2>/dev/null || true
  }
  trap cleanup_lock EXIT

  if cached_agent_browser_valid "$target" "$asset"; then
    "$target" --version >&2
    cleanup_lock
    trap - EXIT
    printf "%s\n" "$target"
    return 0
  fi

  echo "agent-browser not found; downloading $asset from $repo $tag" >&2
  if command -v gh >/dev/null 2>&1; then
    download_with_gh "$repo" "$tag" "$asset" "$bin_dir"
  elif command -v curl >/dev/null 2>&1; then
    download_with_curl "$repo" "$tag" "$asset" "$downloaded"
  else
    echo "Need gh or curl to download agent-browser" >&2
    return 1
  fi

  if [ ! -f "$downloaded" ]; then
    echo "Downloaded release did not create expected asset: $downloaded" >&2
    return 1
  fi

  verify_sha256 "$downloaded" "$expected" "$asset"
  chmod +x "$downloaded" 2>/dev/null || true
  if [ "$downloaded" != "$target" ]; then
    cp "$downloaded" "$target"
    chmod +x "$target" 2>/dev/null || true
  fi
  verify_sha256 "$target" "$expected" "$target"

  "$target" --version >&2
  cleanup_lock
  trap - EXIT
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
