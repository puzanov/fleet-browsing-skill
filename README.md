# Enji Fleet Browser

`enji-fleet-browser` is an agent skill for user-like public website inspection.
It is packaged as a plain skill folder so it can be loaded by Codex, Kimi,
opencode, or any agent runtime that can read local skill instructions. The skill
uses `agent-browser` by default, records evidence to files, and falls back to
Obscura only after clear bot-protection or challenge-page signals. Every Obscura
web command issued by the bundled helper is logged and must run with
`--stealth`.

## What It Does

- Opens and inspects rendered public web pages with `agent-browser`.
- Saves evidence such as title, final URL, DOM text, HTML, snapshots,
  screenshots, status files, and command logs.
- Detects common block signals such as Cloudflare, CAPTCHA, 403/429, "Just a
  moment", and similar challenge pages.
- Uses Obscura as a last-resort stealth fallback only after the normal browser
  path is visibly blocked.
- Includes live regression prompts for Codex, Kimi, and opencode agents.

## Repository Layout

```text
enji-fleet-browser/
  SKILL.md                         # Agent skill instructions
  agents/openai.yaml               # OpenAI/Codex UI metadata
  references/                      # Detailed browser, reporting, fallback docs
  scripts/enji-fetch.sh            # One-page capture helper
  scripts/ensure-agent-browser.sh  # Resolver/downloader for agent-browser
  scripts/ensure-obscura.sh        # Resolver/downloader for Obscura
tests/
  prompts/                         # Fresh-agent live test prompts
  run_agent_tests.py               # Python/uv live test runner
```

## Install Locally

Clone the repository:

```bash
git clone https://github.com/puzanov/fleet-browsing-skill.git
cd fleet-browsing-skill
```

For Codex, symlink the skill into `CODEX_HOME`:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -s "$PWD/enji-fleet-browser" "${CODEX_HOME:-$HOME/.codex}/skills/enji-fleet-browser"
```

For Kimi CLI, point `--skills-dir` at this repository or another directory that
contains the `enji-fleet-browser/` skill folder:

```bash
kimi-cli --work-dir "$PWD" --skills-dir "$PWD" -p 'Use $enji-fleet-browser to inspect https://example.com and save evidence.'
```

For opencode, symlink the skill into the project-local agent skills directory:

```bash
mkdir -p .agents/skills
ln -s "$PWD/enji-fleet-browser" .agents/skills/enji-fleet-browser
opencode run 'Use $enji-fleet-browser to inspect https://example.com and save evidence.' --dir "$PWD"
```

For other agent runtimes, expose `enji-fleet-browser/SKILL.md` plus its
`references/` and `scripts/` directories as a local skill named
`enji-fleet-browser`.

Then ask the agent to use it explicitly:

```text
Use $enji-fleet-browser to inspect https://example.com and save evidence.
```

## Use The Helper Directly

For a simple one-page capture:

```bash
SKILL_DIR="$PWD/enji-fleet-browser"
OUT="/tmp/enji-fleet-browser/example"
"$SKILL_DIR/scripts/enji-fetch.sh" "https://example.com" "$OUT"
```

The helper writes files such as:

- `status.txt` - `ok`, `blocked`, or `agent-browser-error`
- `title.txt` and `final-url.txt`
- `snapshot.txt`, `body.txt`, and `body.html`
- `page.png`
- `commands.log`
- `obscura-stealth.md` and `obscura-stealth.html` when fallback was needed

`ensure-agent-browser.sh` and `ensure-obscura.sh` first look for explicit binary
paths via `ENJI_AGENT_BROWSER_BIN` and `ENJI_OBSCURA_BIN`, then use installed
`agent-browser`/`obscura` binaries on `PATH`, then use their per-user cache.
When downloading is needed, the scripts fetch pinned release assets and verify
their SHA256 before executing them.

Pinned defaults:

- `agent-browser`: `vercel-labs/agent-browser` `v0.27.1`
- `obscura`: `h4ckf0r0day/obscura` `v0.1.7`

The default cache roots are under
`${XDG_CACHE_HOME:-$HOME/.cache}/enji-fleet-browser/` and are created with
private permissions. Override them with `ENJI_AGENT_BROWSER_HOME` and
`ENJI_OBSCURA_HOME` when an isolated cache is needed.

## Run Offline Tests

Offline tests use mocked browser binaries and do not require agent CLIs, network
access, or site availability:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

The same command can be run through `uv`:

```bash
uv run python -m unittest discover -s tests -p 'test_*.py'
```

## Run Live Tests

Live tests launch fresh agents and validate generated artifacts instead of
trusting only the agent's final prose. They require local agent CLIs, working
auth/config for those CLIs, network access, and current target-site behavior.

```bash
uv run tests/run_agent_tests.py --agents codex,kimi,opencode --live
```

Run a single agent:

```bash
uv run tests/run_agent_tests.py --agents codex --live
```

Print the commands without running agents:

```bash
uv run tests/run_agent_tests.py --agents codex,kimi,opencode --dry-run
```

The runner writes reports under `/tmp/enji-agent-tests/<run-id>/report.json`.
It checks that `enji.ai` completes through the normal path, `clutch.co` produces
a bot-protection block signal, Obscura is used for that fallback, and every
Obscura `fetch`, `scrape`, or `download` command in `commands.log` includes
`--stealth`.

Agent binaries can be overridden with `CODEX_BIN`, `KIMI_BIN`, and
`OPENCODE_BIN`.

## License

MIT. See [LICENSE](LICENSE).
