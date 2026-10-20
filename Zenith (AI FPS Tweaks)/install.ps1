# Zenith (AI FPS Tweaks) - installer
#
# Run it by double-clicking "Install Zenith.bat" in the extracted Zenith folder.
# It copies Zenith to Documents\Zenith (AI FPS Tweaks), can create desktop and Start menu
# shortcuts, and can start Zenith. It needs no administrator rights - Zenith itself asks for
# them when it starts. Nothing else on your PC is changed.
#
# Test hooks: ZENITH_INSTALL_DIR (target folder), ZENITH_UNATTENDED=1 (accept every default).
# Target: Windows PowerShell 5.1. Keep this file ASCII-only.

& {
    $ErrorActionPreference = 'Stop'

    $version = '1.0.0'
    $folderName = 'Zenith (AI FPS Tweaks)'
    $src = $PSScriptRoot
    if (-not $src) { $src = $env:ZENITH_SOURCE }
    $unattended = [bool]$env:ZENITH_UNATTENDED
    $onWindows = ($env:OS -eq 'Windows_NT')

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
        $lnk.Description = 'Zenith - PC optimizer (AI FPS Tweaks)'
        $lnk.WindowStyle = 7
        $lnk.Save()
    }

    Write-Host ''
    Write-Host '  ZENITH  -  AI FPS Tweaks installer' -ForegroundColor Yellow
    Write-Host ('  version {0}  |  peak performance for your rig' -f $version) -ForegroundColor DarkGray
    Write-Host '  ---------------------------------------------' -ForegroundColor DarkGray

    try {
        if (-not $src -or -not (Test-Path -LiteralPath (Join-Path $src 'app\Zenith.ps1'))) {
            throw 'Run this from the extracted Zenith folder (double-click "Install Zenith.bat"). Extract the ZIP first if Windows opened it directly.'
        }
        if ($onWindows -and -not [Environment]::Is64BitOperatingSystem) {
            Say 'Zenith needs 64-bit Windows 10 or 11. Nothing was installed.' 'Red'
            return
        }

        # 1. Where to install (Documents, which may live in OneDrive)
        $default = $env:ZENITH_INSTALL_DIR
        if (-not $default) { $default = Join-Path ([Environment]::GetFolderPath('MyDocuments')) $folderName }
        $dir = $default
        if (-not $unattended) {
            Say ('Install folder: {0}' -f $default)
            $answer = (Read-Host '  Press Enter to use it, or type another folder').Trim().Trim('"')
            if ($answer) { $dir = $answer }
        }
        $dir = [IO.Path]::GetFullPath($dir)
        $srcFull = [IO.Path]::GetFullPath($src).TrimEnd('\', '/')
        $sameFolder = ($srcFull -eq $dir.TrimEnd('\', '/'))

        if (-not $sameFolder -and (Test-Path -LiteralPath (Join-Path $dir 'app\Zenith.ps1'))) {
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

        # 2. Copy
        if ($sameFolder) {
            Say 'Zenith is already in this folder - nothing to copy.' 'DarkGray'
        } else {
            Say 'Installing...'
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            foreach ($name in @('app', 'Launch Zenith.bat', 'Emergency Restore.bat', 'Install Zenith.bat', 'install.ps1', 'README.md')) {
                $item = Join-Path $src $name
                if (Test-Path -LiteralPath $item) { Copy-Item -LiteralPath $item -Destination $dir -Recurse -Force }
            }
        }
        if ($onWindows) { Get-ChildItem -LiteralPath $dir -Recurse -File | Unblock-File }
        Say ('Installed to {0}' -f $dir) 'Green'

        # 3. Shortcuts
        if (Ask 'Create desktop and Start menu shortcuts?' $true) {
            if ($onWindows) {
                New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Zenith.lnk') $dir
                New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) 'Zenith.lnk') $dir
                Say 'Shortcuts created: Desktop and Start menu ("Zenith").' 'Green'
            } else {
                Say 'Skipped: shortcuts can only be created on Windows.' 'DarkGray'
            }
        }

        # 4. Start
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
        if (-not $sameFolder) { Say 'You can delete the downloaded ZIP and the folder you extracted it to.' }
        Say 'Uninstall:         click "Restore Original" in Zenith, then delete the Zenith folder,'
        Say '                   C:\ProgramData\Zenith and %LOCALAPPDATA%\Zenith.'
    } catch {
        Write-Host ''
        Say ('Installation failed: ' + $_.Exception.Message) 'Red'
    }
    if (-not $unattended -and $onWindows) {
        Write-Host ''
        [void](Read-Host '  Press Enter to close')
    }
}
