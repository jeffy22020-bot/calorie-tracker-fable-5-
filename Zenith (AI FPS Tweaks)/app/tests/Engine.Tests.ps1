# Zenith engine round-trip tests (mock mode - nothing on the real PC is touched).
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File app\tests\Engine.Tests.ps1
# Exit code = number of failed checks.

$ErrorActionPreference = 'Stop'
$AppRoot = Split-Path -Parent $PSScriptRoot
foreach ($f in @('Platform.ps1', 'Engine.ps1', 'Tweaks.ps1', 'Scanner.ps1', 'Tools.ps1', 'Server.ps1')) { . (Join-Path (Join-Path $AppRoot 'core') $f) }

$data = Join-Path ([IO.Path]::GetTempPath()) ('zenith-test-' + [guid]::NewGuid().ToString('N'))
$Global:ZMock = $null
Initialize-ZContext -AppRoot $AppRoot -DataDir $data -Mock

$script:failures = 0
$script:passes = 0
function Assert {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passes++ } else { $script:failures++; Write-Host ('FAIL: ' + $Message) -ForegroundColor Red }
}

function ConvertTo-Canonical {
    # Deterministic JSON of a nested hashtable/array tree (keys sorted) for exact comparisons.
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = @()
        foreach ($k in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) { $parts += ('"' + $k + '":' + (ConvertTo-Canonical $Value[$k])) }
        return '{' + ($parts -join ',') + '}'
    }
    if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string])) {
        $parts = @()
        foreach ($v in $Value) { $parts += (ConvertTo-Canonical $v) }
        return '[' + ($parts -join ',') + ']'
    }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    return ('"' + [string]$Value + '"')
}

function Get-MockSnapshot {
    $h = @{}
    foreach ($k in @($Global:ZMock.Keys)) { if ($k -ne 'RestorePoints') { $h[$k] = $Global:ZMock[$k] } }
    return ConvertTo-Canonical $h
}

# ---------------------------------------------------------------- catalog sanity
$ids = @($Global:ZTweaks | ForEach-Object { $_.Id })
Assert ($ids.Count -ge 50) ("catalog has 50+ tweaks (found {0})" -f $ids.Count)
Assert (@($ids | Select-Object -Unique).Count -eq $ids.Count) 'tweak ids are unique'
$catIds = @($Global:ZCategories | ForEach-Object { $_.id })
foreach ($t in $Global:ZTweaks) {
    Assert ([bool]$t.Name -and [bool]$t.Desc) ("{0} has name and description" -f $t.Id)
    Assert ($catIds -contains $t.Cat) ("{0} has a known category" -f $t.Id)
    Assert (@('safe', 'moderate', 'advanced') -contains $t.Risk) ("{0} has a valid risk" -f $t.Id)
    Assert (@('high', 'medium', 'low') -contains $t.Impact) ("{0} has a valid impact" -f $t.Id)
    Assert ($t.Ops -or $t.Build) ("{0} has ops" -f $t.Id)
    if ($t.Risk -eq 'advanced') { Assert (-not $t.Preset) ("{0} (advanced) is not in a preset" -f $t.Id) }
    if ($t.Risk -ne 'safe') { Assert ([bool]$t.Warning -or [bool]$t.Details -or $t.Risk -eq 'moderate') ("{0} explains its trade-off" -f $t.Id) }
}
$bal = @(Get-ZPresetIds 'balanced')
$perf = @(Get-ZPresetIds 'performance')
foreach ($b in $bal) { Assert ($perf -contains $b) ("balanced preset item {0} is also in performance" -f $b) }
foreach ($b in $bal) { Assert ($Global:ZTweakIndex[$b].Risk -eq 'safe') ("balanced preset item {0} is safe" -f $b) }
Write-Host ("Catalog: {0} tweaks, balanced preset {1}, performance preset {2}" -f $ids.Count, $bal.Count, $perf.Count)

# ---------------------------------------------------------------- full apply / revert round trip
$original = Get-MockSnapshot
$ledger = Read-ZLedger
$before = @{}
foreach ($s in @(Get-ZTweakStates $ledger)) { $before[$s.id] = $s.state }
$na = @($before.Keys | Where-Object { $before[$_] -eq 'na' })
Write-Host ("Not applicable on mock PC: {0}" -f (($na | Sort-Object) -join ', '))
Assert ($before['game.hags'] -eq 'optimal') 'HAGS already on in the seed shows as optimal'
Assert ($before['bg.chrome'] -eq 'na') 'Chrome tweak is not applicable when Chrome is missing'

$r = Invoke-ZApplyTweaks -Ids $ids
foreach ($x in $r.results) { if (-not $x.ok -and -not $x.skipped) { Assert $false ("apply {0}: {1}" -f $x.id, $x.message) } }
Assert ($r.failed -eq 0) 'no tweak failed to apply'

$ledger = Read-ZLedger
$after = @{}
foreach ($s in @(Get-ZTweakStates $ledger)) { $after[$s.id] = $s.state }
foreach ($id in $ids) {
    if ($before[$id] -eq 'na') { Assert ($after[$id] -eq 'na') ("{0} stays n/a" -f $id); continue }
    Assert ($after[$id] -eq 'applied') ("{0} reports applied after apply (got {1})" -f $id, $after[$id])
}

$snapCount = 0
foreach ($k in $ledger.tweaks.Keys) { $snapCount += @($ledger.tweaks[$k].snaps).Count }
[void](Invoke-ZApplyTweaks -Ids $ids)
$ledger2 = Read-ZLedger
$snapCount2 = 0
foreach ($k in $ledger2.tweaks.Keys) { $snapCount2 += @($ledger2.tweaks[$k].snaps).Count }
Assert ($snapCount -eq $snapCount2) 're-applying keeps the original snapshots (no duplicates)'

# Specific values really changed
Assert ((Get-ZRegValue 'HKCU\System\GameConfigStore' 'GameDVR_Enabled').Value -eq 0) 'Game DVR value set to 0'
Assert ((Get-ZRegValue 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings').Value -eq 'VRROptimizeEnable=1;SwapEffectUpgradeEnable=1;' -or (Get-ZRegValue 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings').Value -eq 'VRROptimizeEnable=1;SwapEffectUpgradeEnable=1;') 'DirectX key=value string merged in place'
Assert ((Get-ZActiveScheme) -eq $Global:ZZenithPlanGuid) 'Zenith power plan active'
Assert ((Get-ZPowerValue $Global:ZZenithPlanGuid '238c9fa8-0aad-41ed-83f4-97be242c8f20' '29f6c1db-86da-48c5-9fdb-f2b67b1f44da') -eq 1800) 'sleep timeout carried over into the Zenith plan'
Assert ((Get-ZService 'DiagTrack').Start -eq 4) 'DiagTrack disabled'
Assert (-not (Get-ZService 'DiagTrack').Running) 'DiagTrack stopped'
Assert (-not (Get-ZTask '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator').Enabled) 'CEIP task disabled'
Assert ((Get-ZRegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex').Value -eq -1) 'NetworkThrottlingIndex stored as 0xFFFFFFFF'
Assert (-not $Global:ZMock.Hibernate) 'hibernation off'

# Single revert
$rr = Invoke-ZRevertTweaks -Ids @('game.dvr')
Assert ($rr.failed -eq 0) 'single revert succeeded'
Assert ((Get-ZRegValue 'HKCU\System\GameConfigStore' 'GameDVR_Enabled').Value -eq 1) 'Game DVR value restored to 1'
Assert (-not (Test-ZRegKey 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR')) 'policy key Zenith created was removed again'

# Startup item + app removal go through the ledger too
$item = @(Get-ZStartupItems | Where-Object { $_.name -eq 'OneDrive' })[0]
Assert ($item.enabled) 'OneDrive starts with Windows in the seed'
[void](Set-ZStartupItem $item.id $false)
Assert (-not @(Get-ZStartupItems | Where-Object { $_.name -eq 'OneDrive' })[0].enabled) 'OneDrive startup disabled'
$spot = @(Get-ZStartupItems | Where-Object { $_.name -eq 'Spotify' })[0]
Assert (-not $spot.enabled) 'Spotify was already disabled in the seed'
[void](Set-ZStartupItem $spot.id $true)
Assert (@(Get-ZStartupItems | Where-Object { $_.name -eq 'Spotify' })[0].enabled) 'Spotify startup enabled'
$ar = Remove-ZBloatApps -Names @('Microsoft.BingNews', 'Clipchamp.Clipchamp')
Assert ($ar.applied -eq 2) 'two bloat apps removed'
Assert (-not (Get-ZAppx 'Microsoft.BingNews').Installed) 'News app removed'
$list = @(Get-ZBloatList | Where-Object { $_.name -eq 'Microsoft.BingNews' })
Assert ($list.Count -eq 1 -and $list[0].removedByZenith) 'removed app still listed so it can be restored'

# Everything back
$ra = Invoke-ZRevertAll
Assert ($ra.failed -eq 0) 'restore-all reported no failures'
$ledger = Read-ZLedger
Assert ($ledger.tweaks.Count -eq 0) 'ledger is empty after restore-all'
Assert (@($ledger.pendingKeys).Count -eq 0) ('no leftover registry keys (pending: {0})' -f (@($ledger.pendingKeys) -join ', '))
$restored = Get-MockSnapshot
Assert ($restored -eq $original) 'simulated PC is identical to its original state after restore-all'
if ($restored -ne $original) {
    $a = $original.ToCharArray(); $b = $restored.ToCharArray()
    for ($i = 0; $i -lt [math]::Min($a.Length, $b.Length); $i++) { if ($a[$i] -ne $b[$i]) { Write-Host ('first difference near: ' + $original.Substring([math]::Max(0, $i - 120), 240)); Write-Host ('restored:              ' + $restored.Substring([math]::Max(0, $i - 120), 240)); break } }
}

# Power-setting tweaks follow the active power plan
[void](Invoke-ZApplyTweaks -Ids @('lat.usb'))
[void](Invoke-ZApplyTweaks -Ids @('power.plan'))
$st = @{}; foreach ($s in @(Get-ZTweakStates (Read-ZLedger))) { $st[$s.id] = $s.state }
Assert ($st['lat.usb'] -eq 'applied') ('USB suspend stays applied after switching to the Zenith plan (got {0})' -f $st['lat.usb'])
[void](Invoke-ZRevertTweaks -Ids @('power.plan'))
$st = @{}; foreach ($s in @(Get-ZTweakStates (Read-ZLedger))) { $st[$s.id] = $s.state }
Assert ($st['lat.usb'] -eq 'applied') ('USB suspend stays applied after the plan is undone (got {0})' -f $st['lat.usb'])
Assert (-not (Test-ZPowerScheme $Global:ZZenithPlanGuid)) 'Zenith plan deleted on undo'
[void](Invoke-ZRevertAll)
Assert ((Get-MockSnapshot) -eq $original) 'power plan scenario restores the original state'

# Failure inside a tweak rolls that tweak back
$Global:ZTweakIndex['test.fail'] = @{ Id = 'test.fail'; Name = 'Failing test tweak'; Cat = 'gaming'; Ops = @(
        @{ T = 'Reg'; Path = 'HKCU\Software\ZenithTest\Deep'; Name = 'A'; Value = 1; Kind = 'DWord' },
        @{ T = 'Fsutil'; Setting = 'NoSuchSetting'; Value = 'not-a-number' }
    )
}
$fr = Invoke-ZApplyTweaks -Ids @('test.fail')
Assert ($fr.failed -eq 1) 'failing tweak reports failure'
Assert (-not (Test-ZRegKey 'HKCU\Software\ZenithTest')) 'failing tweak rolled back its earlier ops'
Assert (-not (Read-ZLedger).tweaks.ContainsKey('test.fail')) 'failing tweak left no ledger entry'

# Scanner + checks in mock
$scan = Get-ZScan
Assert ($scan.cpu.name -like '*5800X*') 'scan reports the Ryzen 7 5800X'
Assert (@($scan.checks | Where-Object { $_.id -eq 'ram-speed' -and $_.level -eq 'bad' }).Count -eq 1) 'RAM speed check flags 2400 MT/s'
Assert ((Get-ZRatedRamSpeed 'CMK32GX4M2E3200C16') -eq 3200) 'part number decode: Corsair'
Assert ((Get-ZRatedRamSpeed 'F4-3600C16D-32GVKC') -eq 3600) 'part number decode: G.Skill'
Assert ((Get-ZRatedRamSpeed 'KF432C16BBK2/32') -eq 3200) 'part number decode: Kingston Fury'
Assert ((Get-ZRatedRamSpeed 'HMA82GU6DJR8N-XN') -eq 3200) 'part number decode: SK hynix'
Assert ((Get-ZRatedRamSpeed 'M378A2K43CB1-CTD') -eq 2666) 'part number decode: Samsung'
Assert ($null -eq (Get-ZRatedRamSpeed 'Module 16GB DDR4')) 'unknown part numbers decode to nothing'

# JSON writer: plain arrays even for pipeline-wrapped arrays, escaping, round trip
$wrapped = Write-Output -NoEnumerate @(1, 2)
$j = ConvertTo-ZJson @{ a = $wrapped; b = @(); c = @('x'); s = "q`"\`n"; n = $null; t = $true; d = -1; f = 2.5 }
$back = ConvertFrom-Json -InputObject $j
Assert (@($back.a).Count -eq 2 -and $back.a[1] -eq 2) ('wrapped array serialises as a plain array: ' + $j)
Assert (@($back.c).Count -eq 1 -and $back.c[0] -eq 'x') 'single-element array stays an array'
Assert ($back.s -eq "q`"\`n") 'strings are escaped correctly'
Assert ($back.d -eq -1 -and $back.f -eq 2.5 -and $back.t -eq $true -and $null -eq $back.n) 'numbers, bools and null round-trip'
$Global:ZServer = @{ RestorePointDone = $false; RebootPending = $false }
$json = ConvertTo-ZJson (Get-ZStatePayload)
$parsed = ConvertFrom-Json -InputObject $json
Assert (@($parsed.tweaks).Count -eq $ids.Count) 'state payload serialises and parses back'

Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("{0} passed, {1} failed" -f $script:passes, $script:failures)
exit $script:failures
