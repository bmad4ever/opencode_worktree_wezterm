[CmdletBinding()]
param(
  [string]$Branch
)

$ErrorActionPreference = "Stop"

function Fail($Message) {
  Write-Output "ERROR: $Message"
  exit 1
}

function Require-Command($Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Fail "$Name is not available"
  }
}

if ([string]::IsNullOrWhiteSpace($Branch)) {
  if ($env:OPENCODE_WORKTREE_BRANCH) {
    $Branch = $env:OPENCODE_WORKTREE_BRANCH
  } else {
    Fail "no branch name provided (pass -Branch or set OPENCODE_WORKTREE_BRANCH)"
  }
}

Require-Command git
Require-Command opencode
Require-Command wezterm

$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
  Fail "not inside a git repository"
}
$repoRoot = $repoRoot.Trim()

$worktree = Join-Path $repoRoot ".opencode\worktree\$Branch"
$opencodeDir = Join-Path $repoRoot ".opencode"
New-Item -ItemType Directory -Force -Path $opencodeDir | Out-Null

if (Test-Path -LiteralPath $worktree) {
  & git -C $worktree rev-parse --is-inside-work-tree *> $null
  if ($LASTEXITCODE -ne 0) {
    Fail "$worktree exists but is not a git worktree"
  }
  Write-Output "Reusing existing worktree: $worktree"
} else {
  & git -C $repoRoot show-ref --verify --quiet "refs/heads/$Branch"
  if ($LASTEXITCODE -eq 0) {
    & git -C $repoRoot worktree add "$worktree" "$Branch"
  } else {
    & git -C $repoRoot worktree add -b "$Branch" "$worktree"
  }
  if ($LASTEXITCODE -ne 0) {
    Fail "failed to create worktree at $worktree"
  }
  Write-Output "Created worktree: $worktree"
}

$worktreePosix = ($worktree -replace '\\', '/')

$currentPaneId = $env:WEZTERM_PANE
if ([string]::IsNullOrWhiteSpace($currentPaneId)) {
  Fail "WEZTERM_PANE is not set; this command must be run from inside a WezTerm pane"
}

$paneId = (& wezterm cli split-pane --pane-id $currentPaneId --right --cwd $worktreePosix -- cmd /c opencode --yolo)
if ($LASTEXITCODE -ne 0) {
  Fail "failed to launch opencode in a new WezTerm pane"
}

Write-Output "Worktree branch: $Branch"
Write-Output "Worktree path: $worktree"
Write-Output "Started opencode --yolo in WezTerm pane: $paneId"
