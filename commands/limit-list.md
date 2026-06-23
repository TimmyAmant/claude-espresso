List all projects that have Claude Espresso resumes queued or active.

When this skill is invoked:

1. Run this script to find all Espresso activity:
```bash
python3 -c "
import json, os, glob, time

pending_dir = os.path.expanduser('~/.claude/pending-resumes')
now = int(time.time())

files = glob.glob(os.path.join(pending_dir, '*.json'))
files = [f for f in files if not os.path.basename(f).startswith('.')]

if not files:
    print('No pending Espresso resumes found.')
else:
    print(f'Pending resumes ({len(files)}):')
    print()
    rows = []
    for pf in sorted(files):
        try:
            d = json.load(open(pf))
            project_dir = d.get('project_dir', '?')
            project_name = os.path.basename(project_dir)
            resume_at = d.get('resume_at', 0)
            resume_human = d.get('resume_at_human', '?')
            limit_type = d.get('limit_type', '?')
            secs_left = resume_at - now
            if secs_left > 0:
                h, rem = divmod(secs_left, 3600)
                m = rem // 60
                when = f'in {h}h {m}m ({resume_human})'
            else:
                when = f'overdue ({resume_human})'

            task = '?'
            cp = os.path.join(project_dir, '.claude/checkpoint.md')
            if os.path.exists(cp):
                for line in open(cp):
                    if line.startswith('task:'): task = line.split(':', 1)[1].strip(); break

            rows.append((project_name, when, limit_type, task, project_dir))
        except Exception as e:
            rows.append(('?', '?', '?', str(e), pf))

    for name, when, ltype, task, path in rows:
        print(f'  {name}')
        print(f'    Resumes: {when}')
        print(f'    Limit:   {ltype}')
        print(f'    Task:    {task}')
        print(f'    Path:    {path}')
        print()
"
```

2. Display the output to the user.

3. If no pending resumes were found, also check if any projects have a `.claude/checkpoint.md` with `status: in_progress` (armed but not yet hit the limit):
```bash
python3 -c "
import os, glob
home = os.path.expanduser('~')
claude_dir = os.path.join(home, '.claude')
checkpoints = [
    cp for cp in glob.glob(os.path.join(home, '**/.claude/checkpoint.md'), recursive=True)
    if not cp.startswith(claude_dir + os.sep)
]
armed = []
for cp in checkpoints:
    try:
        lines = open(cp).readlines()
    except OSError:
        continue
    status = next((l.split(':',1)[1].strip() for l in lines if l.startswith('status:')), '')
    if status == 'in_progress':
        project_dir = os.path.dirname(os.path.dirname(cp))
        task = next((l.split(':',1)[1].strip() for l in lines if l.startswith('task:')), '?')
        armed.append((os.path.basename(project_dir), project_dir, task))
if armed:
    print(f'Armed but not yet limited ({len(armed)}):')
    for name, path, task in armed:
        print(f'  {name} — {task}')
        print(f'    {path}')
"
```

4. Tell the user they can run `/limit-cancel` inside any project to remove its queued resume.
