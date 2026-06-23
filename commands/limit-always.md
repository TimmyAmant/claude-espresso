Enable Claude Espresso globally — it will be automatically armed in every project, every session, without needing to run any command.

When this skill is invoked:

1. Check if the global stop hook already has auto-espresso logic:
```bash
grep -q 'auto-espresso-global' ~/.claude/scripts/stop-hook.sh 2>/dev/null && echo "ALREADY_ENABLED" || echo "NOT_ENABLED"
```

2. If already enabled, tell the user: "Global Auto-Espresso is already enabled. Espresso arms automatically in every project." Stop here.

3. Add the auto-arm logic to the global stop hook at `~/.claude/scripts/stop-hook.sh`. Read the file first, then insert the following block near the top, right after the `CHECKPOINT` variable is set (after the line `CHECKPOINT="$CWD/.claude/checkpoint.md"`):

The block to insert is:
```bash
# auto-espresso-global: create checkpoint if missing so Espresso is always armed
# Skip system/home directories to avoid auto-arming throwaway sessions.
_SKIP=0
[[ "$CWD" == "$HOME" ]] && _SKIP=1
[[ "$CWD" == /tmp* ]] && _SKIP=1
[[ "$CWD" == /private/tmp* ]] && _SKIP=1
if [[ "$_SKIP" == "0" ]] && [[ -n "$CWD" ]] && [[ ! -f "$CHECKPOINT" ]]; then
    mkdir -p "$CWD/.claude"
    {
        printf 'status: in_progress\nproject_dir: '
        printf '%s\n' "$CWD"
        printf 'task: (auto-armed - update with task details)\nstarted_at: '
        date -u +%Y-%m-%dT%H:%M:%SZ
        printf '\n## Task breakdown\n(not yet set)\n\n## Completed steps\n(none yet)\n\n## Current step\n(not yet set)\n\n## Next step\n(not yet set)\n\n## Files modified\n(none yet)\n\n## Notes\n(auto-armed by limit-always global setting)\n'
    } > "$CHECKPOINT"
    echo "[espresso] Auto-armed checkpoint created for $CWD"
fi
```

Insert this block by editing `~/.claude/scripts/stop-hook.sh`: find the line `CHECKPOINT="$CWD/.claude/checkpoint.md"` and insert the block immediately after it — it MUST appear before the very next line `if [[ ! -f "$CHECKPOINT" ]]; then exit 0; fi`. The auto-arm block creates the checkpoint so that guard will pass instead of exiting early.

4. Use the Edit tool to make this change precisely — do not rewrite the entire file.

5. Tell the user: "Global Auto-Espresso is now enabled. Every project will be automatically armed when a session ends — no setup needed. If you ever want to skip a project, run /limit-pause or /limit-cancel inside it. To disable globally, run /limit-always-off."
