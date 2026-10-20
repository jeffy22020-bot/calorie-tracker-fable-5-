# Zenith (Claude PC Tweaks) - one-line installer
#
# Paste this into PowerShell on your PC:
#   irm https://raw.githubusercontent.com/jeffy22020-bot/calorie-tracker-fable-5-/HEAD/install.ps1 | iex
# or press Win+R and run:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/jeffy22020-bot/calorie-tracker-fable-5-/HEAD/install.ps1 | iex"
#
# It downloads Zenith, checks the download, copies it to a folder in your user profile, can create
# desktop and Start menu shortcuts, and can start Zenith. It needs no administrator rights - Zenith
# itself asks for them when it starts. Nothing else on your PC is changed.
#
# Test hooks: ZENITH_INSTALL_DIR (folder), ZENITH_UNATTENDED=1 (accept every default),
#             ZENITH_ZIP_URL (another zip URL or a local zip path; skips the checksum).
# Target: Windows PowerShell 5.1. Keep this file ASCII-only.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $version = '1.0.0'
    $zipUrl = 'https://raw.githubusercontent.com/jeffy22020-bot/calorie-tracker-fable-5-/56cc2ee25ff01b12473b9361183e357a53c62003/Zenith%20(Claude%20PC%20Tweaks)/Zenith-v1.0.zip'
    $zipSha256 = '4e0f1a9cefbb92e30481e6346262290ed98fdbc3497bfbc5de4225a917bca1ea'
    $pageUrl = 'https://github.com/jeffy22020-bot/calorie-tracker-fable-5-/tree/HEAD/Zenith%20(Claude%20PC%20Tweaks)'
    $folderName = 'Zenith (Claude PC Tweaks)'

    $unattended = [bool]$env:ZENITH_UNATTENDED
    $onWindows = ($env:OS -eq 'Windows_NT')
    $checkHash = $true
    if ($env:ZENITH_ZIP_URL) { $zipUrl = $env:ZENITH_ZIP_URL; $checkHash = $false }

    function Say {
        param([string]$Text, [string]$Color = 'Gray')
        Write-Host ('  ' + $Text) -ForegroundColor $Color
    }

    function Ask {
        param([string]$Question, [bool]$Default = $true)
        $hint = '[y/N]'
        if ($Default) { $hint = '[Y/n]' }
        if ($unattended) { Say ('{0} {1} {2}' -f $Question, $hint, $(if ($Default) { 'Y' } else { 'N' })); return $Default }
        while ($true) {
            $a = (Read-Host ('  {0} {1}' -f $Question, $hint)).Trim()
            if (-not $a) { return $Default }
            if ($a -match '^(y|yes)$') { return $true }
            if ($a -match '^(n|no)$') { return $false }
            Say 'Please type Y or N.' 'Yellow'
        }
    }

    function New-Shortcut {
        param([string]$Path, [string]$AppDir)
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
        $lnk.TargetPath = $ps
        $lnk.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $AppDir 'app\Zenith.ps1'))
        $lnk.WorkingDirectory = (Join-Path $AppDir 'app')
        $lnk.IconLocation = (Join-Path $AppDir 'app\ui\zenith.ico') + ',0'
        $lnk.Description = 'Zenith - PC optimizer (Claude PC Tweaks)'
        $lnk.WindowStyle = 7
        $lnk.Save()
    }

    Write-Host ''
    Write-Host '  ZENITH  -  PC Tweaks installer' -ForegroundColor Yellow
    Write-Host ('  version {0}  |  peak performance for your rig' -f $version) -ForegroundColor DarkGray
    Write-Host '  ---------------------------------------------' -ForegroundColor DarkGray

    if ($onWindows -and -not [Environment]::Is64BitOperatingSystem) {
        Say 'Zenith needs 64-bit Windows 10 or 11. Nothing was installed.' 'Red'
        return
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('zenith-install-' + [guid]::NewGuid().ToString('N'))
    try {
        # 1. Where to install
        $default = $env:ZENITH_INSTALL_DIR
        if (-not $default) { $default = Join-Path $env:USERPROFILE $folderName }
        $dir = $default
        if (-not $unattended) {
            Say ('Install folder: {0}' -f $default)
            $answer = (Read-Host '  Press Enter to use it, or type another folder').Trim().Trim('"')
            if ($answer) { $dir = $answer }
        }
        $dir = [IO.Path]::GetFullPath($dir)
        $existing = Test-Path -LiteralPath (Join-Path $dir 'app\Zenith.ps1')
        if ($existing) {
            Say 'Zenith is already installed there.' 'Cyan'
            Say 'Updating keeps your backup, settings and restore history (they are stored in C:\ProgramData\Zenith).' 'DarkGray'
            if (-not (Ask 'Update it to this version?' $true)) { Say 'Nothing was changed.'; return }
            if ($onWindows) {
                $running = $null
                try { $running = [System.Threading.Mutex]::OpenExisting('Local\ZenithClaudePCTweaks') } catch { }
                if ($running) {
                    $running.Dispose()
                    Say 'Zenith is open right now. Close its window first.' 'Yellow'
                    if (-not $unattended) { [void](Read-Host '  Press Enter when Zenith is closed') }
                }
            }
        }

        # 2. Download and check
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $zip = Join-Path $tmp 'Zenith.zip'
        Say 'Downloading Zenith...'
        if (Test-Path -LiteralPath $zipUrl) {
            Copy-Item -LiteralPath $zipUrl -Destination $zip
        } else {
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
            Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
        }
        $size = (Get-Item -LiteralPath $zip).Length
        if ($checkHash) {
            $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne $zipSha256) {
                Say 'The download is incomplete or has been changed (checksum does not match). Nothing was installed.' 'Red'
                Say ('Try again, or download the ZIP yourself from: {0}' -f $pageUrl) 'Yellow'
                return
            }
            Say ('Downloaded {0:N0} KB - checksum verified.' -f ($size / 1KB)) 'Green'
        } else {
            Say ('Downloaded {0:N0} KB (custom source, checksum skipped).' -f ($size / 1KB)) 'Yellow'
        }

        # 3. Extract and copy
        Say 'Installing...'
        $unpacked = Join-Path $tmp 'unpacked'
        Expand-Archive -LiteralPath $zip -DestinationPath $unpacked -Force
        $src = Join-Path $unpacked $folderName
        if (-not (Test-Path -LiteralPath (Join-Path $src 'app\Zenith.ps1'))) { throw 'The downloaded package does not contain Zenith.' }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        foreach ($item in @(Get-ChildItem -LiteralPath $src -Force)) {
            Copy-Item -LiteralPath $item.FullName -Destination $dir -Recurse -Force
        }
        if ($onWindows) { Get-ChildItem -LiteralPath $dir -Recurse -File | Unblock-File }
        Say ('Installed to {0}' -f $dir) 'Green'

        # 4. Shortcuts
        if (Ask 'Create desktop and Start menu shortcuts?' $true) {
            if ($onWindows) {
                New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Zenith.lnk') $dir
                New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'Zenith.lnk') $dir
                Say 'Shortcuts created: Desktop and Start menu ("Zenith").' 'Green'
            } else {
                Say 'Skipped: shortcuts can only be created on Windows.' 'DarkGray'
            }
        }

        # 5. Start
        Write-Host ''
        Say 'Before Zenith changes anything it creates a Windows restore point, and every change'
        Say 'can be undone with the "Restore Original" button or Emergency Restore.bat.'
        if (Ask 'Start Zenith now?' $true) {
            if ($onWindows) {
                Start-Process -FilePath (Join-Path $dir 'Launch Zenith.bat') -WorkingDirectory $dir
                Say 'Starting Zenith - choose Yes when Windows asks for permission.' 'Green'
            } else {
                Say 'Skipped: Zenith runs on Windows.' 'DarkGray'
            }
        }

        Write-Host ''
        Say 'Done!' 'Green'
        Say ('Zenith folder:     {0}' -f $dir)
        Say ('Emergency undo:    {0}' -f (Join-Path $dir 'Emergency Restore.bat'))
        Say 'Uninstall:         click "Restore Original" in Zenith, then delete the Zenith folder,'
        Say '                   C:\ProgramData\Zenith and %LOCALAPPDATA%\Zenith.'
    } catch {
        Write-Host ''
        Say ('Installation failed: ' + $_.Exception.Message) 'Red'
        Say ('You can download Zenith manually from: {0}' -f $pageUrl) 'Yellow'
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if (-not $unattended -and $onWindows) {
        Write-Host ''
        [void](Read-Host '  Press Enter to close')
    }
}
