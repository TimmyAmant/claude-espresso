Install a terminal prompt indicator for Claude Espresso.

Shows a `☕` icon when Espresso is armed (checkpoint in_progress) and a `⚡` icon when limit-auto is configured for the current directory. The indicator updates automatically as you cd between folders.

When this skill is invoked:

1. Detect the user's shell and RC file:
```bash
python3 -c "
import os, subprocess
shell = os.environ.get('SHELL', '')
name = os.path.basename(shell)
rc = os.path.expanduser('~/.zshrc') if name == 'zsh' else os.path.expanduser('~/.bashrc')
print(f'SHELL_NAME={name}')
print(f'SHELL_RC={rc}')
"
```

2. Check if already installed:
```bash
python3 -c "
import os
rc = os.path.expanduser('~/.zshrc')
if not os.path.exists(rc):
    rc = os.path.expanduser('~/.bashrc')
content = open(rc).read() if os.path.exists(rc) else ''
print('FOUND' if '# claude-espresso-prompt' in content else 'NONE')
"
```
If already installed, tell the user "Espresso prompt indicator is already installed." and stop.

3. Detect if the user already has a PROMPT/PS1 set in their RC file:
```bash
grep -n "^PROMPT\|^PS1\|^export PS1\|^export PROMPT" ~/.zshrc ~/.bashrc 2>/dev/null | head -5 || echo "NONE"
```

4. Add the indicator to the shell RC file. Read the RC file first, then append this block:

**For zsh** (append to `~/.zshrc`):
```bash
python3 << 'PYEOF'
import os, re

rc = os.path.expanduser('~/.zshrc')
content = open(rc).read() if os.path.exists(rc) else ''

# Don't double-install
if '# claude-espresso-prompt' in content:
    print('Already installed.')
    exit()

snippet = '''
# claude-espresso-prompt — added by /limit-prompt
_espresso_update() {
  local cp="$PWD/.claude/checkpoint.md"
  local s="$PWD/.claude/settings.json"
  local content
  if [[ -f $cp ]]; then
    content=$(<$cp)
    if [[ $content == *\'status: in_progress\'* ]]; then
      ESPRESSO_STATUS=\'\\u2615 \'; return
    fi
  fi
  if [[ -f $s ]]; then
    content=$(<$s)
    if [[ $content == *\'auto-armed\'* || $content == *\'auto-espresso\'* ]]; then
      ESPRESSO_STATUS=\'\\u26a1 \'; return
    fi
  fi
  ESPRESSO_STATUS=\'\'
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _espresso_update
_espresso_update
setopt PROMPT_SUBST
if [[ "$PROMPT" != *ESPRESSO_STATUS* ]] && [[ "$RPROMPT" != *ESPRESSO_STATUS* ]]; then
  PROMPT=\'${ESPRESSO_STATUS}\'"$PROMPT"
fi
# claude-espresso-prompt-end
'''

with open(rc, 'a') as f:
    f.write(snippet)
print(f'Added Espresso prompt indicator to {rc}')
PYEOF
```

**For bash** (append to `~/.bashrc`):
```bash
python3 << 'PYEOF'
import os

rc = os.path.expanduser('~/.bashrc')
content = open(rc).read() if os.path.exists(rc) else ''

if '# claude-espresso-prompt' in content:
    print('Already installed.')
    exit()

snippet = '''
# claude-espresso-prompt — added by /limit-prompt
_espresso_indicator() {
  local cp="$PWD/.claude/checkpoint.md"
  local settings="$PWD/.claude/settings.json"
  if [[ -f "$cp" ]] && grep -q "^status: in_progress" "$cp" 2>/dev/null; then
    printf '☕ '
  elif [[ -f "$settings" ]] && grep -qE 'auto-armed|auto-espresso' "$settings" 2>/dev/null; then
    printf '⚡ '
  fi
}
_espresso_prompt_cmd() {
  local indicator
  indicator="$(_espresso_indicator)"
  # Prepend to PS1, remove any previous indicator first
  PS1="${indicator}${PS1_BASE:-\\u@\\h:\\w\\$ }"
}
PS1_BASE="${PS1}"
PROMPT_COMMAND="_espresso_prompt_cmd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
# claude-espresso-prompt-end
'''

with open(rc, 'a') as f:
    f.write(snippet)
print(f'Added Espresso prompt indicator to {rc}')
PYEOF
```

5. Tell the user:

"Espresso prompt indicator installed!

- `☕` appears when a task is armed (checkpoint in_progress) in the current folder
- `⚡` appears when limit-auto is configured for the current folder

Run `source ~/.zshrc` (or open a new terminal) to activate it."

6. Ask the user if they want to source the RC file now. If yes, tell them to run:
```
source ~/.zshrc
```
(Note: Claude cannot source a shell file into the user's live terminal session — they need to run this themselves.)
