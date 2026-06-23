# ☕ Claude Espresso

A shot of energy that wakes Claude Code back up when your usage limit resets — automatically, while you sleep.

Give Claude a big task. If the limit hits, Claude Espresso waits the exact right amount of time and picks up exactly where it left off.

> **Platform support:** macOS only (uses launchd). Windows and Linux support coming — see [Contributing](#contributing).
> **Works in:** Claude Code terminal (`claude` CLI) and the Claude Code desktop app on Mac.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/claude-espresso/main/install.sh | bash
```

Then restart Claude Code.

**Requirements:** Claude Code CLI · Python 3 · [jq](https://jqlang.github.io/jq/) (`brew install jq`) · macOS

---

## How to use

At the start of any long task, type:

```
/limit-restart
```

Claude will ask what you're working on, write a checkpoint, and start. If the limit hits while you're away, Claude Espresso wakes it back up the moment your window resets.

To cancel a queued resume:

```
/limit-cancel
```

---

## Works great with these built-in Claude Code skills

Combine `/limit-restart` with these to get the most out of long autonomous sessions:

| Skill | What it does | Why it pairs well |
|---|---|---|
| `/init` | Writes a `CLAUDE.md` for your project | Claude reads `CLAUDE.md` on every resume — project context survives limit hits automatically |
| `/code-review` | Reviews the diff after changes | Run after a resumed session finishes to catch anything that drifted across sessions |
| `/schedule` | Runs a Claude agent on a timed schedule | `/schedule` handles the timing, Claude Espresso handles the limit hits within each run |
| `todo-list` *(if installed)* | Tracks what still needs doing | Checkpoint + todo list = two layers of progress tracking |

**Recommended workflow for big tasks:**

1. Run `/init` once to write your `CLAUDE.md` — project context carries through every resume automatically
2. Run `/limit-restart` at the start of each major task
3. When Claude finishes, run `/code-review` to verify the work across sessions

---

## How it works

Claude goes to sleep when it hits your usage limit. Claude Espresso wakes it back up.

**While Claude works:**
A `statusLine` hook fires after every response and saves the exact reset timestamps for your 5-hour and 7-day windows.

**When the session ends:**
A `Stop` hook reads Claude Code's own session file to find the exact reset time. It queues a resume with a precise wakeup timestamp — not an estimate. If you were 3 hours into your window, it waits 2 hours, not 5.

**In the background:**
A macOS launchd agent runs every 15 minutes. When the reset time passes, it launches Claude Code headlessly in your project directory, reads the checkpoint, and continues the task.

**Weekly limit:**
If your 7-day cap is hit, Claude Espresso detects it, waits for the weekly reset, and sends a macOS notification so you know the wait is longer than usual.

---

## What gets installed

| File | Purpose |
|---|---|
| `~/.claude/scripts/stop-hook.sh` | Fires on session end — computes exact reset time |
| `~/.claude/scripts/statusline-hook.sh` | Fires after every response — captures live reset timestamps |
| `~/.claude/scripts/resume-check.sh` | Runs every 15 min — wakes Claude when the time is right |
| `~/.claude/commands/limit-restart.md` | The `/limit-restart` skill |
| `~/.claude/commands/limit-cancel.md` | The `/limit-cancel` skill |
| `~/Library/LaunchAgents/com.claude.espresso.plist` | macOS background agent |

`~/.claude/settings.json` is updated to wire up the hooks. All existing settings are preserved.

---

## Checkpoint file

Each project gets a `.claude/checkpoint.md` that Claude updates after every step:

```
status: in_progress
project_dir: /Users/you/your-project
task: Build out the authentication system
started_at: 2026-06-23T12:00:00Z

## Task breakdown
1. Set up JWT token generation
2. Build login endpoint
3. Add refresh token logic

## Completed steps
1. Set up JWT token generation

## Current step
2. Build login endpoint

## Next step
3. Add refresh token logic

## Files modified
- src/auth/jwt.ts

## Notes
Using RS256 per existing codebase convention
```

If the limit hits mid-step, the previous step's state is always preserved.

---

## Security note

When Claude resumes headlessly, it runs with `--dangerously-skip-permissions`. This means it can read, write, and run commands in your project without prompting. This is required for unattended operation. Only use `/limit-restart` on projects where you're comfortable with that.

---

## Platform support

| Platform | Status |
|---|---|
| macOS (terminal) | ✅ Fully supported |
| macOS (Claude Code desktop app) | ✅ Fully supported |
| Linux | 🔜 Planned — needs cron instead of launchd |
| Windows | 🔜 Planned — needs Task Scheduler instead of launchd |

The hooks (`Stop`, `statusLine`) and skills work on all platforms — only the background checker is macOS-specific right now.

---

## vs. other tools

| | Claude Espresso | [autoclaude](https://github.com/henryaj/autoclaude) | [claude-auto-resume](https://github.com/terryso/claude-auto-resume) |
|---|---|---|---|
| Requires tmux | No | Yes | No |
| Wraps the claude command | No | No | Yes |
| Reset time source | Claude's own session data + statusLine | Parses terminal screen | Watches CLI output |
| Handles weekly limit | Yes | No | No |
| Saves task context across sessions | Yes (checkpoint file) | No | No |
| Handles multiple limit hits | Yes | Yes | Yes |

---

## Contributing

Windows and Linux support are the biggest gaps. PRs welcome:

- **Linux:** Replace the launchd plist with a cron job or systemd timer
- **Windows:** Replace launchd with Windows Task Scheduler

---

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.claude.espresso.plist
rm ~/Library/LaunchAgents/com.claude.espresso.plist
rm ~/.claude/scripts/stop-hook.sh ~/.claude/scripts/statusline-hook.sh ~/.claude/scripts/resume-check.sh
rm ~/.claude/commands/limit-restart.md ~/.claude/commands/limit-cancel.md
```

Then remove the `statusLine` and `hooks.Stop` entries from `~/.claude/settings.json`.

---

## License

MIT
