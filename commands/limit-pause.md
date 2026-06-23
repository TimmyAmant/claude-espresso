Pause a queued Claude Espresso resume for the current project without losing the task checkpoint.

Unlike /limit-cancel (which marks the task cancelled), pausing keeps the checkpoint intact so you can resume later with /limit-restart.

When this skill is invoked:

1. Check if `.claude/checkpoint.md` exists in the current project.
   - If not, tell the user: "No active Claude Espresso task found for this project." Stop here.

2. Read the current status from `.claude/checkpoint.md`.
   - If status is already `paused`, tell the user: "Espresso is already paused. Run /limit-restart to re-arm it." Stop here.
   - If status is `cancelled` or `complete`, tell the user the task is already done/cancelled and they should run /limit-restart for a new task. Stop here.

3. Update `.claude/checkpoint.md` — change status to `paused`:
```bash
python3 -c "
import os, re
cp = os.path.join(os.getcwd(), '.claude/checkpoint.md')
text = open(cp).read()
new_text = re.sub(r'^status:.*$', 'status: paused', text, count=1, flags=re.MULTILINE)
if new_text == text:
    new_text = 'status: paused\n' + text
tmp = cp + '.tmp'
open(tmp, 'w').write(new_text)
os.replace(tmp, cp)
print('Status set to: paused')
"
```

4. Remove the pending resume file:
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
        except: pass
    if not found: print('No pending resume file found (may not have been queued yet).')
"
```

5. Cancel any scheduled desktop notification for this project:
```bash
python3 -c "
import hashlib, os
cwd = os.getcwd()
h = hashlib.md5(cwd.encode()).hexdigest()[:8]
label = f'com.claude.espresso.notify.{h}'
plist = os.path.expanduser(f'~/Library/LaunchAgents/{label}.plist')
if os.path.exists(plist):
    os.system(f'launchctl unload \"{plist}\" 2>/dev/null')
    os.remove(plist)
    print('Scheduled notification removed.')
"
```

6. Tell the user: "Claude Espresso paused. The task checkpoint is saved. Run /limit-restart when you want to re-arm it — I'll pick up from where we left off."
