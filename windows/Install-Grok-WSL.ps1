# Recommended (simple one-liner - will prompt for distro + username):
#   irm https://raw.githubusercontent.com/christian-deleon/dotfiles/main/windows/Install-Grok-WSL.ps1 | iex
#
# Non-interactive version (with parameters):
#   irm https://raw.githubusercontent.com/christian-deleon/dotfiles/main/windows/Install-Grok-WSL.ps1 -OutFile $env:TEMP\Install-Grok-WSL.ps1; & $env:TEMP\Install-Grok-WSL.ps1 -Distro "Ubuntu-26.04" -WslUsername "your-wsl-user" -IncludeAgent

<# 
.SYNOPSIS
    Download the latest Grok Build Linux (x86_64) binaries from Windows and install them into WSL.

.DESCRIPTION
    Run this script from Windows PowerShell when the WSL side cannot reach the download
    server (e.g. due to firewall or network restrictions).

    It uses the same endpoints as the official Grok CLI installer:
      - https://x.ai/cli/stable          (version pointer)
      - https://x.ai/cli/                (primary CDN)
      - https://storage.googleapis.com/grok-build-public-artifacts/cli/ (fallback)

    The Linux ELF binaries are written directly into the target WSL distro's ~/.local/bin.

    Safe to re-run for updates.

.EXAMPLE
    # Update only the main 'grok' TUI
    .\Install-Grok-WSL.ps1 -Distro "Ubuntu-26.04" -WslUsername "your-wsl-user"

    # Install/update both 'grok' and the headless 'agent' binary
    .\Install-Grok-WSL.ps1 -Distro "Ubuntu-26.04" -WslUsername "your-wsl-user" -IncludeAgent

.NOTES
    Must be run from Windows PowerShell (not inside WSL).
    The Windows side must be able to reach https://x.ai (and the GCS fallback).
    After copying, the script runs `wsl -d <distro> chmod +x` inside the target distro.
#>

[CmdletBinding()]
param(
    [string]$Distro,
    [string]$WslUsername,

    [string]$Channel = "stable",
    [switch]$IncludeAgent,
    [switch]$Force,
    [string]$TargetDir          # Optional: full Windows path (e.g. \\wsl$\...) to override auto-detection
)

# Prompt interactively if values were not passed
if (-not $Distro) {
    $Distro = Read-Host "Enter WSL distro name (e.g. Ubuntu-26.04)"
}
if (-not $WslUsername) {
    $WslUsername = Read-Host "Enter your WSL username"
}

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --- Styling helpers (match style of bootstrap.ps1) ---
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Write-Success {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Yellow
}

# --- WSL target path construction ---
function Get-WslTargetDir {
    param([string]$DistroName, [string]$UserName, [string]$Override)

    if ($Override) {
        return $Override
    }

    $candidates = @(
        "\\wsl$\$DistroName\home\$UserName\.local\bin",
        "\\wsl.localhost\$DistroName\home\$UserName\.local\bin"
    )

    foreach ($path in $candidates) {
        try {
            $null = New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop
            return $path
        } catch {
            # Try the next candidate
        }
    }

    throw "Could not create target directory in WSL distro '$DistroName'. Tried: $($candidates -join ', ')"
}

# --- Download helpers (inspired by the official install.ps1) ---
function Get-LatestVersion {
    param([string]$BaseUrl, [string]$Chan)

    $url = "$BaseUrl/$Chan"
    try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        return $resp.Content.Trim()
    } catch {
        return $null
    }
}

function Download-GrokBinary {
    param(
        [string]$Version,
        [string]$Component,   # "grok" or "agent"
        [string]$OutFile
    )

    $bases = @(
        'https://x.ai/cli',
        'https://storage.googleapis.com/grok-build-public-artifacts/cli'
    )

    $arch = 'linux-x86_64'
    $artifact = "$Component-$Version-$arch"

    foreach ($base in $bases) {
        $urls = @(
            "$base/$artifact",           # raw binary (no extension)
            "$base/$artifact.exe"        # some older artifacts had this
        )

        foreach ($url in $urls) {
            try {
                Write-Info "Trying $url"
                Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
                if ((Get-Item $OutFile).Length -gt 50MB) {
                    return $true
                } else {
                    Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
                }
            } catch {
                # Try next URL
            }
        }
    }
    return $false
}

# --- Main ---
Write-Step "Resolving latest Grok Build version for channel '$Channel'"

$version = $null
$primaryBase = 'https://x.ai/cli'

$version = Get-LatestVersion -BaseUrl $primaryBase -Chan $Channel
if (-not $version) {
    Write-Warn "Primary CDN unreachable, trying GCS fallback..."
    $version = Get-LatestVersion -BaseUrl 'https://storage.googleapis.com/grok-build-public-artifacts/cli' -Chan $Channel
}

if (-not $version) {
    throw "Failed to determine latest version from both CDNs."
}

Write-Success "Latest version: $version"

$targetDir = Get-WslTargetDir -DistroName $Distro -UserName $WslUsername -Override $TargetDir
Write-Info "Target directory: $targetDir"

New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

$components = @('grok')
if ($IncludeAgent) { $components += 'agent' }

$successCount = 0

foreach ($component in $components) {
    $outFile = Join-Path $targetDir $component
    Write-Step "Downloading $component $version (linux-x86_64)"

    $ok = Download-GrokBinary -Version $version -Component $component -OutFile $outFile

    if ($ok) {
        Write-Success "Downloaded $component -> $outFile ($( [math]::Round((Get-Item $outFile).Length / 1MB, 1) ) MB)"
        $successCount++
    } else {
        Write-Warn "Failed to download $component $version"
    }
}

if ($successCount -eq 0) {
    throw "No binaries were downloaded successfully."
}

# Make the binaries executable inside WSL
Write-Step "Fixing permissions inside WSL ($Distro)"

$chmodCmd = "chmod +x " + ($components | ForEach-Object { "/home/$WslUsername/.local/bin/$_" }) -join ' '
try {
    wsl -d $Distro -u $WslUsername -e bash -c $chmodCmd
    Write-Success "Permissions updated"
} catch {
    Write-Warn "Could not run chmod inside WSL. Run this manually once inside WSL:"
    Write-Host "    chmod +x ~/.local/bin/grok" -ForegroundColor Yellow
    if ($IncludeAgent) {
        Write-Host "    chmod +x ~/.local/bin/agent" -ForegroundColor Yellow
    }
}

Write-Step "Done"
Write-Host ""
Write-Host "Installed into WSL:" -ForegroundColor Green
foreach ($c in $components) {
    Write-Host "  $targetDir\$c" -ForegroundColor White
}
Write-Host ""
Write-Host "Inside WSL you can now run:" -ForegroundColor DarkGray
Write-Host "    grok --version" -ForegroundColor White
if ($IncludeAgent) {
    Write-Host "    agent --help" -ForegroundColor White
}
Write-Host ""
Write-Host "To update in the future, just re-run this script (with -IncludeAgent if you want the agent binary)." -ForegroundColor DarkGray
Write-Host ""
