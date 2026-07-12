---
description: Commit the current OpenCode worktree and merge its branch into the main repo (local, no remote)
---
!`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ([Environment]::GetFolderPath('UserProfile') + '\.config\opencode\scripts\mergeworktree.ps1') -CommitMessage '$ARGUMENTS'"`

Report the result above. If it failed, explain the exact next step needed.
