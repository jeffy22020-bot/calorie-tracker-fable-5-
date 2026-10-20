# Zenith (Claude PC Tweaks) - short address for the installer. Paste into PowerShell:
#   irm https://raw.githubusercontent.com/jeffy22020-bot/calorie-tracker-fable-5-/HEAD/install.ps1 | iex
# The installer itself is "Zenith (Claude PC Tweaks)/install.ps1"; read it there before running if you like.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/jeffy22020-bot/calorie-tracker-fable-5-/HEAD/Zenith%20(Claude%20PC%20Tweaks)/install.ps1' -UseBasicParsing | Invoke-Expression
