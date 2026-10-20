# Zenith - Engine
# Every change Zenith makes is an "op". Before an op runs, the engine captures the exact original state
# of what it touches (a "snapshot") into the backup ledger (%ProgramData%\Zenith\backup.json).
# Undo replays snapshots in reverse order, so "Restore Original State" puts every value, service,
# task, power plan and app back exactly as it was before Zenith touched it.
# Target: Windows PowerShell 5.1. Keep this file ASCII-only.

$Global:ZZenithPlanGuid = '5a3e0c7d-3c8b-4f1e-9b6a-7a9e2f1d0c11'
$Global:ZPowerGuids = @{
    Ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    High     = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    Balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
}
$Global:ZImpactWeight = @{ high = 3; medium = 2; low = 1 }

# ---------------------------------------------------------------------------------------------------
# Ledger & settings
# ---------------------------------------------------------------------------------------------------

function New-ZLedger {
    return @{
        version       = 1
        created       = (Get-Date).ToString('o')
        machine       = $env:COMPUTERNAME
        seq           = 0
        tweaks        = @{}
        pendingKeys   = @()
        restorePoints = @()
        history       = @()
    }
}

function Read-ZLedger {
    $l = Read-ZJsonFile $Global:ZCtx.LedgerPath
    if (-not $l) { return New-ZLedger }
    if (-not $l.tweaks) { $l.tweaks = @{} }
    foreach ($f in @('pendingKeys', 'restorePoints', 'history')) { if ($null -eq $l[$f]) { $l[$f] = @() } }
    if ($null -eq $l.seq) { $l.seq = 0 }
    return $l
}

function Save-ZLedger {
    param($Ledger)
    Write-ZJsonFile $Global:ZCtx.LedgerPath $Ledger
}

function Add-ZHistory {
    param($Ledger, [string]$Action, [string]$Detail, [bool]$Ok = $true)
    $h = @($Ledger.history) + @(@{ time = (Get-Date).ToString('o'); action = $Action; detail = $Detail; ok = $Ok })
    if ($h.Count -gt 300) { $h = $h[($h.Count - 300)..($h.Count - 1)] }
    $Ledger.history = $h
}

function Get-ZSettings {
    $s = Read-ZJsonFile $Global:ZCtx.SettingsPath
    if (-not $s) { $s = @{} }
    if ($null -eq $s.autoRestorePoint) { $s.autoRestorePoint = $true }
    if ($null -eq $s.showAdvanced) { $s.showAdvanced = $true }
    return $s
}

function Save-ZSettings {
    param($Settings)
    Write-ZJsonFile $Global:ZCtx.SettingsPath $Settings
}

function Get-ZArray {
    # Emits the elements of $Value with nulls dropped; wrap calls in @() to get an array.
    param($Value)
    if ($null -eq $Value) { return }
    foreach ($v in @($Value)) { if ($null -ne $v) { $v } }
}

# ---------------------------------------------------------------------------------------------------
# key=value; strings (DirectX UserGpuPreferences)
# ---------------------------------------------------------------------------------------------------

function ConvertFrom-ZKV {
    param([string]$Text)
    $d = [ordered]@{}
    if ($Text) {
        foreach ($part in $Text.Split(';')) {
            if (-not $part.Trim()) { continue }
            $i = $part.IndexOf('=')
            if ($i -lt 0) { $d[$part.Trim()] = '' } else { $d[$part.Substring(0, $i).Trim()] = $part.Substring($i + 1).Trim() }
        }
    }
    return $d
}

function ConvertTo-ZKV {
    param($Dict)
    $s = ''
    foreach ($k in $Dict.Keys) { $s += ($k + '=' + $Dict[$k] + ';') }
    return $s
}

# ---------------------------------------------------------------------------------------------------
# Ops: key / description / snapshot / apply / restore / test
# ---------------------------------------------------------------------------------------------------

function Get-ZStartSpec {
    param([string]$Start)
    switch ($Start) {
        'Disabled'         { return @(4, 0) }
        'Manual'           { return @(3, 0) }
        'Automatic'        { return @(2, 0) }
        'AutomaticDelayed' { return @(2, 1) }
    }
    throw "Unknown service start type: $Start"
}

function Get-ZOpKey {
    param($Op)
    switch ($Op.T) {
        'Reg'          { return ('reg|' + $Op.Path + '|' + $Op.Name).ToLowerInvariant() }
        'RegKV'        { return ('regkv|' + $Op.Path + '|' + $Op.Name + '|' + ((@($Op.Pairs.Keys) | Sort-Object) -join ',')).ToLowerInvariant() }
        'Service'      { return ('svc|' + $Op.Name).ToLowerInvariant() }
        'Task'         { return ('task|' + $Op.Path).ToLowerInvariant() }
        'PowerSetting' { return ('pow|' + (Get-ZActiveScheme) + '|' + $Op.Sub + '|' + $Op.Setting).ToLowerInvariant() }
        'PowerPlan'    { return 'powerplan' }
        'Hibernate'    { return 'hibernate' }
        'Fsutil'       { return ('fsutil|' + $Op.Setting).ToLowerInvariant() }
        'NetAdv'       { return ('netadv|' + ($Op.Keywords -join ',')).ToLowerInvariant() }
        'AppX'         { return ('appx|' + $Op.Name).ToLowerInvariant() }
    }
    throw "Unknown op type: $($Op.T)"
}

function Get-ZOpText {
    # Human-readable "what this changes" line for the UI.
    param($Op)
    switch ($Op.T) {
        'Reg' {
            $n = $Op.Name
            if (-not $n) { $n = '(Default)' }
            if ($Op.Delete) { return ('Registry: delete {0} \ {1}' -f $Op.Path, $n) }
            $v = $Op.Value
            if ($Op.Kind -eq 'Binary') { $v = '(binary)' } elseif ($Op.Kind -eq 'String') { $v = '"' + $v + '"' }
            return ('Registry: {0} \ {1} = {2}' -f $Op.Path, $n, $v)
        }
        'RegKV' {
            $pairs = @()
            foreach ($k in $Op.Pairs.Keys) { $pairs += ($k + '=' + $Op.Pairs[$k]) }
            return ('Registry: {0} \ {1} gets {2}' -f $Op.Path, $Op.Name, ($pairs -join '; '))
        }
        'Service' {
            $t = 'Service: {0} -> {1}' -f $Op.Name, $Op.Start
            if ($Op.Stop) { $t += ' (and stopped now)' }
            return $t
        }
        'Task'         { return ('Scheduled task: {0} -> disabled' -f $Op.Path) }
        'PowerSetting' { return ('Power plan: {0} -> {1}' -f $Op.Label, $Op.Value) }
        'PowerPlan'    { return "Power plan: create and activate 'Zenith Ultimate Performance' (your sleep and screen timeouts are kept)" }
        'Hibernate'    { if ($Op.Enabled) { return 'powercfg /hibernate on' } else { return 'powercfg /hibernate off (deletes hiberfil.sys)' } }
        'Fsutil'       { return ('fsutil behavior set {0} {1}' -f $Op.Setting, $Op.Value) }
        'NetAdv'       { return ('Wired network adapter: {0} = {1}' -f ($Op.Keywords -join ' / '), $Op.Value) }
        'AppX'         { return ('Remove app package {0} for your account' -f $Op.Name) }
        'Notify'       { return ('Apply the new {0} settings immediately' -f $Op.What.ToLowerInvariant()) }
    }
    return $Op.T
}

function Get-ZOpSnapshot {
    param($Op)
    switch ($Op.T) {
        'Reg' {
            $c = Get-ZRegValue $Op.Path $Op.Name
            $created = @()
            if (-not $c.KeyExists) { $created = @(Get-ZRegMissingKeys $Op.Path) }
            return @{ T = 'Reg'; Path = $Op.Path; Name = $Op.Name; Existed = [bool]$c.Exists; Kind = $c.Kind; Value = $c.Value; CreatedKeys = $created }
        }
        'RegKV' {
            $c = Get-ZRegValue $Op.Path $Op.Name
            $cur = ConvertFrom-ZKV ([string]$c.Value)
            $old = @{}
            foreach ($k in @($Op.Pairs.Keys)) { if ($cur.Contains($k)) { $old[$k] = [string]$cur[$k] } else { $old[$k] = $null } }
            $created = @()
            if (-not $c.KeyExists) { $created = @(Get-ZRegMissingKeys $Op.Path) }
            return @{ T = 'RegKV'; Path = $Op.Path; Name = $Op.Name; Existed = [bool]$c.Exists; Old = $old; CreatedKeys = $created }
        }
        'Service' {
            $s = Get-ZService $Op.Name
            return @{ T = 'Service'; Name = $Op.Name; Exists = [bool]$s.Exists; Start = $s.Start; Delayed = $s.Delayed; Running = [bool]$s.Running }
        }
        'Task' {
            $t = Get-ZTask $Op.Path
            return @{ T = 'Task'; Path = $Op.Path; Exists = [bool]$t.Exists; Enabled = [bool]$t.Enabled }
        }
        'PowerSetting' {
            $scheme = Get-ZActiveScheme
            return @{ T = 'PowerSetting'; Scheme = $scheme; Sub = $Op.Sub; Setting = $Op.Setting; AC = (Get-ZPowerValue $scheme $Op.Sub $Op.Setting) }
        }
        'PowerPlan' {
            return @{ T = 'PowerPlan'; Prev = (Get-ZActiveScheme); Created = (-not (Test-ZPowerScheme $Global:ZZenithPlanGuid)) }
        }
        'Hibernate' { return @{ T = 'Hibernate'; WasEnabled = [bool](Get-ZHibernateEnabled) } }
        'Fsutil'    { return @{ T = 'Fsutil'; Setting = $Op.Setting; Value = (Get-ZFsutil $Op.Setting) } }
        'NetAdv'    { return @{ T = 'NetAdv'; Items = @(Get-ZNetAdvItems $Op.Keywords) } }
        'AppX' {
            $a = Get-ZAppx $Op.Name
            return @{ T = 'AppX'; Name = $Op.Name; Existed = [bool]$a.Installed; PkgName = $a.Name; FullName = $a.FullName; Family = $a.Family; Location = $a.Location }
        }
    }
    throw "Unknown op type: $($Op.T)"
}

function Invoke-ZOpApply {
    param($Op, $Snap)
    switch ($Op.T) {
        'Reg' {
            if ($Op.Delete) { Remove-ZRegValue $Op.Path $Op.Name } else { Set-ZRegValue $Op.Path $Op.Name $Op.Value $Op.Kind }
        }
        'RegKV' {
            $c = Get-ZRegValue $Op.Path $Op.Name
            $cur = ConvertFrom-ZKV ([string]$c.Value)
            foreach ($k in @($Op.Pairs.Keys)) { $cur[$k] = [string]$Op.Pairs[$k] }
            Set-ZRegValue $Op.Path $Op.Name (ConvertTo-ZKV $cur) 'String'
        }
        'Service' {
            if (-not $Snap.Exists) { return }
            $spec = Get-ZStartSpec $Op.Start
            Set-ZServiceStart $Op.Name $spec[0] $spec[1]
            if ($Op.Stop -and $spec[0] -ge 3 -and $Snap.Running) { Stop-ZService $Op.Name }
        }
        'Task' {
            if (-not $Snap.Exists) { return }
            Set-ZTaskEnabled $Op.Path ([bool]$Op.Enabled)
        }
        'PowerSetting' { Set-ZPowerValue $Snap.Scheme $Op.Sub $Op.Setting $Op.Value }
        'PowerPlan'    { Enable-ZPowerPlan $Snap }
        'Hibernate'    { Set-ZHibernate ([bool]$Op.Enabled) }
        'Fsutil'       { Set-ZFsutil $Op.Setting $Op.Value }
        'NetAdv'       { foreach ($i in @($Snap.Items)) { if ($i) { Set-ZNetAdv $i.Adapter $i.Keyword $Op.Value } } }
        'AppX'         { if ($Snap.Existed) { Remove-ZAppx $Snap.FullName $Snap.PkgName } }
    }
}

function Remove-ZCreatedKeys {
    # Deletes keys Zenith created (deepest first) when they are empty again. Returns the ones it had to leave.
    param($Keys)
    $left = @()
    $arr = @(Get-ZArray $Keys)
    for ($i = $arr.Count - 1; $i -ge 0; $i--) {
        $k = $arr[$i]
        if (-not $k) { continue }
        try { if (-not (Remove-ZRegKeyIfEmpty $k)) { $left += $k } } catch { $left += $k }
    }
    return $left
}

function Invoke-ZOpRestore {
    # Puts the target back to its snapshot. Returns registry keys that could not be removed yet.
    param($Snap)
    switch ($Snap.T) {
        'Reg' {
            if ($Snap.Existed) { Set-ZRegValue $Snap.Path $Snap.Name $Snap.Value $Snap.Kind } else { Remove-ZRegValue $Snap.Path $Snap.Name }
            return Remove-ZCreatedKeys $Snap.CreatedKeys
        }
        'RegKV' {
            $c = Get-ZRegValue $Snap.Path $Snap.Name
            $cur = ConvertFrom-ZKV ([string]$c.Value)
            foreach ($k in @($Snap.Old.Keys)) {
                $ov = $Snap.Old[$k]
                if ($null -eq $ov) { if ($cur.Contains($k)) { $cur.Remove($k) } } else { $cur[$k] = [string]$ov }
            }
            $text = ConvertTo-ZKV $cur
            if (-not $text -and -not $Snap.Existed) { Remove-ZRegValue $Snap.Path $Snap.Name } else { Set-ZRegValue $Snap.Path $Snap.Name $text 'String' }
            return Remove-ZCreatedKeys $Snap.CreatedKeys
        }
        'Service' {
            if (-not $Snap.Exists) { return }
            if (-not (Get-ZService $Snap.Name).Exists) { return }
            Set-ZServiceStart $Snap.Name ([int]$Snap.Start) ([int]$Snap.Delayed)
            if ($Snap.Running -and [int]$Snap.Start -ne 4) { Start-ZService $Snap.Name }
        }
        'Task' {
            if (-not $Snap.Exists) { return }
            if (-not (Get-ZTask $Snap.Path).Exists) { return }
            Set-ZTaskEnabled $Snap.Path ([bool]$Snap.Enabled)
        }
        'PowerSetting' {
            if ($null -eq $Snap.AC) { return }
            if (-not (Test-ZPowerScheme $Snap.Scheme)) { return }
            Set-ZPowerValue $Snap.Scheme $Snap.Sub $Snap.Setting ([long]$Snap.AC)
        }
        'PowerPlan' { Disable-ZPowerPlan $Snap }
        'Hibernate' { Set-ZHibernate ([bool]$Snap.WasEnabled) }
        'Fsutil'    { if ($null -ne $Snap.Value) { Set-ZFsutil $Snap.Setting ([int]$Snap.Value) } }
        'NetAdv'    { foreach ($i in @(Get-ZArray $Snap.Items)) { if ($i) { Set-ZNetAdv $i.Adapter $i.Keyword $i.Value } } }
        'AppX' {
            if (-not $Snap.Existed) { return }
            if ((Get-ZAppx $Snap.PkgName).Installed) { return }
            Restore-ZAppx $Snap.PkgName $Snap.Location $Snap.Family
        }
    }
}

function Test-ZOp {
    # $true when the target is already in the state the op would produce.
    param($Op)
    switch ($Op.T) {
        'Reg' {
            $c = Get-ZRegValue $Op.Path $Op.Name
            if ($Op.Delete) { return (-not $c.Exists) }
            if (-not $c.Exists) { return $false }
            if ($Op.Match -eq 'StartupDisabled') {
                if ($c.Kind -ne 'Binary') { return $false }
                $b = [Convert]::FromBase64String([string]$c.Value)
                return ($b.Length -gt 0 -and ($b[0] -band 1) -eq 1)
            }
            switch ($Op.Kind) {
                'DWord'  { return ((ConvertTo-ZUInt32 $c.Value) -eq (ConvertTo-ZUInt32 $Op.Value)) }
                'QWord'  { return ([long]$c.Value -eq [long]$Op.Value) }
                'Binary' { return ([string]$c.Value -eq [string]$Op.Value) }
                default  { return ([string]$c.Value -eq [string]$Op.Value) }
            }
        }
        'RegKV' {
            $c = Get-ZRegValue $Op.Path $Op.Name
            if (-not $c.Exists) { return $false }
            $cur = ConvertFrom-ZKV ([string]$c.Value)
            foreach ($k in @($Op.Pairs.Keys)) { if (-not $cur.Contains($k) -or [string]$cur[$k] -ne [string]$Op.Pairs[$k]) { return $false } }
            return $true
        }
        'Service' {
            $s = Get-ZService $Op.Name
            if (-not $s.Exists) { return $true }
            switch ($Op.Start) {
                'Disabled'         { return ($s.Start -eq 4) }
                'Manual'           { return ($s.Start -ge 3) }
                'Automatic'        { return ($s.Start -eq 2 -and $s.Delayed -eq 0) }
                'AutomaticDelayed' { return ($s.Start -eq 2 -and $s.Delayed -eq 1) }
            }
            return $false
        }
        'Task' {
            $t = Get-ZTask $Op.Path
            if (-not $t.Exists) { return $true }
            return ($t.Enabled -eq [bool]$Op.Enabled)
        }
        'PowerSetting' {
            $v = Get-ZPowerValue (Get-ZActiveScheme) $Op.Sub $Op.Setting
            return ($null -ne $v -and [long]$v -eq [long]$Op.Value)
        }
        'PowerPlan' { return ((Get-ZActiveScheme) -eq $Global:ZZenithPlanGuid) }
        'Hibernate' { return ([bool](Get-ZHibernateEnabled) -eq [bool]$Op.Enabled) }
        'Fsutil'    { $v = Get-ZFsutil $Op.Setting; return ($null -ne $v -and [int]$v -eq [int]$Op.Value) }
        'NetAdv' {
            foreach ($i in @(Get-ZNetAdvItems $Op.Keywords)) { if ($i -and [string]$i.Value -ne [string]$Op.Value) { return $false } }
            return $true
        }
        'AppX'   { return (-not (Get-ZAppx $Op.Name).Installed) }
        'Notify' { return $true }
    }
    return $false
}

function Invoke-ZNotify {
    param([string]$What)
    if ($What -eq 'Mouse') { Update-ZMouseSettings }
}

# ---------------------------------------------------------------------------------------------------
# Power plan op helpers
# ---------------------------------------------------------------------------------------------------

function Enable-ZPowerPlan {
    param($Snap)
    $z = $Global:ZZenithPlanGuid
    if (-not (Test-ZPowerScheme $z)) {
        $ok = Copy-ZPowerScheme $Global:ZPowerGuids.Ultimate $z
        if (-not $ok) { $ok = Copy-ZPowerScheme $Global:ZPowerGuids.High $z }
        if (-not $ok) { throw 'Windows would not create the Zenith power plan (Ultimate and High performance templates unavailable).' }
        Rename-ZPowerScheme $z 'Zenith Ultimate Performance' 'Maximum performance plan created by Zenith. Undo in Zenith to remove it.'
        $sleep = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
        $video = '7516b95f-f776-4464-8c53-06167f40cc99'
        $carry = @(
            @($sleep, '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'),
            @($sleep, '9d7815a6-7ee4-497e-8888-515a05f02364'),
            @($video, '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e')
        )
        if ($Snap.Prev -and $Snap.Prev -ne $z) {
            foreach ($p in $carry) {
                try {
                    $ac = Get-ZPowerValue $Snap.Prev $p[0] $p[1]
                    if ($null -ne $ac) { Set-ZPowerValue $z $p[0] $p[1] $ac }
                    if (-not $Global:ZCtx.Mock) {
                        $dc = Get-ZPowerValueDC $Snap.Prev $p[0] $p[1]
                        if ($null -ne $dc) { Set-ZPowerValue $z $p[0] $p[1] $dc -DC }
                    }
                } catch { }
            }
        }
    }
    Set-ZActiveScheme $z
}

function Disable-ZPowerPlan {
    param($Snap)
    $z = $Global:ZZenithPlanGuid
    $prev = [string]$Snap.Prev
    if (-not $prev -or $prev -eq $z -or -not (Test-ZPowerScheme $prev)) { $prev = $Global:ZPowerGuids.Balanced }
    if ((Get-ZActiveScheme) -eq $z) { Set-ZActiveScheme $prev }
    if ($Snap.Created -and (Test-ZPowerScheme $z)) { Remove-ZPowerScheme $z }
}

# ---------------------------------------------------------------------------------------------------
# Tweak application
# ---------------------------------------------------------------------------------------------------

function Get-ZTweakOps {
    # Static ops plus ops built for this PC at runtime; ops for services/tasks that do not exist are dropped.
    param($Tweak)
    $id = $Tweak.Id
    if ($Global:ZBuildCache.ContainsKey($id)) { return $Global:ZBuildCache[$id] }
    $ops = New-Object System.Collections.ArrayList
    foreach ($o in @(Get-ZArray $Tweak.Ops)) { if ($o) { [void]$ops.Add($o) } }
    if ($Tweak.Build) {
        try { foreach ($o in @(& $Tweak.Build)) { if ($o) { [void]$ops.Add($o) } } }
        catch { Write-ZLog ("Could not inspect {0}: {1}" -f $id, $_.Exception.Message) 'warn' }
    }
    $final = New-Object System.Collections.ArrayList
    foreach ($o in $ops) {
        if ($o.T -eq 'Service' -and -not (Get-ZService $o.Name).Exists) { continue }
        if ($o.T -eq 'Task' -and -not (Get-ZTask $o.Path).Exists) { continue }
        [void]$final.Add($o)
    }
    $arr = $final.ToArray()
    $Global:ZBuildCache[$id] = $arr
    return $arr
}

function Invoke-ZApplyOps {
    # Snapshots and applies one tweak (or an ad-hoc change such as a startup item) as a unit.
    # If any op fails, everything this call changed is rolled back.
    param($Ledger, [string]$Id, [string]$Name, [string]$Category, $Ops)
    $ops = @(Get-ZArray $Ops)
    if ($ops.Count -eq 0) { return @{ id = $Id; ok = $false; skipped = $true; message = 'Not applicable on this PC' } }
    $entry = $Ledger.tweaks[$Id]
    $isNew = ($null -eq $entry)
    $known = @{}
    if (-not $isNew) { foreach ($s in @(Get-ZArray $entry.snaps)) { if ($s -and $s.Key) { $known[$s.Key] = $s } } }
    $fresh = New-Object System.Collections.ArrayList
    $notify = New-Object System.Collections.ArrayList
    try {
        foreach ($op in $ops) {
            if ($op.T -eq 'Notify') { [void]$notify.Add($op.What); continue }
            $key = Get-ZOpKey $op
            $snap = $known[$key]
            if (-not $snap) {
                $snap = Get-ZOpSnapshot $op
                $snap.Key = $key
                [void]$fresh.Add($snap)
                $known[$key] = $snap
            }
            Invoke-ZOpApply $op $snap
        }
    } catch {
        $err = $_.Exception.Message
        for ($i = $fresh.Count - 1; $i -ge 0; $i--) { try { [void](Invoke-ZOpRestore $fresh[$i]) } catch { } }
        return @{ id = $Id; ok = $false; message = $err }
    }
    foreach ($w in $notify) { Invoke-ZNotify $w }
    if ($isNew) {
        $Ledger.seq = [int]$Ledger.seq + 1
        $entry = @{ id = $Id; name = $Name; category = $Category; seq = $Ledger.seq; appliedAt = (Get-Date).ToString('o'); snaps = @(); notify = @() }
    }
    $entry.snaps = @(Get-ZArray $entry.snaps) + $fresh.ToArray()
    $n = @()
    foreach ($w in (@(Get-ZArray $entry.notify) + $notify.ToArray())) { if ($w -and ($n -notcontains $w)) { $n += $w } }
    $entry.notify = $n
    $entry.updatedAt = (Get-Date).ToString('o')
    $Ledger.tweaks[$Id] = $entry
    Save-ZLedger $Ledger
    return @{ id = $Id; ok = $true }
}

function Invoke-ZPendingKeyCleanup {
    param($Ledger)
    $keys = @(Get-ZArray $Ledger.pendingKeys | Select-Object -Unique)
    $keys = @($keys | Sort-Object { $_.Split('\').Count } -Descending)
    $left = @()
    foreach ($k in $keys) {
        try { if (-not (Remove-ZRegKeyIfEmpty $k)) { $left += $k } } catch { $left += $k }
    }
    $Ledger.pendingKeys = $left
}

function Invoke-ZRevertEntry {
    param($Ledger, [string]$Id)
    $entry = $Ledger.tweaks[$Id]
    if (-not $entry) { return @{ id = $Id; ok = $true; message = 'Nothing to undo' } }
    $snaps = @(Get-ZArray $entry.snaps)
    $failed = New-Object System.Collections.ArrayList
    $errors = @()
    $pending = @()
    for ($i = $snaps.Count - 1; $i -ge 0; $i--) {
        $s = $snaps[$i]
        if (-not $s) { continue }
        try {
            foreach ($k in @(Invoke-ZOpRestore $s)) { if ($k) { $pending += $k } }
        } catch {
            $failed.Insert(0, $s)
            $errors += $_.Exception.Message
        }
    }
    foreach ($w in @(Get-ZArray $entry.notify)) { if ($w) { Invoke-ZNotify $w } }
    if ($failed.Count -gt 0) {
        $entry.snaps = $failed.ToArray()
        $entry.partial = $true
        $Ledger.tweaks[$Id] = $entry
    } else {
        $Ledger.tweaks.Remove($Id)
    }
    $Ledger.pendingKeys = @(Get-ZArray $Ledger.pendingKeys) + $pending
    Invoke-ZPendingKeyCleanup $Ledger
    Save-ZLedger $Ledger
    if ($failed.Count -gt 0) { return @{ id = $Id; ok = $false; message = ($errors -join ' | ') } }
    return @{ id = $Id; ok = $true }
}

function Get-ZEntryName {
    param($Ledger, [string]$Id)
    $e = $Ledger.tweaks[$Id]
    if ($e -and $e.name) { return $e.name }
    return $Id
}

function Test-ZHasOpType {
    param($Tweak, [string]$Type)
    foreach ($o in @(Get-ZArray $Tweak.Ops)) { if ($o.T -eq $Type) { return $true } }
    return $false
}

function Sync-ZPowerSettingTweaks {
    # Power-plan settings live per plan. When the active plan changes, re-apply the power-setting
    # tweaks that are still on so they also hold on the new plan (each plan gets its own snapshot).
    param($Ledger, [string[]]$Exclude = @())
    foreach ($id in @($Ledger.tweaks.Keys)) {
        if (@($Exclude) -contains $id) { continue }
        $t = $Global:ZTweakIndex[$id]
        if (-not $t -or -not (Test-ZHasOpType $t 'PowerSetting')) { continue }
        $r = Invoke-ZApplyOps -Ledger $Ledger -Id $id -Name $t.Name -Category $t.Cat -Ops @(Get-ZTweakOps $t)
        if (-not $r.ok) { Write-ZLog ('Could not carry {0} over to the new power plan: {1}' -f $t.Name, $r.message) 'warn' }
    }
}

function Invoke-ZApplyTweaks {
    param([string[]]$Ids)
    # Catalog order, with the power plan first so power-setting tweaks land on the plan that ends up active.
    $order = @{}
    $n0 = 0
    foreach ($t in $Global:ZTweaks) { $order[$t.Id] = $n0; $n0++ }
    $Ids = @(@($Ids) | Sort-Object {
            $t = $Global:ZTweakIndex[$_]
            if ($t -and (Test-ZHasOpType $t 'PowerPlan')) { -1 } elseif ($order.ContainsKey($_)) { $order[$_] } else { 99999 }
        })
    $ledger = Read-ZLedger
    $results = @()
    $n = [math]::Max(@($Ids).Count, 1)
    $i = 0
    $reboot = $false
    foreach ($id in @($Ids)) {
        $i++
        $t = $Global:ZTweakIndex[$id]
        if (-not $t) { $results += @{ id = $id; ok = $false; message = 'Unknown tweak'; name = $id }; continue }
        Set-ZJobStep ('Applying: ' + $t.Name) ([int](($i - 1) * 100 / $n))
        $r = Invoke-ZApplyOps -Ledger $ledger -Id $id -Name $t.Name -Category $t.Cat -Ops @(Get-ZTweakOps $t)
        $r.name = $t.Name
        if ($r.ok) {
            Write-ZLog ('Applied: ' + $t.Name) 'ok'
            if ($t.Reboot) { $reboot = $true }
            if (Test-ZHasOpType $t 'PowerPlan') { Sync-ZPowerSettingTweaks $ledger @($id) }
        } elseif ($r.skipped) {
            Write-ZLog ('Skipped (not needed on this PC): ' + $t.Name) 'info'
        } else {
            Write-ZLog ('Could not apply {0}: {1} (nothing was changed for this item)' -f $t.Name, $r.message) 'error'
        }
        $results += $r
    }
    $ok = @($results | Where-Object { $_.ok }).Count
    $bad = @($results | Where-Object { -not $_.ok -and -not $_.skipped }).Count
    $ledger = Read-ZLedger
    Add-ZHistory $ledger 'apply' ('{0} applied, {1} failed' -f $ok, $bad) ($bad -eq 0)
    Save-ZLedger $ledger
    return @{ results = $results; applied = $ok; failed = $bad; skipped = @($results | Where-Object { $_.skipped }).Count; reboot = $reboot }
}

function Invoke-ZRevertTweaks {
    param([string[]]$Ids, [string]$Label = 'undo')
    $ledger = Read-ZLedger
    $ordered = @(@($Ids) | Where-Object { $ledger.tweaks.ContainsKey($_) } | Sort-Object { [int]$ledger.tweaks[$_].seq } -Descending)
    $results = @()
    $reboot = $false
    $planReverted = $false
    $n = [math]::Max($ordered.Count, 1)
    $i = 0
    foreach ($id in $ordered) {
        $i++
        $name = Get-ZEntryName $ledger $id
        Set-ZJobStep ('Restoring: ' + $name) ([int](($i - 1) * 100 / $n))
        $r = Invoke-ZRevertEntry -Ledger $ledger -Id $id
        $r.name = $name
        if ($r.ok) { Write-ZLog ('Restored original: ' + $name) 'ok' } else { Write-ZLog ('Could not fully restore {0}: {1}' -f $name, $r.message) 'error' }
        $t = $Global:ZTweakIndex[$id]
        if ($t -and $t.Reboot) { $reboot = $true }
        if ($t -and (Test-ZHasOpType $t 'PowerPlan')) { $planReverted = $true }
        $results += $r
    }
    if ($planReverted) { Sync-ZPowerSettingTweaks $ledger $ordered }
    $ok = @($results | Where-Object { $_.ok }).Count
    $bad = @($results | Where-Object { -not $_.ok }).Count
    Add-ZHistory $ledger $Label ('{0} restored, {1} failed' -f $ok, $bad) ($bad -eq 0)
    Save-ZLedger $ledger
    return @{ results = $results; restored = $ok; failed = $bad; reboot = $reboot }
}

function Invoke-ZRevertAll {
    $ledger = Read-ZLedger
    $ids = @($ledger.tweaks.Keys)
    Write-ZLog ('Restoring original state: {0} change(s) to undo' -f $ids.Count)
    $r = Invoke-ZRevertTweaks -Ids $ids -Label 'restore-all'
    $ledger = Read-ZLedger
    Invoke-ZPendingKeyCleanup $ledger
    Save-ZLedger $ledger
    return $r
}

# ---------------------------------------------------------------------------------------------------
# Windows restore points
# ---------------------------------------------------------------------------------------------------

function Get-ZRestorePoints {
    if ($Global:ZCtx.Mock) { return @($Global:ZMock.RestorePoints | Sort-Object { $_.seq } -Descending) }
    $out = @()
    try { $rps = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch { return @() }
    foreach ($r in $rps) {
        $time = $null
        try { $time = ([Management.ManagementDateTimeConverter]::ToDateTime($r.CreationTime)).ToString('o') } catch { }
        $out += @{ seq = [int]$r.SequenceNumber; description = [string]$r.Description; time = $time; type = [int]$r.RestorePointType }
    }
    return @($out | Sort-Object { $_.seq } -Descending)
}

function Get-ZMaxRestoreSeq {
    $m = 0
    foreach ($r in @(Get-ZRestorePoints)) { if ($r -and [int]$r.seq -gt $m) { $m = [int]$r.seq } }
    return $m
}

function New-ZRestorePoint {
    param([string]$Description = 'Zenith - before optimizations')
    Write-ZLog 'Creating a Windows restore point (this can take up to a minute)...'
    Set-ZJobStep 'Creating a Windows restore point (safety net)...'
    $res = $null
    if ($Global:ZCtx.Mock) {
        Start-Sleep -Milliseconds 900
        $seq = $Global:ZMock.RestorePoints.Count + 1
        [void]$Global:ZMock.RestorePoints.Add(@{ seq = $seq; description = $Description; time = (Get-Date).ToString('o'); type = 12 })
        $res = @{ ok = $true; message = 'Restore point created' }
    } else {
        try { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop } catch { Write-ZLog ('Could not turn on System Protection: ' + $_.Exception.Message) 'warn' }
        $key = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $freq = Get-ZRegValue $key 'SystemRestorePointCreationFrequency'
        $before = Get-ZMaxRestoreSeq
        $err = $null
        try {
            # Windows only allows one restore point per 24h by default; lift that for this one call.
            Set-ZRegValue $key 'SystemRestorePointCreationFrequency' 0 'DWord'
            Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop -WarningAction SilentlyContinue
        } catch { $err = $_.Exception.Message }
        finally {
            try { if ($freq.Exists) { Set-ZRegValue $key 'SystemRestorePointCreationFrequency' $freq.Value $freq.Kind } else { Remove-ZRegValue $key 'SystemRestorePointCreationFrequency' } } catch { }
        }
        if ((Get-ZMaxRestoreSeq) -gt $before) {
            $res = @{ ok = $true; message = 'Restore point created' }
        } else {
            if (-not $err) { $err = 'Windows did not create a restore point. System Protection may be turned off for drive C: or disabled by a policy.' }
            $res = @{ ok = $false; message = $err }
        }
    }
    if ($res.ok) { Write-ZLog 'Windows restore point created.' 'ok' } else { Write-ZLog ('Restore point failed: ' + $res.message) 'warn' }
    $ledger = Read-ZLedger
    $ledger.restorePoints = @(Get-ZArray $ledger.restorePoints) + @(@{ time = (Get-Date).ToString('o'); description = $Description; ok = $res.ok; message = $res.message })
    Add-ZHistory $ledger 'restore-point' $res.message $res.ok
    Save-ZLedger $ledger
    return $res
}

# ---------------------------------------------------------------------------------------------------
# State for the UI
# ---------------------------------------------------------------------------------------------------

function Get-ZTweakStates {
    param($Ledger)
    $out = New-Object System.Collections.ArrayList
    foreach ($t in $Global:ZTweaks) {
        $ops = @(Get-ZTweakOps $t)
        $applicable = ($ops.Count -gt 0)
        $entry = $Ledger.tweaks[$t.Id]
        $satisfied = $false
        if ($applicable) {
            $satisfied = $true
            foreach ($op in $ops) {
                $ok = $false
                try { $ok = [bool](Test-ZOp $op) } catch { $ok = $false }
                if (-not $ok) { $satisfied = $false; break }
            }
        }
        $state = 'off'
        if ($entry -and $satisfied) { $state = 'applied' }
        elseif ($entry) { $state = 'drifted' }
        elseif (-not $applicable) { $state = 'na' }
        elseif ($satisfied) { $state = 'optimal' }
        $changes = @()
        foreach ($op in $ops) { $changes += (Get-ZOpText $op) }
        $tags = @(Get-ZArray $t.Tags)
        $na = $t.NaReason
        if (-not $na) { $na = 'Not needed on this PC' }
        $appliedAt = $null
        $partial = $false
        if ($entry) { $appliedAt = $entry.appliedAt; $partial = [bool]$entry.partial }
        [void]$out.Add(@{
                id = $t.Id; name = $t.Name; cat = $t.Cat; risk = $t.Risk; impact = $t.Impact; preset = $t.Preset
                desc = $t.Desc; details = $t.Details; warning = $t.Warning; tags = $tags; reboot = [bool]$t.Reboot
                changes = $changes; state = $state; naReason = $na; appliedAt = $appliedAt; partial = $partial
            })
    }
    return $out.ToArray()
}

function Get-ZScore {
    param($States)
    $total = 0
    $got = 0
    foreach ($s in $States) {
        if (-not $s.preset -or $s.state -eq 'na') { continue }
        $w = $Global:ZImpactWeight[$s.impact]
        $total += $w
        if ($s.state -eq 'applied' -or $s.state -eq 'optimal') { $got += $w }
    }
    $pct = 0
    if ($total -gt 0) { $pct = [math]::Round($got * 100.0 / $total, 1) }
    foreach ($s in $States) {
        $gain = 0
        if ($s.preset -and $s.state -ne 'na' -and $total -gt 0) { $gain = [math]::Round($Global:ZImpactWeight[$s.impact] * 100.0 / $total, 1) }
        $s.gain = $gain
    }
    return @{ percent = $pct; earned = $got; total = $total }
}

function Get-ZLedgerSummary {
    param($Ledger)
    $items = @()
    foreach ($id in @($Ledger.tweaks.Keys)) {
        $e = $Ledger.tweaks[$id]
        $items += @{ id = $id; name = $e.name; category = $e.category; seq = [int]$e.seq; appliedAt = $e.appliedAt; partial = [bool]$e.partial; changes = @(Get-ZArray $e.snaps).Count }
    }
    $items = @($items | Sort-Object { $_.seq } -Descending)
    $hist = @(Get-ZArray $Ledger.history)
    if ($hist.Count -gt 60) { $hist = $hist[($hist.Count - 60)..($hist.Count - 1)] }
    [array]::Reverse($hist)
    return @{
        items         = $items
        history       = $hist
        restorePoints = @(Get-ZArray $Ledger.restorePoints)
        created       = $Ledger.created
        path          = $Global:ZCtx.LedgerPath
    }
}
