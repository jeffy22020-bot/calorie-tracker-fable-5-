# Zenith - Tweak catalog
# Each tweak is a list of declarative ops (see Engine.ps1). "Build" scriptblocks generate ops for the
# hardware found on this PC (network interfaces, GPU, installed services...). A tweak whose op list
# comes out empty is shown as "not needed on this PC".
#
# Risk:   safe      - no functional downside for a gaming PC
#         moderate  - small trade-off, read the description
#         advanced  - real trade-off (security or compatibility); never part of a preset
# Preset: balanced  - part of both presets (recommended for everyone)
#         performance - part of the Performance preset only
#         $null     - manual only
# Target: Windows PowerShell 5.1. Keep this file ASCII-only.

function ZR { param([string]$Path, [string]$Name, $Value, [string]$Kind = 'DWord') return @{ T = 'Reg'; Path = $Path; Name = $Name; Value = $Value; Kind = $Kind } }
function ZRS { param([string]$Path, [string]$Name, [string]$Value) return @{ T = 'Reg'; Path = $Path; Name = $Name; Value = $Value; Kind = 'String' } }
function ZSvc { param([string]$Name, [string]$Start, [switch]$Stop) return @{ T = 'Service'; Name = $Name; Start = $Start; Stop = [bool]$Stop } }
function ZTask { param([string]$Path) return @{ T = 'Task'; Path = $Path; Enabled = $false } }
function ZPow { param([string]$Sub, [string]$Setting, [long]$Value, [string]$Label) return @{ T = 'PowerSetting'; Sub = $Sub; Setting = $Setting; Value = $Value; Label = $Label } }

$Global:ZCategories = @(
    @{ id = 'gaming';     label = 'Gaming & FPS';        page = 'optimize' }
    @{ id = 'latency';    label = 'Input & Latency';     page = 'optimize' }
    @{ id = 'power';      label = 'CPU & Power';         page = 'optimize' }
    @{ id = 'memory';     label = 'Memory';              page = 'optimize' }
    @{ id = 'gpu';        label = 'Graphics';            page = 'optimize' }
    @{ id = 'network';    label = 'Network';             page = 'optimize' }
    @{ id = 'storage';    label = 'Storage';             page = 'optimize' }
    @{ id = 'stability';  label = 'Stability';           page = 'optimize' }
    @{ id = 'interface';  label = 'Interface';           page = 'optimize' }
    @{ id = 'privacy';    label = 'Privacy & Telemetry'; page = 'debloat' }
    @{ id = 'bloat';      label = 'Windows Bloat';       page = 'debloat' }
    @{ id = 'services';   label = 'Background Services'; page = 'debloat' }
    @{ id = 'background'; label = 'Background Apps';     page = 'debloat' }
)

$kGameBar = 'HKCU\Software\Microsoft\GameBar'
$kGameCfg = 'HKCU\System\GameConfigStore'
$kSysProfile = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$kGfx = 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
$kCdm = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$kAdv = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$kPolWin = 'HKLM\SOFTWARE\Policies\Microsoft\Windows'
$subProc = '54533251-82be-4824-96c1-47b60b740d00'

$Global:ZTweaks = @(

    # ------------------------------------------------------------------ Gaming & FPS
    @{
        Id = 'game.mode'; Cat = 'gaming'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Enable Windows Game Mode'
        Desc = 'Tells Windows to prioritise the game you are playing and hold back Windows Update installs and restarts while you play.'
        Details = 'Game Mode gives the foreground game priority for CPU and GPU scheduling and reduces background activity during a session. It is on by default on most PCs, but some apps and updates switch it off.'
        Ops = @(
            ZR $kGameBar 'AutoGameModeEnabled' 1
            ZR $kGameBar 'AllowAutoGameMode' 1
        )
    }
    @{
        Id = 'game.dvr'; Cat = 'gaming'; Risk = 'safe'; Impact = 'high'; Preset = 'balanced'
        Name = 'Disable Game DVR background recording'
        Desc = 'Stops Xbox Game Bar from silently recording your gameplay in the background - a common cause of FPS drops and stutter.'
        Details = 'Background capture keeps a video encoder and disk writes running the whole time you play. You can still record clips with the NVIDIA App / ShadowPlay (Alt+Z), which uses the dedicated NVENC encoder with much lower overhead.'
        Ops = @(
            ZR $kGameCfg 'GameDVR_Enabled' 0
            ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
            ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 0
            ZR "$kPolWin\GameDVR" 'AllowGameDVR' 0
        )
    }
    @{
        Id = 'game.gamebar'; Cat = 'gaming'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Stop Game Bar popping up on controller press'
        Desc = 'Stops the Xbox button on your controller from opening Game Bar in the middle of a match, and hides the Game Bar startup tips.'
        Ops = @(
            ZR $kGameBar 'UseNexusForGameBarEnabled' 0
            ZR $kGameBar 'ShowStartupPanel' 0
            ZR $kGameBar 'GamePanelStartupTipIndex' 3
        )
    }
    @{
        Id = 'game.hags'; Cat = 'gaming'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'; Reboot = $true
        Name = 'Hardware-accelerated GPU scheduling'
        Desc = 'Lets your RTX 3070 schedule its own video memory work instead of the CPU doing it, lowering CPU overhead and input latency.'
        Details = 'NVIDIA recommends HAGS on RTX cards and newer features depend on it. If one particular older game misbehaves afterwards, simply undo this tweak.'
        Ops = @( ZR $kGfx 'HwSchMode' 2 )
    }
    @{
        Id = 'game.windowed'; Cat = 'gaming'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Optimizations for borderless & windowed games'
        Desc = 'Upgrades DirectX 10/11 games running borderless or windowed to the low-latency flip presentation model, and lets them use G-SYNC / variable refresh rate.'
        Details = 'These are the "Optimizations for windowed games" and "Variable refresh rate" switches from Settings > Display > Graphics. Flip-model presentation removes an extra frame of desktop composition latency in borderless mode, which most competitive players use.'
        Ops = @( @{ T = 'RegKV'; Path = 'HKCU\Software\Microsoft\DirectX\UserGpuPreferences'; Name = 'DirectXUserGlobalSettings'; Pairs = @{ SwapEffectUpgradeEnable = '1'; VRROptimizeEnable = '1' } } )
    }
    @{
        Id = 'game.mmcss'; Cat = 'gaming'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Prioritise games in the multimedia scheduler'
        Desc = 'Raises the CPU and disk priority Windows gives to games that register with the Multimedia Class Scheduler (most DirectX games do).'
        Ops = @(
            ZR "$kSysProfile\Tasks\Games" 'GPU Priority' 8
            ZR "$kSysProfile\Tasks\Games" 'Priority' 6
            ZRS "$kSysProfile\Tasks\Games" 'Scheduling Category' 'High'
            ZRS "$kSysProfile\Tasks\Games" 'SFIO Priority' 'High'
        )
    }
    @{
        Id = 'game.sysresp'; Cat = 'gaming'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Reserve less CPU for background media'
        Desc = 'Lowers the share of CPU time Windows reserves for background multimedia tasks from 20% to 10%, leaving more for your game.'
        Ops = @( ZR $kSysProfile 'SystemResponsiveness' 10 )
    }
    @{
        Id = 'game.priosep'; Cat = 'gaming'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Boost the foreground app'
        Desc = 'Gives the window you are using - your game - longer, boosted CPU time slices compared with programs running in the background.'
        Details = 'Sets Win32PrioritySeparation to 0x26 (short, variable quantums with the maximum foreground boost). The Windows default is 2.'
        Ops = @( ZR 'HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38 )
    }
    @{
        Id = 'game.mouse'; Cat = 'gaming'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable mouse acceleration'
        Desc = 'Turns off "Enhance pointer precision" so your crosshair moves exactly as far as your hand does - essential for consistent aim.'
        Details = 'Applied instantly, no restart needed. The cursor may feel slightly different on the desktop for a day while you get used to 1:1 movement.'
        Ops = @(
            ZRS 'HKCU\Control Panel\Mouse' 'MouseSpeed' '0'
            ZRS 'HKCU\Control Panel\Mouse' 'MouseThreshold1' '0'
            ZRS 'HKCU\Control Panel\Mouse' 'MouseThreshold2' '0'
            @{ T = 'Notify'; What = 'Mouse' }
        )
    }
    @{
        Id = 'game.stickykeys'; Cat = 'gaming'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable Sticky Keys pop-ups'
        Desc = 'Stops the Sticky Keys / Filter Keys prompt from appearing - and minimising your game - when you tap or hold Shift.'
        Ops = @(
            ZRS 'HKCU\Control Panel\Accessibility\StickyKeys' 'Flags' '506'
            ZRS 'HKCU\Control Panel\Accessibility\Keyboard Response' 'Flags' '122'
            ZRS 'HKCU\Control Panel\Accessibility\ToggleKeys' 'Flags' '58'
        )
    }
    @{
        Id = 'game.fso'; Cat = 'gaming'; Risk = 'moderate'; Impact = 'low'; Preset = $null; Tags = @('Experimental')
        Name = 'Disable fullscreen optimizations (global)'
        Desc = 'Forces classic exclusive fullscreen in older games that support it. Can lower latency in some DX9/DX11 titles, but breaks Auto HDR and quick Alt+Tab.'
        Warning = 'Only worth trying if a specific older game feels laggy in fullscreen. Modern games and borderless mode do not benefit.'
        Ops = @(
            ZR $kGameCfg 'GameDVR_FSEBehaviorMode' 2
            ZR $kGameCfg 'GameDVR_HonorUserFSEBehaviorMode' 1
            ZR $kGameCfg 'GameDVR_FSEBehavior' 2
            ZR $kGameCfg 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
            ZR $kGameCfg 'GameDVR_EFSEFeatureFlags' 0
        )
    }
    @{
        Id = 'game.mpo'; Cat = 'gaming'; Risk = 'moderate'; Impact = 'low'; Preset = $null; Reboot = $true; Tags = @('Experimental')
        Name = 'Disable Multi-Plane Overlay (flicker fix)'
        Desc = 'Fixes flickering, black flashes and stutter that some NVIDIA users see in games and browsers, mostly on multi-monitor setups.'
        Details = 'This is the OverlayTestMode=5 workaround NVIDIA published for MPO-related issues. Newer Windows 11 builds may ignore it. Only use it if you actually have these symptoms.'
        Ops = @( ZR 'HKLM\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5 )
    }

    # ------------------------------------------------------------------ Input & Latency
    @{
        Id = 'lat.usb'; Cat = 'latency'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable USB selective suspend'
        Desc = 'Stops Windows putting USB ports to sleep, which prevents mouse, keyboard and headset drop-outs or wake-up lag.'
        Ops = @( ZPow '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0 'USB selective suspend' )
    }
    @{
        Id = 'lat.aspm'; Cat = 'latency'; Risk = 'safe'; Impact = 'low'; Preset = 'performance'; Tags = @('Power hungry')
        Name = 'Disable PCIe link power saving'
        Desc = 'Keeps the PCI Express links to your graphics card and NVMe drive at full power, so they never have to wake up mid-game.'
        Ops = @( ZPow '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5' 0 'PCI Express link state power management' )
    }
    @{
        Id = 'lat.timer'; Cat = 'latency'; Risk = 'moderate'; Impact = 'low'; Preset = $null; Reboot = $true; Tags = @('Experimental', 'Power hungry')
        Name = 'Global timer resolution'
        Desc = 'Restores the classic behaviour where a game that asks for a high-precision timer (0.5 ms) gets it system-wide. Can smooth frame pacing in some titles.'
        Details = 'Since Windows 10 2004, a timer-resolution request only affects the process that made it. GlobalTimerResolutionRequests=1 restores the old global behaviour. Slightly higher idle power use; results vary per game.'
        Ops = @( ZR 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1 )
    }

    # ------------------------------------------------------------------ CPU & Power
    @{
        Id = 'power.plan'; Cat = 'power'; Risk = 'safe'; Impact = 'high'; Preset = 'balanced'; Tags = @('Power hungry')
        Name = 'Zenith Ultimate Performance power plan'
        Desc = 'Creates and activates a maximum-performance power plan so your Ryzen 7 5800X ramps to full boost instantly instead of waiting to clock up.'
        Details = 'Built from the hidden Windows "Ultimate Performance" plan (falls back to High performance). Your current sleep and screen-off timers are copied across. Uses a few more watts at idle. Undo switches back to your previous plan and deletes this one.'
        Ops = @( @{ T = 'PowerPlan' } )
    }
    @{
        Id = 'power.coreparking'; Cat = 'power'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable CPU core parking'
        Desc = 'Keeps all 8 cores / 16 threads awake so game threads never land on a parked core that has to wake up first.'
        Ops = @( ZPow $subProc '0cc5b647-c1df-4637-891a-dec35c318583' 100 'Core parking minimum cores (%)' )
    }
    @{
        Id = 'power.boost'; Cat = 'power'; Risk = 'safe'; Impact = 'low'; Preset = 'performance'; Tags = @('Power hungry')
        Name = 'Aggressive processor boost'
        Desc = 'Asks AMD Precision Boost for the highest clocks as early as possible when load appears.'
        Ops = @( ZPow $subProc 'be337238-0d82-4146-a960-4f3749d470c7' 2 'Processor performance boost mode (2 = Aggressive)' )
    }
    @{
        Id = 'power.throttling'; Cat = 'power'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable power throttling'
        Desc = 'Stops Windows slowing down apps it thinks are in the background (launchers, voice chat, overlays). It is a laptop battery feature you do not need on a desktop.'
        Ops = @( ZR 'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 )
    }
    @{
        Id = 'power.hibernate'; Cat = 'power'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable hibernation (frees ~25 GB)'
        Desc = 'Deletes hiberfil.sys, which on a 64 GB RAM PC takes up roughly 25 GB of your system drive. Normal sleep keeps working.'
        Details = 'Gaming desktops rarely hibernate. Turning it off also turns off Fast Startup. Undo turns hibernation back on (the file is recreated).'
        Ops = @( @{ T = 'Hibernate'; Enabled = $false } )
    }
    @{
        Id = 'power.hvci'; Cat = 'power'; Risk = 'advanced'; Impact = 'high'; Preset = $null; Reboot = $true
        Name = 'Turn off Memory Integrity (HVCI)'
        Desc = 'Removes the virtualization-based security overhead that Microsoft itself says can reduce gaming performance. Typically a few percent more FPS in CPU-heavy games.'
        Warning = 'Security trade-off: Memory Integrity blocks malicious drivers from loading into the Windows kernel. Only turn it off if you get games and drivers from official sources. Some anti-cheat systems may ask you to turn it back on.'
        Ops = @( ZR 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0 )
    }

    # ------------------------------------------------------------------ Memory
    @{
        Id = 'mem.svchost'; Cat = 'memory'; Risk = 'moderate'; Impact = 'medium'; Preset = 'performance'; Reboot = $true
        Name = 'Group service processes (far fewer processes)'
        Desc = 'With more than 3.5 GB of RAM Windows gives every service its own svchost.exe. On your 64 GB PC that means dozens of extra processes - this groups them again.'
        Details = 'Sets SvcHostSplitThresholdInKB to your installed RAM so services share host processes like they did before Windows 10 1703. This is the single biggest drop in process count (often 60-90 fewer). Trade-off: if one service in a group crashes it can take its neighbours with it, which is rare.'
        Build = { ZR 'HKLM\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' ([long](Get-ZTotalMemoryKB) + 1024) }
    }
    @{
        Id = 'mem.pagingexec'; Cat = 'memory'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'; Reboot = $true
        Name = 'Keep the Windows kernel in RAM'
        Desc = 'With 64 GB of RAM there is no reason to page kernel-mode drivers and system code out to disk. Keeps them in memory for quicker responses.'
        Ops = @( ZR 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1 )
    }
    @{
        Id = 'mem.sysmain'; Cat = 'memory'; Risk = 'moderate'; Impact = 'low'; Preset = 'performance'
        Name = 'Disable SysMain (Superfetch)'
        Desc = 'Stops Windows pre-loading apps into RAM in the background. With 64 GB and SSD storage the benefit is small and it can cause disk spikes while gaming.'
        Details = 'If Windows or your games are on a hard drive (HDD), leave SysMain on - it helps more there.'
        Ops = @( ZSvc 'SysMain' 'Disabled' -Stop )
    }

    # ------------------------------------------------------------------ Graphics
    @{
        Id = 'gpu.tdr'; Cat = 'gpu'; Risk = 'safe'; Impact = 'low'; Preset = 'performance'; Reboot = $true
        Name = 'Increase GPU timeout tolerance'
        Desc = 'Gives the graphics driver 10 seconds instead of 2 before Windows resets it, preventing "display driver stopped responding" crashes during heavy shader compilation.'
        Ops = @( ZR $kGfx 'TdrDelay' 10 )
    }
    @{
        Id = 'gpu.nvtelemetry'; Cat = 'gpu'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable NVIDIA telemetry tasks'
        Desc = 'Turns off the NVIDIA crash and usage reporting tasks that run in the background. The driver, control panel and NVIDIA App keep working.'
        NaReason = 'No NVIDIA telemetry tasks found'
        Build = { foreach ($p in @(Find-ZTasks '\' 'NvTm')) { ZTask $p } }
    }
    @{
        Id = 'gpu.msi'; Cat = 'gpu'; Risk = 'advanced'; Impact = 'low'; Preset = $null; Reboot = $true
        Name = 'Enable MSI interrupt mode for your GPU'
        Desc = 'Switches your graphics card to Message Signaled Interrupts, which can lower interrupt latency. Most RTX cards already use it - Zenith shows "Already optimal" if so.'
        Warning = 'Only the NVIDIA/AMD graphics card is touched. In the rare case your screen stays black after the restart, start Windows in Safe Mode and run Emergency Restore.bat, or use System Restore.'
        NaReason = 'No NVIDIA or AMD graphics card found'
        Build = {
            foreach ($g in @(Get-ZGpuDevices)) {
                if ($g.Vendor -eq 'NVIDIA' -or $g.Vendor -eq 'AMD') {
                    ZR ('HKLM\SYSTEM\CurrentControlSet\Enum\' + $g.PnpId + '\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties') 'MSISupported' 1
                }
            }
        }
    }
    @{
        Id = 'gpu.drivers'; Cat = 'gpu'; Risk = 'moderate'; Impact = 'medium'; Preset = $null
        Name = 'Stop Windows Update replacing your GPU driver'
        Desc = 'Prevents Windows Update from silently installing older or generic drivers over the NVIDIA driver you installed - a classic cause of sudden stutter and crashes.'
        Warning = 'Windows Update will stop delivering hardware drivers automatically. Update your GPU driver through the NVIDIA App and chipset drivers from AMD.'
        Ops = @(
            ZR 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0
            ZR "$kPolWin\WindowsUpdate" 'ExcludeWUDriversInQualityUpdate' 1
        )
    }

    # ------------------------------------------------------------------ Network
    @{
        Id = 'net.throttle'; Cat = 'network'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable network throttling'
        Desc = 'Removes the Windows cap on network packet processing that kicks in while audio or video plays, which can add latency to online games.'
        Ops = @( ZR $kSysProfile 'NetworkThrottlingIndex' 4294967295 )
    }
    @{
        Id = 'net.nagle'; Cat = 'network'; Risk = 'safe'; Impact = 'low'; Preset = 'performance'
        Name = "Disable Nagle's algorithm"
        Desc = 'Sends small TCP packets immediately instead of bundling them, reducing latency in games that use TCP (MMOs, some MOBAs and launchers).'
        NaReason = 'No connected network interfaces found'
        Build = {
            $root = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            foreach ($id in @(Get-ZRegSubKeyNames $root)) {
                $p = $root + '\' + $id
                $dhcp = [string](Get-ZRegValue $p 'DhcpIPAddress').Value
                $static = @((Get-ZRegValue $p 'IPAddress').Value | Where-Object { $_ -and $_ -ne '0.0.0.0' })
                if (($dhcp -and $dhcp -ne '0.0.0.0') -or $static.Count -gt 0) {
                    ZR $p 'TcpAckFrequency' 1
                    ZR $p 'TCPNoDelay' 1
                }
            }
        }
    }
    @{
        Id = 'net.eee'; Cat = 'network'; Risk = 'moderate'; Impact = 'low'; Preset = 'performance'; Tags = @('Brief disconnect')
        Name = 'Disable Energy-Efficient Ethernet'
        Desc = 'Stops your wired network adapter dropping into power-saving states between packets, which can cause small ping spikes.'
        Warning = 'Your wired connection drops for a few seconds while the adapter restarts.'
        NaReason = 'No wired adapter with power-saving options found'
        Build = {
            $kw = @('*EEE', 'EEELinkAdvertisement', 'AdvancedEEE', 'EnableGreenEthernet', 'PowerSavingMode')
            if (@(Get-ZNetAdvItems $kw).Count -gt 0) { @{ T = 'NetAdv'; Keywords = $kw; Value = '0' } }
        }
    }
    @{
        Id = 'net.nicpower'; Cat = 'network'; Risk = 'safe'; Impact = 'low'; Preset = 'performance'; Reboot = $true
        Name = 'Stop Windows switching off network adapters'
        Desc = 'Unticks "Allow the computer to turn off this device to save power" for your network adapters, preventing disconnects and wake-up lag.'
        NaReason = 'No physical network adapters found'
        Build = {
            $cls = 'HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
            $guids = @(@(Get-ZPhysicalAdapters) | ForEach-Object { ([string]$_.Guid).ToLowerInvariant() })
            foreach ($sk in @(Get-ZRegSubKeyNames $cls)) {
                if ($sk -notmatch '^\d{4}$') { continue }
                $p = $cls + '\' + $sk
                $id = [string](Get-ZRegValue $p 'NetCfgInstanceId').Value
                if ($id -and ($guids -contains $id.ToLowerInvariant())) { ZR $p 'PnPCapabilities' 24 }
            }
        }
    }
    @{
        Id = 'net.do'; Cat = 'network'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable peer-to-peer update sharing'
        Desc = 'Stops Windows uploading updates to other PCs over the internet (Delivery Optimization), which can eat your upload bandwidth and raise ping.'
        Ops = @( ZR "$kPolWin\DeliveryOptimization" 'DODownloadMode' 0 )
    }

    # ------------------------------------------------------------------ Storage
    @{
        Id = 'storage.trim'; Cat = 'storage'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Make sure SSD TRIM is on'
        Desc = 'Checks that Windows tells your SSDs which blocks are free (TRIM), which keeps write speeds high and wear low over time.'
        Ops = @( @{ T = 'Fsutil'; Setting = 'DisableDeleteNotify'; Value = 0 } )
    }
    @{
        Id = 'storage.lastaccess'; Cat = 'storage'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable last-access timestamps'
        Desc = 'Stops NTFS writing a "last opened" time to disk every time any file is read, cutting small background writes.'
        Ops = @( @{ T = 'Fsutil'; Setting = 'disablelastaccess'; Value = 1 } )
    }
    @{
        Id = 'storage.sense'; Cat = 'storage'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Turn on Storage Sense'
        Desc = 'Lets Windows automatically clear temporary files when your drive starts running low on space.'
        Ops = @(
            ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1
            ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '04' 1
        )
    }
    @{
        Id = 'storage.indexing'; Cat = 'storage'; Risk = 'moderate'; Impact = 'low'; Preset = $null
        Name = 'Disable Windows Search indexing'
        Desc = 'Stops the search indexer crawling your drives in the background. Finding apps in Start still works; searching inside documents gets slower.'
        Ops = @( ZSvc 'WSearch' 'Disabled' -Stop )
    }

    # ------------------------------------------------------------------ Stability
    @{
        Id = 'stab.faststartup'; Cat = 'stability'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable Fast Startup'
        Desc = 'Makes "Shut down" a real shutdown. Fast Startup keeps the kernel hibernated between boots - a common cause of driver glitches and bugs that only a restart fixes.'
        Ops = @( ZR 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 )
    }
    @{
        Id = 'stab.noautoreboot'; Cat = 'stability'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'No surprise update restarts'
        Desc = 'Stops Windows Update restarting your PC on its own while you are signed in - for example in the middle of a match. You restart when it suits you.'
        Ops = @( ZR "$kPolWin\WindowsUpdate\AU" 'NoAutoRebootWithLoggedOnUsers' 1 )
    }

    # ------------------------------------------------------------------ Interface
    @{
        Id = 'ui.startupdelay'; Cat = 'interface'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Remove the startup app delay'
        Desc = 'Windows waits about 10 seconds after sign-in before starting your startup apps. This removes the artificial wait.'
        Ops = @( ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0 )
    }
    @{
        Id = 'ui.menudelay'; Cat = 'interface'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Faster menus'
        Desc = 'Cuts the delay before sub-menus open from 400 ms to 100 ms, so Windows feels snappier.'
        Ops = @( ZRS 'HKCU\Control Panel\Desktop' 'MenuShowDelay' '100' )
    }
    @{
        Id = 'ui.animations'; Cat = 'interface'; Risk = 'safe'; Impact = 'low'; Preset = 'performance'; Tags = @('Sign-out')
        Name = 'Reduce window animations'
        Desc = 'Turns off the minimise/maximise and taskbar animations so windows appear instantly.'
        Ops = @(
            ZRS 'HKCU\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0'
            ZR $kAdv 'TaskbarAnimations' 0
        )
    }
    @{
        Id = 'ui.transparency'; Cat = 'interface'; Risk = 'safe'; Impact = 'low'; Preset = 'performance'
        Name = 'Disable transparency effects'
        Desc = 'Turns off the see-through blur behind the taskbar and Start menu, saving a little GPU work on the desktop.'
        Ops = @( ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 )
    }
    @{
        Id = 'ui.classicmenu'; Cat = 'interface'; Risk = 'safe'; Impact = 'low'; Preset = $null; Tags = @('Explorer restart')
        Name = 'Classic right-click menu'
        Desc = 'Brings back the full Windows 10 style right-click menu, so you never have to click "Show more options".'
        Ops = @( ZRS 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '' '' )
    }
    @{
        Id = 'ui.fileext'; Cat = 'interface'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Show file extensions'
        Desc = 'Shows ".exe", ".zip" and friends in File Explorer - a simple way to spot fake files such as "setup.pdf.exe".'
        Ops = @( ZR $kAdv 'HideFileExt' 0 )
    }
    @{
        Id = 'ui.endtask'; Cat = 'interface'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Add "End task" to the taskbar'
        Desc = 'Adds an "End task" option when you right-click a taskbar app, so you can kill a frozen game without opening Task Manager.'
        Ops = @( ZR "$kAdv\TaskbarDeveloperSettings" 'TaskbarEndTask' 1 )
    }
    @{
        Id = 'ui.keyboard'; Cat = 'interface'; Risk = 'safe'; Impact = 'low'; Preset = $null
        Name = 'Fastest keyboard repeat'
        Desc = 'Sets the shortest delay and fastest rate for repeating keys when you hold them down.'
        Ops = @(
            ZRS 'HKCU\Control Panel\Keyboard' 'KeyboardDelay' '0'
            ZRS 'HKCU\Control Panel\Keyboard' 'KeyboardSpeed' '31'
        )
    }

    # ------------------------------------------------------------------ Privacy & Telemetry
    @{
        Id = 'priv.telemetry'; Cat = 'privacy'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Set diagnostic data to minimum'
        Desc = 'Limits the diagnostic data Windows sends to Microsoft to the lowest level your edition allows (on Windows 11 Home that is "Required").'
        Details = 'Windows Settings may show "Some settings are managed by your organization" afterwards - that only means a policy value is set, it is expected.'
        Ops = @( ZR "$kPolWin\DataCollection" 'AllowTelemetry' 0 )
    }
    @{
        Id = 'priv.tasks'; Cat = 'privacy'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable telemetry scheduled tasks'
        Desc = 'Turns off the compatibility appraiser, CEIP and feedback tasks that wake up in the background and cause CPU and disk spikes.'
        Ops = @(
            ZTask '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
            ZTask '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
            ZTask '\Microsoft\Windows\Application Experience\MareBackup'
            ZTask '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
            ZTask '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
            ZTask '\Microsoft\Windows\Autochk\Proxy'
            ZTask '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
            ZTask '\Microsoft\Windows\Feedback\Siuf\DmClient'
            ZTask '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
            ZTask '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
        )
    }
    @{
        Id = 'priv.adid'; Cat = 'privacy'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable advertising ID'
        Desc = 'Stops apps using your advertising ID to show you personalised ads.'
        Ops = @(
            ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
            ZR "$kPolWin\AdvertisingInfo" 'DisabledByGroupPolicy' 1
        )
    }
    @{
        Id = 'priv.tailored'; Cat = 'privacy'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable tailored experiences'
        Desc = 'Stops Microsoft using your diagnostic data to show personalised tips, ads and recommendations.'
        Ops = @( ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 )
    }
    @{
        Id = 'priv.activity'; Cat = 'privacy'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable activity history'
        Desc = 'Stops Windows recording which apps and files you use and uploading that timeline.'
        Ops = @(
            ZR "$kPolWin\System" 'EnableActivityFeed' 0
            ZR "$kPolWin\System" 'PublishUserActivities' 0
            ZR "$kPolWin\System" 'UploadUserActivities' 0
        )
    }
    @{
        Id = 'priv.feedback'; Cat = 'privacy'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Stop feedback requests'
        Desc = 'No more "How likely are you to recommend Windows?" pop-ups.'
        Ops = @(
            ZR 'HKCU\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
            ZR "$kPolWin\DataCollection" 'DoNotShowFeedbackNotifications' 1
        )
    }
    @{
        Id = 'priv.inking'; Cat = 'privacy'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable typing & inking data collection'
        Desc = 'Stops Windows collecting what you type and write to "improve" its dictionary.'
        Ops = @(
            ZR 'HKCU\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
            ZR 'HKCU\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
            ZR 'HKCU\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
            ZR 'HKCU\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
        )
    }
    @{
        Id = 'priv.ceip'; Cat = 'privacy'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Leave the Customer Experience Program'
        Desc = 'Opts out of the Windows Customer Experience Improvement Program.'
        Ops = @( ZR 'HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0 )
    }
    @{
        Id = 'priv.wer'; Cat = 'privacy'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable Windows Error Reporting uploads'
        Desc = 'Stops Windows collecting and uploading crash reports in the background after an app crashes.'
        Ops = @( ZR 'HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1 )
    }
    @{
        Id = 'priv.speech'; Cat = 'privacy'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable online speech recognition'
        Desc = 'Stops voice input being sent to Microsoft cloud speech services.'
        Ops = @( ZR 'HKCU\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0 )
    }

    # ------------------------------------------------------------------ Windows Bloat
    @{
        Id = 'bloat.suggestions'; Cat = 'bloat'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Remove ads & suggestions in Start and Settings'
        Desc = 'Hides "suggested" apps, tips and promotions in the Start menu and the Settings app.'
        Ops = @(
            ZR $kCdm 'SubscribedContent-338388Enabled' 0
            ZR $kCdm 'SubscribedContent-338389Enabled' 0
            ZR $kCdm 'SubscribedContent-338393Enabled' 0
            ZR $kCdm 'SubscribedContent-353694Enabled' 0
            ZR $kCdm 'SubscribedContent-353696Enabled' 0
            ZR $kCdm 'SystemPaneSuggestionsEnabled' 0
            ZR $kAdv 'Start_IrisRecommendations' 0
        )
    }
    @{
        Id = 'bloat.silentapps'; Cat = 'bloat'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Stop sponsored apps installing themselves'
        Desc = 'Stops Windows quietly downloading games like Candy Crush and other promoted apps onto your PC.'
        Ops = @(
            ZR $kCdm 'SilentInstalledAppsEnabled' 0
            ZR $kCdm 'OemPreInstalledAppsEnabled' 0
            ZR $kCdm 'PreInstalledAppsEnabled' 0
            ZR $kCdm 'PreInstalledAppsEverEnabled' 0
        )
    }
    @{
        Id = 'bloat.bing'; Cat = 'bloat'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Remove Bing web results from Start search'
        Desc = 'Start menu search only looks at your PC, so it is faster and does not send what you type to Bing.'
        Ops = @(
            ZR 'HKCU\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
            ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
        )
    }
    @{
        Id = 'bloat.widgets'; Cat = 'bloat'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable Widgets'
        Desc = 'Turns off the Widgets board and its news feed, which keeps several web processes running in the background.'
        Ops = @( ZR 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 )
    }
    @{
        Id = 'bloat.copilot'; Cat = 'bloat'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable Copilot integration'
        Desc = 'Turns off the built-in Copilot integration and hides its taskbar button. (The Copilot app itself can be removed under Bloatware apps.)'
        Ops = @(
            ZR 'HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
            ZR "$kPolWin\WindowsCopilot" 'TurnOffWindowsCopilot' 1
            ZR $kAdv 'ShowCopilotButton' 0
        )
    }
    @{
        Id = 'bloat.lockscreen'; Cat = 'bloat'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Remove lock screen tips & ads'
        Desc = 'Removes the "fun facts", tips and promotions shown on the lock screen.'
        Ops = @(
            ZR $kCdm 'RotatingLockScreenOverlayEnabled' 0
            ZR $kCdm 'SubscribedContent-338387Enabled' 0
        )
    }
    @{
        Id = 'bloat.nags'; Cat = 'bloat'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Stop "Finish setting up your PC" nags'
        Desc = 'Stops the full-screen "Let us finish setting up your device" prompts and account nags after updates.'
        Ops = @(
            ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
            ZR $kCdm 'SubscribedContent-310093Enabled' 0
            ZR $kAdv 'Start_AccountNotifications' 0
        )
    }
    @{
        Id = 'bloat.searchhighlights'; Cat = 'bloat'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable search highlights'
        Desc = 'Removes the daily doodles and trending content from the search box and search panel.'
        Ops = @( ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0 )
    }

    # ------------------------------------------------------------------ Background Services
    @{
        Id = 'svc.diagtrack'; Cat = 'services'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Disable telemetry services'
        Desc = 'Stops "Connected User Experiences and Telemetry" and the WAP push service that feeds it - both run all the time and use CPU and disk.'
        Ops = @(
            ZSvc 'DiagTrack' 'Disabled' -Stop
            ZSvc 'dmwappushservice' 'Disabled' -Stop
        )
    }
    @{
        Id = 'svc.legacy'; Cat = 'services'; Risk = 'safe'; Impact = 'low'; Preset = 'balanced'
        Name = 'Disable legacy & demo services'
        Desc = 'Disables Fax, the in-store Retail Demo, Remote Registry and Windows Media Player network sharing - none are used on a gaming PC.'
        NaReason = 'None of these services exist on this PC'
        Ops = @(
            ZSvc 'Fax' 'Disabled' -Stop
            ZSvc 'RetailDemo' 'Disabled' -Stop
            ZSvc 'RemoteRegistry' 'Disabled' -Stop
            ZSvc 'WMPNetworkSvc' 'Disabled' -Stop
        )
    }
    @{
        Id = 'svc.ondemand'; Cat = 'services'; Risk = 'safe'; Impact = 'medium'; Preset = 'balanced'
        Name = 'Start non-essential services only when needed'
        Desc = 'Switches Maps Manager, Link Tracking, Program Compatibility Assistant and the Edge updater from "always start" to "start on demand". Nothing breaks - they still run when something needs them.'
        Ops = @(
            ZSvc 'MapsBroker' 'Manual' -Stop
            ZSvc 'TrkWks' 'Manual' -Stop
            ZSvc 'PcaSvc' 'Manual' -Stop
            ZSvc 'edgeupdate' 'Manual'
            ZSvc 'edgeupdatem' 'Manual'
        )
    }
    @{
        Id = 'svc.print'; Cat = 'services'; Risk = 'moderate'; Impact = 'low'; Preset = $null
        Name = 'Disable Print Spooler'
        Desc = 'Only if you never print: stops the printing service that runs all the time.'
        Warning = 'Printing and "Microsoft Print to PDF" stop working until you undo this.'
        Ops = @( ZSvc 'Spooler' 'Disabled' -Stop )
    }
    @{
        Id = 'svc.asus'; Cat = 'services'; Risk = 'moderate'; Impact = 'medium'; Preset = $null
        Name = 'ASUS Armoury Crate services on demand'
        Desc = 'Your ROG STRIX G15DK ships with a stack of ASUS services that run 24/7. Setting them to start on demand removes 6-10 background processes.'
        Warning = 'Armoury Crate RGB effects, software fan profiles and update checks may stop until you undo this (fans fall back to your BIOS fan curve).'
        NaReason = 'No ASUS Armoury Crate services found'
        Ops = @(
            ZSvc 'ArmouryCrateService' 'Manual' -Stop
            ZSvc 'AsusAppService' 'Manual' -Stop
            ZSvc 'ASUSOptimization' 'Manual' -Stop
            ZSvc 'ASUSSoftwareManager' 'Manual' -Stop
            ZSvc 'ASUSSwitch' 'Manual' -Stop
            ZSvc 'ASUSSystemAnalysis' 'Manual' -Stop
            ZSvc 'ASUSSystemDiagnosis' 'Manual' -Stop
            ZSvc 'AsusCertService' 'Manual' -Stop
            ZSvc 'ROG Live Service' 'Manual' -Stop
            ZSvc 'GameSDK Service' 'Manual' -Stop
            ZSvc 'AsusUpdateCheck' 'Manual' -Stop
            ZSvc 'asus' 'Manual' -Stop
            ZSvc 'asusm' 'Manual' -Stop
        )
    }

    # ------------------------------------------------------------------ Background Apps
    @{
        Id = 'bg.apps'; Cat = 'background'; Risk = 'moderate'; Impact = 'medium'; Preset = 'performance'
        Name = 'Stop Store apps running in the background'
        Desc = 'Prevents Microsoft Store apps (Mail, Weather, Phone Link...) from running and syncing in the background.'
        Warning = 'Store apps only update and notify while open. Desktop apps like Discord and Steam are not affected.'
        Ops = @(
            ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
            ZR 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
        )
    }
    @{
        Id = 'bg.edge'; Cat = 'background'; Risk = 'safe'; Impact = 'medium'; Preset = 'performance'
        Name = 'Stop Edge running in the background'
        Desc = 'Stops Microsoft Edge pre-loading at sign-in (Startup Boost) and staying alive after you close it - often a dozen hidden msedge.exe processes.'
        Details = 'Edge will show "Your browser is managed by your organization" in its settings afterwards. That only means a policy value is set - it is expected and harmless.'
        Ops = @(
            ZR 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
            ZR 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
        )
    }
    @{
        Id = 'bg.chrome'; Cat = 'background'; Risk = 'safe'; Impact = 'medium'; Preset = 'performance'
        Name = 'Stop Chrome running in the background'
        Desc = 'Stops Google Chrome keeping processes alive after you close its last window.'
        Details = 'Chrome will show "Managed by your organization" afterwards - that only means a policy value is set.'
        NaReason = 'Google Chrome is not installed'
        Build = { if (Find-ZChrome) { ZR 'HKLM\SOFTWARE\Policies\Google\Chrome' 'BackgroundModeEnabled' 0 } }
    }
)

$Global:ZTweakIndex = @{}
foreach ($t in $Global:ZTweaks) { $Global:ZTweakIndex[$t.Id] = $t }

function Get-ZPresetIds {
    param([string]$Preset, [string]$Page)
    $pages = @{}
    foreach ($c in $Global:ZCategories) { $pages[$c.id] = $c.page }
    $ids = @()
    foreach ($t in $Global:ZTweaks) {
        if ($Page -and $pages[$t.Cat] -ne $Page) { continue }
        if ($Preset -eq 'balanced' -and $t.Preset -eq 'balanced') { $ids += $t.Id }
        elseif ($Preset -eq 'performance' -and ($t.Preset -eq 'balanced' -or $t.Preset -eq 'performance')) { $ids += $t.Id }
    }
    return $ids
}
