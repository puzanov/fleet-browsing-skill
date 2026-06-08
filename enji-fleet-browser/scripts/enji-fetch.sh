#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: enji-fetch.sh <url> [output-dir]

Capture a single page with agent-browser. If the rendered result contains a
bot-protection signal, retry with Obscura in stealth mode only.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ]; then
  usage
  exit 0
fi

url="$1"
out="${2:-/tmp/enji-fleet-browser/capture-$(date +%Y%m%dT%H%M%S)}"
session="${ENJI_AGENT_BROWSER_SESSION:-enji-fetch-$$}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
block_re='Access denied|Forbidden|(^|[^0-9])(403|429)([^0-9]|$)|captcha|hCaptcha|Turnstile|Cloudflare|Just a moment|Checking your browser|verify you are human|bot detection|unusual traffic|automated traffic|temporarily blocked'

mkdir -p "$out"
: > "$out/commands.log"

log_command() {
  printf '%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ) " >> "$out/commands.log"
  printf '%q ' "$@" >> "$out/commands.log"
  printf '\n' >> "$out/commands.log"
}

if [ -z "${AGENT_BROWSER_SOCKET_DIR:-}" ]; then
  export AGENT_BROWSER_SOCKET_DIR="${ENJI_AGENT_BROWSER_SOCKET_DIR:-/tmp/enji-fleet-browser/agent-browser-sockets}"
fi
mkdir -p "$AGENT_BROWSER_SOCKET_DIR"
chmod 700 "$AGENT_BROWSER_SOCKET_DIR" 2>/dev/null || true

ab="$("$script_dir/ensure-agent-browser.sh")"
printf "%s\n" "$url" > "$out/requested-url.txt"
printf "%s\n" "$ab" > "$out/agent-browser-bin.txt"
printf "%s\n" "$AGENT_BROWSER_SOCKET_DIR" > "$out/agent-browser-socket-dir.txt"

ab_status=0
log_command "$ab" --session "$session" open "$url"
"$ab" --session "$session" open "$url" > "$out/agent-browser-open.log" 2>&1 || ab_status=$?
log_command "$ab" --session "$session" wait --load networkidle
"$ab" --session "$session" wait --load networkidle > "$out/agent-browser-wait.log" 2>&1 || true
log_command "$ab" --session "$session" get title
"$ab" --session "$session" get title > "$out/title.txt" 2> "$out/title.err" || true
log_command "$ab" --session "$session" get url
"$ab" --session "$session" get url > "$out/final-url.txt" 2> "$out/final-url.err" || true
log_command "$ab" --session "$session" snapshot -i -u
"$ab" --session "$session" snapshot -i -u > "$out/snapshot.txt" 2> "$out/snapshot.err" || true
log_command "$ab" --session "$session" get text body
"$ab" --session "$session" get text body > "$out/body.txt" 2> "$out/body.err" || true
log_command "$ab" --session "$session" get html body
"$ab" --session "$session" get html body > "$out/body.html" 2> "$out/body-html.err" || true
log_command "$ab" --session "$session" screenshot --full "$out/page.png"
"$ab" --session "$session" screenshot --full "$out/page.png" > "$out/screenshot.log" 2>&1 || true

blocked=0
if grep -Eiq "$block_re" "$out/title.txt" "$out/body.txt" "$out/snapshot.txt" "$out/agent-browser-open.log" 2>/dev/null; then
  blocked=1
fi

exit_code=0
if [ "$blocked" -eq 1 ]; then
  printf "blocked\n" > "$out/status.txt"
  obscura="$("$script_dir/ensure-obscura.sh")"
  printf "%s\n" "$obscura" > "$out/obscura-bin.txt"
  log_command "$obscura" fetch "$url" --stealth --dump markdown --quiet \
    --wait-until networkidle0 --timeout 60 --output "$out/obscura-stealth.md"
  "$obscura" fetch "$url" --stealth --dump markdown --quiet \
    --wait-until networkidle0 --timeout 60 --output "$out/obscura-stealth.md" \
    > "$out/obscura-markdown.log" 2>&1 || true
  log_command "$obscura" fetch "$url" --stealth --dump html --quiet \
    --wait-until networkidle0 --timeout 60 --output "$out/obscura-stealth.html"
  "$obscura" fetch "$url" --stealth --dump html --quiet \
    --wait-until networkidle0 --timeout 60 --output "$out/obscura-stealth.html" \
    > "$out/obscura-html.log" 2>&1 || true
elif [ "$ab_status" -ne 0 ]; then
  printf "agent-browser-error\n" > "$out/status.txt"
  exit_code="$ab_status"
else
  printf "ok\n" > "$out/status.txt"
fi

log_command "$ab" --session "$session" close
"$ab" --session "$session" close > "$out/agent-browser-close.log" 2>&1 || true

printf "capture_dir=%s\n" "$out"
printf "status=%s\n" "$(cat "$out/status.txt")"
exit "$exit_code"
