<#
.SYNOPSIS
    Installs and enables in Claude Code the mods in the repository's mods/ folder.

.DESCRIPTION
    Copies each mod to ~/.claude/mods/<name> and adds it to env.CLAUDE_CODE_PLUGIN_DIRS
    in ~/.claude/settings.json, keeping the rest of the configuration.
    Works with Windows PowerShell 5.1 and with PowerShell 7 on Windows, Linux and macOS.

.PARAMETER Target
    local (default): Claude on this system.
    windows: Claude on Windows. wsl: Claude on WSL (from Windows).
    both: Windows and WSL at once (from Windows).

.PARAMETER Distro
    WSL distribution for -Target wsl or both. Defaults to the default distribution.

.PARAMETER List
    Lists the repository mods and their status.

.PARAMETER Uninstall
    Disables and removes the given mods (with no names, every repository mod).

.EXAMPLE
    .\install.ps1
    .\install.ps1 faf-usage-meter -Target both
    .\install.ps1 -List
    .\install.ps1 -Uninstall faf-usage-meter
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Target = 'local',
    [string]$Distro,
    [switch]$List,
    [switch]$Uninstall,
    # Uso interno: llamada desde install.sh, que ya muestra el aviso final
    [switch]$Nested,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Mods
)
$ErrorActionPreference = 'Stop'
# Salida por tubería (install.sh, Git Bash): UTF-8 para que lleguen bien los acentos
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false }

function Fail([string]$Message) {
    Write-Host "Error: $Message" -ForegroundColor Red
    exit 1
}

if (@('local', 'windows', 'wsl', 'both') -notcontains $Target) { Fail "invalid target: $Target (local, windows, wsl or both)" }

$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$ModsSrc = Join-Path (Split-Path $PSScriptRoot -Parent) 'mods'
$Action = 'install'
if ($List) { $Action = 'list' }
if ($Uninstall) { $Action = 'uninstall' }

# Destinos de esta ejecución
$DoLocal = $false
$DoWsl = $false
switch ($Target) {
    'local' { $DoLocal = $true }
    'windows' {
        if (-not $OnWindows) { Fail '-Target windows only works on Windows; from WSL use install.sh --target windows' }
        $DoLocal = $true
    }
    'wsl' {
        if (-not $OnWindows) { Fail '-Target wsl only works on Windows; from WSL use install.sh' }
        $DoWsl = $true
    }
    'both' {
        if (-not $OnWindows) { Fail '-Target both only works on Windows; from WSL use install.sh --target both' }
        $DoLocal = $true
        $DoWsl = $true
    }
}

# Mods disponibles: subcarpetas de mods/ con .claude-plugin/plugin.json
$Available = @(Get-ChildItem -Directory $ModsSrc |
    Where-Object { Test-Path (Join-Path $_.FullName '.claude-plugin/plugin.json') } |
    ForEach-Object { $_.Name })
if ($Available.Count -eq 0) { Fail "no mods found in $ModsSrc" }
if (-not $Mods -or $Mods.Count -eq 0) {
    $Mods = $Available
} else {
    foreach ($m in $Mods) {
        if ($Available -notcontains $m) { Fail "mod '$m' not found in $ModsSrc (available: $($Available -join ', '))" }
    }
}

# Comprobaciones previas, para no dejar nada a medias
$WslArgs = @()
$WslDir = $null
if ($DoWsl) {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { Fail 'wsl.exe not found; is WSL installed?' }
    # Repositorio dentro de WSL (\\wsl.localhost\<distro>\...): se usa su ruta Linux
    $WslDir = $PSScriptRoot
    if ($PSScriptRoot -match '^\\\\wsl(\.localhost|\$)\\([^\\]+)(\\.*)?$') {
        if (-not $Distro) { $Distro = $Matches[2] }
        $WslDir = ($Matches[3] -replace '\\', '/')
        if (-not $WslDir) { $WslDir = '/' }
    }
    if ($Distro) { $WslArgs += @('-d', $Distro) }
    & wsl.exe @WslArgs --cd $WslDir -e test -f ./install.sh | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "cannot run install.sh in WSL$(if ($Distro) { " ($Distro)" })" }
}

function Get-HomeDir {
    if ($OnWindows) { return $env:USERPROFILE }
    return $HOME
}

function Get-ModRef([string]$Name, [string]$ClaudeDir, [bool]$UseTilde) {
    if ($UseTilde) { return "~/.claude/mods/$Name" }
    return (Join-Path (Join-Path $ClaudeDir 'mods') $Name)
}

function Get-NormalizedPath([string]$Path) {
    if ($Path -eq '~' -or $Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        $Path = (Get-HomeDir) + $Path.Substring(1)
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    if ($OnWindows) { return $full.Replace('/', '\').ToLowerInvariant() }
    return $full
}

function Read-Settings([string]$Path) {
    if (Test-Path $Path) {
        $raw = [IO.File]::ReadAllText($Path)
        if ($raw.Trim()) { return ($raw | ConvertFrom-Json) }
    }
    return [pscustomobject]@{}
}

function Write-Settings([string]$Path, $Cfg) {
    $json = $Cfg | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json + "`n", (New-Object Text.UTF8Encoding $false))
}

function Invoke-Local {
    $sep = if ($OnWindows) { ';' } else { ':' }
    $useTilde = -not $env:CLAUDE_CONFIG_DIR
    $claudeDir = if ($useTilde) { Join-Path (Get-HomeDir) '.claude' } else { $env:CLAUDE_CONFIG_DIR }
    $settings = Join-Path $claudeDir 'settings.json'
    $label = if ($OnWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' }

    Write-Host "== ${label}: $claudeDir"
    $cfg = Read-Settings $settings
    $current = ''
    if ($cfg.PSObject.Properties['env'] -and $cfg.env.PSObject.Properties['CLAUDE_CODE_PLUGIN_DIRS']) {
        $current = [string]$cfg.env.CLAUDE_CODE_PLUGIN_DIRS
    }
    $dirs = @($current -split [regex]::Escape($sep) | Where-Object { $_ })

    if ($Action -eq 'list') {
        $active = @($dirs | ForEach-Object { Get-NormalizedPath $_ })
        foreach ($m in $Mods) {
            $meta = [IO.File]::ReadAllText((Join-Path $ModsSrc "$m/.claude-plugin/plugin.json")) | ConvertFrom-Json
            $installed = Test-Path (Join-Path $claudeDir "mods/$m")
            $isActive = $active -contains (Get-NormalizedPath (Get-ModRef $m $claudeDir $useTilde))
            $state = if ($installed -and $isActive) { 'installed, enabled' } elseif ($installed) { 'installed, disabled' } else { 'not installed' }
            Write-Host ('  {0,-20} {1,-8} {2,-22} {3}' -f $m, $meta.version, $state, $meta.description)
        }
        return
    }

    New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
    if (Test-Path $settings) {
        $backupDir = Join-Path $claudeDir 'backups'
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $backup = Join-Path $backupDir ('settings.json.claude-mods.' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Copy-Item $settings $backup
        Write-Host "  settings.json backed up to $backup"
    }

    $modsDir = Join-Path $claudeDir 'mods'
    foreach ($m in $Mods) {
        $dest = Join-Path $modsDir $m
        # Los tipos que genera Claude Code para desarrollar el mod se conservan al reinstalar
        $types = Join-Path $dest '.claude-plugin/types'
        $keep = $null
        if ($Action -eq 'install' -and (Test-Path $types)) {
            $keep = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            Move-Item $types $keep
        }
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        if ($Action -eq 'install') {
            New-Item -ItemType Directory -Force -Path $modsDir | Out-Null
            Copy-Item -Recurse (Join-Path $ModsSrc $m) $dest
            if ($keep) { Move-Item $keep $types }
            Write-Host "  installed: $m"
        } else {
            Write-Host "  uninstalled: $m"
        }
    }

    $targets = @($Mods | ForEach-Object { Get-NormalizedPath (Get-ModRef $_ $claudeDir $useTilde) })
    $dirs = @($dirs | Where-Object { $targets -notcontains (Get-NormalizedPath $_) })
    if ($Action -eq 'install') {
        $dirs += @($Mods | ForEach-Object { Get-ModRef $_ $claudeDir $useTilde })
    }

    if (-not $cfg.PSObject.Properties['env']) {
        $cfg | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{})
    }
    if ($dirs.Count -gt 0) {
        $cfg.env | Add-Member -Force -NotePropertyName CLAUDE_CODE_PLUGIN_DIRS -NotePropertyValue ($dirs -join $sep)
    } else {
        $cfg.env.PSObject.Properties.Remove('CLAUDE_CODE_PLUGIN_DIRS')
    }
    if (@($cfg.env.PSObject.Properties).Count -eq 0) { $cfg.PSObject.Properties.Remove('env') }
    Write-Settings $settings $cfg
}

function Invoke-Wsl {
    $shArgs = @('--target', 'local', '--nested')
    if ($Action -eq 'list') { $shArgs += '--list' }
    if ($Action -eq 'uninstall') { $shArgs += '--uninstall' }
    $shArgs += $Mods
    & wsl.exe @WslArgs --cd $WslDir -e bash ./install.sh @shArgs
    if ($LASTEXITCODE -ne 0) { Fail 'the operation on WSL failed' }
}

if ($DoLocal) { Invoke-Local }
if ($DoWsl) { Invoke-Wsl }

if ($Action -ne 'list' -and -not $Nested) {
    Write-Host ''
    Write-Host 'Restart Claude Code to apply the changes.'
}
