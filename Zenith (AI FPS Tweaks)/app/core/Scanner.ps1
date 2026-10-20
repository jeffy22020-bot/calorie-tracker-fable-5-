# Zenith - PC scanner
# Reads hardware and Windows details, runs health checks with recommendations, and samples live usage.
# Target: Windows PowerShell 5.1. Keep this file ASCII-only.

function Get-ZRatedRamSpeed {
    # Best-effort decode of a module's rated (XMP/D.O.C.P.) speed from its part number.
    param([string]$Part)
    if (-not $Part) { return $null }
    $p = $Part.Trim().ToUpperInvariant()
    if ($p -match '(?<![0-9])(2133|2400|2666|2933|3000|3200|3333|3466|3600|3733|3800|3866|4000|4133|4266|4400|4600|4800|5200|5600|6000|6400)(?![0-9])') { return [int]$Matches[1] }
    if ($p -match '^(KF|HX)4(\d{2})C') { return [int]$Matches[2] * 100 }
    if ($p -match '^KVR(\d{2})') { return [int]$Matches[1] * 100 }
    if ($p -match '^BL\d+G(\d{2})C') { return [int]$Matches[1] * 100 }
    if ($p -match '-(\d)G(\d)') {
        $map = @{ '21' = 2133; '23' = 2400; '24' = 2400; '26' = 2666; '29' = 2933; '32' = 3200 }
        $k = $Matches[1] + $Matches[2]
        if ($map.ContainsKey($k)) { return $map[$k] }
    }
    if ($p -match '^HMA\w+-(TF|UH|VK|WM|XN)') {
        $map = @{ TF = 2133; UH = 2400; VK = 2666; WM = 2933; XN = 3200 }
        return $map[$Matches[1]]
    }
    if ($p -match '^M37\w+-(CPB|CRC|CTD|CVF|CWE)') {
        $map = @{ CPB = 2133; CRC = 2400; CTD = 2666; CVF = 2933; CWE = 3200 }
        return $map[$Matches[1]]
    }
    return $null
}

function Get-ZNvidiaSmi {
    $paths = @((Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'), (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'))
    foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
    return $null
}

function Initialize-ZDisplayNative {
    if ('ZenithDisplay' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ZenithDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
        public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
        public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent;
        public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2;
        public int dmPanningWidth; public int dmPanningHeight;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettings(string name, int mode, ref DEVMODE dm);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplayDevices(string device, uint index, ref DISPLAY_DEVICE dd, uint flags);

    public static List<string> Describe() {
        var result = new List<string>();
        for (uint i = 0; i < 16; i++) {
            var dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(dd);
            if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
            if ((dd.StateFlags & 1) == 0) continue;
            var cur = new DEVMODE();
            cur.dmSize = (short)Marshal.SizeOf(cur);
            if (!EnumDisplaySettings(dd.DeviceName, -1, ref cur)) continue;
            int maxAtRes = cur.dmDisplayFrequency, maxAny = cur.dmDisplayFrequency;
            int maxW = cur.dmPelsWidth, maxH = cur.dmPelsHeight;
            var m = new DEVMODE();
            m.dmSize = (short)Marshal.SizeOf(m);
            for (int j = 0; EnumDisplaySettings(dd.DeviceName, j, ref m); j++) {
                if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight && m.dmDisplayFrequency > maxAtRes) maxAtRes = m.dmDisplayFrequency;
                if (m.dmDisplayFrequency > maxAny) maxAny = m.dmDisplayFrequency;
                if ((long)m.dmPelsWidth * m.dmPelsHeight > (long)maxW * maxH) { maxW = m.dmPelsWidth; maxH = m.dmPelsHeight; }
            }
            var mon = new DISPLAY_DEVICE();
            mon.cb = Marshal.SizeOf(mon);
            string monName = "", monId = "";
            if (EnumDisplayDevices(dd.DeviceName, 0, ref mon, 0)) { monName = mon.DeviceString; monId = mon.DeviceID; }
            bool primary = (dd.StateFlags & 4) != 0;
            result.Add(string.Join("|", new string[] {
                dd.DeviceName, dd.DeviceString, monName, monId,
                cur.dmPelsWidth.ToString(), cur.dmPelsHeight.ToString(), cur.dmDisplayFrequency.ToString(),
                maxAtRes.ToString(), maxAny.ToString(), maxW.ToString(), maxH.ToString(), primary ? "1" : "0" }));
        }
        return result;
    }
}
'@
}

function Get-ZDisplays {
    $out = @()
    try {
        Initialize-ZDisplayNative
        $friendly = @{}
        try {
            foreach ($m in @(Get-CimInstance -Namespace 'root\wmi' -ClassName WmiMonitorID -ErrorAction Stop)) {
                $code = ([string]$m.InstanceName).Split('\')
                $name = -join (@($m.UserFriendlyName) | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })
                if ($code.Count -gt 1 -and $name) { $friendly[$code[1].ToUpperInvariant()] = $name.Trim() }
            }
        } catch { }
        foreach ($line in [ZenithDisplay]::Describe()) {
            $f = $line.Split('|')
            $name = $f[2]
            $idParts = $f[3].Split('\')
            if ($idParts.Count -gt 1 -and $friendly.ContainsKey($idParts[1].ToUpperInvariant())) { $name = $friendly[$idParts[1].ToUpperInvariant()] }
            if (-not $name) { $name = 'Display' }
            $out += @{
                device = $f[0]; adapter = $f[1]; name = $name
                width = [int]$f[4]; height = [int]$f[5]; hz = [int]$f[6]; maxHzAtRes = [int]$f[7]; maxHz = [int]$f[8]
                maxWidth = [int]$f[9]; maxHeight = [int]$f[10]; primary = ($f[11] -eq '1')
            }
        }
    } catch { Write-ZLog ('Display scan failed: ' + $_.Exception.Message) 'warn' }
    return $out
}

function Get-ZGpuInfo {
    $vram = @{}
    $classKey = 'HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($sk in @(Get-ZRegSubKeyNames $classKey)) {
        if ($sk -notmatch '^\d{4}$') { continue }
        $p = $classKey + '\' + $sk
        $desc = [string](Get-ZRegValue $p 'DriverDesc').Value
        if (-not $desc) { continue }
        $mem = $null
        $q = Get-ZRegValue $p 'HardwareInformation.qwMemorySize'
        if ($q.Exists) { $mem = [long]$q.Value }
        else {
            $dm = Get-ZRegValue $p 'HardwareInformation.MemorySize'
            if ($dm.Exists) {
                if ($dm.Kind -eq 'Binary') { $b = [Convert]::FromBase64String([string]$dm.Value); if ($b.Length -ge 4) { $mem = [long][BitConverter]::ToUInt32($b, 0) } }
                else { $mem = ConvertTo-ZUInt32 $dm.Value }
            }
        }
        if ($mem) { $vram[$desc] = $mem }
    }
    $smi = Get-ZNvidiaSmi
    $bar1 = $null
    if ($smi) {
        try {
            $o = (& $smi -q -d MEMORY 2>$null) -join "`n"
            if ($o -match 'BAR1 Memory Usage\s+Total\s*:\s*(\d+)\s*MiB') { $bar1 = [int]$Matches[1] }
        } catch { }
    }
    $out = @()
    foreach ($vc in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
        if (-not ([string]$vc.PNPDeviceID).StartsWith('PCI\')) { continue }
        $vendor = 'Other'
        if ($vc.PNPDeviceID -like 'PCI\VEN_10DE*') { $vendor = 'NVIDIA' } elseif ($vc.PNPDeviceID -like 'PCI\VEN_1002*') { $vendor = 'AMD' } elseif ($vc.PNPDeviceID -like 'PCI\VEN_8086*') { $vendor = 'Intel' }
        $bytes = $vram[[string]$vc.Name]
        if (-not $bytes) { $bytes = [long]$vc.AdapterRAM }
        $nv = $null
        if ($vendor -eq 'NVIDIA' -and $vc.DriverVersion) {
            $digits = ([string]$vc.DriverVersion).Replace('.', '')
            if ($digits.Length -ge 5) { $last = $digits.Substring($digits.Length - 5); $nv = $last.Substring(0, 3) + '.' + $last.Substring(3) }
        }
        $date = $null; $age = $null
        if ($vc.DriverDate) { $date = ([datetime]$vc.DriverDate).ToString('yyyy-MM-dd'); $age = [int]((Get-Date) - [datetime]$vc.DriverDate).TotalDays }
        $rebar = $null
        if ($vendor -eq 'NVIDIA' -and $bar1) { $rebar = ($bar1 -gt 256) }
        $out += @{
            name = [string]$vc.Name; vendor = $vendor; vramBytes = [long]$bytes; driverVersion = [string]$vc.DriverVersion; nvidiaVersion = $nv
            driverDate = $date; driverAgeDays = $age; pnp = [string]$vc.PNPDeviceID; bar1MB = $bar1; rebar = $rebar
        }
    }
    return @($out | Sort-Object { if ($_.vendor -eq 'NVIDIA' -or $_.vendor -eq 'AMD') { 0 } else { 1 } })
}

function Get-ZScan {
    if ($Global:ZCtx.Mock) { return Get-ZMockScan }
    $scan = @{ scannedAt = (Get-Date).ToString('o') }

    $cs = Get-CimInstance Win32_ComputerSystem
    $osi = Get-CimInstance Win32_OperatingSystem
    $cpu = @(Get-CimInstance Win32_Processor)[0]
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $cv = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $scan.device = @{
        name = [string]$cs.Name; manufacturer = [string]$cs.Manufacturer; model = [string]$cs.Model
        board = ('{0} {1}' -f $board.Manufacturer, $board.Product).Trim()
        bios = [string]$bios.SMBIOSBIOSVersion
        biosDate = $(if ($bios.ReleaseDate) { ([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd') } else { $null })
        deviceId = [string](Get-ZRegValue 'HKLM\SOFTWARE\Microsoft\SQMClient' 'MachineId').Value
    }
    $scan.cpu = @{
        name = ([string]$cpu.Name).Trim(); vendor = [string]$cpu.Manufacturer
        cores = [int]$cpu.NumberOfCores; threads = [int]$cpu.NumberOfLogicalProcessors; baseMHz = [int]$cpu.MaxClockSpeed
    }

    $mods = @()
    foreach ($m in @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)) {
        $type = 'DDR'
        if ([int]$m.SMBIOSMemoryType -eq 26) { $type = 'DDR4' } elseif ([int]$m.SMBIOSMemoryType -eq 34) { $type = 'DDR5' } elseif ([int]$m.SMBIOSMemoryType -eq 24) { $type = 'DDR3' }
        $part = ([string]$m.PartNumber).Trim()
        $mods += @{
            slot = [string]$m.DeviceLocator; sizeGB = [math]::Round([long]$m.Capacity / 1GB); speed = [int]$m.Speed; configured = [int]$m.ConfiguredClockSpeed
            maker = ([string]$m.Manufacturer).Trim(); part = $part; type = $type; rated = (Get-ZRatedRamSpeed $part)
        }
    }
    $configured = 0; $rated = $null; $mtype = 'DDR4'
    foreach ($m in $mods) {
        if ($m.configured -gt $configured) { $configured = $m.configured }
        if ($m.rated -and (-not $rated -or $m.rated -gt $rated)) { $rated = $m.rated }
        $mtype = $m.type
    }
    $installed = 0
    foreach ($m in $mods) { $installed += $m.sizeGB }
    $scan.memory = @{
        totalGB = $installed; usableGB = [math]::Round([long]$cs.TotalPhysicalMemory / 1GB, 1); speed = $configured; rated = $rated
        type = $mtype; modules = $mods; count = $mods.Count
    }

    $scan.gpus = @(Get-ZGpuInfo)
    $scan.displays = @(Get-ZDisplays)

    $build = [string](Get-ZRegValue $cv 'CurrentBuild').Value
    $ubr = (Get-ZRegValue $cv 'UBR').Value
    if ($null -ne $ubr) { $build = $build + '.' + $ubr }
    $boot = [datetime]$osi.LastBootUpTime
    $scan.os = @{
        caption = ([string]$osi.Caption).Replace('Microsoft ', ''); edition = [string](Get-ZRegValue $cv 'EditionID').Value
        displayVersion = [string](Get-ZRegValue $cv 'DisplayVersion').Value; build = $build; arch = [string]$osi.OSArchitecture
        installDate = ([datetime]$osi.InstallDate).ToString('yyyy-MM-dd'); lastBoot = $boot.ToString('o')
        uptimeHours = [math]::Round(((Get-Date) - $boot).TotalHours, 1)
        productId = [string](Get-ZRegValue $cv 'ProductId').Value
    }

    $disks = @()
    $sysDisk = $null
    try { $sysDisk = [string](Get-Partition -DriveLetter ($env:SystemDrive.Substring(0, 1)) -ErrorAction Stop).DiskNumber } catch { }
    try {
        foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
            $disks += @{ name = [string]$d.FriendlyName; media = [string]$d.MediaType; bus = [string]$d.BusType; size = [long]$d.Size; health = [string]$d.HealthStatus; system = ([string]$d.DeviceId -eq $sysDisk) }
        }
    } catch { }
    $vols = @()
    try {
        foreach ($v in @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and [string]$_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter)) {
            $vols += @{ letter = [string]$v.DriveLetter; label = [string]$v.FileSystemLabel; fs = [string]$v.FileSystem; size = [long]$v.Size; free = [long]$v.SizeRemaining }
        }
    } catch { }
    $tot = 0; $free = 0
    foreach ($v in $vols) { $tot += $v.size; $free += $v.free }
    $scan.storage = @{ totalBytes = $tot; freeBytes = $free; usedBytes = ($tot - $free); volumes = $vols; disks = $disks }

    $scan.network = @(Get-ZPhysicalAdapters | ForEach-Object { @{ name = $_.Name; desc = $_.Description; wired = $_.Wired; up = $_.Up; speed = $_.Speed } })

    $procs = @(Get-Process).Count
    $running = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }).Count
    $startup = @(Get-ZStartupItems | Where-Object { $_.enabled }).Count
    $scan.counts = @{ processes = $procs; runningServices = $running; startupEnabled = $startup }

    $hvci = $null
    try { $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop; $hvci = (@($dg.SecurityServicesRunning) -contains 2) } catch { }
    $gm = Get-ZRegValue 'HKCU\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
    $hags = Get-ZRegValue 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
    $plan = Get-ZActiveScheme
    $planName = ''
    foreach ($s in @(Get-ZPowerSchemes)) { if ($s.Guid -eq $plan) { $planName = $s.Name } }
    $hib = 0
    try { $hib = (Get-Item -LiteralPath (Join-Path $env:SystemDrive 'hiberfil.sys') -Force -ErrorAction Stop).Length } catch { }
    $scan.features = @{
        hvci = $hvci; gameMode = (-not $gm.Exists -or [int]$gm.Value -eq 1); hags = ($hags.Exists -and [int]$hags.Value -eq 2)
        powerPlan = $planName; powerPlanGuid = $plan; hiberfilBytes = [long]$hib
    }
    $scan.checks = @(Get-ZHealthChecks $scan)
    return $scan
}

function Get-ZHealthChecks {
    param($Scan)
    $c = @()
    $cpuName = [string]$Scan.cpu.name
    $isRyzen = $cpuName -match 'Ryzen'
    $mem = $Scan.memory

    if ($mem.speed -gt 0 -and $mem.type -eq 'DDR4' -and $mem.speed -lt 3000) {
        if ($mem.rated -and $mem.rated -gt $mem.speed) {
            $detail = ('Your memory modules are rated for {0} MT/s but are running at {1} MT/s because the D.O.C.P./XMP profile is off. ' -f $mem.rated, $mem.speed)
        } else {
            $detail = ('Your memory runs at {0} MT/s. ' -f $mem.speed)
            if ($isRyzen) { $detail += 'Ryzen 5000 CPUs perform best with 3200-3600 MT/s memory. If your sticks are rated higher (check the label or the box), enable the D.O.C.P./XMP profile in BIOS. If they really are 2400 MT/s sticks, a 3200-3600 MT/s CL16 kit is the best-value FPS upgrade for this PC. ' }
        }
        if ($isRyzen) { $detail += 'On Ryzen the memory speed also sets the Infinity Fabric clock, so this typically adds 5-15% FPS in CPU-bound games. This is a BIOS setting - Windows tweaks cannot change it.' }
        if ($mem.count -ge 4) { $detail += ' With four sticks, 3200 MT/s is the reliable target.' }
        $c += @{ id = 'ram-speed'; level = 'bad'; title = ('RAM is running at only {0} MT/s' -f $mem.speed); detail = $detail; action = @{ type = 'guide'; target = 'docp'; label = 'How to enable D.O.C.P.' } }
    } elseif ($mem.speed -gt 0) {
        $c += @{ id = 'ram-speed'; level = 'good'; title = ('RAM speed {0} MT/s' -f $mem.speed); detail = 'Your memory is running at a good speed.' }
    }
    if ($mem.count -eq 1) {
        $c += @{ id = 'ram-channels'; level = 'warn'; title = 'Memory is running in single-channel'; detail = 'Only one memory stick is installed, which halves memory bandwidth. Two matching sticks (dual-channel) give a large FPS boost.' }
    }

    foreach ($g in @($Scan.gpus)) {
        if ($g.vendor -ne 'NVIDIA') { continue }
        if ($g.rebar -eq $false) {
            $c += @{ id = 'rebar'; level = 'warn'; title = 'Resizable BAR is off'; detail = ('Your {0} can use Resizable BAR, which lets the CPU access all of the graphics memory at once (+0-10% FPS depending on the game). It is switched on in the BIOS together with "Above 4G Decoding".' -f $g.name); action = @{ type = 'guide'; target = 'rebar'; label = 'How to enable Resizable BAR' } }
        } elseif ($g.rebar -eq $true) {
            $c += @{ id = 'rebar'; level = 'good'; title = 'Resizable BAR is on'; detail = 'Your graphics card can access its full memory from the CPU.' }
        }
        if ($null -ne $g.driverAgeDays -and $g.driverAgeDays -gt 120) {
            $c += @{ id = 'gpu-driver'; level = 'warn'; title = ('Graphics driver is {0} months old' -f [int]($g.driverAgeDays / 30)); detail = ('Driver {0} ({1}). New NVIDIA drivers regularly add game-specific performance fixes. Update with the NVIDIA App or from nvidia.com.' -f $g.nvidiaVersion, $g.driverDate); action = @{ type = 'open'; target = 'nvidia-drivers'; label = 'Get latest driver' } }
        } elseif ($null -ne $g.driverAgeDays) {
            $c += @{ id = 'gpu-driver'; level = 'good'; title = 'Graphics driver is recent'; detail = ('NVIDIA driver {0} from {1}.' -f $g.nvidiaVersion, $g.driverDate) }
        }
    }

    foreach ($d in @($Scan.displays)) {
        if ($d.maxHzAtRes -gt ($d.hz + 1)) {
            $c += @{ id = 'refresh'; level = 'bad'; title = ('{0} runs at {1} Hz but supports {2} Hz' -f $d.name, $d.hz, $d.maxHzAtRes); detail = 'Your monitor is set below its maximum refresh rate, so you cannot see more than that many frames per second however high your FPS is. Choose the highest refresh rate under Settings > Display > Advanced display.'; action = @{ type = 'open'; target = 'display'; label = 'Open display settings' } }
        } elseif ($d.hz -gt 0) {
            $c += @{ id = 'refresh'; level = 'good'; title = ('{0}: {1} Hz' -f $d.name, $d.hz); detail = 'Running at its highest refresh rate for this resolution.' }
        }
    }

    if ($Scan.os.uptimeHours -gt 72) {
        $c += @{ id = 'uptime'; level = 'warn'; title = ('Windows has not fully restarted in {0} days' -f [math]::Round($Scan.os.uptimeHours / 24, 1)); detail = 'With Fast Startup on, "Shut down" does not reset Windows. A restart clears memory leaks and stuck drivers. Disabling Fast Startup (Stability) makes every shutdown a clean start.'; action = @{ type = 'tweak'; target = 'stab.faststartup'; label = 'Disable Fast Startup' } }
    }

    foreach ($v in @($Scan.storage.volumes)) {
        if ($v.size -le 0) { continue }
        $used = [math]::Round(100 - ($v.free * 100.0 / $v.size))
        if ($used -ge 85) {
            $c += @{ id = ('disk-' + $v.letter); level = 'warn'; title = ('Drive {0}: is {1}% full' -f $v.letter, $used); detail = 'SSDs slow down and games can stutter when a drive is nearly full. Free up space with the Cleaner or move games to another drive.'; action = @{ type = 'page'; target = 'cleaner'; label = 'Open Cleaner' } }
        }
    }
    foreach ($d in @($Scan.storage.disks)) {
        if ($d.system -and $d.media -eq 'HDD') {
            $c += @{ id = 'system-hdd'; level = 'bad'; title = 'Windows is installed on a hard drive'; detail = 'Moving Windows and your games to an SSD is the biggest upgrade for loading times and stutter.' }
        }
        if ($d.health -and $d.health -ne 'Healthy') {
            $c += @{ id = ('disk-health-' + $d.name); level = 'bad'; title = ('{0} reports health: {1}' -f $d.name, $d.health); detail = 'Back up your files and check the drive with its manufacturer tool.' }
        }
    }

    $wiredUp = @($Scan.network | Where-Object { $_.wired -and $_.up }).Count
    $wifiUp = @($Scan.network | Where-Object { -not $_.wired -and $_.up }).Count
    if ($wiredUp -eq 0 -and $wifiUp -gt 0) {
        $c += @{ id = 'wifi'; level = 'info'; title = 'You are gaming over Wi-Fi'; detail = 'An Ethernet cable gives lower and more stable ping than Wi-Fi in online games.' }
    }

    if ($Scan.counts.processes -gt 220) {
        $c += @{ id = 'processes'; level = 'warn'; title = ('{0} processes running' -f $Scan.counts.processes); detail = 'Apply the Balanced preset, enable "Group service processes" (Memory), turn off unneeded Startup apps and disable ASUS / Edge background services to bring this down a lot.'; action = @{ type = 'page'; target = 'optimize'; label = 'Review optimizations' } }
    }
    if ($Scan.counts.startupEnabled -gt 6) {
        $c += @{ id = 'startup'; level = 'warn'; title = ('{0} apps start with Windows' -f $Scan.counts.startupEnabled); detail = 'Every startup app keeps running in the background while you game. Disable the ones you do not need right away.'; action = @{ type = 'page'; target = 'startup'; label = 'Manage startup apps' } }
    }
    $f = $Scan.features
    if ($f.powerPlanGuid -ne $Global:ZZenithPlanGuid -and $f.powerPlan -notmatch 'Ultimate|High') {
        $c += @{ id = 'powerplan'; level = 'warn'; title = ('Power plan: {0}' -f $f.powerPlan); detail = 'A balanced power plan lets the CPU clock down and park cores between frames.'; action = @{ type = 'tweak'; target = 'power.plan'; label = 'Use Zenith Ultimate plan' } }
    }
    if (-not $f.gameMode) {
        $c += @{ id = 'gamemode'; level = 'warn'; title = 'Game Mode is off'; detail = 'Game Mode helps Windows prioritise your game.'; action = @{ type = 'tweak'; target = 'game.mode'; label = 'Turn on Game Mode' } }
    }
    if ($f.hvci -eq $true) {
        $c += @{ id = 'hvci'; level = 'info'; title = 'Memory Integrity (HVCI) is on'; detail = 'Good for security, but it costs a few percent of performance in CPU-heavy games. You can turn it off under Optimizations > CPU & Power (advanced) if you accept the trade-off.' }
    }
    if ($f.hiberfilBytes -gt 1GB) {
        $c += @{ id = 'hibernation'; level = 'info'; title = ('Hibernation file uses {0} GB' -f [math]::Round($f.hiberfilBytes / 1GB, 1)); detail = 'Gaming desktops rarely need hibernation. Disabling it gives you that space back.'; action = @{ type = 'tweak'; target = 'power.hibernate'; label = 'Free this space' } }
    }
    return $c
}

function Get-ZLive {
    if ($Global:ZCtx.Mock) { return Get-ZMockLive }
    $live = @{ time = (Get-Date).ToString('o') }
    $cpu = $null
    try {
        $p = Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction Stop
        $cpu = [math]::Min(100, [double]$p.PercentProcessorUtility)
    } catch {
        try { $cpu = [double](@(Get-CimInstance Win32_Processor) | Measure-Object -Property LoadPercentage -Average).Average } catch { }
    }
    $live.cpu = $cpu
    try {
        $os = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory, TotalVisibleMemorySize
        $total = [double]$os.TotalVisibleMemorySize
        $free = [double]$os.FreePhysicalMemory
        $live.ram = [math]::Round(($total - $free) * 100 / $total, 1)
        $live.ramUsedGB = [math]::Round(($total - $free) / 1MB, 1)
        $live.ramTotalGB = [math]::Round($total / 1MB, 1)
    } catch { }
    $smi = Get-ZNvidiaSmi
    if ($smi) {
        try {
            $line = @(& $smi '--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total' '--format=csv,noheader,nounits' 2>$null)[0]
            $f = ([string]$line).Split(',') | ForEach-Object { $_.Trim() }
            $live.gpu = [double]$f[0]; $live.gpuTemp = [double]$f[1]
            $live.vramUsedGB = [math]::Round([double]$f[2] / 1024, 1); $live.vramTotalGB = [math]::Round([double]$f[3] / 1024, 1)
        } catch { }
    }
    if ($null -eq $live.gpu) {
        try {
            $sum = (@(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop | Where-Object { $_.Name -like '*engtype_3D' }) | Measure-Object -Property UtilizationPercentage -Sum).Sum
            $live.gpu = [math]::Min(100, [double]$sum)
        } catch { }
    }
    $live.processes = [System.Diagnostics.Process]::GetProcesses().Length
    return $live
}

# ---------------------------------------------------------------------------------------------------
# Mock data (mirrors the user's PC) for development without Windows
# ---------------------------------------------------------------------------------------------------

function Get-ZMockScan {
    $hib = 0
    if ($Global:ZMock.Hibernate) { $hib = [long](25.6 * 1GB) }
    $scan = @{
        scannedAt = (Get-Date).ToString('o')
        device    = @{ name = 'DESKTOP-TBT25C2'; manufacturer = 'ASUSTeK COMPUTER INC.'; model = 'ROG STRIX G15DK_G15DK'; board = 'ASUSTeK COMPUTER INC. G15DK'; bios = '0603'; biosDate = '2022-03-18'; deviceId = '{0B7DD6F4-37EB-4623-8911-119F8BAE2642}' }
        cpu       = @{ name = 'AMD Ryzen 7 5800X 8-Core Processor'; vendor = 'AuthenticAMD'; cores = 8; threads = 16; baseMHz = 3801 }
        memory    = @{
            totalGB = 64; usableGB = 63.9; speed = 2400; rated = $null; type = 'DDR4'; count = 4
            modules = @(
                @{ slot = 'DIMM_A1'; sizeGB = 16; speed = 2400; configured = 2400; maker = 'Unknown'; part = 'Module 16GB DDR4'; type = 'DDR4'; rated = $null },
                @{ slot = 'DIMM_A2'; sizeGB = 16; speed = 2400; configured = 2400; maker = 'Unknown'; part = 'Module 16GB DDR4'; type = 'DDR4'; rated = $null },
                @{ slot = 'DIMM_B1'; sizeGB = 16; speed = 2400; configured = 2400; maker = 'Unknown'; part = 'Module 16GB DDR4'; type = 'DDR4'; rated = $null },
                @{ slot = 'DIMM_B2'; sizeGB = 16; speed = 2400; configured = 2400; maker = 'Unknown'; part = 'Module 16GB DDR4'; type = 'DDR4'; rated = $null }
            )
        }
        gpus      = @(@{ name = 'NVIDIA GeForce RTX 3070'; vendor = 'NVIDIA'; vramBytes = 8589934592; driverVersion = '32.0.15.6094'; nvidiaVersion = '560.94'; driverDate = '2024-08-14'; driverAgeDays = 430; pnp = $Global:ZMock.Gpus[0].PnpId; bar1MB = 256; rebar = $false })
        displays  = @(@{ device = '\\.\DISPLAY1'; adapter = 'NVIDIA GeForce RTX 3070'; name = 'ROG XG27AQ'; width = 2560; height = 1440; hz = 60; maxHzAtRes = 170; maxHz = 170; maxWidth = 2560; maxHeight = 1440; primary = $true })
        os        = @{ caption = 'Windows 11 Home'; edition = 'Core'; displayVersion = '25H2'; build = '26200.9711'; arch = '64-bit'; installDate = '2025-09-19'; lastBoot = (Get-Date).AddDays(-9).ToString('o'); uptimeHours = 216.4; productId = '00325-82148-15280-AAOEM' }
        storage   = @{
            totalBytes = 2518679912448; freeBytes = 770396700672; usedBytes = 1748283211776
            volumes    = @(@{ letter = 'C'; label = 'Windows'; fs = 'NTFS'; size = 517955149824; free = 61203283968 }, @{ letter = 'D'; label = 'Games'; fs = 'NTFS'; size = 2000724762624; free = 709193416704 })
            disks      = @(@{ name = 'Samsung SSD 980 500GB'; media = 'SSD'; bus = 'NVMe'; size = 500107862016; health = 'Healthy'; system = $true }, @{ name = 'WD Blue SN570 2TB'; media = 'SSD'; bus = 'NVMe'; size = 2000398934016; health = 'Healthy'; system = $false })
        }
        network   = @(@{ name = 'Ethernet'; desc = 'Realtek PCIe 2.5GbE Family Controller'; wired = $true; up = $true; speed = '1 Gbps' }, @{ name = 'Wi-Fi'; desc = 'Realtek RTL8852BE WiFi 6 802.11ax PCIe Adapter'; wired = $false; up = $false; speed = '0 bps' })
        counts    = @{ processes = 302; runningServices = 141; startupEnabled = @(Get-ZStartupItems | Where-Object { $_.enabled }).Count }
        features  = @{ hvci = $true; gameMode = $true; hags = $true; powerPlan = 'Balanced'; powerPlanGuid = (Get-ZActiveScheme); hiberfilBytes = $hib }
    }
    if ((Get-ZActiveScheme) -eq $Global:ZZenithPlanGuid) { $scan.features.powerPlan = 'Zenith Ultimate Performance' }
    $scan.checks = @(Get-ZHealthChecks $scan)
    return $scan
}

function Get-ZMockLive {
    if (-not $Global:ZMockLive) { $Global:ZMockLive = @{ cpu = 18.0; gpu = 34.0; ram = 31.0 } }
    $r = New-Object System.Random
    $s = $Global:ZMockLive
    $s.cpu = [math]::Max(3, [math]::Min(96, $s.cpu + ($r.NextDouble() - 0.5) * 14))
    $s.gpu = [math]::Max(2, [math]::Min(99, $s.gpu + ($r.NextDouble() - 0.5) * 18))
    $s.ram = [math]::Max(20, [math]::Min(60, $s.ram + ($r.NextDouble() - 0.5) * 2))
    return @{
        time = (Get-Date).ToString('o'); cpu = [math]::Round($s.cpu, 1); gpu = [math]::Round($s.gpu, 1); gpuTemp = [math]::Round(46 + $s.gpu / 4)
        ram = [math]::Round($s.ram, 1); ramUsedGB = [math]::Round(63.9 * $s.ram / 100, 1); ramTotalGB = 63.9
        vramUsedGB = [math]::Round(1.2 + $s.gpu / 20, 1); vramTotalGB = 8.0; processes = 302 - (@((Read-ZLedger).tweaks.Keys).Count * 2)
    }
}
