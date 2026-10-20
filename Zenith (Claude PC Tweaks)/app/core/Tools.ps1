# Zenith - Tools: startup apps, bloatware apps, cleaner, games library, Game Boost, system repair.
# Startup and app changes go through the same backup ledger as tweaks, so "Restore Original State"
# undoes them too.
# Target: Windows PowerShell 5.1. Keep this file ASCII-only.

# ---------------------------------------------------------------------------------------------------
# Startup apps (same mechanism Task Manager uses: StartupApproved flags, nothing is deleted)
# ---------------------------------------------------------------------------------------------------

function Get-ZStartupSources {
    $approved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $userFolder = $null; $commonFolder = $null
    if (-not $Global:ZCtx.Mock) {
        $userFolder = [Environment]::GetFolderPath('Startup')
        $commonFolder = [Environment]::GetFolderPath('CommonStartup')
    }
    return @(
        @{ id = 'hkcu-run'; scope = 'Your account'; kind = 'Run'; path = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'; approved = "HKCU\$approved\Run" }
        @{ id = 'hklm-run'; scope = 'All users'; kind = 'Run'; path = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; approved = "HKLM\$approved\Run" }
        @{ id = 'hklm-run32'; scope = 'All users'; kind = 'Run'; path = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; approved = "HKLM\$approved\Run32" }
        @{ id = 'user-folder'; scope = 'Your account'; kind = 'Folder'; path = $userFolder; approved = "HKCU\$approved\StartupFolder" }
        @{ id = 'common-folder'; scope = 'All users'; kind = 'Folder'; path = $commonFolder; approved = "HKLM\$approved\StartupFolder" }
    )
}

function Get-ZExeFromCommand {
    param([string]$Command)
    if (-not $Command) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    if ($c.StartsWith('"')) { $end = $c.IndexOf('"', 1); if ($end -gt 1) { return $c.Substring(1, $end - 1) } }
    $i = $c.ToLowerInvariant().IndexOf('.exe')
    if ($i -gt 0) { return $c.Substring(0, $i + 4) }
    return $c.Split(' ')[0]
}

function Get-ZPublisher {
    param([string]$Exe)
    if ($Global:ZCtx.Mock) {
        $map = @{ 'onedrive' = 'Microsoft Corporation'; 'update' = 'Discord Inc.'; 'steam' = 'Valve Corporation'; 'spotify' = 'Spotify Ltd'; 'epicgameslauncher' = 'Epic Games, Inc.'; 'msedge' = 'Microsoft Corporation'; 'securityhealthsystray' = 'Microsoft Corporation'; 'rtkaudservice64' = 'Realtek Semiconductor'; 'armourycrate.usersessionhelper' = 'ASUSTeK Computer Inc.' }
        $k = [IO.Path]::GetFileNameWithoutExtension(([string]$Exe).Replace('\', '/')).ToLowerInvariant()
        return $map[$k]
    }
    try { if ($Exe -and (Test-Path -LiteralPath $Exe)) { return [Diagnostics.FileVersionInfo]::GetVersionInfo($Exe).CompanyName } } catch { }
    return $null
}

function Get-ZStartupItems {
    $items = @()
    foreach ($src in (Get-ZStartupSources)) {
        $entries = @()
        if ($src.kind -eq 'Run') {
            foreach ($n in @(Get-ZRegValueNames $src.path)) {
                if (-not $n) { continue }
                $entries += @{ name = $n; command = [string](Get-ZRegValue $src.path $n).Value }
            }
        } elseif ($src.path -and (Test-Path -LiteralPath $src.path)) {
            $shell = $null
            foreach ($f in @(Get-ChildItem -LiteralPath $src.path -File -ErrorAction SilentlyContinue)) {
                if ($f.Name -ieq 'desktop.ini') { continue }
                $cmd = $f.FullName
                if ($f.Extension -ieq '.lnk') {
                    try {
                        if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
                        $lnk = $shell.CreateShortcut($f.FullName)
                        $cmd = ('"{0}" {1}' -f $lnk.TargetPath, $lnk.Arguments).Trim()
                    } catch { }
                }
                $entries += @{ name = $f.Name; command = $cmd }
            }
        }
        foreach ($e in $entries) {
            $flag = Get-ZRegValue $src.approved $e.name
            $enabled = $true
            if ($flag.Exists -and $flag.Kind -eq 'Binary') {
                $b = [Convert]::FromBase64String([string]$flag.Value)
                if ($b.Length -gt 0 -and ($b[0] -band 1) -eq 1) { $enabled = $false }
            }
            $exe = Get-ZExeFromCommand $e.command
            $display = $e.name
            if ($display -match '\.lnk$') { $display = $display.Substring(0, $display.Length - 4) }
            $items += @{
                id = ('startup:' + $src.id + ':' + $e.name); name = $display; valueName = $e.name; command = $e.command; scope = $src.scope
                source = $src.id; approved = $src.approved; enabled = $enabled; publisher = (Get-ZPublisher $exe)
            }
        }
    }
    return $items
}

function New-ZStartupFlag {
    param([bool]$Enabled)
    $b = New-Object byte[] 12
    if ($Enabled) { $b[0] = 2 } else {
        $b[0] = 3
        $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime())
        [Array]::Copy($ft, 0, $b, 4, 8)
    }
    return [Convert]::ToBase64String($b)
}

function Set-ZStartupItem {
    # Toggling an item back to how it started undoes the ledger entry; otherwise a new entry is recorded.
    param([string]$Id, [bool]$Enabled)
    $item = $null
    foreach ($i in (Get-ZStartupItems)) { if ($i.id -eq $Id) { $item = $i } }
    if (-not $item) { throw 'Startup item not found' }
    $ledger = Read-ZLedger
    if ($ledger.tweaks.ContainsKey($Id)) {
        $r = Invoke-ZRevertEntry -Ledger $ledger -Id $Id
        $ledger = Read-ZLedger
        Add-ZHistory $ledger 'startup' ('{0}: restored' -f $item.name) $r.ok
        Save-ZLedger $ledger
        if ((@(Get-ZStartupItems | Where-Object { $_.id -eq $Id -and $_.enabled -eq $Enabled })).Count -gt 0) { return $r }
        $ledger = Read-ZLedger
    }
    $op = @{ T = 'Reg'; Path = $item.approved; Name = $item.valueName; Kind = 'Binary'; Value = (New-ZStartupFlag $Enabled) }
    $label = 'Startup: ' + $item.name
    $r = Invoke-ZApplyOps -Ledger $ledger -Id $Id -Name $label -Category 'startup' -Ops @($op)
    $ledger = Read-ZLedger
    $state = 'disabled'
    if ($Enabled) { $state = 'enabled' }
    Add-ZHistory $ledger 'startup' ('{0}: {1}' -f $item.name, $state) $r.ok
    Save-ZLedger $ledger
    Write-ZLog ('Startup app {0} {1}' -f $item.name, $state) 'ok'
    return $r
}

# ---------------------------------------------------------------------------------------------------
# Bloatware apps (allowlist only - nothing outside this list can be removed)
# ---------------------------------------------------------------------------------------------------

$Global:ZBloatApps = @(
    @{ name = 'Microsoft.BingNews'; label = 'Microsoft News'; note = 'News feed app'; rec = $true }
    @{ name = 'Microsoft.BingWeather'; label = 'Weather'; note = 'MSN Weather'; rec = $true }
    @{ name = 'Microsoft.BingSearch'; label = 'Bing Search'; note = 'Bing web search integration'; rec = $true }
    @{ name = 'Microsoft.GetHelp'; label = 'Get Help'; note = 'Support chat app'; rec = $true }
    @{ name = 'Microsoft.Getstarted'; label = 'Tips'; note = 'Windows tips app'; rec = $true }
    @{ name = 'Microsoft.MicrosoftSolitaireCollection'; label = 'Solitaire Collection'; note = 'Ad-supported card games'; rec = $true }
    @{ name = 'Microsoft.MicrosoftOfficeHub'; label = 'Microsoft 365 (Office) hub'; note = 'Promotes Microsoft 365 subscriptions'; rec = $true }
    @{ name = 'Microsoft.Copilot'; label = 'Copilot'; note = 'AI assistant app'; rec = $true }
    @{ name = 'Microsoft.PowerAutomateDesktop'; label = 'Power Automate'; note = 'Automation tool'; rec = $true }
    @{ name = 'Microsoft.Todos'; label = 'Microsoft To Do'; note = 'Task list app'; rec = $false }
    @{ name = 'Microsoft.WindowsFeedbackHub'; label = 'Feedback Hub'; note = 'Sends feedback to Microsoft'; rec = $true }
    @{ name = 'Microsoft.WindowsMaps'; label = 'Maps'; note = 'Offline maps app'; rec = $true }
    @{ name = 'Microsoft.ZuneVideo'; label = 'Movies & TV'; note = 'Video store app'; rec = $true }
    @{ name = 'Microsoft.People'; label = 'People'; note = 'Contacts app'; rec = $true }
    @{ name = 'Microsoft.MixedReality.Portal'; label = 'Mixed Reality Portal'; note = 'Only for WMR headsets'; rec = $true }
    @{ name = 'Microsoft.SkypeApp'; label = 'Skype'; note = 'Discontinued by Microsoft'; rec = $true }
    @{ name = 'Microsoft.Windows.DevHome'; label = 'Dev Home'; note = 'Developer dashboard'; rec = $true }
    @{ name = 'Clipchamp.Clipchamp'; label = 'Clipchamp'; note = 'Video editor'; rec = $true }
    @{ name = 'MicrosoftCorporationII.QuickAssist'; label = 'Quick Assist'; note = 'Remote help tool (often abused by scammers)'; rec = $true }
    @{ name = 'Microsoft.549981C3F5F10'; label = 'Cortana'; note = 'Discontinued assistant'; rec = $true }
    @{ name = 'MSTeams'; label = 'Microsoft Teams (personal)'; note = 'Starts with Windows'; rec = $true }
    @{ name = 'MicrosoftTeams'; label = 'Microsoft Teams (classic)'; note = 'Starts with Windows'; rec = $true }
    @{ name = 'Microsoft.OutlookForWindows'; label = 'Outlook (new)'; note = 'Remove only if you use another mail app'; rec = $false }
    @{ name = 'Microsoft.YourPhone'; label = 'Phone Link'; note = 'Keep if you link your phone'; rec = $false }
    @{ name = 'Microsoft.WindowsSoundRecorder'; label = 'Sound Recorder'; note = 'Voice recorder'; rec = $false }
    @{ name = 'Microsoft.XboxGamingOverlay'; label = 'Xbox Game Bar'; note = 'Overlay; removing it also removes Win+G capture'; rec = $false }
    @{ name = 'B9ECED6F.ASUSPCAssistant'; label = 'MyASUS'; note = 'ASUS support app'; rec = $false }
    @{ name = 'king.com.CandyCrushSaga'; label = 'Candy Crush Saga'; note = 'Sponsored game'; rec = $true }
    @{ name = 'king.com.CandyCrushSodaSaga'; label = 'Candy Crush Soda Saga'; note = 'Sponsored game'; rec = $true }
    @{ name = 'Facebook.Facebook'; label = 'Facebook'; note = 'Sponsored app'; rec = $true }
    @{ name = 'BytedancePte.Ltd.TikTok'; label = 'TikTok'; note = 'Sponsored app'; rec = $true }
    @{ name = 'AmazonVideo.PrimeVideo'; label = 'Prime Video'; note = 'Sponsored app'; rec = $false }
    @{ name = '*Disney*'; label = 'Disney+'; note = 'Sponsored app'; rec = $false }
)

function Get-ZBloatList {
    $installed = @(Get-ZAppxInstalled)
    $ledger = Read-ZLedger
    $out = @()
    foreach ($a in $Global:ZBloatApps) {
        $hit = $null
        foreach ($p in $installed) { if ($p.Name -like $a.name) { $hit = $p; break } }
        $lid = 'appx:' + $a.name
        $removed = $ledger.tweaks.ContainsKey($lid)
        if (-not $hit -and -not $removed) { continue }
        $out += @{ name = $a.name; label = $a.label; note = $a.note; recommended = [bool]$a.rec; installed = [bool]$hit; removedByZenith = $removed }
    }
    return $out
}

function Remove-ZBloatApps {
    param([string[]]$Names)
    $ledger = Read-ZLedger
    $allowed = @{}
    foreach ($a in $Global:ZBloatApps) { $allowed[$a.name] = $a }
    $results = @()
    $n = [math]::Max(@($Names).Count, 1); $i = 0
    foreach ($name in @($Names)) {
        $i++
        $a = $allowed[$name]
        if (-not $a) { $results += @{ id = $name; ok = $false; message = 'Not on the removable list' }; continue }
        Set-ZJobStep ('Removing ' + $a.label) ([int](($i - 1) * 100 / $n))
        $r = Invoke-ZApplyOps -Ledger $ledger -Id ('appx:' + $name) -Name ('App: ' + $a.label) -Category 'apps' -Ops @(@{ T = 'AppX'; Name = $name })
        $r.name = $a.label
        if ($r.ok) { Write-ZLog ('Removed app: ' + $a.label) 'ok' } else { Write-ZLog ('Could not remove {0}: {1}' -f $a.label, $r.message) 'error' }
        $results += $r
    }
    $ledger = Read-ZLedger
    Add-ZHistory $ledger 'apps' ('{0} app(s) removed' -f @($results | Where-Object { $_.ok }).Count) $true
    Save-ZLedger $ledger
    return @{ results = $results; applied = @($results | Where-Object { $_.ok }).Count; failed = @($results | Where-Object { -not $_.ok }).Count }
}

# ---------------------------------------------------------------------------------------------------
# Cleaner
# ---------------------------------------------------------------------------------------------------

function Get-ZCleanTargets {
    $sr = $env:SystemRoot
    $la = $env:LOCALAPPDATA
    $pd = $env:ProgramData
    return @(
        @{ id = 'user-temp'; prune = $true; label = 'Temporary files (your account)'; desc = 'Leftovers from installers and apps. Files used in the last 24 hours are kept.'; paths = @($env:TEMP); minAgeHours = 24; default = $true }
        @{ id = 'win-temp'; prune = $true; label = 'Windows temporary files'; desc = 'System temp folder. Files used in the last 24 hours are kept.'; paths = @((Join-Path $sr 'Temp')); minAgeHours = 24; default = $true }
        @{ id = 'wu-cache'; prune = $true; label = 'Windows Update download cache'; desc = 'Already-installed update packages. Windows re-downloads anything it still needs.'; paths = @((Join-Path $sr 'SoftwareDistribution\Download')); minAgeHours = 0; stop = @('wuauserv', 'bits'); default = $true }
        @{ id = 'do-cache'; prune = $true; label = 'Delivery Optimization cache'; desc = 'Update pieces kept for sharing with other PCs.'; paths = @((Join-Path $sr 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache')); minAgeHours = 0; special = 'do'; default = $true }
        @{ id = 'dumps'; prune = $true; label = 'Crash dumps & error reports'; desc = 'Memory dumps from app, game and driver crashes (GPU driver resets can leave GB-sized files).'; paths = @((Join-Path $la 'CrashDumps'), (Join-Path $pd 'Microsoft\Windows\WER\ReportArchive'), (Join-Path $pd 'Microsoft\Windows\WER\ReportQueue'), (Join-Path $sr 'Minidump'), (Join-Path $sr 'LiveKernelReports')); files = @((Join-Path $sr 'MEMORY.DMP')); minAgeHours = 0; default = $true }
        @{ id = 'thumbs'; label = 'Thumbnail cache'; desc = 'Picture previews in File Explorer; rebuilt automatically. Files in use are skipped.'; paths = @((Join-Path $la 'Microsoft\Windows\Explorer')); filter = 'thumbcache_*.db'; minAgeHours = 0; default = $false }
        @{ id = 'logs'; label = 'Old Windows log files'; desc = 'Setup and servicing logs older than 7 days.'; paths = @((Join-Path $sr 'Logs\CBS'), (Join-Path $sr 'Logs\DISM'), (Join-Path $sr 'Panther')); filter = '*.log'; minAgeHours = 168; default = $false }
        @{ id = 'recycle'; label = 'Recycle Bin'; desc = 'Permanently deletes what is in your Recycle Bin.'; special = 'recycle'; default = $false }
        @{ id = 'dism'; label = 'Windows component store cleanup'; desc = 'Runs DISM /StartComponentCleanup to remove superseded Windows files. Safe; can take 5-15 minutes.'; special = 'dism'; default = $false }
    )
}

function Get-ZFolderFiles {
    # Enumerates files below $Path, skipping folders we cannot read.
    param([string]$Path, [string]$Filter = '*', [int]$MinAgeHours = 0)
    $out = New-Object System.Collections.ArrayList
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $out }
    $cut = (Get-Date).AddHours(-$MinAgeHours)
    $stack = New-Object System.Collections.Stack
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try { foreach ($d in [IO.Directory]::GetDirectories($dir)) { $stack.Push($d) } } catch { }
        try {
            foreach ($f in [IO.Directory]::GetFiles($dir, $Filter)) {
                try {
                    $fi = New-Object IO.FileInfo($f)
                    if ($MinAgeHours -le 0 -or $fi.LastWriteTime -lt $cut) { [void]$out.Add($fi) }
                } catch { }
            }
        } catch { }
    }
    return $out
}

function Get-ZRecycleBinFolders {
    $out = @()
    try {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        foreach ($v in @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and [string]$_.DriveType -eq 'Fixed' })) {
            $p = ('{0}:\$Recycle.Bin\{1}' -f $v.DriveLetter, $sid)
            if (Test-Path -LiteralPath $p) { $out += $p }
        }
    } catch { }
    return $out
}

function Get-ZCleanerAnalysis {
    if ($Global:ZCtx.Mock) {
        $sizes = @{ 'user-temp' = 3.4GB; 'win-temp' = 812MB; 'wu-cache' = 6.1GB; 'do-cache' = 2.2GB; 'dumps' = 4.7GB; 'thumbs' = 412MB; 'logs' = 1.1GB; 'recycle' = 9.8GB; 'dism' = -1 }
        $out = @()
        foreach ($t in (Get-ZCleanTargets)) { Set-ZJobStep ('Scanning ' + $t.label); Start-Sleep -Milliseconds 120; $out += @{ id = $t.id; label = $t.label; desc = $t.desc; default = $t.default; bytes = [long]$sizes[$t.id]; files = 1200 } }
        return $out
    }
    $out = @()
    $targets = @(Get-ZCleanTargets)
    $i = 0
    foreach ($t in $targets) {
        $i++
        Set-ZJobStep ('Scanning ' + $t.label) ([int](($i - 1) * 100 / $targets.Count))
        $bytes = [long]0; $count = 0
        if ($t.special -eq 'dism') { $bytes = -1 }
        elseif ($t.special -eq 'recycle') {
            foreach ($p in (Get-ZRecycleBinFolders)) { foreach ($f in (Get-ZFolderFiles $p)) { $bytes += $f.Length; $count++ } }
        } else {
            $filter = '*'
            if ($t.filter) { $filter = $t.filter }
            foreach ($p in @($t.paths)) { foreach ($f in (Get-ZFolderFiles $p $filter $t.minAgeHours)) { $bytes += $f.Length; $count++ } }
            foreach ($fp in @($t.files)) { if ($fp -and (Test-Path -LiteralPath $fp)) { $bytes += (Get-Item -LiteralPath $fp -Force).Length; $count++ } }
        }
        $out += @{ id = $t.id; label = $t.label; desc = $t.desc; default = $t.default; bytes = $bytes; files = $count }
    }
    return $out
}

function Invoke-ZClean {
    param([string[]]$Ids)
    $freed = [long]0
    $done = @()
    $targets = @(Get-ZCleanTargets | Where-Object { @($Ids) -contains $_.id })
    $i = 0
    foreach ($t in $targets) {
        $i++
        Set-ZJobStep ('Cleaning ' + $t.label) ([int](($i - 1) * 100 / [math]::Max($targets.Count, 1)))
        $before = $freed
        if ($Global:ZCtx.Mock) { Start-Sleep -Milliseconds 250; $freed += 1GB; $done += @{ id = $t.id; label = $t.label; bytes = 1GB }; continue }
        try {
            if ($t.special -eq 'dism') {
                Write-ZLog 'Running DISM component cleanup (this can take a while)...'
                & dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1 | Out-Null
                Write-ZLog ('DISM finished with exit code ' + $LASTEXITCODE)
            } elseif ($t.special -eq 'recycle') {
                foreach ($p in (Get-ZRecycleBinFolders)) { foreach ($f in (Get-ZFolderFiles $p)) { $freed += $f.Length } }
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            } else {
                if ($t.special -eq 'do') { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { } }
                foreach ($s in @($t.stop)) { if ($s) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue } }
                $filter = '*'
                if ($t.filter) { $filter = $t.filter }
                foreach ($p in @($t.paths)) {
                    foreach ($f in (Get-ZFolderFiles $p $filter $t.minAgeHours)) {
                        try { $len = $f.Length; [IO.File]::Delete($f.FullName); $freed += $len } catch { }
                    }
                    if ($t.prune -and $p -and (Test-Path -LiteralPath $p)) {
                        foreach ($d in @(Get-ChildItem -LiteralPath $p -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
                            try { if (@(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction Stop).Count -eq 0) { [IO.Directory]::Delete($d.FullName) } } catch { }
                        }
                    }
                }
                foreach ($fp in @($t.files)) { if ($fp -and (Test-Path -LiteralPath $fp)) { try { $len = (Get-Item -LiteralPath $fp -Force).Length; Remove-Item -LiteralPath $fp -Force -ErrorAction Stop; $freed += $len } catch { } } }
                foreach ($s in @($t.stop)) { if ($s) { Start-Service -Name $s -ErrorAction SilentlyContinue } }
            }
        } catch { Write-ZLog ('Cleaning {0} failed: {1}' -f $t.label, $_.Exception.Message) 'warn' }
        $done += @{ id = $t.id; label = $t.label; bytes = ($freed - $before) }
        Write-ZLog ('Cleaned {0}: {1:N1} MB' -f $t.label, (($freed - $before) / 1MB)) 'ok'
    }
    $ledger = Read-ZLedger
    Add-ZHistory $ledger 'clean' ('Freed {0:N2} GB' -f ($freed / 1GB)) $true
    Save-ZLedger $ledger
    return @{ freed = $freed; items = $done }
}

# ---------------------------------------------------------------------------------------------------
# Games library (Steam, Epic Games, Riot)
# ---------------------------------------------------------------------------------------------------

function Get-ZGames {
    if ($Global:ZCtx.Mock) {
        return @(
            @{ id = 'steam-1172470'; name = 'Apex Legends'; platform = 'Steam'; sizeBytes = 75GB; image = 'https://cdn.cloudflare.steamstatic.com/steam/apps/1172470/library_600x900.jpg' }
            @{ id = 'steam-730'; name = 'Counter-Strike 2'; platform = 'Steam'; sizeBytes = 33GB; image = 'https://cdn.cloudflare.steamstatic.com/steam/apps/730/library_600x900.jpg' }
            @{ id = 'steam-252950'; name = 'Rocket League'; platform = 'Steam'; sizeBytes = 25GB; image = 'https://cdn.cloudflare.steamstatic.com/steam/apps/252950/library_600x900.jpg' }
            @{ id = 'epic-fortnite'; name = 'Fortnite'; platform = 'Epic Games'; sizeBytes = 98GB; image = $null }
            @{ id = 'riot-valorant'; name = 'VALORANT'; platform = 'Riot'; sizeBytes = 41GB; image = $null }
            @{ id = 'riot-league_of_legends'; name = 'League of Legends'; platform = 'Riot'; sizeBytes = 22GB; image = $null }
        )
    }
    $games = @()
    # Steam
    try {
        $steam = [string](Get-ZRegValue 'HKCU\Software\Valve\Steam' 'SteamPath').Value
        if ($steam) {
            $steam = $steam.Replace('/', '\')
            $libs = @($steam)
            $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value.Replace('\\', '\') }
            }
            $seen = @{}
            foreach ($lib in ($libs | Select-Object -Unique)) {
                $apps = Join-Path $lib 'steamapps'
                if (-not (Test-Path -LiteralPath $apps)) { continue }
                foreach ($acf in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue)) {
                    $t = [IO.File]::ReadAllText($acf.FullName)
                    $appid = ''; $name = ''; $size = 0
                    if ($t -match '"appid"\s+"(\d+)"') { $appid = $Matches[1] }
                    if ($t -match '"name"\s+"([^"]+)"') { $name = $Matches[1] }
                    if ($t -match '"SizeOnDisk"\s+"(\d+)"') { $size = [long]$Matches[1] }
                    if (-not $appid -or $seen[$appid]) { continue }
                    if ($appid -eq '228980' -or $name -match 'Redistributable|Proton|Steam Linux Runtime|Steamworks|Dedicated Server|SDK$') { continue }
                    $seen[$appid] = $true
                    $games += @{ id = ('steam-' + $appid); name = $name; platform = 'Steam'; sizeBytes = $size; image = ('https://cdn.cloudflare.steamstatic.com/steam/apps/{0}/library_600x900.jpg' -f $appid); launch = ('steam://rungameid/' + $appid) }
                }
            }
        }
    } catch { Write-ZLog ('Steam library scan failed: ' + $_.Exception.Message) 'warn' }
    # Epic Games
    try {
        $man = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
        if (Test-Path -LiteralPath $man) {
            foreach ($f in @(Get-ChildItem -LiteralPath $man -Filter '*.item' -ErrorAction SilentlyContinue)) {
                try {
                    $j = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($f.FullName))
                    if ($j.bIsIncompleteInstall) { continue }
                    if ($j.AppCategories -and -not (@($j.AppCategories) -contains 'games')) { continue }
                    $uri = 'com.epicgames.launcher://apps/{0}%3A{1}%3A{2}?action=launch&silent=true' -f $j.CatalogNamespace, $j.CatalogItemId, $j.AppName
                    $games += @{ id = ('epic-' + $j.AppName); name = [string]$j.DisplayName; platform = 'Epic Games'; sizeBytes = [long]$j.InstallSize; image = $null; launch = $uri }
                } catch { }
            }
        }
    } catch { }
    # Riot Games
    try {
        $meta = Join-Path $env:ProgramData 'Riot Games\Metadata'
        $names = @{ 'league_of_legends' = 'League of Legends'; 'valorant' = 'VALORANT'; 'bacon' = 'Legends of Runeterra' }
        if (Test-Path -LiteralPath $meta) {
            foreach ($d in @(Get-ChildItem -LiteralPath $meta -Directory -ErrorAction SilentlyContinue)) {
                $prod = $d.Name.Split('.')[0]
                if (-not $names.ContainsKey($prod)) { continue }
                $games += @{ id = ('riot-' + $prod); name = $names[$prod]; platform = 'Riot'; sizeBytes = 0; image = $null; product = $prod }
            }
        }
    } catch { }
    return @($games | Sort-Object { $_.name })
}

function Start-ZDeElevated {
    # Opens a URL or shortcut through Explorer so it runs as you (not as administrator).
    param([string]$Target)
    Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"' + $Target + '"')
}

function Start-ZGame {
    param([string]$Id)
    $g = $null
    foreach ($x in (Get-ZGames)) { if ($x.id -eq $Id) { $g = $x } }
    if (-not $g) { throw 'Game not found' }
    if ($Global:ZCtx.Mock) { Write-ZLog ('Launching ' + $g.name + ' (mock)') 'ok'; return }
    if ($g.launch) { Start-ZDeElevated $g.launch; return }
    if ($g.platform -eq 'Riot') {
        $lnk = Get-ChildItem -LiteralPath (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs') -Filter ($g.name + '.lnk') -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lnk) { Start-ZDeElevated $lnk.FullName; return }
        $rc = Join-Path $env:ProgramData 'Riot Games\RiotClientInstalls.json'
        if (Test-Path -LiteralPath $rc) {
            $exe = (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($rc))).rc_default
            $tmp = Join-Path $Global:ZCtx.DataDir ('launch-' + $g.product + '.lnk')
            $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($tmp)
            $sh.TargetPath = $exe
            $sh.Arguments = ('--launch-product={0} --launch-patchline=live' -f $g.product)
            $sh.Save()
            Start-ZDeElevated $tmp
            return
        }
    }
    throw ('Could not find how to launch ' + $g.name)
}

# ---------------------------------------------------------------------------------------------------
# Game Boost (one-shot, nothing persistent)
# ---------------------------------------------------------------------------------------------------

$Global:ZBoostApps = @(
    @{ proc = 'OneDrive'; label = 'OneDrive'; default = $true }
    @{ proc = 'ms-teams'; label = 'Microsoft Teams'; default = $true }
    @{ proc = 'Teams'; label = 'Microsoft Teams (classic)'; default = $true }
    @{ proc = 'Widgets'; label = 'Widgets'; default = $true }
    @{ proc = 'WidgetService'; label = 'Widgets service'; default = $true }
    @{ proc = 'PhoneExperienceHost'; label = 'Phone Link'; default = $true }
    @{ proc = 'Copilot'; label = 'Copilot'; default = $true }
    @{ proc = 'GameBar'; label = 'Xbox Game Bar'; default = $true }
    @{ proc = 'ArmouryCrate'; label = 'Armoury Crate window'; default = $false }
    @{ proc = 'Spotify'; label = 'Spotify'; default = $false }
    @{ proc = 'EpicGamesLauncher'; label = 'Epic Games Launcher'; default = $false }
    @{ proc = 'Discord'; label = 'Discord'; default = $false }
)

function Get-ZBoostCandidates {
    $out = @()
    foreach ($a in $Global:ZBoostApps) {
        $count = 0; $mem = 0
        if ($Global:ZCtx.Mock) {
            if (@('OneDrive', 'ms-teams', 'Widgets', 'PhoneExperienceHost', 'Spotify', 'Discord', 'ArmouryCrate') -contains $a.proc) { $count = 2; $mem = 180MB }
        } else {
            $ps = @(Get-Process -Name $a.proc -ErrorAction SilentlyContinue)
            $count = $ps.Count
            foreach ($p in $ps) { $mem += $p.WorkingSet64 }
        }
        if ($count -gt 0) { $out += @{ proc = $a.proc; label = $a.label; default = $a.default; count = $count; memMB = [math]::Round($mem / 1MB) } }
    }
    return $out
}

function Clear-ZStandbyMemory {
    if ($Global:ZCtx.Mock) { return $true }
    if (-not ('ZenithMemory' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ZenithMemory {
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct TokenPrivileges { public int Count; public long Luid; public int Attr; }
    [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int infoClass, ref int info, int length);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr process, int access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool LookupPrivilegeValue(string host, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivileges state, int len, IntPtr prev, IntPtr retLen);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    public static int PurgeStandbyList() {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) return -1;
        TokenPrivileges tp = new TokenPrivileges();
        tp.Count = 1; tp.Attr = 2;
        if (!LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out tp.Luid)) return -2;
        AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        int command = 4;
        return NtSetSystemInformation(80, ref command, sizeof(int));
    }
}
'@
    }
    return ([ZenithMemory]::PurgeStandbyList() -eq 0)
}

function Invoke-ZGameBoost {
    param([string[]]$Procs)
    $closed = @()
    $allowed = @{}
    foreach ($a in $Global:ZBoostApps) { $allowed[$a.proc] = $a }
    foreach ($p in @($Procs)) {
        if (-not $allowed.ContainsKey($p)) { continue }
        if ($Global:ZCtx.Mock) { $closed += $allowed[$p].label; continue }
        $ps = @(Get-Process -Name $p -ErrorAction SilentlyContinue)
        if ($ps.Count -gt 0) {
            $ps | Stop-Process -Force -ErrorAction SilentlyContinue
            $closed += $allowed[$p].label
        }
    }
    $purged = $false
    try { $purged = Clear-ZStandbyMemory } catch { Write-ZLog ('Standby purge failed: ' + $_.Exception.Message) 'warn' }
    $dns = $false
    if (-not $Global:ZCtx.Mock) { try { Clear-DnsClientCache -ErrorAction Stop; $dns = $true } catch { } } else { $dns = $true }
    $msg = 'Game Boost: closed {0} app(s), standby memory {1}, DNS cache {2}' -f $closed.Count, $(if ($purged) { 'freed' } else { 'unchanged' }), $(if ($dns) { 'flushed' } else { 'unchanged' })
    Write-ZLog $msg 'ok'
    $ledger = Read-ZLedger
    Add-ZHistory $ledger 'boost' $msg $true
    Save-ZLedger $ledger
    return @{ closed = $closed; purged = $purged; dns = $dns; message = $msg }
}

# ---------------------------------------------------------------------------------------------------
# System repair (DISM + SFC)
# ---------------------------------------------------------------------------------------------------

function Invoke-ZSystemRepair {
    if ($Global:ZCtx.Mock) {
        foreach ($s in @('Checking component store...', 'Restoring health...', 'Running System File Checker...')) { Set-ZJobStep $s; Write-ZLog $s; Start-Sleep -Milliseconds 600 }
        return @{ dism = 0; sfc = 0; message = 'No problems found (mock)' }
    }
    Set-ZJobStep 'Step 1/2: DISM is repairing the Windows component store (10-20 minutes)...' 5
    Write-ZLog 'Running DISM /Online /Cleanup-Image /RestoreHealth ...'
    $o = & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1
    $dism = $LASTEXITCODE
    foreach ($l in @($o | Select-Object -Last 3)) { $t = ([string]$l).Replace([char]0, '').Trim(); if ($t) { Write-ZLog $t } }
    Set-ZJobStep 'Step 2/2: System File Checker is verifying Windows files...' 55
    Write-ZLog 'Running sfc /scannow ...'
    $o = & sfc.exe /scannow 2>&1
    $sfc = $LASTEXITCODE
    foreach ($l in @($o | Select-Object -Last 4)) { $t = ([string]$l).Replace([char]0, '').Trim(); if ($t) { Write-ZLog $t } }
    $msg = 'DISM exit code {0}, SFC exit code {1}. Restart your PC to finish any repairs.' -f $dism, $sfc
    $ledger = Read-ZLedger
    Add-ZHistory $ledger 'repair' $msg ($dism -eq 0)
    Save-ZLedger $ledger
    return @{ dism = $dism; sfc = $sfc; message = $msg }
}

# ---------------------------------------------------------------------------------------------------
# Shortcuts & allowlisted "open" targets
# ---------------------------------------------------------------------------------------------------

$Global:ZOpenTargets = @{
    'system-restore' = @{ kind = 'exe'; target = 'rstrui.exe' }
    'display'        = @{ kind = 'uri'; target = 'ms-settings:display-advanced' }
    'graphics'       = @{ kind = 'uri'; target = 'ms-settings:display-advancedgraphics' }
    'gamemode'       = @{ kind = 'uri'; target = 'ms-settings:gaming-gamemode' }
    'storage'        = @{ kind = 'uri'; target = 'ms-settings:storagesense' }
    'startup'        = @{ kind = 'uri'; target = 'ms-settings:startupapps' }
    'windows-update' = @{ kind = 'uri'; target = 'ms-settings:windowsupdate' }
    'nvidia-drivers' = @{ kind = 'uri'; target = 'https://www.nvidia.com/en-us/geforce/drivers/' }
    'amd-chipset'    = @{ kind = 'uri'; target = 'https://www.amd.com/en/support/download/drivers.html' }
    'data-folder'    = @{ kind = 'folder'; target = '' }
}

function Open-ZTarget {
    param([string]$Name)
    $t = $Global:ZOpenTargets[$Name]
    if (-not $t) { throw 'Unknown target' }
    if ($Global:ZCtx.Mock) { Write-ZLog ('Open ' + $Name + ' (mock)'); return }
    switch ($t.kind) {
        'exe'    { Start-Process -FilePath (Join-Path $env:SystemRoot ('System32\' + $t.target)) }
        'uri'    { Start-ZDeElevated $t.target }
        'folder' { Start-ZDeElevated $Global:ZCtx.DataDir }
    }
}

function New-ZDesktopShortcut {
    if ($Global:ZCtx.Mock) { return 'Zenith.lnk (mock)' }
    $desk = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desk 'Zenith.lnk'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script = Join-Path $Global:ZCtx.AppRoot 'Zenith.ps1'
    $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
    $sh.TargetPath = $ps
    $sh.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script)
    $sh.WorkingDirectory = $Global:ZCtx.AppRoot
    $sh.IconLocation = (Join-Path $Global:ZCtx.AppRoot 'ui\zenith.ico') + ',0'
    $sh.Description = 'Zenith - PC optimizer (Claude PC Tweaks)'
    $sh.WindowStyle = 7
    $sh.Save()
    return $lnkPath
}
