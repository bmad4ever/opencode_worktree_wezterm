[CmdletBinding()]
param(
  [string]$Branch,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Rest
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

# Parse trailing args: collect each "--link <dir>" into $LinkDir.
$LinkDir = @()
if ($Rest) {
  for ($i = 0; $i -lt $Rest.Count; $i++) {
    $token = $Rest[$i]
    if ($token -eq "--link") {
      $i++
      if ($i -ge $Rest.Count -or [string]::IsNullOrWhiteSpace($Rest[$i])) {
        Fail "--link requires a directory argument"
      }
      $LinkDir += $Rest[$i].Trim().TrimEnd('/', '\')
    } else {
      Fail "unknown argument: $token"
    }
  }
}

if ([string]::IsNullOrWhiteSpace($Branch)) {
  if ($env:OPENCODE_WORKTREE_BRANCH) {
    $Branch = $env:OPENCODE_WORKTREE_BRANCH
  } else {
    Fail "no branch name provided (pass <branch> or set OPENCODE_WORKTREE_BRANCH)"
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
  if ($LinkDir.Count -gt 0) {
    foreach ($dir in $LinkDir) {
      Write-Output "WARN: --link $dir ignored on reuse; '$dir' left as-is (not converted to a junction)"
    }
  }
} else {
  $branchExists = $false
  & git -C $repoRoot show-ref --verify --quiet "refs/heads/$Branch"
  if ($LASTEXITCODE -eq 0) { $branchExists = $true }

  if ($LinkDir.Count -eq 0) {
    # Default behavior: full checkout copy.
    if ($branchExists) {
      & git -C $repoRoot worktree add "$worktree" "$Branch"
    } else {
      & git -C $repoRoot worktree add -b "$Branch" "$worktree"
    }
    if ($LASTEXITCODE -ne 0) {
      Fail "failed to create worktree at $worktree"
    }
  } else {
    # Link mode: create worktree without checkout, exclude linked dirs via
    # sparse-checkout, then junction them to the main repo (no copy).
    $linkableDirs = @()
    foreach ($dir in $LinkDir) {
      $tracked = & git -C $repoRoot ls-files -- "$dir"
      if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($tracked | Select-Object -First 1))) {
        Write-Output "WARN: '$dir' is not a tracked directory in the main repo; it will be copied normally"
      } else {
        $linkableDirs += $dir
      }
    }

    if ($branchExists) {
      & git -C $repoRoot worktree add --no-checkout "$worktree" "$Branch"
    } else {
      & git -C $repoRoot worktree add --no-checkout -b "$Branch" "$worktree"
    }
    if ($LASTEXITCODE -ne 0) {
      Fail "failed to create worktree at $worktree"
    }

    if ($linkableDirs.Count -eq 0) {
      # Nothing linkable after validation; fall back to a normal checkout.
      & git -C $worktree checkout
      if ($LASTEXITCODE -ne 0) { Fail "failed to checkout worktree at $worktree" }
    } else {
      & git -C $worktree config core.sparseCheckout true
      & git -C $worktree config extensions.worktreeConfig true

      $patterns = @("/*")
      foreach ($dir in $linkableDirs) {
        $patterns += "!/$dir/"
      }
      $sparseRel = (& git -C $worktree rev-parse --git-path info/sparse-checkout).Trim()
      if ([System.IO.Path]::IsPathRooted($sparseRel)) {
        $sparseFile = $sparseRel
      } else {
        $sparseFile = Join-Path $worktree $sparseRel
      }
      $sparseDir = Split-Path -Parent $sparseFile
      New-Item -ItemType Directory -Force -Path $sparseDir | Out-Null
      Set-Content -LiteralPath $sparseFile -Value $patterns -Encoding ASCII

      & git -C $worktree checkout
      if ($LASTEXITCODE -ne 0) { Fail "failed to checkout worktree at $worktree" }

      foreach ($dir in $linkableDirs) {
        $linkPath = Join-Path $worktree $dir
        $targetPath = Join-Path $repoRoot $dir
        if (Test-Path -LiteralPath $linkPath) {
          Remove-Item -LiteralPath $linkPath -Recurse -Force
        }
        $linkParent = Split-Path -Parent $linkPath
        New-Item -ItemType Directory -Force -Path $linkParent | Out-Null
        & cmd /c mklink /J "$linkPath" "$targetPath" | Out-Null
        if ($LASTEXITCODE -ne 0) {
          Fail "failed to create junction: $linkPath -> $targetPath"
        }
        Write-Output "Junctioned: $dir -> $targetPath"
      }
    }
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
