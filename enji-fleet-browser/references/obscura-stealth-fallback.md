# Obscura Stealth Fallback

Load this reference only after `agent-browser` produced evidence of bot protection or a challenge page. Obscura is not the default browser for this skill.

## Non-Negotiable Rule

Every Obscura command that fetches, renders, scrapes, evaluates, or downloads a target URL must include `--stealth`.

Allowed setup commands:

```bash
SKILL_DIR="${ENJI_FLEET_BROWSER_SKILL_DIR:-./enji-fleet-browser}"
OBSCURA="$("$SKILL_DIR/scripts/ensure-obscura.sh)"
"$OBSCURA" --version
```

Allowed web commands must look like these:

```bash
"$OBSCURA" fetch "https://target.example" --stealth --dump markdown --quiet \
  --wait-until networkidle0 --timeout 60 --output "$OUT/obscura-stealth.md"

"$OBSCURA" fetch "https://target.example" --stealth --dump html --quiet \
  --wait-until networkidle0 --timeout 60 --output "$OUT/obscura-stealth.html"
```

Do not run `obscura fetch`, `obscura scrape`, or raw download commands against a target URL without `--stealth`.

## Resolve Or Download Obscura

The resolver checks `ENJI_OBSCURA_BIN`, then `command -v obscura`, then `/tmp/enji-fleet-browser/obscura`. If missing, it downloads the latest prebuilt `h4ckf0r0day/obscura` release with `gh` or `curl`.

```bash
SKILL_DIR="${ENJI_FLEET_BROWSER_SKILL_DIR:-./enji-fleet-browser}"
OBSCURA="$("$SKILL_DIR/scripts/ensure-obscura.sh)"
```

Use the absolute path stored in `OBSCURA` for every fallback command.

## Stealth Recipes

Rendered text:

```bash
"$OBSCURA" fetch "https://target.example" --stealth --dump text --quiet \
  --wait-until networkidle0 --timeout 60 --output "$OUT/obscura-stealth.txt"
```

Structured page extraction:

```bash
"$OBSCURA" fetch "https://target.example/pricing" --stealth --quiet \
  --wait-until networkidle0 --timeout 60 \
  --eval '(function(){ return JSON.stringify(Array.from(document.querySelectorAll(".plan")).map(function(el){ var q=function(s){ return el.querySelector(s)?.textContent.trim() || null; }; return {name:q("h2,h3"), price:q(".price"), cta:q("a,button")}; })); })()' \
  > "$OUT/obscura-plans.json"
```

Raw binary or direct file URL after a blocked browser path:

```bash
"$OBSCURA" fetch "https://target.example/file.pdf" --stealth --dump original --quiet \
  --timeout 60 --output "$OUT/file.pdf"
```

Multiple blocked URLs with the same extraction:

```bash
"$OBSCURA" scrape "https://target.example/a" "https://target.example/b" \
  --stealth --quiet --concurrency 2 --timeout 60 --format json \
  --eval 'document.title' > "$OUT/obscura-titles.json"
```

## Eval Rules

`--eval` returns one expression. Wrap multi-statement logic in an IIFE and return JSON for structured data. Do not rely on promises, `setTimeout`, or async functions inside `--eval`.

Use defensive selectors and cap output size:

```bash
"$OBSCURA" fetch "https://target.example" --stealth --quiet --timeout 60 \
  --eval '(function(){ return JSON.stringify(Array.from(document.querySelectorAll("a[href]")).slice(0,100).map(function(a){ return {text:a.textContent.trim(), href:a.href}; })); })()'
```

## Proxies

Do not combine `--stealth` with SOCKS proxies. If a proxy is required, use HTTP(S):

```bash
"$OBSCURA" --proxy http://127.0.0.1:8080 fetch "https://target.example" \
  --stealth --dump markdown --quiet --timeout 60
```

## Limits

Stealth is not a CAPTCHA solver and does not bypass hard auth, paywalls, consent requirements, or site-specific legal restrictions. If the stealth fallback still shows a challenge, report the blocker and include the saved evidence.
