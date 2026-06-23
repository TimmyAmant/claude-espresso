# ☕ Claude Espresso

> Automatically resumes Claude Code when your usage limit resets — no monitoring, no manual restarts.

![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Claude Code](https://img.shields.io/badge/Claude%20Code-required-orange)

Give Claude a big task and walk away. If the limit hits, Claude Espresso waits the exact right amount of time and picks up exactly where it left off — whether you're asleep, in a meeting, or just done watching a timer.

---

## Install

```bash
git clone https://github.com/TimmyAmant/claude-espresso.git
cd claude-espresso
bash install.sh
```

Then **restart Claude Code** to activate the hooks.

**Requirements**

| Requirement | macOS | Linux | Windows |
|---|---|---|---|
| [Claude Code](https://claude.ai/code) | ✅ | ✅ | ✅ (Git Bash or WSL) |
| Python 3 | ✅ built-in | ✅ built-in | ✅ |
| jq | `brew install jq` | `sudo apt install jq` | `winget install jqlang.jq` |

---

## Usage

At the start of any long task, type:

```
/limit-restart
```

Claude will ask what you're working on, write a checkpoint file, and begin. From that point, **you don't need to do anything else.**

When the limit hits:
- The exact reset time is read from Claude Code's own session data
- A background process wakes up at the right moment
- Claude resumes in your project directory, reads the checkpoint, and keeps going

To cancel a queued resume at any time:

```
/limit-cancel
```

---

## How It Works

Claude Espresso is built entirely on Claude Code's native hook system — no wrappers, no screen-scraping, no polling the terminal.

### 1. While Claude works
A `statusLine` hook fires after every response and captures the **exact** 5-hour and 7-day reset timestamps directly from Claude Code's rate limit data.

### 2. When the session ends
A `Stop` hook reads Claude Code's own session file (`~/.claude/sessions/{pid}.json`) to identify the project directory and session start time. It cross-references the saved reset timestamps, determines whether you hit the 5-hour or weekly limit, and writes a pending resume file with the precise wakeup time.

If you were 3 hours into your window, it schedules a resume in **2 hours**, not 5.

### 3. In the background
A scheduler (launchd on macOS, cron on Linux, Task Scheduler on Windows) runs `resume-check.sh` every 15 minutes. The moment your reset time passes, it launches Claude Code headlessly in your project directory and resumes from the checkpoint.

### 4. Handles weekly limits too
If your 7-day cap is exhausted — not just the 5-hour window — Claude Espresso detects it from the usage percentage, queues a resume for the weekly reset time, and sends you a system notification so you know the wait is longer than usual.

### 5. Chains automatically
If Claude hits the limit again during a resumed session, the whole process repeats. Claude Espresso keeps going until the task is marked complete.

---

## Checkpoint File

Each project gets a `.claude/checkpoint.md` that Claude updates after every significant step:

```
status: in_progress
project_dir: /Users/you/your-project
task: Build the authentication system
started_at: 2026-06-23T12:00:00Z

## Task breakdown
1. Set up JWT token generation
2. Build login endpoint
3. Add refresh token logic
4. Write tests

## Completed steps
1. Set up JWT token generation

## Current step
2. Build login endpoint

## Next step
3. Add refresh token logic

## Files modified
- src/auth/jwt.ts
- src/auth/login.ts

## Notes
Using RS256 per existing codebase convention
resumed_at: 2026-06-23T17:09:02Z
```

If the limit hits mid-step, the previous completed step is always preserved. On each resume, Claude immediately writes a `resumed_at` timestamp before doing any work — so even if the limit hits again immediately, there's a record of the session.

---

## What Gets Installed

| File | Purpose |
|---|---|
| `~/.claude/scripts/stop-hook.sh` | Fires on every session end — computes exact reset time and queues resume |
| `~/.claude/scripts/statusline-hook.sh` | Fires after every response — saves live reset timestamps |
| `~/.claude/scripts/resume-check.sh` | Runs every 15 min — wakes Claude when the time is right |
| `~/.claude/commands/limit-restart.md` | The `/limit-restart` skill |
| `~/.claude/commands/limit-cancel.md` | The `/limit-cancel` skill |
| `~/Library/LaunchAgents/com.claude.espresso.plist` | macOS background agent (launchd) |

`~/.claude/settings.json` is updated to wire up the `Stop` and `statusLine` hooks. **All existing settings are preserved.** The installer is safe to run multiple times.

---

## Pairs Well With These Built-in Claude Code Skills

| Skill | What it does | Why it pairs well |
|---|---|---|
| `/init` | Writes a `CLAUDE.md` for your project | Claude reads `CLAUDE.md` on every startup, including every auto-resume — project context carries through automatically |
| `/code-review` | Reviews the current diff | Run after a long resumed session to catch anything that drifted across multiple sessions |
| `/schedule` | Runs a Claude agent on a schedule | `/schedule` handles the timing, Claude Espresso handles limit hits within each run |

**Recommended workflow for big tasks:**
1. Run `/init` once to write your project's `CLAUDE.md`
2. Run `/limit-restart` at the start of each major task
3. Run `/code-review` when it finishes to verify the work

---

## vs. Other Tools

| | Claude Espresso | [autoclaude](https://github.com/henryaj/autoclaude) | [claude-auto-resume](https://github.com/terryso/claude-auto-resume) |
|---|---|---|---|
| Install method | `git clone` | Homebrew / Go binary | Shell script |
| Requires tmux | No | Yes | No |
| Wraps `claude` command | No | No | Yes |
| Reset time source | Claude's own session + statusLine data | Parses terminal UI | Watches CLI output |
| Handles weekly limit | Yes | No | No |
| Saves task context across sessions | Yes (checkpoint file) | No | No |
| Works in Claude Code desktop app | Yes | No | No |
| Handles multiple limit hits | Yes | Yes | Yes |

---

## Security

When Claude resumes headlessly, it uses `--dangerously-skip-permissions`. This allows it to read, write, and run commands in your project without prompting — which is required for fully unattended operation.

Only use `/limit-restart` in projects where you're comfortable with Claude operating autonomously. The checkpoint file lives in `.claude/checkpoint.md` inside your project, so you can always inspect what Claude is planning to do next.

---

## Uninstall

```bash
# Stop and remove the background checker
launchctl unload ~/Library/LaunchAgents/com.claude.espresso.plist
rm ~/Library/LaunchAgents/com.claude.espresso.plist

# Remove scripts and skills
rm ~/.claude/scripts/stop-hook.sh \
   ~/.claude/scripts/statusline-hook.sh \
   ~/.claude/scripts/resume-check.sh \
   ~/.claude/commands/limit-restart.md \
   ~/.claude/commands/limit-cancel.md
```

Then open `~/.claude/settings.json` and remove the `statusLine` key and the `Stop` entry under `hooks`.

---

## Contributing

PRs welcome. The biggest gaps:

- **Linux:** Cron is installed but not tested across distros — reports welcome
- **Windows:** Task Scheduler path via Git Bash needs real-world testing
- **Notifications:** Linux `notify-send` and Windows PowerShell toast need testing

---

## License

MIT
