---
description: Create an OpenCode worktree and launch it in a right WezTerm pane
---
!`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ([Environment]::GetFolderPath('UserProfile') + '\.config\opencode\scripts\startworktree.ps1') $ARGUMENTS"`

Usage: `/startworktree <branch> [--link <dir> ...]`
  - `--link <dir>` shares a tracked dir (e.g. `assets`) via a junction to the main
    repo instead of copying it into the worktree. Repeatable. Omit for a full copy.

Report the result above. If it failed, explain the exact next step needed.
