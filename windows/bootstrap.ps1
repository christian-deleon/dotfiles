<#
.SYNOPSIS
    Windows bootstrap: install Alacritty, JetBrainsMono Nerd Font, and Ubuntu-26.04 in WSL.

.DESCRIPTION
    Run from PowerShell on a fresh Windows machine. Installs Alacritty and
    JetBrainsMono Nerd Font via winget, then installs Ubuntu-26.04 via WSL.

    WSL setup is two-phase with a readiness probe (wsl --status):
      - If WSL is already ready, jumps straight to the distro install.
      - Otherwise enables WSL features (wsl --install --no-distribution) first,
        then re-probes. If the probe still fails, features were just enabled and
        Windows needs a reboot — the script prints a clear message and stops
        before wasting the distro download.

    Safe to run twice — winget steps no-op on already-installed packages, and
    the WSL phase resumes correctly after a reboot.

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

function Test-WslReady {
    # Probe WSL readiness. `wsl --status` returns 0 only when the WSL service
    # can actually start, which requires both the WSL feature and VM Platform to
    # be active. On a system where features were just enabled but Windows hasn't
    # rebooted yet, the service can't start and this returns non-zero.
    try {
        $null = & wsl.exe --status 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is not installed. Install 'App Installer' from the Microsoft Store and re-run."
    return
}

Write-Step "Installing Alacritty"
Invoke-Winget -Id 'Alacritty.Alacritty' -Label 'Alacritty'

Write-Step "Installing JetBrainsMono Nerd Font"
Invoke-Winget -Id 'DEVCOM.JetBrainsMonoNerdFont' -Label 'JetBrainsMono Nerd Font'

Write-Step "Writing Alacritty config"
$alacrittyDir = Join-Path $env:APPDATA 'alacritty'
$alacrittyDst = Join-Path $alacrittyDir 'alacritty.toml'
$alacrittyUrl = 'https://raw.githubusercontent.com/christian-deleon/dotfiles/refs/heads/main/windows/alacritty.toml'
if (-not (Test-Path $alacrittyDir)) {
    New-Item -ItemType Directory -Path $alacrittyDir | Out-Null
}
Invoke-WebRequest -Uri $alacrittyUrl -OutFile $alacrittyDst -UseBasicParsing
Write-Host "  Wrote $alacrittyDst"

$rebootRequired = $false
$distroInstalled = $false

Write-Step "Checking WSL readiness"
if (Test-WslReady) {
    Write-Host "  WSL is ready — skipping feature enable."
} else {
    Write-Host "  WSL not ready — enabling features (wsl --install --no-distribution)..."
    & wsl --install --no-distribution
    if (-not (Test-WslReady)) {
        $rebootRequired = $true
    }
}

if (-not $rebootRequired) {
    Write-Step "Installing Ubuntu-26.04 via WSL"
    & wsl --install --distribution Ubuntu-26.04 --no-launch
    $distroInstalled = ($LASTEXITCODE -eq 0)
}

Write-Step "Done"
Write-Host ""
if ($rebootRequired) {
    Write-Host "WSL features have been enabled, but Windows needs a reboot to activate them." -ForegroundColor Yellow
    Write-Host "Reboot Windows, then re-run this script:" -ForegroundColor Yellow
    Write-Host "  irm https://raw.githubusercontent.com/christian-deleon/dotfiles/refs/heads/main/windows/bootstrap.ps1 | iex" -ForegroundColor Cyan
    Write-Host ""
} elseif (-not $distroInstalled) {
    Write-Host "Ubuntu-26.04 install did not complete cleanly." -ForegroundColor Yellow
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "  - Hardware virtualization (VT-x/AMD-V) is disabled in BIOS/UEFI." -ForegroundColor Yellow
    Write-Host "  - WSL features were just enabled and Windows still needs a reboot." -ForegroundColor Yellow
    Write-Host "Fix the cause, then re-run this script." -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "Next steps:" -ForegroundColor Green
    Write-Host "  1. Launch the new Ubuntu app from the Start menu and finish the user setup."
    Write-Host "  2. Inside Ubuntu:"
    Write-Host "       git clone git@github.com:christian-deleon/dotfiles.git ~/.dotfiles"
    Write-Host "       cd ~/.dotfiles && ./install.sh"
    Write-Host ""
}
