# Zenith - local engine server
# Serves the UI and a small JSON API on 127.0.0.1 only. Every API call must carry the random session
# token the launcher generated, so web pages in your browser cannot talk to the engine. The API only
# accepts catalog IDs / allowlisted names - there is no "run this command" endpoint.
# Long operations run in a background runspace ("job") so the UI stays responsive and can show progress.
# Target: Windows PowerShell 5.1. Keep this file ASCII-only.

$Global:ZJobs = @{}

$Global:ZJobBootstrap = @'
param($Body)
$ErrorActionPreference = 'Continue'
$core = Join-Path $ZBoot.AppRoot 'core'
foreach ($f in @('Platform.ps1', 'Engine.ps1', 'Tweaks.ps1', 'Scanner.ps1', 'Tools.ps1')) { . (Join-Path $core $f) }
Initialize-ZContext -AppRoot $ZBoot.AppRoot -DataDir $ZBoot.DataDir -Mock:([bool]$ZBoot.Mock)
try {
    $result = & ([scriptblock]::Create($Body))
    $ZSync.result = $result
    $ZSync.progress = 100
    $ZSync.step = 'Done'
    $ZSync.status = 'done'
} catch {
    $ZSync.error = $_.Exception.Message
    Write-ZLog ('Task failed: ' + $_.Exception.Message) 'error'
    $ZSync.status = 'error'
}
'@

$Global:ZJobBodies = @{
    apply           = @'
$rp = $null
if ($ZJobArgs.restorePoint) {
    $rp = New-ZRestorePoint 'Zenith - before optimizations'
    if (-not $rp.ok) { return @{ restorePointFailed = $true; restorePoint = $rp; applied = 0; failed = 0; results = @() } }
}
$r = Invoke-ZApplyTweaks -Ids @($ZJobArgs.ids)
$r.restorePoint = $rp
return $r
'@
    revert          = 'return Invoke-ZRevertTweaks -Ids @($ZJobArgs.ids)'
    'revert-all'    = 'return Invoke-ZRevertAll'
    'restore-point' = 'return New-ZRestorePoint ''Zenith - manual restore point'''
    'apps-remove'   = @'
$rp = $null
if ($ZJobArgs.restorePoint) {
    $rp = New-ZRestorePoint 'Zenith - before removing apps'
    if (-not $rp.ok) { return @{ restorePointFailed = $true; restorePoint = $rp; applied = 0; failed = 0; results = @() } }
}
$r = Remove-ZBloatApps -Names @($ZJobArgs.names)
$r.restorePoint = $rp
return $r
'@
    'cleaner-scan'  = 'return @{ items = @(Get-ZCleanerAnalysis) }'
    'cleaner-clean' = 'return Invoke-ZClean -Ids @($ZJobArgs.ids)'
    repair          = 'return Invoke-ZSystemRepair'
}

# ---------------------------------------------------------------------------------------------------
# Helpers shared with the launcher
# ---------------------------------------------------------------------------------------------------

function Get-ZFreePort {
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $l.Start()
    $p = $l.LocalEndpoint.Port
    $l.Stop()
    return $p
}

function New-ZToken {
    $b = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($b)
    return (($b | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Invoke-ZEngine {
    # Small HTTP client used by the launcher. Returns $true on HTTP 2xx.
    param([int]$Port, [string]$Token, [string]$Path, [string]$Method = 'GET')
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Proxy = $null
        $wc.Headers.Add('X-Zenith-Token', $Token)
        $url = 'http://127.0.0.1:{0}{1}' -f $Port, $Path
        if ($Method -eq 'POST') { $wc.Headers.Add('Content-Type', 'application/json'); [void]$wc.UploadString($url, '{}') } else { [void]$wc.DownloadString($url) }
        return $true
    } catch { return $false }
}

# ---------------------------------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------------------------------

function Get-ZRunningJob {
    foreach ($id in @($Global:ZJobs.Keys)) { if ($Global:ZJobs[$id].sync.status -eq 'running') { return $id } }
    return $null
}

function Start-ZJob {
    param([string]$Name, [hashtable]$JobArgs = @{})
    if (Get-ZRunningJob) { throw 'Another task is still running - please wait for it to finish.' }
    $body = $Global:ZJobBodies[$Name]
    if (-not $body) { throw "Unknown task $Name" }
    $id = ([guid]::NewGuid().ToString('N')).Substring(0, 12)
    $log = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    $sync = [hashtable]::Synchronized(@{ id = $id; name = $Name; status = 'running'; progress = 0; step = 'Starting...'; log = $log; result = $null; error = $null; started = (Get-Date).ToString('o') })
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    if (-not $Global:ZCtx.Mock) { try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch { } }
    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($iss)
    if (-not $Global:ZCtx.Mock) { try { $rs.ApartmentState = [System.Threading.ApartmentState]::STA } catch { } }
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('ZSync', $sync)
    $rs.SessionStateProxy.SetVariable('ZJobArgs', $JobArgs)
    $rs.SessionStateProxy.SetVariable('ZMock', $Global:ZMock)
    $rs.SessionStateProxy.SetVariable('ZBoot', @{ AppRoot = $Global:ZCtx.AppRoot; DataDir = $Global:ZCtx.DataDir; Mock = $Global:ZCtx.Mock })
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Global:ZJobBootstrap).AddArgument($body)
    $handle = $ps.BeginInvoke()
    $Global:ZJobs[$id] = @{ sync = $sync; ps = $ps; rs = $rs; handle = $handle; name = $Name; finished = $false }
    Write-ZLog ('Started task: ' + $Name)
    return $id
}

function Complete-ZJob {
    # Runs once on the main thread after a job ends: releases the runspace and refreshes engine state.
    param($Job)
    if ($Job.finished) { return }
    $s = $Job.sync
    if ($s.status -eq 'running' -and $Job.handle.IsCompleted) {
        $msg = 'The task stopped unexpectedly.'
        try { if ($Job.ps.Streams.Error.Count -gt 0) { $msg = [string]$Job.ps.Streams.Error[0] } } catch { }
        $s.error = $msg
        $s.status = 'error'
    }
    if ($s.status -eq 'running') { return }
    $Job.finished = $true
    try { [void]$Job.ps.EndInvoke($Job.handle) } catch { }
    try { $Job.ps.Dispose(); $Job.rs.Dispose() } catch { }
    $Global:ZBuildCache = @{}
    Clear-ZCache
    $Global:ZServer.ScanStale = $true
    $r = $s.result
    if ($r -is [hashtable]) {
        if ($r.restorePoint -and $r.restorePoint.ok) { $Global:ZServer.RestorePointDone = $true }
        if ($Job.name -eq 'restore-point' -and $r.ok) { $Global:ZServer.RestorePointDone = $true }
        if ($r.reboot) { $Global:ZServer.RebootPending = $true }
    }
}

function Get-ZJobStatus {
    param([string]$Id)
    $j = $Global:ZJobs[$Id]
    if (-not $j) { return @{ id = $Id; status = 'unknown' } }
    Complete-ZJob $j
    $s = $j.sync
    return @{ id = $Id; name = $s.name; status = $s.status; progress = $s.progress; step = $s.step; log = $s.log.ToArray(); result = $s.result; error = $s.error }
}

# ---------------------------------------------------------------------------------------------------
# HTTP plumbing
# ---------------------------------------------------------------------------------------------------

function Send-ZBytes {
    param($Ctx, [byte[]]$Bytes, [string]$ContentType, [int]$Status = 200)
    $res = $Ctx.Response
    $res.StatusCode = $Status
    $res.ContentType = $ContentType
    $res.AddHeader('X-Content-Type-Options', 'nosniff')
    $res.ContentLength64 = $Bytes.Length
    $res.OutputStream.Write($Bytes, 0, $Bytes.Length)
}

function Send-ZJson {
    param($Ctx, $Data, [int]$Status = 200)
    $json = ConvertTo-ZJson $Data
    $Ctx.Response.AddHeader('Cache-Control', 'no-store')
    Send-ZBytes $Ctx ([Text.Encoding]::UTF8.GetBytes([string]$json)) 'application/json; charset=utf-8' $Status
}

function Send-ZText {
    param($Ctx, [string]$Text, [int]$Status = 200)
    Send-ZBytes $Ctx ([Text.Encoding]::UTF8.GetBytes($Text)) 'text/plain; charset=utf-8' $Status
}

function Read-ZBody {
    param($Ctx)
    $reader = New-Object System.IO.StreamReader($Ctx.Request.InputStream, [Text.Encoding]::UTF8)
    $text = $reader.ReadToEnd()
    $reader.Close()
    if (-not $text -or -not $text.Trim()) { return @{} }
    $h = ConvertTo-ZHashtable (ConvertFrom-Json -InputObject $text)
    if (-not ($h -is [hashtable])) { return @{} }
    return $h
}

$Global:ZMime = @{
    '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'
    '.svg' = 'image/svg+xml'; '.ico' = 'image/x-icon'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.webp' = 'image/webp'
}

function Send-ZStatic {
    param($Ctx, [string]$Path)
    if (-not $Path -or $Path -eq '/') { $Path = '/index.html' }
    $sep = [IO.Path]::DirectorySeparatorChar
    $rel = [Uri]::UnescapeDataString($Path.TrimStart('/')).Replace('/', $sep).Replace('\', $sep)
    $root = [IO.Path]::GetFullPath($Global:ZServer.UiRoot).TrimEnd($sep)
    $full = [IO.Path]::GetFullPath((Join-Path $root $rel))
    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
    if (-not $full.StartsWith($root + $sep) -or -not $Global:ZMime.ContainsKey($ext) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
        Send-ZText $Ctx 'Not found' 404
        return
    }
    $res = $Ctx.Response
    $res.AddHeader('Cache-Control', 'no-cache')
    if ($ext -eq '.html') {
        $res.AddHeader('Content-Security-Policy', "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
        $res.AddHeader('Referrer-Policy', 'no-referrer')
    }
    Send-ZBytes $Ctx ([IO.File]::ReadAllBytes($full)) $Global:ZMime[$ext]
}

# ---------------------------------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------------------------------

function Get-ZStatePayload {
    $ledger = Read-ZLedger
    $states = @(Get-ZTweakStates $ledger)
    $score = Get-ZScore $states
    $settings = Get-ZSettings
    return @{
        version    = $Global:ZCtx.Version
        mock       = $Global:ZCtx.Mock
        admin      = (Test-ZAdmin)
        score      = $score
        tweaks     = $states
        categories = $Global:ZCategories
        presets    = @{
            balanced    = @(Get-ZPresetIds 'balanced')
            performance = @(Get-ZPresetIds 'performance')
            debloat     = @(Get-ZPresetIds 'balanced' 'debloat')
        }
        settings   = $settings
        ledger     = (Get-ZLedgerSummary $ledger)
        session    = @{ restorePointDone = [bool]$Global:ZServer.RestorePointDone; rebootPending = [bool]$Global:ZServer.RebootPending }
        runningJob = (Get-ZRunningJob)
        dataDir    = $Global:ZCtx.DataDir
    }
}

function Start-ZApplyJob {
    param([string]$Name, [hashtable]$JobArgs, [bool]$SkipRestorePoint)
    $settings = Get-ZSettings
    $JobArgs.restorePoint = ([bool]$settings.autoRestorePoint -and -not $Global:ZServer.RestorePointDone -and -not $SkipRestorePoint)
    return Start-ZJob $Name $JobArgs
}

function Invoke-ZApi {
    param($Ctx, [string]$Method, [string]$Path)
    $q = $Ctx.Request.QueryString
    switch ($Method + ' ' + $Path) {
        'GET /api/health' { Send-ZJson $Ctx @{ ok = $true; version = $Global:ZCtx.Version; mock = $Global:ZCtx.Mock } }
        'GET /api/state' { Send-ZJson $Ctx (Get-ZStatePayload) }
        'GET /api/scan' {
            if ($q['refresh'] -eq '1' -or $Global:ZServer.ScanStale -or -not $Global:ZServer.ScanCache) {
                $Global:ZServer.ScanCache = Get-ZScan
                $Global:ZServer.ScanStale = $false
            }
            Send-ZJson $Ctx $Global:ZServer.ScanCache
        }
        'GET /api/live' { Send-ZJson $Ctx (Get-ZLive) }
        'POST /api/apply' {
            $b = Read-ZBody $Ctx
            $ids = @(@($b.ids) | Where-Object { $Global:ZTweakIndex.ContainsKey([string]$_) })
            if ($ids.Count -eq 0) { Send-ZJson $Ctx @{ error = 'Nothing to apply' } 400; return }
            Send-ZJson $Ctx @{ jobId = (Start-ZApplyJob 'apply' @{ ids = $ids } ([bool]$b.skipRestorePoint)) }
        }
        'POST /api/revert' {
            $b = Read-ZBody $Ctx
            Send-ZJson $Ctx @{ jobId = (Start-ZJob 'revert' @{ ids = @(@($b.ids) | ForEach-Object { [string]$_ }) }) }
        }
        'POST /api/revert-all' { Send-ZJson $Ctx @{ jobId = (Start-ZJob 'revert-all' @{}) } }
        'POST /api/restore-point' { Send-ZJson $Ctx @{ jobId = (Start-ZJob 'restore-point' @{}) } }
        'GET /api/restore-points' { Send-ZJson $Ctx @{ items = @(Get-ZRestorePoints) } }
        'GET /api/job' { Send-ZJson $Ctx (Get-ZJobStatus ([string]$q['id'])) }
        'GET /api/startup' { Send-ZJson $Ctx @{ items = @(Get-ZStartupItems) } }
        'POST /api/startup' {
            if (Get-ZRunningJob) { Send-ZJson $Ctx @{ error = 'Please wait for the current task to finish.' } 409; return }
            $b = Read-ZBody $Ctx
            $r = Set-ZStartupItem ([string]$b.id) ([bool]$b.enabled)
            $Global:ZServer.ScanStale = $true
            Send-ZJson $Ctx @{ result = $r; items = @(Get-ZStartupItems) }
        }
        'GET /api/apps' { Send-ZJson $Ctx @{ items = @(Get-ZBloatList) } }
        'POST /api/apps/remove' {
            $b = Read-ZBody $Ctx
            Send-ZJson $Ctx @{ jobId = (Start-ZApplyJob 'apps-remove' @{ names = @(@($b.names) | ForEach-Object { [string]$_ }) } ([bool]$b.skipRestorePoint)) }
        }
        'POST /api/apps/restore' {
            $b = Read-ZBody $Ctx
            Send-ZJson $Ctx @{ jobId = (Start-ZJob 'revert' @{ ids = @(@($b.names) | ForEach-Object { 'appx:' + [string]$_ }) }) }
        }
        'POST /api/cleaner/scan' { Send-ZJson $Ctx @{ jobId = (Start-ZJob 'cleaner-scan' @{}) } }
        'POST /api/cleaner/clean' {
            $b = Read-ZBody $Ctx
            Send-ZJson $Ctx @{ jobId = (Start-ZJob 'cleaner-clean' @{ ids = @(@($b.ids) | ForEach-Object { [string]$_ }) }) }
        }
        'POST /api/repair' { Send-ZJson $Ctx @{ jobId = (Start-ZJob 'repair' @{}) } }
        'GET /api/games' { Send-ZJson $Ctx @{ items = @(Get-ZGames) } }
        'POST /api/games/launch' { $b = Read-ZBody $Ctx; Start-ZGame ([string]$b.id); Send-ZJson $Ctx @{ ok = $true } }
        'GET /api/boost' { Send-ZJson $Ctx @{ items = @(Get-ZBoostCandidates) } }
        'POST /api/boost' { $b = Read-ZBody $Ctx; Send-ZJson $Ctx (Invoke-ZGameBoost @(@($b.procs) | ForEach-Object { [string]$_ })) }
        'POST /api/open' { $b = Read-ZBody $Ctx; Open-ZTarget ([string]$b.target); Send-ZJson $Ctx @{ ok = $true } }
        'POST /api/settings' {
            $b = Read-ZBody $Ctx
            $s = Get-ZSettings
            foreach ($k in @('autoRestorePoint', 'showAdvanced')) { if ($b.ContainsKey($k)) { $s[$k] = [bool]$b[$k] } }
            Save-ZSettings $s
            Send-ZJson $Ctx $s
        }
        'POST /api/shortcut' { Send-ZJson $Ctx @{ path = (New-ZDesktopShortcut) } }
        'POST /api/explorer-restart' {
            if (-not $Global:ZCtx.Mock) { Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force }
            Send-ZJson $Ctx @{ ok = $true }
        }
        'POST /api/reboot' {
            if (-not $Global:ZCtx.Mock) { & shutdown.exe /r /t 10 /c 'Restarting to finish Zenith optimizations' | Out-Null }
            Send-ZJson $Ctx @{ ok = $true }
        }
        'POST /api/shutdown' { $Global:ZServer.Running = $false; Send-ZJson $Ctx @{ ok = $true } }
        'POST /api/bye' { $Global:ZServer.ByeAt = (Get-Date).AddSeconds(8); Send-ZJson $Ctx @{ ok = $true } }
        default { Send-ZJson $Ctx @{ error = 'Not found' } 404 }
    }
}

function Invoke-ZRequest {
    param($Ctx)
    $req = $Ctx.Request
    if (-not $req.IsLocal) { Send-ZText $Ctx 'Forbidden' 403; return }
    $path = $req.Url.AbsolutePath
    if ($path.StartsWith('/api/')) {
        $tok = [string]$req.Headers['X-Zenith-Token']
        # navigator.sendBeacon() cannot set headers, so the goodbye ping alone may carry the token in the URL.
        if (-not $tok -and $path -eq '/api/bye') { $tok = [string]$req.QueryString['t'] }
        if (-not $tok -or $tok -ne $Global:ZServer.Token) { Send-ZJson $Ctx @{ error = 'Invalid session. Close this window and start Zenith again.' } 403; return }
        if ($path -ne '/api/health') {
            $Global:ZServer.LastRequest = Get-Date
            if ($path -ne '/api/bye') { $Global:ZServer.ByeAt = $null }
        }
        try {
            Invoke-ZApi $Ctx $req.HttpMethod $path
        } catch {
            $msg = $_.Exception.Message
            Write-ZLog ('API {0} failed: {1}' -f $path, $msg) 'error'
            try { Send-ZJson $Ctx @{ error = $msg } 500 } catch { }
        }
        return
    }
    if ($req.HttpMethod -ne 'GET') { Send-ZText $Ctx 'Method not allowed' 405; return }
    Send-ZStatic $Ctx $path
}

function Test-ZShouldStop {
    # Never stop in the middle of a task - it always finishes and saves the backup ledger first.
    if (Get-ZRunningJob) { return $false }
    if (-not $Global:ZServer.Running) { return $true }
    $now = Get-Date
    if ($Global:ZServer.ByeAt -and $now -gt $Global:ZServer.ByeAt) { Write-ZLog 'UI window closed - shutting down.'; return $true }
    if (($now - $Global:ZServer.LastRequest).TotalMinutes -gt 20) { Write-ZLog 'No activity for 20 minutes - shutting down.'; return $true }
    if ($Global:ZServer.LauncherPid -gt 0) {
        $alive = $null
        try { $alive = Get-Process -Id $Global:ZServer.LauncherPid -ErrorAction Stop } catch { }
        if (-not $alive) { Write-ZLog 'Launcher exited - shutting down.'; return $true }
    }
    return $false
}

function Start-ZServer {
    param([int]$Port, [string]$Token, [int]$LauncherPid = 0)
    $Global:ZServer = @{
        Token = $Token; Port = $Port; Running = $true; LastRequest = (Get-Date); ByeAt = $null; LauncherPid = $LauncherPid
        RestorePointDone = $false; RebootPending = $false; ScanCache = $null; ScanStale = $true
        UiRoot = (Join-Path $Global:ZCtx.AppRoot 'ui')
    }
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add(('http://127.0.0.1:{0}/' -f $Port))
    $listener.Start()
    Write-ZLog ('Zenith {0} engine started on 127.0.0.1:{1} (mock={2})' -f $Global:ZCtx.Version, $Port, $Global:ZCtx.Mock)
    $lastCheck = Get-Date
    try {
        $pending = $listener.GetContextAsync()
        while ($true) {
            if ($pending.Wait(400)) {
                $ctx = $pending.Result
                $pending = $listener.GetContextAsync()
                try { Invoke-ZRequest $ctx } catch { Write-ZLog ('Request failed: ' + $_.Exception.Message) 'error' }
                finally { try { $ctx.Response.Close() } catch { } }
            }
            if (((Get-Date) - $lastCheck).TotalSeconds -ge 2) {
                $lastCheck = Get-Date
                foreach ($j in @($Global:ZJobs.Values)) { Complete-ZJob $j }
                if (Test-ZShouldStop) { break }
            }
        }
    } finally {
        try { $listener.Stop(); $listener.Close() } catch { }
        Write-ZLog 'Zenith engine stopped.'
    }
}
