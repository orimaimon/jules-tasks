# shellcheck shell=bash
# Environment for child `claude -p` runs: drop variables that tie a child to the parent session
# (set when the harness itself runs inside Claude Code), so each run is a fresh, separate session.
ISOLATE=(env)
for v in CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_CODE_REMOTE_SESSION_ID CLAUDE_CODE_MESSAGING_SOCKET \
         CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_TEE_SDK_STDOUT CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD \
         CLAUDE_ADDITIONAL_DIRECTORIES CLAUDE_CODE_DIAGNOSTICS_FILE CLAUDE_CODE_SYNC_SESSION_REFS; do
  ISOLATE+=(-u "$v")
done
