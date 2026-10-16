#Requires -Version 7.0
# Simulates two machines that share one bare repo. Run: pwsh tests/run.ps1
param([string]$Case = 'all')
$ErrorActionPreference = 'Stop'
$tool = Join-Path (Split-Path $PSScriptRoot -Parent) 'onesync.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('onesync-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$env:GIT_AUTHOR_NAME = $env:GIT_COMMITTER_NAME = 'test'
$env:GIT_AUTHOR_EMAIL = $env:GIT_COMMITTER_EMAIL = 'test@example.com'
$passed = 0

function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }

function New-World([string]$Name) {
  $w = Join-Path $root $Name
  $origin = "$w/origin.git"
  git init -q --bare -b main $origin
  $seed = "$w/seed"
  git init -q $seed
  New-Item -ItemType Directory -Force "$seed/claude", "$seed/memory/_shared" | Out-Null
  '' | Set-Content "$seed/claude/.gitkeep"; '' | Set-Content "$seed/memory/_shared/.gitkeep"
  git -C $seed add -A; git -C $seed commit -qm init; git -C $seed branch -M main
  git -C $seed remote add origin $origin; git -C $seed push -q -u origin main
  foreach ($m in 'a', 'b') {
    git clone -q $origin "$w/$m-repo"
    New-Item -ItemType Directory -Force "$w/$m-home/.claude/projects" | Out-Null
  }
  [pscustomobject]@{ Root = $w; A = "$w/a-home/.claude"; B = "$w/b-home/.claude" }
}

function Sync([object]$World, [string]$Machine, [string[]]$Extra = @()) {
  $claudeHome = if ($Machine -eq "a") { $World.A } else { $World.B }
  & $tool sync -Repo "$($World.Root)/$Machine-repo" -ClaudeHome $claudeHome @Extra *> $null
}

function Set-File([string]$Path, [string]$Text, [datetime]$Time = (Get-Date)) {
  New-Item -ItemType Directory -Force (Split-Path $Path -Parent) | Out-Null
  [IO.File]::WriteAllText($Path, $Text)
  (Get-Item $Path).LastWriteTime = $Time
}

function Test-Case([string]$Name, [scriptblock]$Body) {
  if ($Case -ne 'all' -and $Case -ne $Name) { return }
  & $Body
  $script:passed++
  Write-Host "PASS $Name"
}

Test-Case 'edit-propagates' {
  $w = New-World 'edit'
  Set-File "$($w.A)/CLAUDE.md" 'v1' (Get-Date).AddMinutes(-10)
  Sync $w a; Sync $w b
  Assert-True ((Get-Content "$($w.B)/CLAUDE.md" -Raw) -eq 'v1') 'B did not get the new file'
  Start-Sleep -Seconds 1
  Set-File "$($w.A)/CLAUDE.md" 'v2'
  Sync $w a; Sync $w b
  Assert-True ((Get-Content "$($w.B)/CLAUDE.md" -Raw) -eq 'v2') 'B did not get the edit'
}

Test-Case 'delete-propagates' {
  $w = New-World 'delete'
  Set-File "$($w.A)/skills/demo/SKILL.md" 'skill' (Get-Date).AddMinutes(-10)
  Sync $w a; Sync $w b
  Assert-True (Test-Path "$($w.B)/skills/demo/SKILL.md") 'B did not get the skill'
  Remove-Item "$($w.A)/skills/demo" -Recurse
  Sync $w a; Sync $w b
  Assert-True (-not (Test-Path "$($w.B)/skills/demo/SKILL.md")) 'Delete did not reach B'
  Assert-True (@(Get-ChildItem "$($w.B)/.onesync-trash" -Recurse -Filter SKILL.md).Count -eq 1) 'Deleted file is not in the trash on B'
  Sync $w a
  Assert-True (-not (Test-Path "$($w.A)/skills/demo/SKILL.md")) 'Deleted file came back on A'
}

Test-Case 'shared-memory' {
  $w = New-World 'shared'
  Set-File "$($w.A)/projects/proj-a/memory/rule.md" "---`nname: My rule`ndescription: Always do X`ntype: feedback`n---`nDo X." (Get-Date).AddMinutes(-10)
  Set-File "$($w.A)/projects/proj-a/memory/notes.md" "---`ntype: project`n---`nOnly here." (Get-Date).AddMinutes(-10)
  New-Item -ItemType Directory -Force "$($w.B)/projects/proj-b", "$($w.B)/projects/proj-c" | Out-Null
  Sync $w a; Sync $w b
  foreach ($ns in 'proj-a', 'proj-b', 'proj-c') {
    Assert-True (Test-Path "$($w.B)/projects/$ns/memory/rule.md") "Shared memory is missing in $ns"
  }
  Assert-True (-not (Test-Path "$($w.B)/projects/proj-b/memory/notes.md")) 'Project memory leaked into another project'
  Assert-True ((Get-Content "$($w.B)/projects/proj-b/memory/MEMORY.md" -Raw) -match '\[My rule\]\(rule\.md\)') 'Shared index line is missing'
}

Test-Case 'newer-wins' {
  $w = New-World 'newer'
  Set-File "$($w.A)/settings.json" '{"a":1}' (Get-Date).AddMinutes(-30)
  Sync $w a; Sync $w b
  Start-Sleep -Seconds 1
  Set-File "$($w.A)/settings.json" '{"a":2}' (Get-Date).AddMinutes(-5)
  Sync $w a
  # B changed the file after A published, so B's version is the newest and must win.
  Set-File "$($w.B)/settings.json" '{"b":3}' (Get-Date).AddMinutes(5)
  Sync $w b; Sync $w a
  Assert-True ((Get-Content "$($w.A)/settings.json" -Raw) -eq '{"b":3}') 'The newer edit did not win'
}

Test-Case 'safety' {
  $w = New-World 'safety'
  $outside = Join-Path $w.Root 'outside'
  Set-File "$outside/SKILL.md" 'not ours'
  New-Item -ItemType Directory -Force "$($w.A)/skills" | Out-Null
  $linkType = if ($IsWindows) { "Junction" } else { "SymbolicLink" }
  New-Item -ItemType $linkType -Path "$($w.A)/skills/linked" -Target $outside | Out-Null
  foreach ($i in 1..3) { Set-File "$($w.A)/agents/agent$i.md" "agent $i" (Get-Date).AddMinutes(-10) }
  Sync $w a
  Assert-True (-not (Test-Path "$($w.Root)/a-repo/claude/skills/linked")) 'A linked folder was uploaded'
  Remove-Item "$($w.A)/agents" -Recurse
  $failed = $false
  try { & $tool sync -Repo "$($w.Root)/a-repo" -ClaudeHome $w.A -MaxDelete 2 *> $null } catch { $failed = $true }
  Assert-True $failed 'A mass delete did not stop the round'
  Assert-True (Test-Path "$($w.Root)/a-repo/claude/agents/agent1.md") 'Files were deleted although the round stopped'
  Assert-True (Test-Path "$outside/SKILL.md") 'A file behind a link was touched'
}

Test-Case 'secrets' {
  $w = New-World 'secrets'
  Set-File "$($w.A)/settings.json" ('{"env":{"ANTHROPIC_API_KEY":"sk-ant-' + ('x' * 40) + '"}}')
  Set-File "$($w.A)/CLAUDE.md" 'rules'
  Sync $w a
  Assert-True (-not (Test-Path "$($w.Root)/a-repo/claude/settings.json")) 'A file with an API key was uploaded'
  Assert-True (Test-Path "$($w.Root)/a-repo/claude/CLAUDE.md") 'A clean file was not uploaded'
}

Write-Host "Passed $passed cases. Fixtures: $root"
