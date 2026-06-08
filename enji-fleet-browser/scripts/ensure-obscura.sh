#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: ensure-obscura.sh [--check-only] [--print-export]

Resolve an Obscura binary for the stealth fallback. This script should only be
used after agent-browser has hit bot-protection or a challenge page. If none is
installed, download the pinned release into a per-user cache and verify SHA256.

Environment:
  ENJI_OBSCURA_BIN   Absolute path to an existing obscura binary.
  ENJI_OBSCURA_HOME  Cache root. Default: $XDG_CACHE_HOME/enji-fleet-browser/obscura
USAGE
}

OBSCURA_REPO="h4ckf0r0day/obscura"
OBSCURA_VERSION="v0.1.7"

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

  local cache_root cached asset
  cache_root="$(default_cache_root)" || return 1
  asset="$(detect_asset)" || return 1
  cached="$cache_root/bin/obscura"
  if cached_obscura_valid "$cached" "$asset"; then
    printf "%s\n" "$cached"
    return 0
  fi

  return 1
}

default_cache_root() {
  if [ -n "${ENJI_OBSCURA_HOME:-}" ]; then
    printf "%s\n" "$ENJI_OBSCURA_HOME"
  elif [ -n "${XDG_CACHE_HOME:-}" ]; then
    printf "%s/enji-fleet-browser/obscura\n" "$XDG_CACHE_HOME"
  elif [ -n "${HOME:-}" ]; then
    printf "%s/.cache/enji-fleet-browser/obscura\n" "$HOME"
  else
    echo "Could not determine a per-user cache root; set ENJI_OBSCURA_HOME" >&2
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

obscura_sha256() {
  case "$1" in
    obscura-aarch64-linux-cross.tar.gz) printf "88cd7644b37191ad462cfee104043f035c6a371da32df93f4795af2297bf95cb\n" ;;
    obscura-aarch64-linux.tar.gz) printf "43a5a53aed3e6c1019a711015790206721b619752ba45f4929e7d6d6985a3fbd\n" ;;
    obscura-aarch64-macos.tar.gz) printf "7ffab88bf88f6f2d46b2719e91f706c04cbbfebab5f4563df329ca197ba63fe8\n" ;;
    obscura-x86_64-linux.tar.gz) printf "b87036c2a162b927eb0d22ca7671f9c53c5bbde257ddc47e3a728140a777286e\n" ;;
    obscura-x86_64-macos.tar.gz) printf "4f83ea81540eb8435f62879c3e8301740275a6dab5474483dba84c833466d222\n" ;;
    obscura-x86_64-windows.zip) printf "ad7267f073a6670bc7d3dabb76759161ea79f81b0ef390496da6da89719a469c\n" ;;
    *) echo "No pinned SHA256 for Obscura asset: $1" >&2; return 1 ;;
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

cached_obscura_valid() {
  local target="$1" asset="$2" meta cache_root expected version_seen asset_seen archive_seen binary_seen actual_binary
  [ -x "$target" ] || return 1
  meta="$target.meta"
  [ -f "$meta" ] || return 1
  cache_root="$(dirname "$(dirname "$target")")"
  ensure_private_cache_root "$cache_root" || return 1
  expected="$(obscura_sha256 "$asset")" || return 1
  # shellcheck disable=SC2162
  read version_seen asset_seen archive_seen binary_seen < "$meta" || return 1
  [ "$version_seen" = "$OBSCURA_VERSION" ] || return 1
  [ "$asset_seen" = "$asset" ] || return 1
  [ "$archive_seen" = "$expected" ] || return 1
  actual_binary="$(sha256_file "$target")" || return 1
  [ "$actual_binary" = "$binary_seen" ]
}

download_with_gh() {
  local repo="$1" tag="$2" asset="$3" dest_dir="$4"
  gh release view "$tag" --repo "$repo" --json tagName,publishedAt,assets \
    --jq '{tagName,publishedAt,assets:[.assets[].name]}' >&2
  gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$dest_dir" --clobber >&2
}

download_with_curl() {
  local repo="$1" tag="$2" asset="$3" dest="$4"
  curl -fL "https://github.com/$repo/releases/download/$tag/$asset" -o "$dest" >&2
}

download_obscura() {
  local repo="$OBSCURA_REPO"
  local tag="$OBSCURA_VERSION"
  local cache_root
  cache_root="$(default_cache_root)"
  local download_dir="$cache_root/downloads"
  local extract_dir="$cache_root/extract"
  local bin_dir="$cache_root/bin"
  local asset archive found target worker lock_dir waited expected binary_sha

  asset="$(detect_asset)"
  archive="$download_dir/$asset"
  target="$bin_dir/obscura"
  expected="$(obscura_sha256 "$asset")"

  ensure_private_cache_root "$cache_root"
  mkdir -p "$download_dir" "$extract_dir" "$bin_dir"
  lock_dir="$cache_root/.download.lock"
  waited=0

  while ! mkdir "$lock_dir" 2>/dev/null; do
    if cached_obscura_valid "$target" "$asset"; then
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

  if cached_obscura_valid "$target" "$asset"; then
    "$target" --version >&2
    cleanup_lock
    trap - EXIT
    printf "%s\n" "$target"
    return 0
  fi

  echo "Obscura not found; downloading $asset from $repo $tag" >&2
  if command -v gh >/dev/null 2>&1; then
    download_with_gh "$repo" "$tag" "$asset" "$download_dir"
  elif command -v curl >/dev/null 2>&1; then
    download_with_curl "$repo" "$tag" "$asset" "$archive"
  else
    echo "Need gh or curl to download Obscura" >&2
    return 1
  fi

  if [ ! -f "$archive" ]; then
    echo "Downloaded release did not create expected archive: $archive" >&2
    return 1
  fi

  verify_sha256 "$archive" "$expected" "$asset"
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
  binary_sha="$(sha256_file "$target")"
  printf "%s %s %s %s\n" "$tag" "$asset" "$expected" "$binary_sha" > "$target.meta"

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
