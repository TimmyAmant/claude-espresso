Configure this project to automatically arm Claude Espresso at the start of every Claude session.

Once enabled, you never need to run /limit-restart manually — Espresso will be armed automatically whenever Claude opens this project, using the current task as context.

When this skill is invoked:

1. Check if `.claude/settings.json` already has an auto-espresso hook:
```bash
python3 -c "
import json, os
f = os.path.join(os.getcwd(), '.claude/settings.json')
if not os.path.exists(f): print('NONE'); exit()
try:
    d = json.load(open(f))
    hooks = d.get('hooks', {})
    pre_hooks = hooks.get('UserPromptSubmit', [])
    found = any('auto-armed' in str(h) or 'auto-espresso' in str(h) for h in pre_hooks)
    print('FOUND' if found else 'NONE')
except: print('NONE')
"
```

2. If already enabled, tell the user: "Auto-Espresso is already enabled for this project." Stop here.

3. Create or update `.claude/settings.json` to add an auto-arm hook. Read the current settings first:
```bash
python3 << 'PYEOF'
import json, os, shlex

project_dir = os.getcwd()
settings_path = os.path.join(project_dir, '.claude/settings.json')
os.makedirs(os.path.join(project_dir, '.claude'), exist_ok=True)

settings = {}
if os.path.exists(settings_path):
    try: settings = json.load(open(settings_path))
    except: pass

# Use a UserPromptSubmit hook — fires on every user message, including conversational
# sessions with no tool calls. PreToolUse would miss sessions where the model responds
# with plain text only, leaving no checkpoint for the Stop hook to find.
# shlex.quote() escapes project_dir so paths with spaces or quotes are safe.
pdir_q = shlex.quote(project_dir)
auto_hook = {
    "matcher": "",
    "hooks": [{
        "type": "command",
        "command": f"PDIR={pdir_q}; CP=\"$PDIR/.claude/checkpoint.md\"; if [ ! -f \"$CP\" ]; then mkdir -p \"$PDIR/.claude\" && {{ printf 'status: in_progress\\nproject_dir: '; printf '%s\\n' \"$PDIR\"; printf 'task: (auto-armed - update with task details)\\nstarted_at: '; date -u +%Y-%m-%dT%H:%M:%SZ; printf '\\n## Task breakdown\\n(not yet set)\\n\\n## Completed steps\\n(none yet)\\n\\n## Current step\\n(not yet set)\\n\\n## Next step\\n(not yet set)\\n\\n## Files modified\\n(none yet)\\n\\n## Notes\\n(auto-armed by limit-auto)\\n'; }} > \"$CP\"; elif grep -qE '^status: (complete|cancelled|paused)' \"$CP\"; then sed -i '' 's/^status: .*/status: in_progress/' \"$CP\" && echo '[espresso] Auto-Espresso re-armed for new session'; fi",
        "timeout": 5
    }]
}

hooks = settings.setdefault('hooks', {})
pre_hooks = hooks.setdefault('UserPromptSubmit', [])

# Don't add a duplicate
already = any('auto-armed' in str(h) or 'auto-espresso' in str(h) for h in pre_hooks)
if not already:
    pre_hooks.append(auto_hook)
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
    print('Auto-Espresso hook added to .claude/settings.json')
else:
    print('Already configured.')
PYEOF
```

4. Tell the user: "Auto-Espresso is now enabled for this project. A checkpoint will be created automatically at the start of each session so Espresso is always armed. You can still run /limit-restart to set a specific task description, or edit `.claude/checkpoint.md` directly."

5. Remind the user: "To disable Auto-Espresso, remove the UserPromptSubmit hook from `.claude/settings.json`, or run /limit-pause to pause (keeps the checkpoint file so the hook won't re-arm this session). Note: if you run /limit-cancel, the hook will re-create the checkpoint on your next message in the same session — use /limit-pause instead if you want to stop Espresso without ending the session."
