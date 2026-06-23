Re-queue the Claude Espresso resume for the current project, recalculating the resume time from current rate limit state.

Use this when the resume time was calculated incorrectly, the queued resume seems stuck, or you want to force an earlier retry.

When this skill is invoked:

1. Check if `.claude/checkpoint.md` exists in the current project.
   - If not, tell the user: "No Claude Espresso checkpoint found for this project. Use /limit-restart to start a new Espresso task." Stop here.
   - Read the `status:` field. If status is `cancelled`, tell the user: "This task was cancelled. Use /limit-restart to start a new Espresso task." Stop here.
   - If status is `complete`, tell the user: "This task is already complete. Use /limit-restart to start a new Espresso task." Stop here.

2. Read the task summary from `.claude/checkpoint.md` and show it to the user so they can confirm it's the right task.

3. Read and remove any existing pending resume, saving its `resume_at` to a temp file as a fallback for step 5:
```bash
python3 -c "
import hashlib, os, glob, json
cwd = os.getcwd()
h = hashlib.md5(cwd.encode()).hexdigest()[:8]
f = os.path.expanduser(f'~/.claude/pending-resumes/{h}.json')
old_resume_at = 0
if os.path.exists(f):
    try: old_resume_at = json.load(open(f)).get('resume_at', 0)
    except: pass
    os.remove(f); print(f'Old pending resume removed (was resume_at={old_resume_at}).')
else:
    found = False
    for pf in glob.glob(os.path.expanduser('~/.claude/pending-resumes/*.json')):
        try:
            d = json.load(open(pf))
            if d.get('project_dir') == cwd:
                old_resume_at = d.get('resume_at', 0)
                os.remove(pf); print(f'Old pending resume removed (was resume_at={old_resume_at}).'); found = True; break
        except: pass
    if not found: print('No pending resume file found (may not have been queued yet).')
open(os.path.expanduser(f'~/.claude/pending-resumes/{h}.old_resume_at'), 'w').write(str(old_resume_at))
"
```

4. If the checkpoint status is `paused`, update it to `in_progress` so the stop-hook will queue further resumes after this session ends:
```bash
python3 -c "
import os, re
cp = os.path.join(os.getcwd(), '.claude/checkpoint.md')
text = open(cp).read()
status = next((l.split(':',1)[1].strip() for l in text.splitlines() if l.startswith('status:')), '')
if status == 'paused':
    new_text = re.sub(r'^status:.*$', 'status: in_progress', text, count=1, flags=re.MULTILINE)
    if new_text == text:
        new_text = 'status: in_progress\n' + text
    tmp = cp + '.tmp'
    open(tmp, 'w').write(new_text)
    os.replace(tmp, cp)
    print('Status updated: paused -> in_progress')
else:
    print(f'Status is already \"{status}\" — no change needed')
"
```

5. Re-queue by writing a new pending resume based on current rate limit state:
```bash
python3 -c "
import json, os, hashlib, time

cwd = os.getcwd()
project_hash = hashlib.md5(cwd.encode()).hexdigest()[:8]
now = int(time.time())
state_file = os.path.expanduser('~/.claude/rate-limit-state.json')
pending_dir = os.path.expanduser('~/.claude/pending-resumes')
os.makedirs(pending_dir, exist_ok=True)

limit_type = '5-hour'
reset_at = 0
weekly_hit = False

if os.path.exists(state_file):
    try:
        state = json.load(open(state_file))
        if now - state.get('updated_at', 0) < 1800:
            five  = state.get('five_hour', {})
            seven = state.get('seven_day', {})
            if seven.get('used_pct', 0) >= 95 and seven.get('resets_at', 0) > 0:
                limit_type = 'weekly'; reset_at = seven['resets_at']; weekly_hit = True
            elif five.get('resets_at', 0) > 0:
                limit_type = '5-hour'; reset_at = five['resets_at']
    except: pass

if reset_at <= now:
    # Fall back to the old resume_at saved by step 3 (scoped to this project's hash).
    fallback_file = os.path.join(pending_dir, f'{project_hash}.old_resume_at')
    try:
        old_resume_at = int(open(fallback_file).read().strip())
    except: old_resume_at = 0
    try: os.remove(fallback_file)
    except: pass
    if old_resume_at > now:
        reset_at = old_resume_at
        limit_type = '5-hour (from previous schedule)'
    else:
        reset_at = now + 7200
        limit_type = '5-hour (estimated)'

reset_human = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(reset_at))
hours_until = (reset_at - now) / 3600

data = {
    'project_dir': cwd,
    'checkpoint': os.path.join(cwd, '.claude/checkpoint.md'),
    'resume_at': reset_at,
    'resume_at_human': reset_human,
    'limit_type': limit_type,
    'weekly_hit': weekly_hit,
    'queued_at': now,
    'retried': True,
}
with open(os.path.join(pending_dir, f'{project_hash}.json'), 'w') as f:
    json.dump(data, f, indent=2)

print(f'Re-queued resume for {reset_human} ({hours_until:.1f}h from now)')
print(f'Limit type: {limit_type}')
"
```

6. Tell the user: "Claude Espresso re-queued. I'll automatically resume at the new calculated time."
