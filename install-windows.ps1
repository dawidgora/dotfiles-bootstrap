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

function Ensure-PersistentProfileExecutionPolicy {
    [CmdletBinding()]
    param(
        [scriptblock]$GetPolicyList = { Get-ExecutionPolicy -List },
        [scriptblock]$GetDefaultPolicy = {
            $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            if ($operatingSystem.ProductType -eq 1) { 'Restricted' } else { 'RemoteSigned' }
        },
        [scriptblock]$Prompt = { param($Message) Read-Host $Message },
        [scriptblock]$SetPolicy = {
            param($ExecutionPolicy, $Scope)
            Set-ExecutionPolicy -ExecutionPolicy $ExecutionPolicy -Scope $Scope -Force
        }
    )

    $policyValues = @{}
    foreach ($entry in @(& $GetPolicyList)) {
        $policyValues[[string]$entry.Scope] = [string]$entry.ExecutionPolicy
    }
    foreach ($scope in @('MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine')) {
        if (-not $policyValues.ContainsKey($scope) -or [string]::IsNullOrWhiteSpace($policyValues[$scope])) {
            $policyValues[$scope] = 'Undefined'
        }
    }

    $governedScope = $null
    $governedPolicy = $null
    if ($policyValues.MachinePolicy -ne 'Undefined') {
        $governedScope = 'MachinePolicy'
        $governedPolicy = $policyValues.MachinePolicy
    } elseif ($policyValues.UserPolicy -ne 'Undefined') {
        $governedScope = 'UserPolicy'
        $governedPolicy = $policyValues.UserPolicy
    }

    if ($null -ne $governedScope) {
        if ($governedPolicy -in @('Restricted', 'AllSigned')) {
            Write-Warning "Execution policy $governedPolicy is enforced by $governedScope. Unsigned local managed profiles may not load. Ask your administrator to review the policy; bootstrap will not override it."
            return $false
        }
        if ($governedPolicy -in @('RemoteSigned', 'Unrestricted', 'Bypass')) {
            return $true
        }
        Write-Warning "Execution policy $governedPolicy is enforced by $governedScope and was not recognized. Bootstrap will not change execution policy."
        return $false
    }

    if ($policyValues.CurrentUser -ne 'Undefined') {
        $persistentPolicy = $policyValues.CurrentUser
        $persistentScope = 'CurrentUser'
    } elseif ($policyValues.LocalMachine -ne 'Undefined') {
        $persistentPolicy = $policyValues.LocalMachine
        $persistentScope = 'LocalMachine'
    } else {
        try {
            $persistentPolicy = [string](& $GetDefaultPolicy)
        } catch {
            Write-Warning "Could not determine the Windows default execution policy: $($_.Exception.Message)"
            return $false
        }
        $persistentScope = 'Windows default'
    }

    if ($persistentPolicy -in @('RemoteSigned', 'Unrestricted', 'Bypass')) {
        return $true
    }
    if ($persistentPolicy -notin @('Restricted', 'AllSigned')) {
        Write-Warning "Persistent execution policy $persistentPolicy at $persistentScope was not recognized. Bootstrap will not change execution policy."
        return $false
    }

    $message = "Persistent execution policy is $persistentPolicy at $persistentScope. Set only CurrentUser to RemoteSigned so unsigned local managed profiles can load? [y/N]"
    $response = [string](& $Prompt $message)
    if ($response -notin @('y', 'Y', 'yes', 'YES', 'Yes')) {
        Write-Warning 'Execution policy was not changed. New PowerShell sessions may block unsigned managed profiles and token loading. Rerun bootstrap and consent, or ask your administrator for help.'
        return $false
    }

    try {
        [void](& $SetPolicy 'RemoteSigned' 'CurrentUser')
    } catch {
        Write-Warning "Could not set CurrentUser execution policy to RemoteSigned: $($_.Exception.Message)"
        return $false
    }

    $verifiedPolicies = @{}
    try {
        foreach ($entry in @(& $GetPolicyList)) {
            $verifiedPolicies[[string]$entry.Scope] = [string]$entry.ExecutionPolicy
        }
    } catch {
        Write-Warning "Could not verify the persistent execution policy after the change: $($_.Exception.Message)"
        return $false
    }
    $verifiedMachinePolicy = [string]$verifiedPolicies.MachinePolicy
    $verifiedUserPolicy = [string]$verifiedPolicies.UserPolicy
    $verifiedCurrentUser = [string]$verifiedPolicies.CurrentUser
    if ([string]::IsNullOrWhiteSpace($verifiedMachinePolicy)) { $verifiedMachinePolicy = 'Undefined' }
    if ([string]::IsNullOrWhiteSpace($verifiedUserPolicy)) { $verifiedUserPolicy = 'Undefined' }
    $verifiedGoverningPolicy = $verifiedMachinePolicy
    if ($verifiedGoverningPolicy -eq 'Undefined') { $verifiedGoverningPolicy = $verifiedUserPolicy }
    if ($verifiedCurrentUser -ne 'RemoteSigned' -or $verifiedGoverningPolicy -in @('Restricted', 'AllSigned')) {
        Write-Warning 'CurrentUser RemoteSigned did not become the effective persistent policy. A managed policy may take precedence; ask your administrator to review it.'
        return $false
    }
    return $true
}

$profilePolicyReady = Ensure-PersistentProfileExecutionPolicy

function Get-MergedPathEntries {
    param(
        [AllowNull()][string]$MachinePath,
        [AllowNull()][string]$UserPath,
        [AllowNull()][string]$ProcessPath,
        [string[]]$PathHints = @()
    )

    $seen = @{}
    $entries = @(
        @($MachinePath, $UserPath, $ProcessPath) + $PathHints |
            ForEach-Object { $_ -split ';' } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    foreach ($entry in $entries) {
        if (-not $seen.ContainsKey($entry)) {
            $seen[$entry] = $true
            $entry
        }
    }
}

function Update-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathHints = @(
        (Join-Path $env:ProgramFiles 'PowerShell\7'),
        (Join-Path $env:ProgramFiles 'Git\cmd'),
        # WinGet exposes portable package command links, including op.exe, here.
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }

    $userEntries = @($userPath -split ';' | Where-Object { $_ })
    $knownEntries = @{}
    foreach ($entry in @($machinePath -split ';') + $userEntries) {
        if ($entry) { $knownEntries[$entry] = $true }
    }
    foreach ($directory in $pathHints) {
        if (-not $knownEntries.ContainsKey($directory)) {
            $userEntries += $directory
            $knownEntries[$directory] = $true
        }
    }
    $updatedUserPath = $userEntries -join ';'
    if ($userEntries.Count -gt 0 -and $updatedUserPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable('Path', $updatedUserPath, 'User')
        $userPath = $updatedUserPath
    }

    $env:Path = (Get-MergedPathEntries -MachinePath $machinePath -UserPath $userPath -ProcessPath $env:Path -PathHints $pathHints) -join ';'
}

Update-ProcessPath

foreach ($package in @(
    @{ Id = 'Microsoft.PowerShell'; Name = 'PowerShell 7'; Command = 'pwsh.exe' },
    @{ Id = 'Git.Git'; Name = 'Git'; Command = 'git.exe' },
    @{ Id = 'twpayne.chezmoi'; Name = 'chezmoi'; Command = 'chezmoi.exe' },
    @{ Id = 'AgileBits.1Password.CLI'; Name = '1Password CLI'; Command = 'op.exe' }
)) {
    if (-not (Get-Command $package.Command -ErrorAction SilentlyContinue)) {
        Write-Host "Installing $($package.Name)..."
        & $winget.Source install --id $package.Id --exact --source winget --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget could not install $($package.Name). Exit code: $LASTEXITCODE"
        }
        Update-ProcessPath
    }
}

foreach ($command in @('git.exe', 'chezmoi.exe', 'op.exe')) {
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

function Set-OpServiceAccountTokenForProcess {
    [CmdletBinding()]
    param([scriptblock]$Prompt = { Read-Host '1Password service account token (leave empty to skip)' -AsSecureString })

    if (-not [string]::IsNullOrWhiteSpace($env:OP_SERVICE_ACCOUNT_TOKEN)) {
        Write-Host 'Using the inherited 1Password token for this bootstrap process.'
        return $true
    }

    $secureToken = & $Prompt
    if ($null -eq $secureToken -or $secureToken.Length -eq 0) {
        if ($null -ne $secureToken) { $secureToken.Dispose() }
        Write-Warning 'No 1Password token was provided. Secret-dependent configurations need authentication before review or apply.'
        return $false
    }

    $tokenPointer = [IntPtr]::Zero
    try {
        $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
        if ([string]::IsNullOrWhiteSpace($token)) {
            Write-Warning 'No 1Password token was provided. Secret-dependent configurations need authentication before review or apply.'
            return $false
        }
        $env:OP_SERVICE_ACCOUNT_TOKEN = $token
        return $true
    } finally {
        if ($tokenPointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
        }
        $secureToken.Dispose()
    }
}

$tokenHelper = Join-Path $target '.chezmoitemplates\windows-op-token.ps1'
$hasTokenHelper = Test-Path -LiteralPath $tokenHelper -PathType Leaf
if ($hasTokenHelper) {
    Write-Host 'Using the dotfiles source 1Password token helper.'
    & $tokenHelper -Setup
} else {
    Write-Warning 'This dotfiles source has no Windows token helper. Token storage will remain process-only until the source is updated.'
    [void](Set-OpServiceAccountTokenForProcess)
}
$hasOpToken = -not [string]::IsNullOrWhiteSpace($env:OP_SERVICE_ACCOUNT_TOKEN)

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

Write-Host 'Bootstrap prerequisites and source setup are complete.'
Write-Host 'No dotfiles or selected packages have been applied.'
if ($hasOpToken) {
    if ($hasTokenHelper) {
        Write-Host 'The token is available in this process. Continue review here; the parent PowerShell process is unchanged.'
    } else {
        Write-Host 'The 1Password token is process-only and was not saved. Continue review here; the parent PowerShell process is unchanged.'
    }
} else {
    Write-Host 'Secret-dependent configurations need authentication before review or apply. Rerun this bootstrap to provide or reload the token.'
}
if (-not $profilePolicyReady) {
    Write-Host 'New PowerShell sessions may not load the token helper or managed profiles until execution policy permits unsigned local scripts.'
}
Write-Host 'The documented -NoExit command keeps this process open. Without -NoExit, its process token ends when the process exits.'
Write-Host 'Next steps:'
Write-Host '  1. Configure features before the first apply: chezmoi edit-config'
Write-Host '  2. Review config changes: chezmoi diff --skip-secrets'
Write-Host '  3. Review dotfiles package scripts separately. The diff is not a package plan.'
Write-Host '  4. Apply only after reviewing both: chezmoi apply'
Write-Host '  5. Open a fresh PowerShell or SSH session to use updated PATH entries.'
