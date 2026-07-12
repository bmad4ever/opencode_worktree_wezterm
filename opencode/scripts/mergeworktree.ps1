[CmdletBinding()]
param(
  [string]$MainBranch,
  [string]$CommitMessage
)

function Fail($Message) {
  Write-Output "ERROR: $Message"
  exit 1
}

function Require-Command($Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Fail "$Name is not available"
  }
}

function Test-UncommittedChanges($Repo, $Exclude) {
  $lines = (& git -C $Repo status --porcelain)
  if ([string]::IsNullOrWhiteSpace($lines)) { return $false }
  foreach ($line in $lines) {
    if ($Exclude -and ($line -match [regex]::Escape($Exclude))) { continue }
    return $true
  }
  return $false
}

function Get-DefaultBranch {
  $originHead = (& git symbolic-ref refs/remotes/origin/HEAD 2>$null)
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($originHead)) {
    return ($originHead.Trim() -replace '^refs/remotes/origin/', '')
  }

  foreach ($candidate in @("main", "master", "trunk")) {
    & git show-ref --verify --quiet "refs/heads/$candidate"
    if ($LASTEXITCODE -eq 0) {
      return $candidate
    }
  }

  return $null
}

function Get-WorktreePathForBranch($BranchName) {
  $currentPath = $null

  foreach ($line in (& git worktree list --porcelain)) {
    if ($line -like "worktree *") {
      $currentPath = $line.Substring("worktree ".Length)
      continue
    }

    if ($line -like "branch refs/heads/*") {
      $foundBranch = $line.Substring("branch refs/heads/".Length)
      if ($foundBranch -eq $BranchName) {
        return $currentPath
      }
    }
  }

  return $null
}

Require-Command git

if ([string]::IsNullOrWhiteSpace($MainBranch)) {
  if ($env:OPENCODE_WORK_TREE_MAIN_BRANCH) {
    $MainBranch = $env:OPENCODE_WORK_TREE_MAIN_BRANCH
  } else {
    $detected = Get-DefaultBranch
    if ([string]::IsNullOrWhiteSpace($detected)) {
      $available = ((& git branch --format="%(refname:short)") -join ", ")
      Fail "could not detect the main branch; pass -MainBranch explicitly. Local branches: $available"
    }
    $MainBranch = $detected
  }
}
if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
  $CommitMessage = if ($env:OPENCODE_WORK_TREE_COMMIT_MESSAGE) { $env:OPENCODE_WORK_TREE_COMMIT_MESSAGE } else { "opencode worktree changes" }
}

$currentRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentRoot)) {
  Fail "not inside a git worktree"
}

$currentRoot = $currentRoot.Trim()
$currentBranch = (& git -C $currentRoot branch --show-current).Trim()

if ([string]::IsNullOrWhiteSpace($currentBranch)) {
  Fail "current worktree is detached; merge from a named branch"
}

if ($currentBranch -eq $MainBranch) {
  Fail "run this from the feature worktree, not $MainBranch"
}

& git -C $currentRoot show-ref --verify --quiet "refs/heads/$MainBranch"
if ($LASTEXITCODE -ne 0) {
  Fail "local branch $MainBranch does not exist; pass -MainBranch if it's named differently"
}

$mainWorktree = Get-WorktreePathForBranch $MainBranch
if ([string]::IsNullOrWhiteSpace($mainWorktree)) {
  Fail "$MainBranch is not checked out in another worktree"
}

# Keep .opencode/ (which holds the worktrees) out of git tracking in the main repo.
$gitignore = Join-Path $mainWorktree ".gitignore"
$needed = $true
if (Test-Path -LiteralPath $gitignore) {
  $existing = Get-Content -LiteralPath $gitignore -Raw
  if ($existing -match '(?m)^/?\.opencode/\s*$') { $needed = $false }
}
if ($needed) {
  Add-Content -LiteralPath $gitignore -Value "`n.opencode/"
  & git -C $mainWorktree add -A
  & git -C $mainWorktree commit -q -m "chore: ignore .opencode directory"
  if ($LASTEXITCODE -ne 0) {
    Fail "failed to record .opencode ignore in $MainBranch; check $mainWorktree state"
  }
  Write-Output "Added .opencode/ to $MainBranch .gitignore"
}

if (Test-UncommittedChanges $currentRoot) {
  & git -C $currentRoot add -A
  if ($LASTEXITCODE -ne 0) {
    Fail "failed to stage worktree changes"
  }

  & git -C $currentRoot commit -m $CommitMessage
  if ($LASTEXITCODE -ne 0) {
    Fail "failed to commit worktree changes"
  }
}

if (Test-UncommittedChanges $mainWorktree ".opencode/") {
  Fail "$MainBranch worktree has uncommitted changes (excluding .opencode); clean or commit them before merging"
}

& git -C $mainWorktree merge --no-ff $currentBranch -m "Merge $currentBranch into $MainBranch"
if ($LASTEXITCODE -ne 0) {
  Fail "failed to merge $currentBranch into $MainBranch"
}

Write-Output "Merged branch $currentBranch into $MainBranch at $mainWorktree"
