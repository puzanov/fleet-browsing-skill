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

capture_image_audit() {
  local file="$1"
  local err="${file%.json}.err"
  log_command "$ab" --session "$session" eval --stdin "<image-audit>"
  "$ab" --session "$session" eval --stdin > "$file" 2> "$err" <<'JS' || true
(() => {
  const fallbackRe = /(^|\/)nuxt-lazy-load-fallback\.svg([?#]|$)/;
  const imgs = Array.from(document.images);
  const rendered = (img) => {
    const style = getComputedStyle(img);
    const rect = img.getBoundingClientRect();
    return style.display !== "none" && style.visibility !== "hidden" &&
      rect.width > 0 && rect.height > 0;
  };
  const inViewport = (img) => {
    const rect = img.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 &&
      rect.bottom >= 0 && rect.top <= innerHeight &&
      rect.right >= 0 && rect.left <= innerWidth;
  };
  const details = imgs.map((img, index) => {
    const src = img.currentSrc || img.src || "";
    const dataSrc = img.getAttribute("data-src") || "";
    const isFallback = fallbackRe.test(src);
    const isRendered = rendered(img);
    return {
      index,
      alt: img.alt || "",
      src,
      dataSrc,
      loading: img.getAttribute("loading") || "",
      complete: img.complete,
      naturalWidth: img.naturalWidth,
      naturalHeight: img.naturalHeight,
      rendered: isRendered,
      inViewport: inViewport(img),
      fallbackSrc: isFallback,
      actualLoaded: !isFallback && img.naturalWidth > 0,
      lazyCue: isFallback || Boolean(dataSrc) || img.getAttribute("loading") === "lazy" ||
        /\blazy(load|loaded|loading)?\b/i.test(typeof img.className === "string" ? img.className : ""),
      top: Math.round(img.getBoundingClientRect().top),
      classes: typeof img.className === "string" ? img.className : ""
    };
  });
  const lazyCueCount = details.filter((item) => item.lazyCue).length;
  return {
    url: location.href,
    scrollY: Math.round(scrollY),
    viewport: { width: innerWidth, height: innerHeight },
    documentHeight: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
    total: details.length,
    needsWarmup: lazyCueCount > 0,
    lazyCueCount,
    actualLoaded: details.filter((item) => item.actualLoaded).length,
    fallbackSrc: details.filter((item) => item.fallbackSrc).length,
    renderedFallback: details.filter((item) => item.rendered && item.fallbackSrc).length,
    inViewport: details.filter((item) => item.inViewport).length,
    inViewportActualLoaded: details.filter((item) => item.inViewport && item.actualLoaded).length,
    visibleProblemCandidates: details.filter((item) =>
      item.inViewport && (!item.actualLoaded || item.fallbackSrc)
    ),
    hiddenOrOffscreenFallbackSamples: details.filter((item) =>
      item.fallbackSrc && !item.inViewport
    ).slice(0, 20),
    unloadedActualSrcSamples: details.filter((item) =>
      !item.fallbackSrc && item.naturalWidth === 0
    ).slice(0, 20)
  };
})()
JS
}

warm_lazy_media() {
  log_command "$ab" --session "$session" eval --stdin "<lazy-media-warmup>"
  "$ab" --session "$session" eval --stdin > "$out/media-warmup.json" 2> "$out/media-warmup.err" <<'JS' || true
(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const root = document.scrollingElement || document.documentElement;
  const previousScrollBehavior = document.documentElement.style.scrollBehavior;
  document.documentElement.style.scrollBehavior = "auto";
  const max = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
  const step = Math.max(450, Math.floor(innerHeight * 0.8));
  const positions = [];
  for (let y = 0; y <= max; y += step) {
    positions.push(y);
  }
  positions.push(max);
  for (const y of positions) {
    window.scrollTo(0, y);
    root.scrollTop = y;
    window.dispatchEvent(new Event("scroll"));
    document.dispatchEvent(new Event("scroll"));
    await sleep(220);
  }
  await sleep(800);
  const decodes = Array.from(document.images)
    .filter((img) => img.currentSrc && !/(^|\/)nuxt-lazy-load-fallback\.svg([?#]|$)/.test(img.currentSrc))
    .map((img) => img.decode ? img.decode().catch(() => {}) : Promise.resolve());
  await Promise.race([Promise.all(decodes), sleep(1500)]);
  window.scrollTo(0, 0);
  root.scrollTop = 0;
  document.body.scrollTop = 0;
  await sleep(300);
  document.documentElement.style.scrollBehavior = previousScrollBehavior;
  return {
    scrolledPositions: positions.length,
    finalScrollY: Math.round(scrollY),
    imageCount: document.images.length
  };
})()
JS
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

blocked=0
if grep -Eiq "$block_re" "$out/title.txt" "$out/body.txt" "$out/snapshot.txt" "$out/agent-browser-open.log" 2>/dev/null; then
  blocked=1
fi

if [ "$blocked" -eq 0 ] && [ "$ab_status" -eq 0 ]; then
  capture_image_audit "$out/images-before-scroll.json"
  if grep -Eq '"needsWarmup"[[:space:]]*:[[:space:]]*true' "$out/images-before-scroll.json" 2>/dev/null; then
    warm_lazy_media
    capture_image_audit "$out/images-after-scroll.json"
  else
    printf "skipped: no lazy-loaded media cues found\n" > "$out/media-warmup-skipped.txt"
    cp "$out/images-before-scroll.json" "$out/images-after-scroll.json"
  fi
else
  printf "skipped: blocked or agent-browser open failed\n" > "$out/media-warmup-skipped.txt"
fi

log_command "$ab" --session "$session" get html body
"$ab" --session "$session" get html body > "$out/body.html" 2> "$out/body-html.err" || true
log_command "$ab" --session "$session" screenshot --full "$out/page.png"
"$ab" --session "$session" screenshot --full "$out/page.png" > "$out/screenshot.log" 2>&1 || true

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
