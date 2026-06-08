# Agent Test Harness

This directory contains live regression prompts and a Python runner for the
`enji-fleet-browser` skill.

Run deterministic offline tests first:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

or with `uv`:

```bash
uv run python -m unittest discover -s tests -p 'test_*.py'
```

Run all supported live agents:

```bash
uv run tests/run_agent_tests.py --agents codex,kimi,opencode --live
```

Run one agent:

```bash
uv run tests/run_agent_tests.py --agents codex --live
```

The live runner writes artifacts under `/tmp/enji-agent-tests/<run-id>/` and
validates the generated files instead of relying only on the agent's final
answer. Live tests require installed agent CLIs, local auth/config, network
access, and current target-site behavior:

- `enji.ai` must complete through the normal `agent-browser` path with
  `status=ok`.
- `clutch.co` must show a bot-protection block through the normal path.
- Obscura must be used only for that fallback.
- Every Obscura `fetch`, `scrape`, or `download` line in `commands.log` must
  include `--stealth`.

Agent discovery:

- Codex uses a temporary `CODEX_HOME` with `skills/enji-fleet-browser` symlinked
  to this repository.
- Kimi uses `--skills-dir` pointing at this repository.
- opencode runs in a temporary workspace with `.agents/skills/enji-fleet-browser`
  symlinked to this repository.
