#!/usr/bin/env python3
"""Run live agent-skill tests for enji-fleet-browser.

The runner intentionally validates artifacts produced by the skill helper instead
of trusting only the agent's final prose. It can be launched with:

    uv run tests/run_agent_tests.py --agents codex,kimi,opencode --live
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
SKILL_DIR = REPO_ROOT / "enji-fleet-browser"
PROMPTS_DIR = Path(__file__).resolve().parent / "prompts"
DEFAULT_ARTIFACT_ROOT = Path("/tmp/enji-agent-tests")
DEFAULT_TIMEOUT = 900
SUPPORTED_AGENTS = ("codex", "kimi", "opencode")
OBSCURA_WEB_RE = re.compile(r"\bobscura\b.*\b(fetch|scrape|download)\b")


@dataclass
class CommandSpec:
    argv: list[str]
    cwd: Path
    env: dict[str, str]


@dataclass
class AgentResult:
    agent: str
    command: list[str]
    returncode: int | None = None
    timed_out: bool = False
    passed: bool = False
    checks: dict[str, object] = field(default_factory=dict)
    artifact_dir: str = ""
    final_output_path: str = ""
    stdout_path: str = ""
    stderr_path: str = ""
    error: str = ""


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except FileNotFoundError:
        return ""


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def resolve_from_login_shell(binary: str) -> str | None:
    script = f"source ~/.nvm/nvm.sh 2>/dev/null || true; command -v {binary} 2>/dev/null || true"
    proc = subprocess.run(
        ["bash", "-lc", script],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        timeout=10,
    )
    value = proc.stdout.strip().splitlines()
    return value[-1] if value else None


def resolve_binary(agent: str) -> str | None:
    env_names = {
        "codex": "CODEX_BIN",
        "kimi": "KIMI_BIN",
        "opencode": "OPENCODE_BIN",
    }
    binary_names = {
        "codex": "codex",
        "kimi": "kimi-cli",
        "opencode": "opencode",
    }

    override = os.environ.get(env_names[agent])
    if override:
        return override

    found = shutil.which(binary_names[agent])
    if found:
        return found

    login_found = resolve_from_login_shell(binary_names[agent])
    if login_found:
        return login_found

    if agent == "opencode":
        for candidate in (
            Path.home() / ".opencode/bin/opencode",
            Path.home() / ".local/bin/opencode",
        ):
            if candidate.exists():
                return str(candidate)

    return None


def safe_clean_dir(path: Path) -> None:
    resolved = path.resolve()
    if "enji-agent-tests" not in str(resolved):
        raise ValueError(f"refusing to clean unexpected path: {resolved}")
    shutil.rmtree(resolved, ignore_errors=True)
    resolved.mkdir(parents=True, exist_ok=True)


def render_prompt(agent: str, artifact_dir: Path, skill_dir: Path) -> str:
    prompt = read_text(PROMPTS_DIR / f"{agent}_live.md")
    if not prompt:
        raise FileNotFoundError(f"missing prompt for {agent}")
    return (
        prompt.replace("{{ARTIFACT_DIR}}", str(artifact_dir))
        .replace("{{SKILL_DIR}}", str(skill_dir))
        .replace("{{REPO_ROOT}}", str(REPO_ROOT))
    )


def base_env(agent_dir: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "ENJI_AGENT_BROWSER_HOME": str(agent_dir / "cache/agent-browser"),
            "ENJI_OBSCURA_HOME": str(agent_dir / "cache/obscura"),
            "AGENT_BROWSER_SOCKET_DIR": str(agent_dir / "agent-browser-sockets"),
            "ENJI_AGENT_BROWSER_SOCKET_DIR": str(agent_dir / "agent-browser-sockets"),
            "ENJI_FLEET_BROWSER_SKILL_DIR": str(SKILL_DIR),
            "NO_COLOR": "1",
        }
    )
    return env


def prepare_codex(agent_dir: Path, prompt: str) -> CommandSpec:
    codex = resolve_binary("codex")
    if not codex:
        raise FileNotFoundError("codex binary not found; set CODEX_BIN")

    codex_home = agent_dir / "codex-home"
    (codex_home / "skills").mkdir(parents=True, exist_ok=True)
    auth = Path.home() / ".codex/auth.json"
    config = Path.home() / ".codex/config.toml"
    if auth.exists() and not (codex_home / "auth.json").exists():
        (codex_home / "auth.json").symlink_to(auth)
    if config.exists() and not (codex_home / "config.toml").exists():
        (codex_home / "config.toml").symlink_to(config)
    skill_link = codex_home / "skills/enji-fleet-browser"
    if not skill_link.exists():
        skill_link.symlink_to(SKILL_DIR, target_is_directory=True)

    output_file = agent_dir / "agent-final.txt"
    quoted = " ".join(
        [
            "source ~/.nvm/nvm.sh 2>/dev/null || true;",
            f"CODEX_HOME={sh_quote(str(codex_home))}",
            sh_quote(codex),
            "exec",
            "-C",
            sh_quote(str(REPO_ROOT)),
            "--skip-git-repo-check",
            "--dangerously-bypass-approvals-and-sandbox",
            "--ephemeral",
            "-o",
            sh_quote(str(output_file)),
            sh_quote(prompt),
        ]
    )
    return CommandSpec(argv=["bash", "-lc", quoted], cwd=REPO_ROOT, env=base_env(agent_dir))


def prepare_kimi(agent_dir: Path, prompt: str) -> CommandSpec:
    kimi = resolve_binary("kimi")
    if not kimi:
        raise FileNotFoundError("kimi-cli binary not found; set KIMI_BIN")
    return CommandSpec(
        argv=[
            kimi,
            "--work-dir",
            str(REPO_ROOT),
            "--skills-dir",
            str(REPO_ROOT),
            "--print",
            "--output-format",
            "text",
            "--final-message-only",
            "-p",
            prompt,
        ],
        cwd=REPO_ROOT,
        env=base_env(agent_dir),
    )


def prepare_opencode(agent_dir: Path, prompt: str) -> CommandSpec:
    opencode = resolve_binary("opencode")
    if not opencode:
        raise FileNotFoundError("opencode binary not found; set OPENCODE_BIN")

    workspace = agent_dir / "workspace"
    skills_dir = workspace / ".agents/skills"
    skills_dir.mkdir(parents=True, exist_ok=True)
    root_skill_link = workspace / "enji-fleet-browser"
    agents_skill_link = skills_dir / "enji-fleet-browser"
    if not root_skill_link.exists():
        root_skill_link.symlink_to(SKILL_DIR, target_is_directory=True)
    if not agents_skill_link.exists():
        agents_skill_link.symlink_to(SKILL_DIR, target_is_directory=True)

    return CommandSpec(
        argv=[
            opencode,
            "run",
            prompt,
            "--dir",
            str(workspace),
            "--dangerously-skip-permissions",
        ],
        cwd=workspace,
        env=base_env(agent_dir),
    )


def sh_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def prepare_command(agent: str, agent_dir: Path) -> CommandSpec:
    prompt = render_prompt(agent, agent_dir, SKILL_DIR)
    if agent == "codex":
        return prepare_codex(agent_dir, prompt)
    if agent == "kimi":
        return prepare_kimi(agent_dir, prompt)
    if agent == "opencode":
        return prepare_opencode(agent_dir, prompt)
    raise ValueError(f"unsupported agent: {agent}")


def run_command(agent: str, spec: CommandSpec, agent_dir: Path, timeout: int) -> AgentResult:
    stdout_path = agent_dir / "agent-stdout.log"
    stderr_path = agent_dir / "agent-stderr.log"
    final_path = agent_dir / "agent-final.txt"
    result = AgentResult(
        agent=agent,
        command=spec.argv,
        artifact_dir=str(agent_dir),
        final_output_path=str(final_path),
        stdout_path=str(stdout_path),
        stderr_path=str(stderr_path),
    )
    try:
        proc = subprocess.run(
            spec.argv,
            cwd=spec.cwd,
            env=spec.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
        result.returncode = proc.returncode
        write_text(stdout_path, proc.stdout)
        write_text(stderr_path, proc.stderr)
        if not final_path.exists():
            write_text(final_path, proc.stdout.strip())
    except subprocess.TimeoutExpired as exc:
        result.timed_out = True
        result.returncode = None
        write_text(stdout_path, exc.stdout or "")
        write_text(stderr_path, exc.stderr or "")
        result.error = f"timed out after {timeout}s"
    except Exception as exc:  # noqa: BLE001 - command harness should report all launch failures.
        result.returncode = None
        result.error = str(exc)
    return result


def obscura_stealth_check(commands_log: Path) -> tuple[int, int, list[str]]:
    total = 0
    missing = 0
    bad_lines: list[str] = []
    for line in read_text(commands_log).splitlines():
        if OBSCURA_WEB_RE.search(line):
            total += 1
            if "--stealth" not in line:
                missing += 1
                bad_lines.append(line)
    return total, missing, bad_lines


def validate_artifacts(result: AgentResult, agent_dir: Path) -> AgentResult:
    enji = agent_dir / "enji-ai"
    clutch = agent_dir / "clutch-co"
    checks: dict[str, object] = {}

    enji_status = read_text(enji / "status.txt")
    clutch_status = read_text(clutch / "status.txt")
    enji_title = read_text(enji / "title.txt")
    clutch_title = read_text(clutch / "title.txt")
    enji_commands = enji / "commands.log"
    clutch_commands = clutch / "commands.log"
    obscura_bin = clutch / "obscura-bin.txt"
    total_obscura, missing_stealth, bad_lines = obscura_stealth_check(clutch_commands)
    final_text = read_text(Path(result.final_output_path))

    checks.update(
        {
            "process_exit_zero": result.returncode == 0,
            "timed_out": result.timed_out,
            "skill_loaded_claim": bool(re.search(r"SKILL_LOADED\s*=\s*(yes|true)", final_text, re.I)),
            "default_tool_claim": "agent-browser" in final_text.lower(),
            "enji_status": enji_status,
            "enji_title": enji_title,
            "enji_ok": enji_status == "ok" and "Enji" in enji_title,
            "clutch_status": clutch_status,
            "clutch_title": clutch_title,
            "clutch_blocked": clutch_status == "blocked" and (
                "Just a moment" in clutch_title
                or "Cloudflare" in read_text(clutch / "body.txt")
                or "security verification" in read_text(clutch / "body.txt")
            ),
            "enji_commands_log_present": enji_commands.exists(),
            "clutch_commands_log_present": clutch_commands.exists(),
            "obscura_used": obscura_bin.exists() and total_obscura > 0,
            "obscura_web_lines": total_obscura,
            "obscura_missing_stealth": missing_stealth,
            "obscura_bad_lines": bad_lines,
            "agent_browser_bin": read_text(enji / "agent-browser-bin.txt") or read_text(clutch / "agent-browser-bin.txt"),
            "final_answer_preview": final_text[-2000:],
        }
    )

    required = [
        checks["process_exit_zero"],
        not checks["timed_out"],
        checks["skill_loaded_claim"],
        checks["default_tool_claim"],
        checks["enji_ok"],
        checks["clutch_blocked"],
        checks["enji_commands_log_present"],
        checks["clutch_commands_log_present"],
        checks["obscura_used"],
        checks["obscura_web_lines"] >= 1,
        checks["obscura_missing_stealth"] == 0,
    ]
    result.checks = checks
    result.passed = all(bool(item) for item in required)
    return result


def parse_agents(raw: str) -> list[str]:
    if raw == "all":
        return list(SUPPORTED_AGENTS)
    agents = [item.strip() for item in raw.split(",") if item.strip()]
    unknown = sorted(set(agents) - set(SUPPORTED_AGENTS))
    if unknown:
        raise SystemExit(f"unsupported agents: {', '.join(unknown)}")
    return agents


def run_agents(args: argparse.Namespace) -> dict[str, object]:
    run_id = args.run_id or dt.datetime.now(dt.UTC).strftime("%Y%m%dT%H%M%SZ")
    artifact_root = Path(args.artifact_root).expanduser().resolve() / run_id
    artifact_root.mkdir(parents=True, exist_ok=True)

    report: dict[str, object] = {
        "run_id": run_id,
        "started_at": utc_now(),
        "repo_root": str(REPO_ROOT),
        "skill_dir": str(SKILL_DIR),
        "artifact_root": str(artifact_root),
        "live": args.live,
        "agents": {},
    }

    agents = parse_agents(args.agents)
    for agent in agents:
        agent_dir = artifact_root / agent
        attempts: list[dict[str, object]] = []
        result = AgentResult(agent=agent, command=[], artifact_dir=str(agent_dir))
        max_attempts = 1 if (args.dry_run or not args.live) else args.retries + 1

        for attempt in range(1, max_attempts + 1):
            if not args.keep_artifacts:
                safe_clean_dir(agent_dir)
            else:
                agent_dir.mkdir(parents=True, exist_ok=True)

            print(f"==> {agent}: preparing attempt {attempt}/{max_attempts}", flush=True)
            try:
                spec = prepare_command(agent, agent_dir)
                if args.dry_run or not args.live:
                    result = AgentResult(
                        agent=agent,
                        command=spec.argv,
                        artifact_dir=str(agent_dir),
                        checks={"dry_run": True},
                        passed=True,
                    )
                    print(" ".join(spec.argv), flush=True)
                else:
                    print(f"==> {agent}: running attempt {attempt}/{max_attempts}", flush=True)
                    result = run_command(agent, spec, agent_dir, args.timeout)
                    result = validate_artifacts(result, agent_dir)
                    print(f"==> {agent}: {'PASS' if result.passed else 'FAIL'}", flush=True)
            except Exception as exc:  # noqa: BLE001 - runner should continue across agents.
                result = AgentResult(agent=agent, command=[], artifact_dir=str(agent_dir), error=str(exc))
                print(f"==> {agent}: FAIL ({exc})", flush=True)

            attempts.append(
                {
                    "attempt": attempt,
                    "passed": result.passed,
                    "returncode": result.returncode,
                    "timed_out": result.timed_out,
                    "error": result.error,
                    "checks": result.checks,
                }
            )
            if result.passed or args.dry_run or not args.live:
                break

        report["agents"][agent] = {
            "passed": result.passed,
            "returncode": result.returncode,
            "timed_out": result.timed_out,
            "command": result.command,
            "artifact_dir": result.artifact_dir,
            "final_output_path": result.final_output_path,
            "stdout_path": result.stdout_path,
            "stderr_path": result.stderr_path,
            "error": result.error,
            "attempts": attempts,
            "checks": result.checks,
        }

    report["finished_at"] = utc_now()
    report["passed"] = all(item["passed"] for item in report["agents"].values())
    report_path = artifact_root / "report.json"
    write_text(report_path, json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    report["report_path"] = str(report_path)
    return report


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agents", default="all", help="Comma-separated agents or 'all'.")
    parser.add_argument("--artifact-root", default=str(DEFAULT_ARTIFACT_ROOT), help="Base output directory.")
    parser.add_argument("--run-id", default="", help="Optional stable run id.")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help="Timeout per agent in seconds.")
    parser.add_argument("--retries", type=int, default=1, help="Retries per live agent after a failed attempt.")
    parser.add_argument("--live", action="store_true", help="Actually run agent CLIs.")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without running them.")
    parser.add_argument("--keep-artifacts", action="store_true", help="Do not clean per-agent artifact dirs first.")
    args = parser.parse_args(list(argv) if argv is not None else None)

    report = run_agents(args)
    print(json.dumps({"passed": report["passed"], "report_path": report["report_path"]}, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
