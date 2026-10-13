[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Source = 'https://github.com/dawidgora/dotfiles.git',

    [ValidateNotNullOrEmpty()]
    [string]$SourcePath = (Join-Path $HOME '.local\share\chezmoi'),

    [string]$SourceRef = ''
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Run this script on Windows.'
}

$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $winget) {
    throw 'winget is required. Install App Installer, then run this script again.'
}

foreach ($package in @(
    @{ Id = 'Microsoft.PowerShell'; Name = 'PowerShell 7'; Command = 'pwsh.exe' },
    @{ Id = 'Git.Git'; Name = 'Git'; Command = 'git.exe' },
    @{ Id = 'twpayne.chezmoi'; Name = 'chezmoi'; Command = 'chezmoi.exe' }
)) {
    if (-not (Get-Command $package.Command -ErrorAction SilentlyContinue)) {
        Write-Host "Installing $($package.Name)..."
        & $winget.Source install --id $package.Id --exact --source winget --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget could not install $($package.Name). Exit code: $LASTEXITCODE"
        }
    }
}

$pathHints = @(
    (Join-Path $env:ProgramFiles 'PowerShell\7'),
    (Join-Path $env:ProgramFiles 'Git\cmd'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userEntries = @($userPath -split ';' | Where-Object { $_ })
$knownEntries = @($machinePath -split ';') + $userEntries
foreach ($directory in $pathHints) {
    if ($knownEntries -notcontains $directory) {
        $userEntries += $directory
        $knownEntries += $directory
    }
}
if ($userEntries.Count -gt 0 -and ($userEntries -join ';') -ne $userPath) {
    [Environment]::SetEnvironmentVariable('Path', ($userEntries -join ';'), 'User')
}
$env:Path = (@($env:Path -split ';') + $pathHints | Select-Object -Unique) -join ';'

foreach ($command in @('git.exe', 'chezmoi.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "$command is not available. Open a new PowerShell session and rerun this script."
    }
}

$target = [IO.Path]::GetFullPath($SourcePath)
$clone = $false
if (Test-Path -LiteralPath $target) {
    if (Test-Path -LiteralPath (Join-Path $target '.git')) {
        if (-not (Test-Path -LiteralPath (Join-Path $target '.chezmoi.yaml.tmpl') -PathType Leaf)) {
            throw "Existing Git checkout is not the expected chezmoi source: $target"
        }
    } else {
        if (@(Get-ChildItem -LiteralPath $target -Force).Count -gt 0) {
            throw "Refusing to use a non-empty directory without Git metadata: $target"
        }
        $clone = $true
    }
} else {
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
    $clone = $true
}

if ($clone) {
    $cloneArgs = @('clone')
    if ($SourceRef) { $cloneArgs += @('--branch', $SourceRef) }
    $cloneArgs += @($Source, $target)
    & git.exe @cloneArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Git could not clone the source into $target. Exit code: $LASTEXITCODE"
    }
}

if ($SourceRef) {
    $currentRef = (& git.exe -C $target branch --show-current | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentRef -ne $SourceRef) {
        throw "Existing checkout is on '$currentRef', not '$SourceRef'. Switch branches in $target before rerunning."
    }
}

$configDirectories = @((Join-Path $HOME '.config\chezmoi'))
if ($env:XDG_CONFIG_HOME) {
    $configDirectories += Join-Path $env:XDG_CONFIG_HOME 'chezmoi'
}
if ($env:APPDATA) {
    $configDirectories += Join-Path $env:APPDATA 'chezmoi'
}
$configNames = @('chezmoi.yaml', 'chezmoi.yml', 'chezmoi.toml', 'chezmoi.json', 'chezmoi.jsonc')
$configExists = $false
foreach ($directory in $configDirectories) {
    foreach ($name in $configNames) {
        if (Test-Path -LiteralPath (Join-Path $directory $name) -PathType Leaf) {
            $configExists = $true
            break
        }
    }
    if ($configExists) { break }
}

if (-not $configExists) {
    & chezmoi.exe init --source $target
    if ($LASTEXITCODE -ne 0) { throw "chezmoi init failed. Exit code: $LASTEXITCODE" }
} else {
    Write-Host 'Keeping the existing chezmoi configuration.'
}

& chezmoi.exe --source $target apply
if ($LASTEXITCODE -ne 0) { throw "chezmoi apply failed. Exit code: $LASTEXITCODE" }

Write-Host 'Bootstrap complete. Open a fresh PowerShell or SSH session to use the updated User PATH.'
