Use $enji-fleet-browser.

You are testing whether the skill works in a fresh Kimi agent.

Rules:
- You may run commands and access the network.
- Do not modify project files.
- Use only {{ARTIFACT_DIR}} for generated artifacts.
- The runner already exports ENJI_AGENT_BROWSER_HOME, ENJI_OBSCURA_HOME, AGENT_BROWSER_SOCKET_DIR, and ENJI_AGENT_BROWSER_SOCKET_DIR.
- Use the skill helper at {{SKILL_DIR}}/scripts/enji-fetch.sh, not ad hoc curl.
- Run captures sequentially: finish enji.ai first, then run clutch.co.

Tasks:
1. Prove you loaded the skill by naming its default tool, fallback condition, stealth rule, and scripts.
2. Run the skill helper for https://enji.ai into {{ARTIFACT_DIR}}/enji-ai.
3. Run the skill helper for https://clutch.co into {{ARTIFACT_DIR}}/clutch-co.
4. Verify commands.log exists in both captures.
5. If clutch.co is blocked, verify every Obscura fetch/scrape/download line in {{ARTIFACT_DIR}}/clutch-co/commands.log contains --stealth.

Final answer fields only:
AGENT=kimi
SKILL_LOADED=
DEFAULT_TOOL=
AGENT_BROWSER_BIN_STATUS=
ENJI_STATUS=
ENJI_TITLE_OR_SIGNAL=
CLUTCH_STATUS=
WHETHER_OBSCURA_USED=
WHETHER_EVERY_OBSCURA_FETCH_HAD_STEALTH_FROM_COMMANDS_LOG=
COMMANDS_LOG_PRESENT=
ARTIFACT_DIRS=
BUGS=
