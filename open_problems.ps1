#
# open_problems.ps1 - open CodeForces problems for the solutions in this repo.
#
# Walks the *.cpp solution files, turns each filename into its problem URL,
# then opens the first N problems (in chronological contest order) that have
# NOT been opened before. Already-opened problems are remembered in
# .opened_problems so reruns never reopen them.
#
# Usage:
#   .\open_problems.ps1            # open the next 20 unopened problems
#   .\open_problems.ps1 10         # open the next 10 unopened problems
#   .\open_problems.ps1 --reset    # forget all opened problems
#
# Set BROWSER to override the opener, e.g. $env:BROWSER = "firefox"
#
# If script execution is blocked, run:
#   powershell -ExecutionPolicy Bypass -File .\open_problems.ps1

$ErrorActionPreference = "Stop"

# Accept an optional positional argument: a count, or "--reset". Using $args
# (instead of a param block) so the double-dash flag is not parsed as a switch.
$Count = if ($args.Count -ge 1) { [string]$args[0] } else { "20" }

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateFile = Join-Path $RepoDir ".opened_problems"

# Pick an opener. Prefer Brave when available, otherwise fall back to the
# system default browser.
function Get-Opener {
  if ($env:BROWSER) {
    return @{ Path = $env:BROWSER; Args = @() }
  }
  $brave = @(
    "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
    "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if ($brave) {
    return @{ Path = $brave; Args = @() }
  }
  return $null
}

$Opener = Get-Opener

if ($Count -eq "--reset") {
  Set-Content -Path $StateFile -Value "" -NoNewline -Encoding ASCII
  Write-Host "Reset: cleared $StateFile"
  exit 0
}

if ($Count -notmatch '^\d+$') {
  Write-Host "Usage: $(Split-Path -Leaf $MyInvocation.MyCommand.Path) [COUNT] | --reset" -ForegroundColor Red
  exit 1
}
$Count = [int]$Count

Set-Location $RepoDir
if (-not (Test-Path $StateFile)) {
  New-Item -ItemType File -Path $StateFile -Force | Out-Null
}

# Build the full list of problem URLs from solution filenames, in chronological
# order (ascending contest id, then problem letter).
# Filename format: <contestId><letter>[-<digits>]-<ProblemName>.cpp
#   e.g. 2266B-ThreePiles.cpp  -> https://codeforces.com/problemset/problem/2266/B
#   e.g. 102694A-CircumferenceOfATree.cpp -> https://codeforces.com/gym/102694/problem/A
$entries = New-Object System.Collections.Generic.List[object]
foreach ($f in Get-ChildItem -Path $RepoDir -Filter *.cpp -File) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  if ($base -cmatch '^(\d+)([A-Z][0-9]?)-') {
    $id = [int]$Matches[1]
    $letter = $Matches[2]
    if ($id -ge 100000) {
      $url = "https://codeforces.com/gym/$id/problem/$letter"
    } else {
      $url = "https://codeforces.com/problemset/problem/$id/$letter"
    }
    $entries.Add([pscustomobject]@{ Id = $id; Letter = $letter; Url = $url })
  }
}

# Sort chronologically and dedupe URLs while keeping order.
$allUrls = New-Object System.Collections.Generic.List[string]
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($e in ($entries | Sort-Object Id, Letter)) {
  if ($seen.Add($e.Url)) {
    $allUrls.Add($e.Url)
  }
}

$opened = @()
if (Test-Path $StateFile) {
  $opened = Get-Content $StateFile | Where-Object { $_ -ne "" }
}
$openedSet = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]$opened,
  [System.StringComparer]::Ordinal
)

$unopened = @($allUrls | Where-Object { -not $openedSet.Contains($_) })

$totalAll = $allUrls.Count
$totalOpen = $unopened.Count

if ($totalOpen -eq 0) {
  Write-Host "Nothing left to open - all $totalAll problems have been opened already."
  Write-Host "Run $($MyInvocation.MyCommand.Path) --reset to forget them."
  exit 0
}

# Pick the next COUNT unopened problems in chronological order.
$picked = @($unopened | Select-Object -First $Count)

Write-Host "Opening $($picked.Count) problem(s) (out of $totalOpen still unopened, $totalAll total):"
foreach ($url in $picked) {
  Write-Host "  $url"
  Add-Content -Path $StateFile -Value $url
  if ($Opener) {
    Start-Process -FilePath $Opener.Path -ArgumentList @($Opener.Args + $url) | Out-Null
  } else {
    Start-Process $url
  }
  Start-Sleep -Milliseconds 400
}

Write-Host "Done. Progress: $($totalAll - $totalOpen + $picked.Count)/$totalAll opened."
