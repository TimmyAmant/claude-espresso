Disable the global Claude Espresso auto-arm. After running this, Espresso will no longer activate automatically in every project — you'll need to use /limit-restart or /limit-auto per-project.

When this skill is invoked:

1. Check if global auto-espresso is enabled:
```bash
grep -q 'auto-espresso-global' ~/.claude/scripts/stop-hook.sh 2>/dev/null && echo "ENABLED" || echo "NOT_ENABLED"
```

   - If `NOT_ENABLED`, tell the user: "Global Auto-Espresso is not currently enabled." Stop here.

2. Read `~/.claude/scripts/stop-hook.sh`, then use the Edit tool to remove the auto-espresso block. The block to remove is exactly:

```
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

Use this exact text (including the trailing newline after `fi`) as the `old_string` for the Edit tool, replacing it with an empty string. If the block in the file differs slightly (e.g. extra blank line), read the file first and match exactly what's there.

3. Tell the user: "Global Auto-Espresso disabled. Existing checkpoints and queued resumes are unchanged — they'll still fire. Only new sessions won't be auto-armed."
