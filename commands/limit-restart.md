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
