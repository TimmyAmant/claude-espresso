Show the current Claude Espresso status for this project.

When this skill is invoked:

1. Run this script to gather all status info:
```bash
python3 -c "
import json, os, glob, hashlib, time

cwd = os.getcwd()
project_name = os.path.basename(cwd)
h = hashlib.md5(cwd.encode()).hexdigest()[:8]

# Check checkpoint
checkpoint = os.path.join(cwd, '.claude/checkpoint.md')
cp_status = None
cp_task = None
if os.path.exists(checkpoint):
    for line in open(checkpoint):
        if line.startswith('status:'): cp_status = line.split(':', 1)[1].strip()
        if line.startswith('task:'): cp_task = line.split(':', 1)[1].strip()

# Check pending resume
pending_file = os.path.expanduser(f'~/.claude/pending-resumes/{h}.json')
resume_data = None
if not os.path.exists(pending_file):
    for pf in glob.glob(os.path.expanduser('~/.claude/pending-resumes/*.json')):
        try:
            d = json.load(open(pf))
            if d.get('project_dir') == cwd:
                resume_data = d; break
        except: pass
else:
    try: resume_data = json.load(open(pending_file))
    except: pass

# Check rate limit state
state_file = os.path.expanduser('~/.claude/rate-limit-state.json')
rate_state = None
if os.path.exists(state_file):
    try: rate_state = json.load(open(state_file))
    except: pass

now = int(time.time())

print(f'Project: {project_name}')
print(f'Dir:     {cwd}')
print()

if cp_status:
    print(f'Checkpoint status: {cp_status}')
    if cp_task: print(f'Task:              {cp_task}')
else:
    print('Checkpoint: none (Espresso not armed for this project)')

print()

if resume_data:
    resume_at = resume_data.get('resume_at', 0)
    resume_human = resume_data.get('resume_at_human', '?')
    limit_type = resume_data.get('limit_type', '?')
    secs_left = resume_at - now
    if secs_left > 0:
        h2, rem = divmod(secs_left, 3600)
        m2 = rem // 60
        print(f'Resume queued: {resume_human} (in {h2}h {m2}m)')
    else:
        print(f'Resume queued: {resume_human} (overdue — should fire soon)')
    print(f'Limit type:    {limit_type}')
else:
    print('No pending resume queued.')

print()

if rate_state:
    updated = rate_state.get('updated_at', 0)
    age_min = (now - updated) // 60
    five = rate_state.get('five_hour', {})
    seven = rate_state.get('seven_day', {})
    print(f'Rate limit state (updated {age_min}m ago):')
    print(f'  5-hour window:  {five.get(\"used_pct\", \"?\"):>3}% used  resets {time.strftime(\"%H:%M\", time.localtime(five.get(\"resets_at\", 0)))}')
    print(f'  7-day window:   {seven.get(\"used_pct\", \"?\"):>3}% used  resets {time.strftime(\"%a %H:%M\", time.localtime(seven.get(\"resets_at\", 0)))}')
"
```

2. Display the output to the user clearly.

3. If checkpoint status is `in_progress` and no pending resume exists, tell the user: "Espresso is armed but no resume is queued yet — one will be created automatically if you hit your rate limit."

4. If checkpoint status is `complete`, tell the user: "The last Espresso task is complete. Run /limit-restart to arm a new one."
