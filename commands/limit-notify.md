Set up a desktop notification to fire when a Claude Espresso resume is scheduled to happen for this project.

When this skill is invoked:

1. Check if there is a pending resume for this project:
```bash
python3 -c "
import hashlib, os, glob, json
cwd = os.getcwd()
h = hashlib.md5(cwd.encode()).hexdigest()[:8]
f = os.path.expanduser(f'~/.claude/pending-resumes/{h}.json')
data = None
if os.path.exists(f):
    try: data = json.load(open(f))
    except: pass
else:
    for pf in glob.glob(os.path.expanduser('~/.claude/pending-resumes/*.json')):
        try:
            d = json.load(open(pf))
            if d.get('project_dir') == cwd:
                data = d; break
        except: pass
if data:
    print(data['resume_at'])
    print(data['resume_at_human'])
    print(data.get('limit_type', '?'))
else:
    print('NONE')
"
```

   - If output is `NONE`, tell the user: "No pending Espresso resume found for this project. Arm Espresso first with /limit-restart." Stop here.

2. Schedule a macOS notification to fire once at resume time using `launchd`:
```bash
python3 << 'PYEOF'
import json, os, glob, hashlib, time, datetime
import xml.sax.saxutils as sax

cwd = os.getcwd()
project_name = os.path.basename(cwd)
h = hashlib.md5(cwd.encode()).hexdigest()[:8]

# Look up pending resume
data = None
pf_path = os.path.expanduser(f'~/.claude/pending-resumes/{h}.json')
if os.path.exists(pf_path):
    try: data = json.load(open(pf_path))
    except: pass
else:
    for pf in glob.glob(os.path.expanduser('~/.claude/pending-resumes/*.json')):
        try:
            d = json.load(open(pf))
            if d.get('project_dir') == cwd:
                data = d; break
        except: pass

if data is None:
    print('ERROR: pending resume disappeared — run /limit-notify again after checking /limit-status')
    exit(1)

resume_at = data['resume_at']
resume_human = data['resume_at_human']
now = int(time.time())
resume_dt = datetime.datetime.fromtimestamp(resume_at)

label = f'com.claude.espresso.notify.{h}'
plist_path = os.path.expanduser(f'~/Library/LaunchAgents/{label}.plist')

# Build notification message. Pass it as $1 to bash so it's never interpolated
# into the script source — no AppleScript or shell injection possible.
# The bash script also self-deletes the plist (passed as $2) after firing,
# making this a true one-shot. StartCalendarInterval without Year fires annually,
# but self-deletion means the plist won't exist to fire next year.
msg = f'Espresso resuming for {project_name} — open Claude Code to continue.'

# Remove any existing notification plist for this project
os.system(f'launchctl unload "{plist_path}" 2>/dev/null; rm -f "{plist_path}"')

# bash -c 'script' -- $1 $2: $1=message, $2=plist_path for self-cleanup.
# osascript receives message as argv so it is data, not embedded in script source.
# sax.escape() handles XML encoding of all string values.
bash_script = (
    "/usr/bin/osascript -e 'on run argv'"
    " -e 'display notification (item 1 of argv)"
    ' with title "Claude Espresso" sound name "Glass"\''
    " -e 'end run' -- \"$1\""
    '; launchctl unload "$2" 2>/dev/null; rm -f "$2"'
)

plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{sax.escape(label)}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>{sax.escape(bash_script)}</string>
        <string>--</string>
        <string>{sax.escape(msg)}</string>
        <string>{sax.escape(plist_path)}</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Month</key>
        <integer>{resume_dt.month}</integer>
        <key>Day</key>
        <integer>{resume_dt.day}</integer>
        <key>Hour</key>
        <integer>{resume_dt.hour}</integer>
        <key>Minute</key>
        <integer>{resume_dt.minute}</integer>
    </dict>
    <key>LaunchOnlyOnce</key>
    <true/>
</dict>
</plist>"""

with open(plist_path, 'w') as f:
    f.write(plist)

os.system(f'launchctl load "{plist_path}"')
print(f'Notification scheduled for {resume_human}')
print(f'Label: {label}')
PYEOF
```

3. Tell the user: "Notification armed. You'll get a desktop alert when Espresso is ready to resume at [resume_at_human]. No need to watch the clock."

4. Note: If the resume time changes (e.g. after /limit-retry), run /limit-notify again to update it. Running /limit-cancel or /limit-pause will automatically remove the notification too.
