<#
    Zenith - PC optimizer (AI FPS Tweaks)

    Start it by double-clicking "Launch Zenith.bat" in the folder above this one.

      (no switches)  Launcher: asks for administrator permission, starts the engine, opens the app window.
      -Serve         Engine only (started by the launcher, elevated).
      -RevertAll     Console "Restore Original State" - undoes every change Zenith made (Emergency Restore.bat).
      -Mock          Development mode: simulated PC, no real system changes.

    Target: Windows PowerShell 5.1 (built into Windows 10/11). Keep this file ASCII-only.
#>
[CmdletBinding()]
param(
    [switch]$Serve,
    [int]$Port = 0,
    [string]$Token = '',
    [int]$LauncherPid = 0,
    [switch]$RevertAll,
    [switch]$Mock,
    [string]$DataDir = '',
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Continue'
$AppRoot = $PSScriptRoot
$CoreDir = Join-Path $AppRoot 'core'

# Always run as 64-bit PowerShell so registry and system folders are not redirected.
if (-not $Mock -and [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $forward = @()
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $forward += ('-' + $k) } }
        else { $forward += ('-' + $k); $forward += [string]$v }
    }
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @forward
    exit $LASTEXITCODE
}

foreach ($f in @('Platform.ps1', 'Engine.ps1', 'Tweaks.ps1', 'Scanner.ps1', 'Tools.ps1', 'Server.ps1')) { . (Join-Path $CoreDir $f) }

function Show-ZMessage {
    param([string]$Text, [string]$Icon = 'Information')
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [void][System.Windows.MessageBox]::Show($Text, 'Zenith', 'OK', $Icon)
    } catch { Write-Host $Text }
}

function Find-ZBrowser {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    return $null
}

function Open-ZAppWindow {
    # Opens the UI as a chromeless app window (Edge/Chrome "--app" mode) with its own profile.
    param([string]$Url)
    $exe = Find-ZBrowser
    if (-not $exe) { Start-Process $Url; return $null }
    $uiProfile = Join-Path $env:LOCALAPPDATA 'Zenith\ui-profile'
    $w = 1440; $h = 920
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $area = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $w = [math]::Max(1000, [math]::Min($w, $area.Width - 60))
        $h = [math]::Max(680, [math]::Min($h, $area.Height - 40))
    } catch { }
    $argLine = @(
        ('--app=' + $Url),
        ('--user-data-dir="' + $uiProfile + '"'),
        ('--window-size={0},{1}' -f $w, $h),
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-extensions',
        '--disable-features=Translate,msEdgeSidebarV2,msHubApps'
    ) -join ' '
    return (Start-Process -FilePath $exe -ArgumentList $argLine -PassThru)
}

function Start-ZLauncher {
    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Local\ZenithClaudePCTweaks', [ref]$createdNew)
    if (-not $createdNew) { Show-ZMessage 'Zenith is already open - look for its window on the taskbar.'; return }
    try {
        $port = Get-ZFreePort
        $token = New-ZToken
        $psExe = Join-Path $PSHOME 'powershell.exe'
        $argLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Serve -Port {1} -Token {2} -LauncherPid {3}' -f $PSCommandPath, $port, $token, $PID
        $engine = $null
        try {
            if (Test-ZAdmin) { $engine = Start-Process -FilePath $psExe -ArgumentList $argLine -WindowStyle Hidden -PassThru }
            else { $engine = Start-Process -FilePath $psExe -ArgumentList $argLine -Verb RunAs -WindowStyle Hidden -PassThru }
        } catch {
            Show-ZMessage ("Zenith needs administrator permission to change Windows settings.`n`nStart it again and choose Yes when Windows asks.") 'Warning'
            return
        }
        $ready = $false
        for ($i = 0; $i -lt 160; $i++) {
            if (Invoke-ZEngine $port $token '/api/health') { $ready = $true; break }
            try { if ($engine -and $engine.HasExited) { break } } catch { }
            Start-Sleep -Milliseconds 250
        }
        if (-not $ready) {
            Show-ZMessage ("Zenith's engine did not start.`n`nDetails are in:`n" + (Join-Path $env:ProgramData 'Zenith\logs\zenith.log')) 'Error'
            return
        }
        $url = 'http://127.0.0.1:{0}/?t={1}' -f $port, $token
        $window = Open-ZAppWindow $url
        $watch = [Diagnostics.Stopwatch]::StartNew()
        if ($window) { $window.WaitForExit() }
        if (-not $window -or $watch.Elapsed.TotalSeconds -lt 6) {
            # The window was handed to an already-running browser; the engine shuts itself down when the page closes.
            while (Invoke-ZEngine $port $token '/api/health') { Start-Sleep -Seconds 3 }
            return
        }
        [void](Invoke-ZEngine $port $token '/api/shutdown' 'POST')
    } finally {
        try { $mutex.ReleaseMutex() } catch { }
        $mutex.Dispose()
    }
}

function Invoke-ZConsoleRevert {
    $Global:ZConsole = $true
    try { $host.UI.RawUI.WindowTitle = 'Zenith - Emergency Restore' } catch { }
    Write-Host ''
    Write-Host '  ZENITH  -  Restore Original State' -ForegroundColor Yellow
    Write-Host '  ---------------------------------' -ForegroundColor DarkGray
    $ledger = Read-ZLedger
    $items = @((Get-ZLedgerSummary $ledger).items)
    if (@($items).Count -eq 0) {
        Write-Host '  Nothing to restore: Zenith has not changed anything on this PC.' -ForegroundColor Green
    } else {
        Write-Host ('  Zenith has {0} change(s) recorded in {1}:' -f @($items).Count, $Global:ZCtx.LedgerPath)
        foreach ($i in $items) { Write-Host ('   - ' + $i.name) -ForegroundColor Gray }
        Write-Host ''
        $answer = Read-Host '  Type YES to put all of them back to how they were'
        if ($answer -eq 'YES') {
            Write-Host ''
            $r = Invoke-ZRevertAll
            Write-Host ''
            if ($r.failed -eq 0) { Write-Host ('  Done. {0} change(s) restored. Restart your PC to finish.' -f $r.restored) -ForegroundColor Green }
            else { Write-Host ('  {0} restored, {1} could not be fully restored (see above). Use Windows System Restore for those.' -f $r.restored, $r.failed) -ForegroundColor Yellow }
        } else { Write-Host '  Cancelled - nothing was changed.' }
    }
    Write-Host ''
    Write-Host '  You can also roll the whole PC back with Windows System Restore'
    Write-Host '  (pick the restore point named "Zenith - before optimizations").'
    $o = Read-Host '  Open Windows System Restore now? (y/N)'
    if ($o -match '^[yY]' -and -not $Global:ZCtx.Mock) { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\rstrui.exe') }
    [void](Read-Host '  Press Enter to close')
}

if ($RevertAll) {
    if (-not $Mock -and -not (Test-ZAdmin)) {
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -RevertAll' -f $PSCommandPath)
        exit
    }
    Initialize-ZContext -AppRoot $AppRoot -DataDir $DataDir -Mock:$Mock
    Invoke-ZConsoleRevert
    exit
}

if ($Serve) {
    Initialize-ZContext -AppRoot $AppRoot -DataDir $DataDir -Mock:$Mock
    if (-not (Test-ZAdmin)) { Write-ZLog 'The engine must run as administrator.' 'error'; exit 1 }
    if ($Port -eq 0) { $Port = Get-ZFreePort }
    if (-not $Token) { $Token = New-ZToken }
    if ($NoBrowser) { Write-Host ('Zenith engine: http://127.0.0.1:{0}/?t={1}' -f $Port, $Token) }
    try { Start-ZServer -Port $Port -Token $Token -LauncherPid $LauncherPid }
    catch { Write-ZLog ('Engine crashed: ' + $_.Exception.Message) 'error'; exit 1 }
    exit 0
}

Start-ZLauncher
