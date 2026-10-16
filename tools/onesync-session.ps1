# SessionStart hook: run one onesync round before Claude Code reads its config.
# The repo path is in ~/.claude/.onesync-repo (written by "onesync.ps1 install-hook").
# It prints nothing, because hook output goes into the session context.
$pathFile = Join-Path $HOME '.claude/.onesync-repo'
if (-not (Test-Path -LiteralPath $pathFile)) { exit 0 }
$repo = (Get-Content -LiteralPath $pathFile -Raw).Trim()
$tool = Join-Path $repo 'onesync.ps1'
if (-not (Test-Path -LiteralPath $tool)) { exit 0 }
try { & $tool sync -Repo $repo -Quiet *> $null } catch { }
exit 0
