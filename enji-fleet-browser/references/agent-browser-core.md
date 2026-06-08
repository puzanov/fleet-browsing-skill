# Agent Browser Core

This reference is copied and adapted from the bundled `agent-browser` skill material so `enji-fleet-browser` can stand alone. Use it for normal browsing, parsing, downloads, competitor review, and QA/user-testing workflows.

## Resolve The Binary

```bash
SKILL_DIR="${ENJI_FLEET_BROWSER_SKILL_DIR:-./enji-fleet-browser}"
export AGENT_BROWSER_SOCKET_DIR="${AGENT_BROWSER_SOCKET_DIR:-/tmp/enji-fleet-browser/agent-browser-sockets}"
mkdir -p "$AGENT_BROWSER_SOCKET_DIR"
AB="$("$SKILL_DIR/scripts/ensure-agent-browser.sh")"
"$AB" --version
```

Use `AGENT_BROWSER_SOCKET_DIR` in `/tmp` for restricted agent sandboxes where `/run/user/...` is read-only.

If the binary is absent, the resolver downloads the latest prebuilt `vercel-labs/agent-browser` release into `/tmp/enji-fleet-browser/agent-browser`. If Chrome/Chromium is missing, run:

```bash
"$AB" install
```

On Linux, `"$AB" install --with-deps` may be required when system libraries are missing.

## Core Loop

```bash
"$AB" --session enji open "https://example.com"
"$AB" --session enji wait --load networkidle
"$AB" --session enji snapshot -i -u
"$AB" --session enji click @e3
"$AB" --session enji snapshot -i -u
```

Refs like `@e3` are fresh per snapshot. After navigation, form submit, modal open, click-driven render, or tab switch, run a new snapshot before using refs again.

## Reading And Navigation

```bash
"$AB" snapshot                    # full accessibility tree
"$AB" snapshot -i                 # interactive elements only
"$AB" snapshot -i -u              # include href URLs on links
"$AB" snapshot -i -c              # compact output
"$AB" snapshot -s "#main"         # scope to a CSS selector
"$AB" get title
"$AB" get url
"$AB" get text body
"$AB" get html body
"$AB" get count ".card"
```

Prefer `snapshot -i -u` for exploration. Use `get text/html` when saving evidence to files.

## Interactions

```bash
"$AB" click @e1
"$AB" click @e1 --new-tab
"$AB" fill @e2 "text"
"$AB" type @e2 " more"
"$AB" press Enter
"$AB" hover @e3
"$AB" check @e4
"$AB" select @e5 "value"
"$AB" scroll down 700
"$AB" scrollintoview @e6
```

Semantic locators are useful when refs are unavailable:

```bash
"$AB" find role button click --name "Submit"
"$AB" find text "Pricing" click
"$AB" find label "Email" fill "user@example.com"
"$AB" find placeholder "Search" type "competitor"
```

## Waits

Choose a specific wait after page-changing actions:

```bash
"$AB" wait --text "Success"
"$AB" wait --url "**/dashboard"
"$AB" wait --load networkidle
"$AB" wait --fn "window.appReady === true"
```

Use fixed sleeps only as a debugging fallback.

## Extraction

For structured data, use JavaScript from stdin to avoid shell quoting bugs:

```bash
cat <<'JS' | "$AB" eval --stdin > "$OUT/cards.json"
Array.from(document.querySelectorAll(".card")).slice(0, 50).map((el) => ({
  title: el.querySelector("h2,h3,.title")?.textContent.trim() || null,
  price: el.querySelector(".price,[data-price]")?.textContent.trim() || null,
  href: el.querySelector("a[href]")?.href || null,
  badge: el.querySelector(".badge,.label")?.textContent.trim() || null
}))
JS
```

Probe selectors before extracting:

```bash
"$AB" get count ".card"
"$AB" get count "table tbody tr"
```

Save raw evidence:

```bash
"$AB" get text body > "$OUT/body.txt"
"$AB" get html body > "$OUT/body.html"
"$AB" snapshot -i -u > "$OUT/snapshot.txt"
```

## Screenshots, PDF, HAR, Downloads

```bash
"$AB" screenshot "$OUT/page.png"
"$AB" screenshot --full "$OUT/full-page.png"
"$AB" screenshot --annotate "$OUT/annotated.png"
"$AB" pdf "$OUT/page.pdf"
```

For download links, set a download directory and click the real link as a user:

```bash
mkdir -p "$OUT/downloads"
AGENT_BROWSER_DOWNLOAD_PATH="$OUT/downloads" "$AB" --session enji open "https://example.com"
"$AB" --session enji snapshot -i -u
"$AB" --session enji click @download_ref
```

Use HAR only when network evidence is needed and may contain secrets:

```bash
"$AB" network har start
# perform workflow
"$AB" network har stop "$OUT/network.har"
```

## Sessions And Auth

Use named sessions to isolate runs:

```bash
"$AB" --session competitor-a open "https://competitor.example"
"$AB" --session competitor-b open "https://other.example"
```

For authenticated targets, prefer a user-provided cookie/auth state file. Do not put secrets in command arguments or chat.

```bash
"$AB" --state ./auth.json open "https://app.example.com"
"$AB" state save ./auth.json
```

## Troubleshooting

- `Ref not found`: page changed; run `snapshot -i` again.
- Empty snapshot: wait for text/selector, scroll, or inspect whether the page is a challenge.
- Click does nothing: check for cookie banners, overlays, disabled buttons, or off-screen elements.
- Dynamic content missing: use `wait --load networkidle`, scroll, then re-snapshot.
- Install problems: run `"$AB" doctor --offline --quick`, then `"$AB" doctor` if local checks do not explain it.
