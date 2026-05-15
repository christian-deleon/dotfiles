<#
.SYNOPSIS
    Windows bootstrap: install Alacritty, JetBrainsMono Nerd Font, and Ubuntu-26.04 in WSL.

.DESCRIPTION
    Run from PowerShell on a fresh Windows machine. Installs Alacritty and
    JetBrainsMono Nerd Font via winget, then runs `wsl --install` for Ubuntu-26.04.
    Safe to run twice — on a system where WSL features were just enabled, Windows
    may need a reboot before the distro install completes; re-running the script
    after the reboot will pick up where it left off.

    After this finishes, launch Ubuntu, finish first-time user setup, then clone
    this repo inside Ubuntu and run ./install.sh.

.NOTES
    See the top-level README.md "Windows bootstrap" section for the GitHub one-liner.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# winget's progress bars emit UTF-8 block characters. Switch the console host
# codepage to UTF-8 (chcp 65001) so they render correctly instead of as mojibake.
# Windows PowerShell 5.1 defaults to a legacy OEM codepage (typically 437/850),
# which is what causes the rûêrûêr garbage. Setting [Console]::OutputEncoding
# alone is not enough — that only affects PowerShell's own writes, not winget's.
$null = & chcp.com 65001
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Winget {
    param(
        [Parameter(Mandatory)] [string]$Id,
        [string]$Label = $Id
    )
    Write-Host "  Installing $Label ($Id)..."
    # Don't pipe winget through Out-Host — the pipeline buffers line-by-line and
    # breaks the in-place spinner/progress bar (each frame ends up on its own line).
    # Letting winget write straight to the console preserves its \r overwrites.
    & winget install --id $Id --exact --silent `
        --accept-package-agreements --accept-source-agreements
    $code = $LASTEXITCODE
    # winget returns 0 on success, -1978335189 (0x8A15002B) if already installed.
    if ($code -ne 0 -and $code -ne -1978335189) {
        Write-Warning "winget install of $Id returned exit code $code (continuing)"
    }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is not installed. Install 'App Installer' from the Microsoft Store and re-run."
    exit 1
}

$rebootHinted = $false

Write-Step "Installing Alacritty"
Invoke-Winget -Id 'Alacritty.Alacritty' -Label 'Alacritty'

Write-Step "Installing JetBrainsMono Nerd Font"
Invoke-Winget -Id 'DEVCOM.JetBrainsMonoNerdFont' -Label 'JetBrainsMono Nerd Font'

Write-Step "Installing Ubuntu-26.04 via WSL"
& wsl --install --distribution Ubuntu-26.04 --no-launch
$wslCode = $LASTEXITCODE
if ($wslCode -ne 0) {
    Write-Host ""
    Write-Host "wsl --install returned exit code $wslCode." -ForegroundColor Yellow
    Write-Host "If WSL features were just enabled, Windows needs a reboot before the distro install can proceed." -ForegroundColor Yellow
    $rebootHinted = $true
}

Write-Step "Done"
Write-Host ""
if ($rebootHinted) {
    Write-Host "Reboot Windows and re-run this script — it is safe to run twice." -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Launch the new Ubuntu app from the Start menu and finish the user setup."
Write-Host "  2. Inside Ubuntu:"
Write-Host "       git clone git@github.com:christian-deleon/dotfiles.git ~/.dotfiles"
Write-Host "       cd ~/.dotfiles && ./install.sh"
Write-Host ""
