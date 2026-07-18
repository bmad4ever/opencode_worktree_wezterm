---
description: Commit and merge the current OpenCode worktree branch into main
---
!`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ([Environment]::GetFolderPath('UserProfile') + '\.config\opencode\scripts\mergeworktree.ps1') -CommitMessage '$ARGUMENTS'"`

Report the result above. If it failed, explain the exact next step needed.
