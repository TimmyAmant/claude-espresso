#!/bin/bash
# ☕ Claude Espresso — Installer
# Run once: bash install.sh
# Supports: macOS, Linux, Windows (Git Bash or WSL)

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo ""
echo "☕ Claude Espresso — Installer"
echo "======================================"
echo ""

# ── 1. Detect Platform ────────────────────────────────────────────────────────

case "$(uname -s)" in
    Darwin)          PLATFORM="macos" ;;
    Linux)           PLATFORM="linux" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    *)               fail "Unsupported platform: $(uname -s)" ;;
esac
ok "Platform: $PLATFORM"

# ── 2. Prerequisites ──────────────────────────────────────────────────────────

CLAUDE_BIN=$(which claude 2>/dev/null || echo "")
[[ -z "$CLAUDE_BIN" ]] && fail "claude not found in PATH. Install Claude Code first: https://claude.ai/code"
ok "claude found at $CLAUDE_BIN"

command -v python3 &>/dev/null || fail "python3 is required but not found."
ok "python3 found"

if ! command -v jq &>/dev/null; then
    case "$PLATFORM" in
        macos)   fail "jq is required. Run: brew install jq" ;;
        linux)   fail "jq is required. Run: sudo apt install jq  (or: sudo yum install jq)" ;;
        windows) fail "jq is required. Run: winget install jqlang.jq  (or: choco install jq)" ;;
    esac
fi
ok "jq found"

echo ""

# ── 3. Directories ────────────────────────────────────────────────────────────

mkdir -p "$HOME/.claude/scripts"
mkdir -p "$HOME/.claude/commands"
mkdir -p "$HOME/.claude/pending-resumes"
ok "Directories created"

# ── 4. Stop Hook ──────────────────────────────────────────────────────────────

cat > "$HOME/.claude/scripts/stop-hook.sh" << 'STOP_HOOK'
#!/bin/bash
# Claude Espresso — Stop Hook
# Fires on every session end. Computes exact reset time and queues a resume.

PENDING_DIR="$HOME/.claude/pending-resumes"
STATE_FILE="$HOME/.claude/rate-limit-state.json"
LOG="$HOME/.claude/espresso.log"
mkdir -p "$PENDING_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [stop] $1" >> "$LOG"; }

HOOK_INPUT=$(cat)
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // .sessionId // ""')
if [[ -z "$SESSION_ID" ]]; then
    log "no session_id in hook input — skipping"
    exit 0
fi

SESSION_FILE=""
for f in "$HOME/.claude/sessions/"*.json; do
    [[ -f "$f" ]] || continue
    SID=$(jq -r '.sessionId // ""' "$f" 2>/dev/null)
    if [[ "$SID" == "$SESSION_ID" ]]; then SESSION_FILE="$f"; break; fi
done
if [[ -z "$SESSION_FILE" ]]; then
    log "no session file found for session_id=$SESSION_ID — skipping"
    exit 0
fi

CWD=$(jq -r '.cwd // ""' "$SESSION_FILE" 2>/dev/null)
STARTED_AT_MS=$(jq -r '.startedAt // 0' "$SESSION_FILE" 2>/dev/null)
if [[ -z "$CWD" ]]; then
    log "no cwd in session file $SESSION_FILE — skipping"
    exit 0
fi

CHECKPOINT="$CWD/.claude/checkpoint.md"
if [[ ! -f "$CHECKPOINT" ]]; then
    log "no checkpoint at $CHECKPOINT — skipping (run /limit-restart to arm Espresso)"
    exit 0
fi

STATUS=$(grep -m1 '^status:' "$CHECKPOINT" 2>/dev/null | sed 's/status:[[:space:]]*//' | tr -d '"' | tr -d "'" | xargs)
if [[ "$STATUS" != "in_progress" ]]; then
    log "checkpoint status='$STATUS' (not in_progress) for $(basename "$CWD") — skipping"
    exit 0
fi

NOW=$(date +%s)

CWD="$CWD" STARTED_AT_MS="$STARTED_AT_MS" SESSION_ID="$SESSION_ID" \
STATE_FILE="$STATE_FILE" PENDING_DIR="$PENDING_DIR" NOW="$NOW" LOG="$LOG" \
python3 - <<'PYEOF'
import json, os, time, hashlib

cwd         = os.environ['CWD']
started_ms  = int(os.environ.get('STARTED_AT_MS') or 0)
session_id  = os.environ['SESSION_ID']
state_file  = os.environ['STATE_FILE']
pending_dir = os.environ['PENDING_DIR']
log_file    = os.environ['LOG']
now         = int(os.environ['NOW'])

def log(msg):
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    with open(log_file, 'a') as f:
        f.write(f'[{ts}] [stop] {msg}\n')

limit_type = '5-hour (estimated)'
reset_at   = 0
weekly_hit = False

five_reset  = 0
seven_reset = 0

if os.path.exists(state_file):
    try:
        with open(state_file) as f:
            state = json.load(f)
        age = now - state.get('updated_at', 0)
        if age < 3600:
            five  = state.get('five_hour', {})
            seven = state.get('seven_day', {})
            five_reset  = five.get('resets_at', 0)
            seven_reset = seven.get('resets_at', 0)
            log(f'rate state age={age}s  5h={five.get("used_pct",0):.0f}% resets@{five_reset}  7d={seven.get("used_pct",0):.0f}% resets@{seven_reset}')
        else:
            log(f'rate state too old ({age}s) — ignoring')
    except Exception as e:
        log(f'could not read rate state: {e}')

# Determine which limit was hit by checking used_pct, then use its reset time.
# We do NOT use max(reset_times) — the 7-day window always resets later than 5h,
# so max() would schedule a 7-day wait even when only the 5-hour limit was hit.
five_pct  = 0
seven_pct = 0
if os.path.exists(state_file):
    try:
        with open(state_file) as f:
            state2 = json.load(f)
        five_pct  = state2.get('five_hour', {}).get('used_pct', 0)
        seven_pct = state2.get('seven_day', {}).get('used_pct', 0)
    except Exception:
        pass

if seven_pct >= 95 and seven_reset > now:
    reset_at = seven_reset; weekly_hit = True; limit_type = 'weekly'
elif five_reset > now:
    reset_at = five_reset; limit_type = '5-hour'
else:
    # No usable reset time — estimate 5h from session start
    estimated = int(started_ms / 1000) + 18000
    reset_at  = estimated if estimated > now + 60 else now + 7200

if reset_at <= now:
    reset_at = now + 300

reset_human  = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(reset_at))
hours_until  = (reset_at - now) / 3600
project_hash = hashlib.md5(cwd.encode()).hexdigest()[:8]
project_name = os.path.basename(cwd)

data = {
    'project_dir': cwd, 'checkpoint': os.path.join(cwd, '.claude/checkpoint.md'),
    'resume_at': reset_at, 'resume_at_human': reset_human,
    'limit_type': limit_type, 'weekly_hit': weekly_hit,
    'queued_at': now, 'session_id': session_id,
}
with open(os.path.join(pending_dir, f'{project_hash}.json'), 'w') as f:
    json.dump(data, f, indent=2)

if weekly_hit:
    log(f'⚠️  WEEKLY LIMIT — queued resume for {project_name} at {reset_human} ({hours_until:.1f}h from now)')
    print(f'[espresso] ⚠️  WEEKLY LIMIT hit for {project_name}')
    print(f'[espresso] Resume queued for {reset_human} ({hours_until:.1f}h from now)')
else:
    log(f'{limit_type} limit — queued resume for {project_name} at {reset_human} ({hours_until:.1f}h from now)')
    print(f'[espresso] {limit_type} limit — resume queued for {reset_human} ({hours_until:.1f}h from now)')
PYEOF

# Weekly limit notification — platform-specific
WEEKLY_FLAG="$HOME/.claude/pending-resumes/.weekly-notified"
WEEKLY_HIT=$(python3 -c "
import json, glob, os
files = glob.glob(os.path.expanduser('~/.claude/pending-resumes/*.json'))
print('yes' if any(json.load(open(f)).get('weekly_hit') for f in files) else 'no')
" 2>/dev/null)

if [[ "$WEEKLY_HIT" == "yes" ]] && [[ ! -f "$WEEKLY_FLAG" ]]; then
    touch "$WEEKLY_FLAG"
    MSG="Weekly limit hit — Claude Espresso will resume when your 7-day window resets."
    case "$(uname -s)" in
        Darwin)
            osascript -e "display notification \"$MSG\" with title \"Claude Espresso ☕\" sound name \"Basso\"" 2>/dev/null || true
            ;;
        Linux)
            notify-send "Claude Espresso ☕" "$MSG" 2>/dev/null || true
            ;;
        MINGW*|MSYS*|CYGWIN*)
            powershell.exe -Command "
                Add-Type -AssemblyName System.Windows.Forms
                [System.Windows.Forms.MessageBox]::Show('$MSG','Claude Espresso')
            " 2>/dev/null || true
            ;;
    esac
elif [[ "$WEEKLY_HIT" == "no" ]]; then
    rm -f "$WEEKLY_FLAG"
fi

exit 0
STOP_HOOK

# ── 5. StatusLine Hook ────────────────────────────────────────────────────────

cat > "$HOME/.claude/scripts/statusline-hook.sh" << 'STATUSLINE_HOOK'
#!/bin/bash
# Claude Espresso — StatusLine Hook
# Captures exact 5-hour and 7-day reset timestamps after every response,
# and outputs an Espresso status indicator for the Claude Code status bar.

STATE_FILE="$HOME/.claude/rate-limit-state.json"
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
cat > "$TMPFILE"

STATE_FILE="$STATE_FILE" TMPFILE="$TMPFILE" python3 - <<'PYEOF'
import json, sys, os, time

tmpfile    = os.environ['TMPFILE']
state_file = os.environ['STATE_FILE']

cwd = ''
try:
    with open(tmpfile) as f:
        data = json.load(f)
    cwd = data.get('cwd', '') or data.get('session', {}).get('cwd', '')
    rl = data.get('rate_limits', {})
    if rl:
        five  = rl.get('five_hour', {})
        seven = rl.get('seven_day', {})
        state = {
            'updated_at': int(time.time()),
            'five_hour': {'used_pct': five.get('used_percentage', 0), 'resets_at': five.get('resets_at', 0)},
            'seven_day': {'used_pct': seven.get('used_percentage', 0), 'resets_at': seven.get('resets_at', 0)},
        }
        with open(state_file, 'w') as f:
            json.dump(state, f, indent=2)
except Exception:
    pass

if cwd:
    cp       = os.path.join(cwd, '.claude', 'checkpoint.md')
    settings = os.path.join(cwd, '.claude', 'settings.json')
    indicator = ''
    try:
        if os.path.exists(cp):
            with open(cp) as f:
                for line in f:
                    if line.startswith('status:'):
                        if 'in_progress' in line:
                            indicator = '☕ Espresso armed'
                        break
        if not indicator and os.path.exists(settings):
            with open(settings) as f:
                for line in f:
                    if 'auto-armed' in line or 'auto-espresso' in line:
                        indicator = '⚡ Auto-Espresso on'
                        break
    except Exception:
        pass
    if indicator:
        print(indicator)
PYEOF

exit 0
STATUSLINE_HOOK

# ── 6. Resume Checker ─────────────────────────────────────────────────────────

cat > "$HOME/.claude/scripts/resume-check.sh" << RESUME_CHECK
#!/bin/bash
# Claude Espresso — Resume Checker
# Runs every 15 minutes. Fires resumes when the reset time passes.

PENDING_DIR="\$HOME/.claude/pending-resumes"
CLAUDE_BIN="$CLAUDE_BIN"
LOG="\$HOME/.claude/espresso.log"
NOW=\$(date +%s)

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG"; }

# Trim log to last 500 lines
if [[ -f "\$LOG" ]] && [[ \$(wc -l < "\$LOG") -gt 500 ]]; then
    tail -n 500 "\$LOG" > "\$LOG.tmp" && mv "\$LOG.tmp" "\$LOG"
fi

[[ -d "\$PENDING_DIR" ]] || exit 0

# Cross-platform file modification time
file_mtime() {
    case "\$(uname -s)" in
        Darwin) date -r "\$1" +%s 2>/dev/null ;;
        *)      stat -c %Y "\$1" 2>/dev/null ;;
    esac
}

for RESUME_FILE in "\$PENDING_DIR"/*.json; do
    [[ -f "\$RESUME_FILE" ]] || continue

    unset PROJECT_DIR CHECKPOINT RESUME_AT LIMIT_TYPE PARSE_ERROR

    eval "\$(RESUME_FILE="\$RESUME_FILE" python3 - <<'PYEOF'
import json, os
try:
    with open(os.environ['RESUME_FILE']) as f:
        d = json.load(f)
    print(f"PROJECT_DIR={repr(d['project_dir'])}")
    print(f"CHECKPOINT={repr(d['checkpoint'])}")
    print(f"RESUME_AT={d['resume_at']}")
    print(f"LIMIT_TYPE={repr(d.get('limit_type','5-hour'))}")
except Exception as e:
    print(f"PARSE_ERROR={repr(str(e))}")
PYEOF
)"

    if [[ -n "\${PARSE_ERROR:-}" ]]; then
        log "Failed to parse \$RESUME_FILE — skipping"; continue
    fi

    if [[ \$NOW -lt \$RESUME_AT ]]; then
        REMAINING=\$(( RESUME_AT - NOW ))
        log "[\$LIMIT_TYPE] Waiting for \$(basename "\$PROJECT_DIR") — \$(( REMAINING / 3600 ))h \$(( (REMAINING % 3600) / 60 ))m remaining"
        continue
    fi

    if [[ ! -f "\$CHECKPOINT" ]]; then
        log "Checkpoint gone — removing resume"; rm -f "\$RESUME_FILE"; continue
    fi

    STATUS=\$(grep -m1 '^status:' "\$CHECKPOINT" 2>/dev/null | sed 's/status:[[:space:]]*//' | tr -d '"' | tr -d "'" | xargs)
    if [[ "\$STATUS" == "complete" ]]; then
        log "Task complete in \$PROJECT_DIR — removing resume"; rm -f "\$RESUME_FILE"; continue
    fi

    LOCK_FILE="\$PROJECT_DIR/.claude/resume.lock"
    if [[ -f "\$LOCK_FILE" ]]; then
        LOCK_MTIME=\$(file_mtime "\$LOCK_FILE" || echo "\$NOW")
        LOCK_AGE=\$(( NOW - LOCK_MTIME ))
        if [[ \$LOCK_AGE -lt 3600 ]]; then
            log "Resume already running for \$(basename "\$PROJECT_DIR") (lock age: \${LOCK_AGE}s)"; continue
        else
            log "Stale lock — removing"; rm -f "\$LOCK_FILE"
        fi
    fi

    rm -f "\$RESUME_FILE"
    touch "\$LOCK_FILE"
    log "Resuming [\$LIMIT_TYPE] task in \$PROJECT_DIR"

    (
        cd "\$PROJECT_DIR" && \
        nohup "\$CLAUDE_BIN" --dangerously-skip-permissions -p \
            "Read .claude/checkpoint.md. First, immediately add a 'resumed_at' timestamp to the Notes section so this session is recorded even if interrupted. Then resume the task exactly from where it left off. After each step you complete, update the Completed steps and Current step fields. When the full task is done, set status to complete and delete .claude/resume.lock." \
            >> "\$LOG" 2>&1 &
        log "Launched resume process (PID: \$!) for \$(basename "\$PROJECT_DIR")"
    )
done
RESUME_CHECK

# ── 7. Skills ─────────────────────────────────────────────────────────────────

cat > "$HOME/.claude/commands/limit-restart.md" << 'SKILL_RESTART'
Activate Claude Espresso for a long-running task in the current project.

When this skill is invoked:

1. Ask the user to describe the task if they haven't already. If the task is already clear from context, skip asking.

2. Create the `.claude/` directory in the current project if it doesn't exist.

3. Write `.claude/checkpoint.md` with this exact format:
```
status: in_progress
project_dir: <absolute path to current working directory>
task: <one sentence summary of what we're doing>
started_at: <current ISO timestamp>

## Task breakdown
<numbered list of every step needed to complete the full task>

## Completed steps
(none yet)

## Current step
<first step>

## Next step
<second step>

## Files modified
(none yet)

## Notes
<any important context, constraints, or decisions>
```

4. Tell the user: "☕ Claude Espresso is armed. If you hit your usage limit, I'll automatically pick back up when your window resets — you don't need to do anything."

5. Begin the task immediately.

---

While working through the task, after EVERY significant step:
- Move completed step into "Completed steps"
- Update "Current step" and "Next step"
- Add modified files to "Files modified"
- Add any decisions or blockers to "Notes"

Keep checkpoints factual — enough for a fresh Claude session to pick up cold.

---

When the task is fully done:
1. Set `status: complete` in `.claude/checkpoint.md`
2. Delete `.claude/resume.lock` if it exists
3. Tell the user the task is complete and Claude Espresso has disarmed.
SKILL_RESTART

cat > "$HOME/.claude/commands/limit-cancel.md" << 'SKILL_CANCEL'
Cancel a queued Claude Espresso resume for the current project.

When this skill is invoked:

1. Check if `.claude/checkpoint.md` exists in the current project.
   - If not, tell the user: "No active Claude Espresso task found for this project."
   - Stop here.

2. Update `.claude/checkpoint.md` — set `status: cancelled`

3. Delete `.claude/resume.lock` if it exists in this project.

4. Run this shell command to remove the pending resume:
```bash
python3 -c "
import hashlib, os, glob, json
cwd = os.getcwd()
h = hashlib.md5(cwd.encode()).hexdigest()[:8]
f = os.path.expanduser(f'~/.claude/pending-resumes/{h}.json')
if os.path.exists(f):
    os.remove(f); print('Pending resume removed.')
else:
    found = False
    for pf in glob.glob(os.path.expanduser('~/.claude/pending-resumes/*.json')):
        try:
            d = json.load(open(pf))
            if d.get('project_dir') == cwd:
                os.remove(pf); print('Pending resume removed.'); found = True; break
        except Exception: pass
    if not found: print('No pending resume file found (may have already fired).')
"
```

5. Tell the user: "Claude Espresso cancelled. The task was left at whatever step it reached."
SKILL_CANCEL

ok "Scripts and skills written"

# ── 8. Permissions ────────────────────────────────────────────────────────────

chmod +x "$HOME/.claude/scripts/stop-hook.sh"
chmod +x "$HOME/.claude/scripts/statusline-hook.sh"
chmod +x "$HOME/.claude/scripts/resume-check.sh"
ok "Scripts made executable"

# ── 9. Update settings.json ───────────────────────────────────────────────────

python3 - <<PYEOF
import json, os

settings_path  = os.path.expanduser('~/.claude/settings.json')
hook_cmd       = 'bash $HOME/.claude/scripts/stop-hook.sh'
statusline_cmd = 'bash $HOME/.claude/scripts/statusline-hook.sh'

settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except Exception as e:
        print(f'Warning: could not read existing settings.json: {e}')

settings['statusLine'] = {'type': 'command', 'command': statusline_cmd}

new_entry = {'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 30}]}
if 'hooks' not in settings:
    settings['hooks'] = {}
existing = settings['hooks'].get('Stop', [])
already = any(any(h.get('command') == hook_cmd for h in e.get('hooks', [])) for e in existing)
if not already:
    settings['hooks']['Stop'] = existing + [new_entry]

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
print('settings.json updated')
PYEOF

ok "settings.json updated (existing settings preserved)"

# ── 10. Background Scheduler ──────────────────────────────────────────────────

case "$PLATFORM" in

    macos)
        PLIST="$HOME/Library/LaunchAgents/com.claude.espresso.plist"
        cat > "$PLIST" << PLIST_CONTENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.espresso</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/.claude/scripts/resume-check.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.claude/espresso.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.claude/espresso.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname "$CLAUDE_BIN"):/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
</dict>
</plist>
PLIST_CONTENT
        launchctl unload "$PLIST" 2>/dev/null || true
        launchctl load "$PLIST"
        ok "Background checker installed via launchd (every 15 min)"
        ;;

    linux)
        CRON_LINE="*/15 * * * * /bin/bash $HOME/.claude/scripts/resume-check.sh >> $HOME/.claude/espresso.log 2>&1"
        # Add to crontab if not already there
        if crontab -l 2>/dev/null | grep -q "espresso"; then
            warn "Cron entry already exists — skipping"
        else
            (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
            ok "Background checker installed via cron (every 15 min)"
        fi
        ;;

    windows)
        # Requires Git Bash. Convert path to Windows format for Task Scheduler.
        WIN_SCRIPT=$(cygpath -w "$HOME/.claude/scripts/resume-check.sh" 2>/dev/null || echo "$HOME/.claude/scripts/resume-check.sh")
        WIN_BASH=$(cygpath -w "$(which bash)" 2>/dev/null || echo "bash")
        WIN_LOG=$(cygpath -w "$HOME/.claude/espresso.log" 2>/dev/null || echo "$HOME/.claude/espresso.log")
        schtasks //Create //TN "ClaudeEspresso" \
            //TR "\"$WIN_BASH\" \"$WIN_SCRIPT\" >> \"$WIN_LOG\" 2>&1" \
            //SC MINUTE //MO 15 //F 2>/dev/null \
            && ok "Background checker installed via Task Scheduler (every 15 min)" \
            || warn "Could not install Task Scheduler task — run resume-check.sh manually or use WSL"
        ;;
esac

# ── 11. Prompt Indicator ──────────────────────────────────────────────────────

SHELL_NAME=$(basename "$SHELL")
SHELL_RC=""
case "$SHELL_NAME" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
esac

if [[ -n "$SHELL_RC" ]]; then
    if grep -q "# claude-espresso-prompt" "$SHELL_RC" 2>/dev/null; then
        warn "Prompt indicator already in $SHELL_RC — skipping"
    else
        if [[ "$SHELL_NAME" == "zsh" ]]; then
            cat >> "$SHELL_RC" << 'ZSH_PROMPT'

# claude-espresso-prompt — added by Claude Espresso installer
_espresso_update() {
  local cp="$PWD/.claude/checkpoint.md"
  local s="$PWD/.claude/settings.json"
  local content
  if [[ -f $cp ]]; then
    content=$(<$cp)
    if [[ $content == *'status: in_progress'* ]]; then
      ESPRESSO_STATUS='☕ '; return
    fi
  fi
  if [[ -f $s ]]; then
    content=$(<$s)
    if [[ $content == *'auto-armed'* || $content == *'auto-espresso'* ]]; then
      ESPRESSO_STATUS='⚡ '; return
    fi
  fi
  ESPRESSO_STATUS=''
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _espresso_update
_espresso_update
setopt PROMPT_SUBST
if [[ "$PROMPT" != *ESPRESSO_STATUS* ]] && [[ "$RPROMPT" != *ESPRESSO_STATUS* ]]; then
  PROMPT='${ESPRESSO_STATUS}'"$PROMPT"
fi
# claude-espresso-prompt-end
ZSH_PROMPT
        else
            cat >> "$SHELL_RC" << 'BASH_PROMPT'

# claude-espresso-prompt — added by Claude Espresso installer
_espresso_update() {
  local cp="$PWD/.claude/checkpoint.md"
  local s="$PWD/.claude/settings.json"
  local content
  if [[ -f $cp ]]; then
    content=$(cat "$cp")
    if [[ $content == *'status: in_progress'* ]]; then
      ESPRESSO_STATUS='☕ '; return
    fi
  fi
  if [[ -f $s ]]; then
    content=$(cat "$s")
    if [[ $content == *'auto-armed'* || $content == *'auto-espresso'* ]]; then
      ESPRESSO_STATUS='⚡ '; return
    fi
  fi
  ESPRESSO_STATUS=''
}
_espresso_prompt_cmd() { PS1="${ESPRESSO_STATUS}${PS1_BASE:-\u@\h:\w\$ }"; }
PS1_BASE="${PS1}"
PROMPT_COMMAND="_espresso_prompt_cmd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
cd() { builtin cd "$@" && _espresso_update; }
_espresso_update
# claude-espresso-prompt-end
BASH_PROMPT
        fi
        ok "Prompt indicator added to $SHELL_RC"
        warn "Run: source $SHELL_RC   (or open a new terminal) to activate"
    fi
else
    warn "Unknown shell '$SHELL_NAME' — skipping prompt indicator (run /limit-prompt in Claude Code to install manually)"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "======================================"
echo -e "${GREEN}☕ Claude Espresso installed.${NC}"
echo ""
echo "Commands:"
echo "  /limit-restart   — arm auto-resume at the start of a big task"
echo "  /limit-cancel    — cancel a queued resume"
echo "  /limit-prompt    — install/reinstall the terminal prompt indicator"
echo ""
echo "Prompt indicator:"
echo "  ☕  = task is armed (checkpoint in_progress)"
echo "  ⚡  = limit-auto is configured for this folder"
echo ""
echo "Logs: ~/.claude/espresso.log"
echo ""
echo "Restart Claude Code now to activate the hooks."
echo ""
