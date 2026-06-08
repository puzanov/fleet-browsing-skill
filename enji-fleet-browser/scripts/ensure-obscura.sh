#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: ensure-obscura.sh [--check-only] [--print-export]

Resolve an Obscura binary for the stealth fallback. This script should only be
used after agent-browser has hit bot-protection or a challenge page.

Environment:
  ENJI_OBSCURA_BIN   Absolute path to an existing obscura binary.
  ENJI_OBSCURA_HOME  Cache root. Default: /tmp/enji-fleet-browser/obscura
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
    printf "export ENJI_OBSCURA_BIN=%q\n" "$1"
  else
    printf "%s\n" "$1"
  fi
}

resolve_existing() {
  if [ -n "${ENJI_OBSCURA_BIN:-}" ] && [ -x "$ENJI_OBSCURA_BIN" ]; then
    printf "%s\n" "$ENJI_OBSCURA_BIN"
    return 0
  fi

  if command -v obscura >/dev/null 2>&1; then
    command -v obscura
    return 0
  fi

  local cache_root="${ENJI_OBSCURA_HOME:-/tmp/enji-fleet-browser/obscura}"
  local cached="$cache_root/bin/obscura"
  if [ -x "$cached" ]; then
    printf "%s\n" "$cached"
    return 0
  fi

  return 1
}

detect_asset() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os:$arch" in
    Linux:x86_64|Linux:amd64) printf "obscura-x86_64-linux.tar.gz\n" ;;
    Linux:aarch64|Linux:arm64) printf "obscura-aarch64-linux.tar.gz\n" ;;
    Darwin:arm64|Darwin:aarch64) printf "obscura-aarch64-macos.tar.gz\n" ;;
    Darwin:x86_64) printf "obscura-x86_64-macos.tar.gz\n" ;;
    MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64) printf "obscura-x86_64-windows.zip\n" ;;
    *) echo "Unsupported OS/arch for Obscura: $os/$arch" >&2; return 1 ;;
  esac
}

download_with_gh() {
  local repo="$1" asset="$2" dest_dir="$3"
  gh release view --repo "$repo" --json tagName,publishedAt,assets \
    --jq '{tagName,publishedAt,assets:[.assets[].name]}' >&2
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

download_obscura() {
  local repo="h4ckf0r0day/obscura"
  local cache_root="${ENJI_OBSCURA_HOME:-/tmp/enji-fleet-browser/obscura}"
  local download_dir="$cache_root/downloads"
  local extract_dir="$cache_root/extract"
  local bin_dir="$cache_root/bin"
  local asset archive found target worker lock_dir waited

  asset="$(detect_asset)"
  archive="$download_dir/$asset"
  target="$bin_dir/obscura"

  mkdir -p "$download_dir" "$extract_dir" "$bin_dir"
  lock_dir="$cache_root/.download.lock"
  waited=0

  while ! mkdir "$lock_dir" 2>/dev/null; do
    if [ -x "$target" ]; then
      "$target" --version >&2
      printf "%s\n" "$target"
      return 0
    fi
    if [ "$waited" -ge 180 ]; then
      echo "Timed out waiting for Obscura download lock: $lock_dir" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  cleanup_lock() {
    rmdir "$lock_dir" 2>/dev/null || true
  }
  trap cleanup_lock EXIT

  if [ -x "$target" ]; then
    "$target" --version >&2
    cleanup_lock
    trap - EXIT
    printf "%s\n" "$target"
    return 0
  fi

  echo "Obscura not found; downloading $asset from $repo latest release" >&2
  if command -v gh >/dev/null 2>&1; then
    download_with_gh "$repo" "$asset" "$download_dir"
  elif command -v curl >/dev/null 2>&1; then
    download_with_curl "$repo" "$asset" "$archive"
  else
    echo "Need gh or curl to download Obscura" >&2
    return 1
  fi

  if [ ! -f "$archive" ]; then
    echo "Downloaded release did not create expected archive: $archive" >&2
    return 1
  fi

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  case "$asset" in
    *.tar.gz) tar -xzf "$archive" -C "$extract_dir" ;;
    *.zip) unzip -q "$archive" -d "$extract_dir" ;;
    *) echo "Unsupported Obscura archive format: $asset" >&2; return 1 ;;
  esac

  found="$(find "$extract_dir" -type f \( -name obscura -o -name obscura.exe \) -print -quit)"
  if [ -z "$found" ]; then
    echo "Downloaded $asset but could not find an obscura executable" >&2
    return 1
  fi

  cp "$found" "$target"
  chmod +x "$target" 2>/dev/null || true

  worker="$(find "$extract_dir" -type f \( -name obscura-worker -o -name obscura-worker.exe \) -print -quit)"
  if [ -n "$worker" ]; then
    cp "$worker" "$bin_dir/$(basename "$worker")"
    chmod +x "$bin_dir/$(basename "$worker")" 2>/dev/null || true
  else
    echo "warning: obscura-worker not found beside obscura; batch scrape may fail" >&2
  fi

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
  echo "Obscura not found. Run without --check-only only after agent-browser is blocked." >&2
  exit 1
fi

downloaded="$(download_obscura)"
emit_path "$downloaded"
