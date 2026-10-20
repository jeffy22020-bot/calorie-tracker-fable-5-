# Zenith - Platform layer
# Thin wrappers over the Windows APIs Zenith touches (registry, services, scheduled tasks, power plans,
# fsutil, network adapters, AppX). Every wrapper has an in-memory "mock" twin so the whole engine can be
# exercised and tested on a machine that is not running Windows.
# Target: Windows PowerShell 5.1. Keep this file ASCII-only.

# ---------------------------------------------------------------------------------------------------
# Context, logging, JSON helpers
# ---------------------------------------------------------------------------------------------------

function Initialize-ZContext {
    param([string]$AppRoot, [string]$DataDir, [switch]$Mock)
    if ($Mock) {
        # Development on a non-Windows machine: give the Windows folders placeholder values.
        $defaults = @{ SystemRoot = 'C:\Windows'; SystemDrive = 'C:'; ProgramData = 'C:\ProgramData'; ProgramFiles = 'C:\Program Files'; 'ProgramFiles(x86)' = 'C:\Program Files (x86)'; LOCALAPPDATA = 'C:\Users\Gamer\AppData\Local'; TEMP = 'C:\Users\Gamer\AppData\Local\Temp'; COMPUTERNAME = 'DESKTOP-TBT25C2' }
        foreach ($k in $defaults.Keys) { if (-not [Environment]::GetEnvironmentVariable($k)) { [Environment]::SetEnvironmentVariable($k, $defaults[$k]) } }
    }
    if (-not $DataDir) {
        if ($Mock) { $DataDir = Join-Path ([IO.Path]::GetTempPath()) 'zenith-mock' } else { $DataDir = Join-Path $env:ProgramData 'Zenith' }
    }
    foreach ($d in @($DataDir, (Join-Path $DataDir 'logs'))) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    $Global:ZCtx = @{
        Version      = '1.0.0'
        AppRoot      = $AppRoot
        DataDir      = $DataDir
        Mock         = [bool]$Mock
        LedgerPath   = Join-Path $DataDir 'backup.json'
        SettingsPath = Join-Path $DataDir 'settings.json'
        LogPath      = Join-Path (Join-Path $DataDir 'logs') 'zenith.log'
    }
    if ($Mock -and -not $Global:ZMock) { $Global:ZMock = New-ZMockState }
    $Global:ZBuildCache = @{}
    $Global:ZCache = @{}
    try {
        $log = Get-Item -LiteralPath $Global:ZCtx.LogPath -ErrorAction Stop
        if ($log.Length -gt 2MB) { Move-Item -LiteralPath $log.FullName -Destination ($log.FullName + '.old') -Force }
    } catch { }
}

function Write-ZLog {
    param([string]$Message, [string]$Level = 'info')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpperInvariant(), $Message
    try { [IO.File]::AppendAllText($Global:ZCtx.LogPath, $line + [Environment]::NewLine) } catch { }
    if ($Global:ZSync) {
        [void]$Global:ZSync.log.Add(@{ t = (Get-Date -Format 'HH:mm:ss'); level = $Level; msg = $Message })
    }
    if ($Global:ZConsole) {
        $color = 'Gray'
        if ($Level -eq 'ok') { $color = 'Green' } elseif ($Level -eq 'warn') { $color = 'Yellow' } elseif ($Level -eq 'error') { $color = 'Red' }
        Write-Host ('  ' + $Message) -ForegroundColor $color
    }
}

function Set-ZJobStep {
    param([string]$Step, [int]$Progress = -1)
    if ($Global:ZSync) {
        $Global:ZSync.step = $Step
        if ($Progress -ge 0) { $Global:ZSync.progress = $Progress }
    }
}

function ConvertTo-ZHashtable {
    # Turns ConvertFrom-Json output (PSCustomObject trees) into hashtables/arrays so the rest of the
    # code can treat stored data and freshly-built data the same way.
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject.GetType().FullName -eq 'System.Management.Automation.PSCustomObject') {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-ZHashtable $p.Value }
        return $h
    }
    if (($InputObject -is [System.Collections.IList]) -and -not ($InputObject -is [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($i in $InputObject) { [void]$list.Add((ConvertTo-ZHashtable $i)) }
        return , $list.ToArray()
    }
    return $InputObject
}

function ConvertTo-ZJson {
    # Deterministic JSON writer. Windows PowerShell 5.1's ConvertTo-Json can turn arrays that passed
    # through the pipeline into {"value":[...],"Count":n}, which would corrupt the backup ledger.
    param($Value)
    $sb = New-Object System.Text.StringBuilder
    Write-ZJsonValue $sb $Value
    return $sb.ToString()
}

function Write-ZJsonString {
    param([System.Text.StringBuilder]$Sb, [string]$Text)
    [void]$Sb.Append('"')
    if ($Text -match '[\\"\x00-\x1f\u2028\u2029]') {
        foreach ($ch in $Text.ToCharArray()) {
            $code = [int]$ch
            if ($ch -eq '"') { [void]$Sb.Append('\"') }
            elseif ($ch -eq '\') { [void]$Sb.Append('\\') }
            elseif ($code -eq 10) { [void]$Sb.Append('\n') }
            elseif ($code -eq 13) { [void]$Sb.Append('\r') }
            elseif ($code -eq 9) { [void]$Sb.Append('\t') }
            elseif ($code -lt 32 -or $code -eq 0x2028 -or $code -eq 0x2029) { [void]$Sb.Append('\u' + $code.ToString('x4')) }
            else { [void]$Sb.Append($ch) }
        }
    } else { [void]$Sb.Append($Text) }
    [void]$Sb.Append('"')
}

function Write-ZJsonValue {
    param([System.Text.StringBuilder]$Sb, $Value)
    if ($null -eq $Value) { [void]$Sb.Append('null'); return }
    if ($Value -is [System.Management.Automation.PSObject] -and $Value.PSObject.BaseObject -ne $null -and -not ($Value.PSObject.BaseObject -is [System.Management.Automation.PSCustomObject])) { $Value = $Value.PSObject.BaseObject }
    if ($Value -is [string]) { Write-ZJsonString $Sb $Value; return }
    if ($Value -is [System.Collections.IDictionary]) {
        [void]$Sb.Append('{')
        $first = $true
        foreach ($k in @($Value.Keys)) {
            if (-not $first) { [void]$Sb.Append(',') }
            $first = $false
            Write-ZJsonString $Sb ([string]$k)
            [void]$Sb.Append(':')
            Write-ZJsonValue $Sb $Value[$k]
        }
        [void]$Sb.Append('}')
        return
    }
    $code = [Type]::GetTypeCode($Value.GetType())
    switch ([int]$code) {
        3 { if ($Value) { [void]$Sb.Append('true') } else { [void]$Sb.Append('false') }; return }
        4 { Write-ZJsonString $Sb ([string]$Value); return }
        { $_ -ge 5 -and $_ -le 12 } { [void]$Sb.Append(([long]$Value).ToString([Globalization.CultureInfo]::InvariantCulture)); return }
        { $_ -ge 13 -and $_ -le 15 } {
            $d = [double]$Value
            if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { [void]$Sb.Append('null') } else { [void]$Sb.Append($d.ToString('R', [Globalization.CultureInfo]::InvariantCulture)) }
            return
        }
        16 { Write-ZJsonString $Sb (([datetime]$Value).ToString('o')); return }
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        [void]$Sb.Append('[')
        $first = $true
        foreach ($item in $Value) {
            if (-not $first) { [void]$Sb.Append(',') }
            $first = $false
            Write-ZJsonValue $Sb $item
        }
        [void]$Sb.Append(']')
        return
    }
    if ($Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [System.Management.Automation.PSObject]) {
        [void]$Sb.Append('{')
        $first = $true
        foreach ($p in $Value.PSObject.Properties) {
            if (-not $first) { [void]$Sb.Append(',') }
            $first = $false
            Write-ZJsonString $Sb $p.Name
            [void]$Sb.Append(':')
            Write-ZJsonValue $Sb $p.Value
        }
        [void]$Sb.Append('}')
        return
    }
    Write-ZJsonString $Sb ([string]$Value)
}

function Read-ZJsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
            if (-not $text.Trim()) { return $null }
            return ConvertTo-ZHashtable (ConvertFrom-Json -InputObject $text)
        } catch {
            Start-Sleep -Milliseconds 120
        }
    }
    throw "Could not read $Path"
}

function Write-ZJsonFile {
    # Atomic write: temp file, then replace (keeps the previous version as .bak).
    param([string]$Path, $Data)
    $json = ConvertTo-ZJson $Data
    $tmp = $Path + '.tmp'
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) {
        [IO.File]::Replace($tmp, $Path, ($Path + '.bak'))
    } else {
        [IO.File]::Move($tmp, $Path)
    }
}

function Get-ZCached {
    # Tiny time-based cache for slow system queries (network adapters). Cleared after every task.
    param([string]$Key, [int]$Seconds, [scriptblock]$Script)
    if (-not $Global:ZCache) { $Global:ZCache = @{} }
    $e = $Global:ZCache[$Key]
    if ($e -and ((Get-Date) - $e.At).TotalSeconds -lt $Seconds) { return $e.Value }
    $v = & $Script
    $Global:ZCache[$Key] = @{ At = (Get-Date); Value = $v }
    return $v
}

function Clear-ZCache { $Global:ZCache = @{} }

function Test-ZAdmin {
    if ($Global:ZCtx -and $Global:ZCtx.Mock) { return $true }
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function ConvertTo-ZInt32 {
    # DWORDs are stored signed by .NET; accept 0..4294967295 and fold into Int32.
    param($Value)
    $l = [long]$Value
    if ($l -gt [int]::MaxValue) { $l = $l - 4294967296 }
    return [int]$l
}

function ConvertTo-ZUInt32 {
    param($Value)
    $l = [long]$Value
    if ($l -lt 0) { $l = $l + 4294967296 }
    return $l
}

# ---------------------------------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------------------------------

function Split-ZRegPath {
    param([string]$Path)
    $i = $Path.IndexOf('\')
    if ($i -lt 0) { $hive = $Path; $sub = '' } else { $hive = $Path.Substring(0, $i); $sub = $Path.Substring($i + 1) }
    $hive = ($hive.ToUpperInvariant()).TrimEnd(':')
    if ($hive -eq 'HKEY_LOCAL_MACHINE') { $hive = 'HKLM' }
    if ($hive -eq 'HKEY_CURRENT_USER') { $hive = 'HKCU' }
    return @($hive, $sub.TrimEnd('\'))
}

function Open-ZBaseKey {
    param([string]$Hive)
    if ($Hive -eq 'HKLM') { return [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64) }
    if ($Hive -eq 'HKCU') { return [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64) }
    throw "Unsupported registry hive: $Hive"
}

function ConvertTo-ZStoredValue {
    # Registry value -> JSON-friendly value (binary as base64).
    param([string]$Kind, $Value)
    if ($null -eq $Value) { return $null }
    switch ($Kind) {
        'Binary'      { return [Convert]::ToBase64String([byte[]]$Value) }
        'MultiString' { return , ([string[]]$Value) }
        'DWord'       { return [int]$Value }
        'QWord'       { return [long]$Value }
        default       { return [string]$Value }
    }
}

function ConvertFrom-ZStoredValue {
    param([string]$Kind, $Value)
    switch ($Kind) {
        'DWord'       { return [int](ConvertTo-ZInt32 $Value) }
        'QWord'       { return [long]$Value }
        'Binary'      { if ($Value -is [string]) { return , ([Convert]::FromBase64String($Value)) } else { return , ([byte[]]$Value) } }
        'MultiString' { return , ([string[]]@($Value)) }
        default       { return [string]$Value }
    }
}

function Test-ZRegKey {
    param([string]$Path)
    if ($Global:ZCtx.Mock) { return $Global:ZMock.RegKeySet.ContainsKey($Path.ToLowerInvariant().TrimEnd('\')) }
    $hive, $sub = Split-ZRegPath $Path
    $base = Open-ZBaseKey $hive
    try {
        $k = $null
        try { $k = $base.OpenSubKey($sub, $false) } catch { return $true }
        if ($k) { $k.Close(); return $true }
        return $false
    } finally { $base.Close() }
}

function Get-ZRegValue {
    # Returns @{ KeyExists; Exists; Kind; Value }
    param([string]$Path, [string]$Name)
    if ($Global:ZCtx.Mock) { return Get-ZMockRegValue $Path $Name }
    $hive, $sub = Split-ZRegPath $Path
    $base = Open-ZBaseKey $hive
    try {
        $k = $base.OpenSubKey($sub, $false)
        if (-not $k) { return @{ KeyExists = $false; Exists = $false; Kind = $null; Value = $null } }
        try {
            $hit = $false
            foreach ($n in $k.GetValueNames()) { if ($n -eq $Name) { $hit = $true; break } }
            if (-not $hit) { return @{ KeyExists = $true; Exists = $false; Kind = $null; Value = $null } }
            $kind = $k.GetValueKind($Name).ToString()
            $val = $k.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            return @{ KeyExists = $true; Exists = $true; Kind = $kind; Value = (ConvertTo-ZStoredValue $kind $val) }
        } finally { $k.Close() }
    } finally { $base.Close() }
}

function Get-ZRegMissingKeys {
    # Keys (shallowest first) that do not exist yet and would be created by writing to $Path.
    param([string]$Path)
    $hive, $sub = Split-ZRegPath $Path
    $missing = New-Object System.Collections.ArrayList
    if (-not $sub) { return @() }
    $cur = ''
    foreach ($part in $sub.Split('\')) {
        if ($cur) { $cur = $cur + '\' + $part } else { $cur = $part }
        $full = $hive + '\' + $cur
        if (-not (Test-ZRegKey $full)) { [void]$missing.Add($full) }
    }
    return $missing.ToArray()
}

function Set-ZRegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Kind = 'DWord')
    if ($Global:ZCtx.Mock) { Set-ZMockRegValue $Path $Name $Value $Kind; return }
    $hive, $sub = Split-ZRegPath $Path
    $base = Open-ZBaseKey $hive
    try {
        $k = $base.CreateSubKey($sub)
        if (-not $k) { throw "Could not open or create registry key $Path" }
        try {
            $k.SetValue($Name, (ConvertFrom-ZStoredValue $Kind $Value), [Microsoft.Win32.RegistryValueKind]$Kind)
        } finally { $k.Close() }
    } finally { $base.Close() }
}

function Remove-ZRegValue {
    param([string]$Path, [string]$Name)
    if ($Global:ZCtx.Mock) { Remove-ZMockRegValue $Path $Name; return }
    $hive, $sub = Split-ZRegPath $Path
    $base = Open-ZBaseKey $hive
    try {
        $k = $base.OpenSubKey($sub, $true)
        if ($k) { try { $k.DeleteValue($Name, $false) } finally { $k.Close() } }
    } finally { $base.Close() }
}

function Remove-ZRegKeyIfEmpty {
    # Returns $true when the key is gone afterwards.
    param([string]$Path)
    if ($Global:ZCtx.Mock) { return Remove-ZMockRegKeyIfEmpty $Path }
    $hive, $sub = Split-ZRegPath $Path
    $base = Open-ZBaseKey $hive
    try {
        $k = $base.OpenSubKey($sub, $false)
        if (-not $k) { return $true }
        $empty = ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0)
        $k.Close()
        if (-not $empty) { return $false }
        $base.DeleteSubKey($sub, $false)
        return $true
    } finally { $base.Close() }
}

function Get-ZRegSubKeyNames {
    param([string]$Path)
    if ($Global:ZCtx.Mock) { return Get-ZMockRegSubKeyNames $Path }
    $hive, $sub = Split-ZRegPath $Path
    $base = Open-ZBaseKey $hive
    try {
        $k = $base.OpenSubKey($sub, $false)
        if (-not $k) { return @() }
        try { return $k.GetSubKeyNames() } finally { $k.Close() }
    } catch { return @() } finally { $base.Close() }
}

function Get-ZRegValueNames {
    param([string]$Path)
    if ($Global:ZCtx.Mock) { return Get-ZMockRegValueNames $Path }
    $hive, $sub = Split-ZRegPath $Path
    $base = Open-ZBaseKey $hive
    try {
        $k = $base.OpenSubKey($sub, $false)
        if (-not $k) { return @() }
        try { return $k.GetValueNames() } finally { $k.Close() }
    } catch { return @() } finally { $base.Close() }
}

# ---------------------------------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------------------------------

function Get-ZService {
    param([string]$Name)
    if ($Global:ZCtx.Mock) {
        $s = $Global:ZMock.Services[$Name]
        if (-not $s) { return @{ Exists = $false } }
        return @{ Exists = $true; Start = [int]$s.Start; Delayed = [int]$s.Delayed; Running = [bool]$s.Running }
    }
    $key = 'HKLM\SYSTEM\CurrentControlSet\Services\' + $Name
    $start = Get-ZRegValue $key 'Start'
    if (-not $start.Exists) { return @{ Exists = $false } }
    $delayed = Get-ZRegValue $key 'DelayedAutostart'
    $running = $false
    try { $running = ((Get-Service -Name $Name -ErrorAction Stop).Status -eq 'Running') } catch { }
    $d = 0
    if ($delayed.Exists) { $d = [int]$delayed.Value }
    return @{ Exists = $true; Start = [int]$start.Value; Delayed = $d; Running = $running }
}

function Set-ZServiceStart {
    param([string]$Name, [int]$Start, [int]$Delayed = 0)
    if ($Global:ZCtx.Mock) {
        $s = $Global:ZMock.Services[$Name]
        if ($s) { $s.Start = $Start; $s.Delayed = $Delayed }
        return
    }
    $mode = 'demand'
    if ($Start -eq 2 -and $Delayed -eq 1) { $mode = 'delayed-auto' }
    elseif ($Start -eq 2) { $mode = 'auto' }
    elseif ($Start -eq 4) { $mode = 'disabled' }
    elseif ($Start -eq 1) { $mode = 'system' }
    elseif ($Start -eq 0) { $mode = 'boot' }
    $out = & sc.exe config "$Name" start= $mode 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("sc.exe config {0} failed ({1}): {2}" -f $Name, $LASTEXITCODE, (($out | Out-String).Trim())) }
    if ($Start -eq 2 -and $Delayed -eq 0) {
        $key = 'HKLM\SYSTEM\CurrentControlSet\Services\' + $Name
        if ((Get-ZRegValue $key 'DelayedAutostart').Exists) { try { Set-ZRegValue $key 'DelayedAutostart' 0 'DWord' } catch { } }
    }
}

function Stop-ZService {
    param([string]$Name)
    if ($Global:ZCtx.Mock) { $s = $Global:ZMock.Services[$Name]; if ($s) { $s.Running = $false }; return }
    try { Stop-Service -Name $Name -Force -NoWait -ErrorAction Stop } catch { Write-ZLog ("Could not stop {0}: {1}" -f $Name, $_.Exception.Message) 'warn' }
}

function Start-ZService {
    param([string]$Name)
    if ($Global:ZCtx.Mock) { $s = $Global:ZMock.Services[$Name]; if ($s) { $s.Running = $true }; return }
    & sc.exe start "$Name" 2>&1 | Out-Null
}

# ---------------------------------------------------------------------------------------------------
# Scheduled tasks (Task Scheduler COM API - fast and works on every edition)
# ---------------------------------------------------------------------------------------------------

function Get-ZTaskScheduler {
    if (-not $Global:ZTaskSvc) {
        $s = New-Object -ComObject 'Schedule.Service'
        $s.Connect()
        $Global:ZTaskSvc = $s
    }
    return $Global:ZTaskSvc
}

function Split-ZTaskPath {
    param([string]$Path)
    $i = $Path.LastIndexOf('\')
    $folder = $Path.Substring(0, $i)
    if (-not $folder) { $folder = '\' }
    return @($folder, $Path.Substring($i + 1))
}

function Get-ZTask {
    param([string]$Path)
    if ($Global:ZCtx.Mock) {
        $t = $Global:ZMock.Tasks[$Path]
        if ($null -eq $t) { return @{ Exists = $false } }
        return @{ Exists = $true; Enabled = [bool]$t }
    }
    $folder, $name = Split-ZTaskPath $Path
    try {
        $t = (Get-ZTaskScheduler).GetFolder($folder).GetTask($name)
        return @{ Exists = $true; Enabled = [bool]$t.Enabled }
    } catch { return @{ Exists = $false } }
}

function Set-ZTaskEnabled {
    param([string]$Path, [bool]$Enabled)
    if ($Global:ZCtx.Mock) { if ($Global:ZMock.Tasks.ContainsKey($Path)) { $Global:ZMock.Tasks[$Path] = $Enabled }; return }
    $folder, $name = Split-ZTaskPath $Path
    $t = (Get-ZTaskScheduler).GetFolder($folder).GetTask($name)
    $t.Enabled = $Enabled
}

function Find-ZTasks {
    # Full paths of tasks in $Folder whose name starts with $Prefix.
    param([string]$Folder, [string]$Prefix)
    if ($Global:ZCtx.Mock) {
        $out = @()
        foreach ($p in @($Global:ZMock.Tasks.Keys)) {
            $f, $n = Split-ZTaskPath $p
            if ($f -eq $Folder -and $n -like ($Prefix + '*')) { $out += $p }
        }
        return $out
    }
    $out = @()
    try {
        $tasks = (Get-ZTaskScheduler).GetFolder($Folder).GetTasks(1)
        foreach ($t in $tasks) { if ($t.Name -like ($Prefix + '*')) { $out += $t.Path } }
    } catch { }
    return $out
}

# ---------------------------------------------------------------------------------------------------
# Power plans (powercfg)
# ---------------------------------------------------------------------------------------------------

$Global:ZGuidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

function Get-ZActiveScheme {
    if ($Global:ZCtx.Mock) { return $Global:ZMock.Power.Active }
    $o = (& powercfg.exe /getactivescheme) -join ' '
    if ($o -match $Global:ZGuidPattern) { return $Matches[0].ToLowerInvariant() }
    return $null
}

function Get-ZPowerSchemes {
    if ($Global:ZCtx.Mock) {
        $out = @()
        foreach ($g in @($Global:ZMock.Power.Schemes.Keys)) {
            $out += @{ Guid = $g; Name = $Global:ZMock.Power.Schemes[$g].Name; Active = ($g -eq $Global:ZMock.Power.Active) }
        }
        return $out
    }
    $out = @()
    foreach ($line in (& powercfg.exe /list)) {
        if ($line -match ('(' + $Global:ZGuidPattern + ')\s+\((.+?)\)(\s*\*)?')) {
            $out += @{ Guid = $Matches[1].ToLowerInvariant(); Name = $Matches[2]; Active = [bool]$Matches[3] }
        }
    }
    return $out
}

function Test-ZPowerScheme {
    param([string]$Guid)
    foreach ($s in (Get-ZPowerSchemes)) { if ($s.Guid -eq $Guid.ToLowerInvariant()) { return $true } }
    return $false
}

function Get-ZPowerValue {
    # AC value of a power setting (hidden settings included).
    param([string]$Scheme, [string]$Sub, [string]$Setting)
    if ($Global:ZCtx.Mock) {
        $s = $Global:ZMock.Power.Schemes[$Scheme]
        if (-not $s) { return $null }
        $k = ($Sub + '|' + $Setting).ToLowerInvariant()
        if ($s.Values.ContainsKey($k)) { return [long]$s.Values[$k] }
        if ($Global:ZMock.PowerDefaults.ContainsKey($k)) { return [long]$Global:ZMock.PowerDefaults[$k] }
        return 1
    }
    foreach ($verb in @('/qh', '/query')) {
        $o = (& powercfg.exe $verb $Scheme $Sub $Setting 2>$null) -join "`n"
        $m = [regex]::Matches($o, '0x[0-9a-fA-F]{8}')
        if ($m.Count -ge 2) { return [Convert]::ToInt64($m[$m.Count - 2].Value.Substring(2), 16) }
    }
    return $null
}

function Get-ZPowerValueDC {
    param([string]$Scheme, [string]$Sub, [string]$Setting)
    if ($Global:ZCtx.Mock) { return Get-ZPowerValue $Scheme $Sub $Setting }
    foreach ($verb in @('/qh', '/query')) {
        $o = (& powercfg.exe $verb $Scheme $Sub $Setting 2>$null) -join "`n"
        $m = [regex]::Matches($o, '0x[0-9a-fA-F]{8}')
        if ($m.Count -ge 2) { return [Convert]::ToInt64($m[$m.Count - 1].Value.Substring(2), 16) }
    }
    return $null
}

function Set-ZPowerValue {
    param([string]$Scheme, [string]$Sub, [string]$Setting, [long]$Value, [switch]$DC)
    if ($Global:ZCtx.Mock) {
        $s = $Global:ZMock.Power.Schemes[$Scheme]
        if ($s) { $s.Values[($Sub + '|' + $Setting).ToLowerInvariant()] = $Value }
        return
    }
    $verb = '/setacvalueindex'
    if ($DC) { $verb = '/setdcvalueindex' }
    & powercfg.exe $verb $Scheme $Sub $Setting $Value 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw ("powercfg {0} failed for {1}" -f $verb, $Setting) }
    if ((Get-ZActiveScheme) -eq $Scheme) { & powercfg.exe /setactive $Scheme 2>&1 | Out-Null }
}

function Copy-ZPowerScheme {
    param([string]$Source, [string]$Dest)
    if ($Global:ZCtx.Mock) {
        if (-not $Global:ZMock.Power.Schemes.ContainsKey($Source)) { return $false }
        $src = $Global:ZMock.Power.Schemes[$Source]
        $vals = @{}
        foreach ($k in @($src.Values.Keys)) { $vals[$k] = $src.Values[$k] }
        $Global:ZMock.Power.Schemes[$Dest] = @{ Name = $src.Name; Values = $vals }
        return $true
    }
    & powercfg.exe /duplicatescheme $Source $Dest 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0 -and (Test-ZPowerScheme $Dest))
}

function Rename-ZPowerScheme {
    param([string]$Guid, [string]$Name, [string]$Description)
    if ($Global:ZCtx.Mock) { $Global:ZMock.Power.Schemes[$Guid].Name = $Name; return }
    & powercfg.exe /changename $Guid $Name $Description 2>&1 | Out-Null
}

function Set-ZActiveScheme {
    param([string]$Guid)
    if ($Global:ZCtx.Mock) { $Global:ZMock.Power.Active = $Guid; return }
    & powercfg.exe /setactive $Guid 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive $Guid failed" }
}

function Remove-ZPowerScheme {
    param([string]$Guid)
    if ($Global:ZCtx.Mock) { $Global:ZMock.Power.Schemes.Remove($Guid); return }
    & powercfg.exe /delete $Guid 2>&1 | Out-Null
}

# ---------------------------------------------------------------------------------------------------
# Hibernation, fsutil
# ---------------------------------------------------------------------------------------------------

function Get-ZHibernateEnabled {
    if ($Global:ZCtx.Mock) { return [bool]$Global:ZMock.Hibernate }
    $v = Get-ZRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
    if ($v.Exists) { return ([int]$v.Value -ne 0) }
    return (Test-Path -LiteralPath (Join-Path $env:SystemDrive 'hiberfil.sys'))
}

function Set-ZHibernate {
    param([bool]$Enabled)
    if ($Global:ZCtx.Mock) { $Global:ZMock.Hibernate = $Enabled; return }
    $arg = 'off'
    if ($Enabled) { $arg = 'on' }
    & powercfg.exe /hibernate $arg 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /hibernate $arg failed" }
}

function Get-ZFsutil {
    param([string]$Setting)
    if ($Global:ZCtx.Mock) { return [int]$Global:ZMock.Fsutil[$Setting] }
    $o = (& fsutil.exe behavior query $Setting 2>$null) -join "`n"
    if ($o -match '=\s*(\d+)') { return [int]$Matches[1] }
    return $null
}

function Set-ZFsutil {
    param([string]$Setting, [int]$Value)
    if ($Global:ZCtx.Mock) { $Global:ZMock.Fsutil[$Setting] = $Value; return }
    & fsutil.exe behavior set $Setting $Value 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "fsutil behavior set $Setting $Value failed" }
}

# ---------------------------------------------------------------------------------------------------
# Network adapters
# ---------------------------------------------------------------------------------------------------

function Get-ZPhysicalAdapters {
    # @{ Name; Description; Guid; Wired; Up; Speed }
    if ($Global:ZCtx.Mock) { return $Global:ZMock.Adapters }
    return Get-ZCached 'adapters' 30 {
        $out = @()
        try {
            foreach ($a in (Get-NetAdapter -Physical -ErrorAction Stop)) {
                $pmt = [string]$a.PhysicalMediaType
                $wired = ($pmt -eq '802.3') -or ($pmt -eq 'Unspecified' -and [string]$a.MediaType -eq '802.3' -and [string]$a.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|802\.11|Bluetooth')
                $out += @{ Name = $a.Name; Description = $a.InterfaceDescription; Guid = [string]$a.InterfaceGuid; Wired = $wired; Up = ($a.Status -eq 'Up'); Speed = [string]$a.LinkSpeed }
            }
        } catch { }
        $out
    }
}

function Get-ZNetAdvItems {
    # Current values of the given advanced-property keywords on wired adapters.
    param([string[]]$Keywords)
    if (-not $Global:ZCtx.Mock) { return Get-ZCached ('netadv|' + ($Keywords -join ',')) 30 { Get-ZNetAdvItemsNow $Keywords } }
    return Get-ZNetAdvItemsNow $Keywords
}

function Get-ZNetAdvItemsNow {
    param([string[]]$Keywords)
    $items = @()
    foreach ($a in (Get-ZPhysicalAdapters)) {
        if (-not $a.Wired) { continue }
        if ($Global:ZCtx.Mock) {
            foreach ($kw in $Keywords) {
                if ($a.Props.ContainsKey($kw)) { $items += @{ Adapter = $a.Name; Keyword = $kw; Value = [string]$a.Props[$kw] } }
            }
            continue
        }
        try {
            $props = Get-NetAdapterAdvancedProperty -Name $a.Name -AllProperties -ErrorAction Stop | Where-Object { $Keywords -contains $_.RegistryKeyword }
            foreach ($p in $props) { $items += @{ Adapter = $a.Name; Keyword = $p.RegistryKeyword; Value = [string](@($p.RegistryValue)[0]) } }
        } catch { }
    }
    return $items
}

function Set-ZNetAdv {
    param([string]$Adapter, [string]$Keyword, [string]$Value)
    if ($Global:ZCtx.Mock) {
        foreach ($a in $Global:ZMock.Adapters) { if ($a.Name -eq $Adapter) { $a.Props[$Keyword] = $Value } }
        return
    }
    Clear-ZCache
    Set-NetAdapterAdvancedProperty -Name $Adapter -RegistryKeyword $Keyword -RegistryValue $Value -ErrorAction Stop
}

# ---------------------------------------------------------------------------------------------------
# AppX packages
# ---------------------------------------------------------------------------------------------------

function Get-ZAppxInstalled {
    # All AppX packages of the current user: @{ Name; FullName; Family; Location; Publisher }
    if ($Global:ZCtx.Mock) {
        $out = @()
        foreach ($n in @($Global:ZMock.Appx.Keys)) { $p = $Global:ZMock.Appx[$n]; if ($p.Installed) { $out += @{ Name = $n; FullName = $p.FullName; Family = $p.Family; Location = $p.Location } } }
        return $out
    }
    $out = @()
    try {
        foreach ($p in (Get-AppxPackage -ErrorAction Stop)) {
            $out += @{ Name = $p.Name; FullName = $p.PackageFullName; Family = $p.PackageFamilyName; Location = $p.InstallLocation }
        }
    } catch { Write-ZLog ("Get-AppxPackage failed: " + $_.Exception.Message) 'warn' }
    return $out
}

function Get-ZAppx {
    param([string]$Name)
    foreach ($p in (Get-ZAppxInstalled)) { if ($p.Name -like $Name) { return @{ Installed = $true; Name = $p.Name; FullName = $p.FullName; Family = $p.Family; Location = $p.Location } } }
    return @{ Installed = $false }
}

function Remove-ZAppx {
    param([string]$FullName, [string]$Name)
    if ($Global:ZCtx.Mock) { if ($Global:ZMock.Appx.ContainsKey($Name)) { $Global:ZMock.Appx[$Name].Installed = $false }; return }
    Remove-AppxPackage -Package $FullName -ErrorAction Stop
}

function Restore-ZAppx {
    param([string]$Name, [string]$Location, [string]$Family)
    if ($Global:ZCtx.Mock) { if ($Global:ZMock.Appx.ContainsKey($Name)) { $Global:ZMock.Appx[$Name].Installed = $true }; return }
    $manifest = Join-Path $Location 'AppxManifest.xml'
    if ($Location -and (Test-Path -LiteralPath $manifest)) {
        Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
        return
    }
    throw ("App files are no longer on disk - reinstall it from the Microsoft Store (ms-windows-store://pdp/?PFN={0})" -f $Family)
}

# ---------------------------------------------------------------------------------------------------
# Misc system info used by dynamic tweaks
# ---------------------------------------------------------------------------------------------------

function Get-ZTotalMemoryKB {
    if ($Global:ZCtx.Mock) { return 67043328 }
    return [long]([math]::Ceiling((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1KB))
}

function Get-ZGpuDevices {
    # @{ Name; PnpId; Vendor }
    if ($Global:ZCtx.Mock) { return $Global:ZMock.Gpus }
    $out = @()
    foreach ($g in (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
        $vendor = 'Other'
        if ($g.PNPDeviceID -like 'PCI\VEN_10DE*') { $vendor = 'NVIDIA' }
        elseif ($g.PNPDeviceID -like 'PCI\VEN_1002*') { $vendor = 'AMD' }
        elseif ($g.PNPDeviceID -like 'PCI\VEN_8086*') { $vendor = 'Intel' }
        $out += @{ Name = $g.Name; PnpId = $g.PNPDeviceID; Vendor = $vendor }
    }
    return $out
}

function Test-ZFileExists {
    param([string]$Path)
    if ($Global:ZCtx.Mock) { return [bool]$Global:ZMock.Files[$Path] }
    return (Test-Path -LiteralPath $Path)
}

function Find-ZChrome {
    if ($Global:ZCtx.Mock) { return $null }
    $paths = @(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    foreach ($p in $paths) { if ($p -and (Test-ZFileExists $p)) { return $p } }
    return $null
}

function Update-ZMouseSettings {
    # Applies the registry mouse values to the live session (no sign-out needed).
    if ($Global:ZCtx.Mock) { return }
    try {
        if (-not ('ZenithNative' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ZenithNative {
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool SystemParametersInfo(uint action, uint param, int[] vparam, uint winIni);
    public static bool SetMouse(int t1, int t2, int speed) {
        return SystemParametersInfo(0x0004, 0, new int[] { t1, t2, speed }, 0x02);
    }
}
'@
        }
        $k = 'HKCU\Control Panel\Mouse'
        $t1 = [int](Get-ZRegValue $k 'MouseThreshold1').Value
        $t2 = [int](Get-ZRegValue $k 'MouseThreshold2').Value
        $sp = [int](Get-ZRegValue $k 'MouseSpeed').Value
        [void][ZenithNative]::SetMouse($t1, $t2, $sp)
    } catch { Write-ZLog ("Mouse refresh failed: " + $_.Exception.Message) 'warn' }
}

# ---------------------------------------------------------------------------------------------------
# Mock provider (used with -Mock for development and tests)
# ---------------------------------------------------------------------------------------------------

function New-ZMockState {
    $m = [hashtable]::Synchronized(@{})
    $m.RegKeySet = @{}
    $m.RegValues = @{}
    $m.Services = @{}
    $m.Tasks = @{}
    $m.Files = @{}
    $m.RestorePoints = New-Object System.Collections.ArrayList
    $m.Hibernate = $true
    $m.Fsutil = @{ disablelastaccess = 2; DisableDeleteNotify = 0 }
    $m.PowerDefaults = @{}
    $m.Power = @{
        Active  = '381b4222-f694-41f0-9685-ff5bb260df2e'
        Schemes = @{
            '381b4222-f694-41f0-9685-ff5bb260df2e' = @{ Name = 'Balanced'; Values = @{} }
            '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = @{ Name = 'High performance'; Values = @{} }
            'a1841308-3541-4fab-bc81-f71556f20b4a' = @{ Name = 'Power saver'; Values = @{} }
            'e9a42b02-d5df-448d-aa00-03f14749eb61' = @{ Name = 'Ultimate Performance'; Values = @{} }
        }
    }
    $Global:ZMock = $m
    foreach ($k in @('HKLM', 'HKCU', 'HKLM\SOFTWARE', 'HKLM\SYSTEM', 'HKCU\Software', 'HKCU\Control Panel', 'HKCU\System')) { Add-ZMockKey $k }
    Initialize-ZMockSeed
    return $m
}

function Add-ZMockKey {
    param([string]$Path)
    $l = $Path.ToLowerInvariant().TrimEnd('\')
    $parts = $l.Split('\')
    $cur = ''
    foreach ($p in $parts) {
        if ($cur) { $cur = $cur + '\' + $p } else { $cur = $p }
        if (-not $Global:ZMock.RegKeySet.ContainsKey($cur)) { $Global:ZMock.RegKeySet[$cur] = $true }
    }
}

function Get-ZMockRegValue {
    param([string]$Path, [string]$Name)
    $l = $Path.ToLowerInvariant().TrimEnd('\')
    if (-not $Global:ZMock.RegKeySet.ContainsKey($l)) { return @{ KeyExists = $false; Exists = $false; Kind = $null; Value = $null } }
    $vals = $Global:ZMock.RegValues[$l]
    $n = $Name.ToLowerInvariant()
    if (-not $vals -or -not $vals.ContainsKey($n)) { return @{ KeyExists = $true; Exists = $false; Kind = $null; Value = $null } }
    $v = $vals[$n]
    return @{ KeyExists = $true; Exists = $true; Kind = $v.Kind; Value = $v.Value }
}

function Set-ZMockRegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Kind)
    $l = $Path.ToLowerInvariant().TrimEnd('\')
    Add-ZMockKey $l
    if (-not $Global:ZMock.RegValues.ContainsKey($l)) { $Global:ZMock.RegValues[$l] = @{} }
    $stored = $Value
    if ($Kind -eq 'DWord') { $stored = [int](ConvertTo-ZInt32 $Value) }
    elseif ($Kind -eq 'Binary' -and -not ($Value -is [string])) { $stored = [Convert]::ToBase64String([byte[]]$Value) }
    $Global:ZMock.RegValues[$l][$Name.ToLowerInvariant()] = @{ Name = $Name; Kind = $Kind; Value = $stored }
}

function Remove-ZMockRegValue {
    param([string]$Path, [string]$Name)
    $l = $Path.ToLowerInvariant().TrimEnd('\')
    if ($Global:ZMock.RegValues.ContainsKey($l)) {
        $Global:ZMock.RegValues[$l].Remove($Name.ToLowerInvariant())
        if ($Global:ZMock.RegValues[$l].Count -eq 0) { $Global:ZMock.RegValues.Remove($l) }
    }
}

function Remove-ZMockRegKeyIfEmpty {
    param([string]$Path)
    $l = $Path.ToLowerInvariant().TrimEnd('\')
    if (-not $Global:ZMock.RegKeySet.ContainsKey($l)) { return $true }
    if ($Global:ZMock.RegValues.ContainsKey($l) -and $Global:ZMock.RegValues[$l].Count -gt 0) { return $false }
    $prefix = $l + '\'
    foreach ($k in @($Global:ZMock.RegKeySet.Keys)) { if ($k.StartsWith($prefix)) { return $false } }
    $Global:ZMock.RegKeySet.Remove($l)
    return $true
}

function Get-ZMockRegSubKeyNames {
    param([string]$Path)
    $prefix = $Path.ToLowerInvariant().TrimEnd('\') + '\'
    $names = @{}
    foreach ($k in @($Global:ZMock.RegKeySet.Keys)) {
        if ($k.StartsWith($prefix)) {
            $rest = $k.Substring($prefix.Length)
            $first = $rest.Split('\')[0]
            if ($first) { $names[$first] = $true }
        }
    }
    return @($names.Keys)
}

function Get-ZMockRegValueNames {
    param([string]$Path)
    $l = $Path.ToLowerInvariant().TrimEnd('\')
    if (-not $Global:ZMock.RegValues.ContainsKey($l)) { return @() }
    $out = @()
    foreach ($v in $Global:ZMock.RegValues[$l].Values) { $out += $v.Name }
    return $out
}

function Initialize-ZMockSeed {
    # A believable starting point that mirrors a stock Windows 11 Home gaming PC.
    $d = 'DWord'; $s = 'String'
    $seed = @(
        @('HKCU\System\GameConfigStore', 'GameDVR_Enabled', 1, $d),
        @('HKCU\System\GameConfigStore', 'GameDVR_FSEBehaviorMode', 0, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR', 'AppCaptureEnabled', 1, $d),
        @('HKCU\Software\Microsoft\GameBar', 'UseNexusForGameBarEnabled', 1, $d),
        @('HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers', 'HwSchMode', 2, $d),
        @('HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile', 'SystemResponsiveness', 20, $d),
        @('HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile', 'NetworkThrottlingIndex', 10, $d),
        @('HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games', 'GPU Priority', 8, $d),
        @('HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games', 'Priority', 2, $d),
        @('HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games', 'Scheduling Category', 'Medium', $s),
        @('HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games', 'SFIO Priority', 'Normal', $s),
        @('HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl', 'Win32PrioritySeparation', 2, $d),
        @('HKCU\Control Panel\Mouse', 'MouseSpeed', '1', $s),
        @('HKCU\Control Panel\Mouse', 'MouseThreshold1', '6', $s),
        @('HKCU\Control Panel\Mouse', 'MouseThreshold2', '10', $s),
        @('HKCU\Control Panel\Accessibility\StickyKeys', 'Flags', '510', $s),
        @('HKCU\Control Panel\Accessibility\Keyboard Response', 'Flags', '126', $s),
        @('HKCU\Control Panel\Accessibility\ToggleKeys', 'Flags', '62', $s),
        @('HKCU\Control Panel\Desktop', 'MenuShowDelay', '400', $s),
        @('HKCU\Control Panel\Desktop\WindowMetrics', 'MinAnimate', '1', $s),
        @('HKCU\Control Panel\Keyboard', 'KeyboardDelay', '1', $s),
        @('HKCU\Control Panel\Keyboard', 'KeyboardSpeed', '31', $s),
        @('HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management', 'DisablePagingExecutive', 0, $d),
        @('HKLM\SYSTEM\CurrentControlSet\Control', 'SvcHostSplitThresholdInKB', 3670016, $d),
        @('HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power', 'HiberbootEnabled', 1, $d),
        @('HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity', 'Enabled', 1, $d),
        @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching', 'SearchOrderConfig', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338388Enabled', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338389Enabled', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SilentInstalledAppsEnabled', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'RotatingLockScreenOverlayEnabled', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'HideFileExt', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarAnimations', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ShowCopilotButton', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'Start_IrisRecommendations', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'EnableTransparency', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings', 'IsDynamicSearchBoxEnabled', 1, $d),
        @('HKCU\Software\Microsoft\DirectX\UserGpuPreferences', 'DirectXUserGlobalSettings', 'VRROptimizeEnable=0;', $s),
        @('HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{7d2c4b10-5a1e-4f3b-9c61-2b8f0e6d1a11}', 'DhcpIPAddress', '192.168.1.42', $s),
        @('HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0c9e2a77-31d4-4b8e-a0f2-6e5d4c3b2a19}', 'DhcpIPAddress', '0.0.0.0', $s),
        @('HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\0001', 'NetCfgInstanceId', '{7d2c4b10-5a1e-4f3b-9c61-2b8f0e6d1a11}', $s),
        @('HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\0001', 'DriverDesc', 'Realtek PCIe 2.5GbE Family Controller', $s),
        @('HKLM\SYSTEM\CurrentControlSet\Enum\PCI\VEN_10DE&DEV_2484&SUBSYS_87B91043&REV_A1\4&2b1a7c3d&0&0019\Device Parameters', 'FirmwareIdentified', 1, $d),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Run', 'OneDrive', '"C:\Users\Gamer\AppData\Local\Microsoft\OneDrive\OneDrive.exe" /background', $s),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Run', 'Discord', '"C:\Users\Gamer\AppData\Local\Discord\Update.exe" --processStart Discord.exe', $s),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Run', 'Steam', '"C:\Program Files (x86)\Steam\steam.exe" -silent', $s),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Run', 'Spotify', '"C:\Users\Gamer\AppData\Roaming\Spotify\Spotify.exe" /background', $s),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Run', 'EpicGamesLauncher', '"C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe" -silent', $s),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Run', 'MicrosoftEdgeAutoLaunch', '"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --no-startup-window --win-session-start', $s),
        @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'SecurityHealth', '%windir%\system32\SecurityHealthSystray.exe', 'ExpandString'),
        @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'RtkAudUService', '"C:\Windows\System32\DriverStore\FileRepository\realtekservice.inf_amd64\RtkAudUService64.exe" -background', $s),
        @('HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'ArmouryCrate', '"C:\Program Files\ASUS\ARMOURY CRATE Lite Service\ArmouryCrate.UserSessionHelper.exe"', $s),
        @('HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', 'Spotify', 'AwAAAAAAAAAAAAAA', 'Binary')
    )
    foreach ($e in $seed) { Set-ZMockRegValue $e[0] $e[1] $e[2] $e[3] }

    $svc = @{
        'DiagTrack' = @(2, 0, $true); 'dmwappushservice' = @(3, 0, $false); 'SysMain' = @(2, 0, $true); 'WSearch' = @(2, 1, $true)
        'MapsBroker' = @(2, 1, $false); 'TrkWks' = @(2, 0, $true); 'PcaSvc' = @(2, 1, $true); 'RemoteRegistry' = @(4, 0, $false)
        'RetailDemo' = @(3, 0, $false); 'WMPNetworkSvc' = @(3, 0, $false); 'Spooler' = @(2, 0, $true); 'edgeupdate' = @(2, 1, $false); 'edgeupdatem' = @(3, 0, $false)
        'ArmouryCrateService' = @(2, 0, $true); 'AsusAppService' = @(2, 0, $true); 'ASUSOptimization' = @(2, 0, $true); 'ASUSSoftwareManager' = @(2, 0, $true)
        'ASUSSwitch' = @(2, 0, $true); 'ASUSSystemAnalysis' = @(2, 0, $true); 'ASUSSystemDiagnosis' = @(2, 0, $true); 'ROG Live Service' = @(3, 0, $false)
        'WerSvc' = @(3, 0, $false); 'wuauserv' = @(3, 0, $true); 'bits' = @(2, 1, $true)
    }
    foreach ($n in $svc.Keys) { $v = $svc[$n]; $Global:ZMock.Services[$n] = @{ Start = $v[0]; Delayed = $v[1]; Running = $v[2] } }

    $tasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Application Experience\MareBackup',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
        '\NvTmRep_CrashReport1_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
        '\NvTmRep_CrashReport2_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
        '\NvTmRep_CrashReport3_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}'
    )
    foreach ($t in $tasks) { $Global:ZMock.Tasks[$t] = $true }

    # Like real Windows, every plan carries an explicit value for every setting.
    $powerDefaults = @{
        '2a737441-1930-4402-8d77-b2bebba308a3|48e6b7a6-50f5-4782-a5d4-53bb8f07e226' = 1
        '501a4d13-42af-4429-9fd1-a8218c268e20|ee12f906-d277-404b-b6da-e5fa1a576df5' = 1
        '54533251-82be-4824-96c1-47b60b740d00|0cc5b647-c1df-4637-891a-dec35c318583' = 10
        '54533251-82be-4824-96c1-47b60b740d00|be337238-0d82-4146-a960-4f3749d470c7' = 1
        '238c9fa8-0aad-41ed-83f4-97be242c8f20|29f6c1db-86da-48c5-9fdb-f2b67b1f44da' = 1800
        '238c9fa8-0aad-41ed-83f4-97be242c8f20|9d7815a6-7ee4-497e-8888-515a05f02364' = 0
        '7516b95f-f776-4464-8c53-06167f40cc99|3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e' = 600
    }
    foreach ($g in @($Global:ZMock.Power.Schemes.Keys)) {
        foreach ($k in $powerDefaults.Keys) { $Global:ZMock.Power.Schemes[$g].Values[$k] = [long]$powerDefaults[$k] }
    }
    foreach ($g in @('8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'e9a42b02-d5df-448d-aa00-03f14749eb61')) {
        $Global:ZMock.Power.Schemes[$g].Values['54533251-82be-4824-96c1-47b60b740d00|0cc5b647-c1df-4637-891a-dec35c318583'] = [long]100
        $Global:ZMock.Power.Schemes[$g].Values['238c9fa8-0aad-41ed-83f4-97be242c8f20|29f6c1db-86da-48c5-9fdb-f2b67b1f44da'] = [long]0
    }

    $Global:ZMock.Adapters = @(
        @{ Name = 'Ethernet'; Description = 'Realtek PCIe 2.5GbE Family Controller'; Guid = '{7d2c4b10-5a1e-4f3b-9c61-2b8f0e6d1a11}'; Wired = $true; Up = $true; Speed = '1 Gbps'; Props = @{ '*EEE' = '1'; 'EnableGreenEthernet' = '1'; 'PowerSavingMode' = '1' } },
        @{ Name = 'Wi-Fi'; Description = 'Realtek RTL8852BE WiFi 6 802.11ax PCIe Adapter'; Guid = '{0c9e2a77-31d4-4b8e-a0f2-6e5d4c3b2a19}'; Wired = $false; Up = $false; Speed = '0 bps'; Props = @{} }
    )
    $Global:ZMock.Gpus = @(@{ Name = 'NVIDIA GeForce RTX 3070'; PnpId = 'PCI\VEN_10DE&DEV_2484&SUBSYS_87B91043&REV_A1\4&2b1a7c3d&0&0019'; Vendor = 'NVIDIA' })

    $Global:ZMock.Appx = @{}
    foreach ($n in @('Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftOfficeHub',
            'Microsoft.Copilot', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub', 'Microsoft.ZuneVideo', 'Clipchamp.Clipchamp', 'MSTeams',
            'Microsoft.YourPhone', 'Microsoft.OutlookForWindows', 'Microsoft.WindowsMaps', 'king.com.CandyCrushSaga', 'Microsoft.XboxGamingOverlay', 'B9ECED6F.ASUSPCAssistant', 'Microsoft.Windows.DevHome')) {
        $Global:ZMock.Appx[$n] = @{ Installed = $true; FullName = ($n + '_1.0.0.0_x64__8wekyb3d8bbwe'); Family = ($n + '_8wekyb3d8bbwe'); Location = ('C:\Program Files\WindowsApps\' + $n) }
    }
}
