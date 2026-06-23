Cancel a queued Claude Espresso resume for the current project.

When this skill is invoked:

1. Check if `.claude/checkpoint.md` exists in the current project.
   - If not, tell the user: "No active Claude Espresso task found for this project." Stop here.
   - Read the `status:` field.
   - If status is `cancelled`, tell the user: "This task is already cancelled." Stop here.
   - If status is `complete`, tell the user: "This task is already complete — nothing to cancel." Stop here.

2. Update `.claude/checkpoint.md` — set `status: cancelled`:
```bash
python3 -c "
import os, re
cp = os.path.join(os.getcwd(), '.claude/checkpoint.md')
text = open(cp).read()
new_text = re.sub(r'^status:.*$', 'status: cancelled', text, count=1, flags=re.MULTILINE)
if new_text == text:
    new_text = 'status: cancelled\n' + text
tmp = cp + '.tmp'
open(tmp, 'w').write(new_text)
os.replace(tmp, cp)
print('Status set to: cancelled')
"
```

3. Delete `.claude/resume.lock` if it exists in this project:
```bash
python3 -c "
import os
lock = os.path.join(os.getcwd(), '.claude/resume.lock')
if os.path.exists(lock):
    os.remove(lock); print('resume.lock removed.')
"
```

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

6. Tell the user: "Claude Espresso cancelled. The task was left at whatever step it reached."
