$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'install-windows.ps1'
$readmePath = Join-Path $repoRoot 'README.md'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "PowerShell parse errors: $($parseErrors -join '; ')"
}

foreach ($functionName in @('Get-MergedPathEntries', 'Set-OpServiceAccountTokenForProcess', 'Ensure-PersistentProfileExecutionPolicy')) {
    $functionAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
    }, $true) | Select-Object -First 1
    if (-not $functionAst) { throw "Missing function: $functionName" }
    Invoke-Expression $functionAst.Extent.Text
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) { throw "$Message. Expected '$Expected', got '$Actual'." }
}

function New-TestPolicyList {
    param(
        [string]$MachinePolicy = 'Undefined',
        [string]$UserPolicy = 'Undefined',
        [string]$CurrentUser = 'Undefined',
        [string]$LocalMachine = 'Undefined'
    )
    @(
        [pscustomobject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = $MachinePolicy },
        [pscustomobject]@{ Scope = 'UserPolicy'; ExecutionPolicy = $UserPolicy },
        [pscustomobject]@{ Scope = 'CurrentUser'; ExecutionPolicy = $CurrentUser },
        [pscustomobject]@{ Scope = 'LocalMachine'; ExecutionPolicy = $LocalMachine }
    )
}

function Invoke-PolicyPreflightCase {
    param(
        [object[]]$Policies,
        [string]$Consent = 'no',
        [string]$DefaultPolicy = 'Restricted'
    )

    $state = @{
        Policies = $Policies
        Consent = $Consent
        DefaultPolicy = $DefaultPolicy
        ReadCalls = 0
        PromptCalls = 0
        SetCalls = 0
        SetScope = ''
        SetPolicy = ''
    }
    $getPolicyList = { $state.ReadCalls++; @($state.Policies) }.GetNewClosure()
    $getDefaultPolicy = { $state.DefaultPolicy }.GetNewClosure()
    $prompt = { param($Message) $state.PromptCalls++; $state.Consent }.GetNewClosure()
    $setPolicy = {
        param($ExecutionPolicy, $Scope)
        $state.SetCalls++
        $state.SetScope = $Scope
        $state.SetPolicy = $ExecutionPolicy
        $updatedPolicies = @()
        foreach ($entry in $state.Policies) {
            if ($entry.Scope -eq 'CurrentUser') {
                $updatedPolicies += [pscustomobject]@{ Scope = 'CurrentUser'; ExecutionPolicy = $ExecutionPolicy }
            } else {
                $updatedPolicies += $entry
            }
        }
        $state.Policies = $updatedPolicies
    }.GetNewClosure()
    $warnings = @()
    $ready = Ensure-PersistentProfileExecutionPolicy -GetPolicyList $getPolicyList -GetDefaultPolicy $getDefaultPolicy -Prompt $prompt -SetPolicy $setPolicy -WarningVariable warnings
    [pscustomobject]@{ Ready = $ready; State = $state; Warnings = $warnings }
}

$merged = @(Get-MergedPathEntries -MachinePath 'C:\Machine' -UserPath 'C:\User' -ProcessPath 'C:\Old;C:\machine' -PathHints @('C:\Hint'))
Assert-Equal ($merged -join ';') 'C:\Machine;C:\User;C:\Old;C:\Hint' 'PATH refresh must include persisted Machine/User entries, process PATH, and hints without case-insensitive duplicates'
$emptyPath = @(Get-MergedPathEntries -MachinePath '' -UserPath $null -ProcessPath '' -PathHints @())
Assert-Equal $emptyPath.Count 0 'Empty PATH inputs must remain empty'

# Model an install that adds a command directory to persisted PATH after the
# process PATH was created. The refreshed merge must make it immediately usable.
$afterInstall = @(Get-MergedPathEntries -MachinePath 'C:\Windows;C:\NewInstall' -UserPath '' -ProcessPath 'C:\Old' -PathHints @())
Assert-Equal ($afterInstall -contains 'C:\NewInstall') $true 'A newly persisted command directory must be available immediately'

$consentedRestricted = Invoke-PolicyPreflightCase -Policies (New-TestPolicyList) -Consent 'yes'
Assert-Equal $consentedRestricted.Ready $true 'Consenting to the default client Restricted policy should permit managed profiles'
Assert-Equal $consentedRestricted.State.SetCalls 1 'Consent should make exactly one persistent policy change'
Assert-Equal $consentedRestricted.State.SetScope 'CurrentUser' 'The policy change must be limited to CurrentUser'
Assert-Equal $consentedRestricted.State.SetPolicy 'RemoteSigned' 'The only policy bootstrap may persist is RemoteSigned'
Assert-Equal $consentedRestricted.State.ReadCalls 2 'Bootstrap must re-read policy scopes after changing CurrentUser'

$declinedRestricted = Invoke-PolicyPreflightCase -Policies (New-TestPolicyList -LocalMachine Restricted) -Consent 'no'
Assert-Equal $declinedRestricted.Ready $false 'Declining must leave a blocking persistent policy unchanged'
Assert-Equal $declinedRestricted.State.SetCalls 0 'Declining must not change execution policy'
Assert-Equal (($declinedRestricted.Warnings -join ' ') -match 'New PowerShell sessions may block unsigned managed profiles and token loading') $true 'Declining must explain the impact on future sessions'

$remoteSigned = Invoke-PolicyPreflightCase -Policies (New-TestPolicyList -CurrentUser RemoteSigned) -Consent 'no'
Assert-Equal $remoteSigned.Ready $true 'An existing CurrentUser RemoteSigned policy should be retained'
Assert-Equal $remoteSigned.State.PromptCalls 0 'An acceptable existing policy must not prompt'
Assert-Equal $remoteSigned.State.SetCalls 0 'An acceptable existing policy must not be changed'

foreach ($acceptablePolicy in @('Unrestricted', 'Bypass')) {
    $existingPolicy = Invoke-PolicyPreflightCase -Policies (New-TestPolicyList -CurrentUser $acceptablePolicy) -Consent 'no'
    Assert-Equal $existingPolicy.Ready $true "An existing $acceptablePolicy policy should be retained"
    Assert-Equal $existingPolicy.State.SetCalls 0 "Bootstrap must not downgrade or persist a replacement for $acceptablePolicy"
}

$allSigned = Invoke-PolicyPreflightCase -Policies (New-TestPolicyList -CurrentUser AllSigned) -Consent 'yes'
Assert-Equal $allSigned.Ready $true 'Explicit consent may replace blocking CurrentUser AllSigned with RemoteSigned'
Assert-Equal $allSigned.State.SetPolicy 'RemoteSigned' 'AllSigned must only be changed to CurrentUser RemoteSigned after consent'

$groupPolicy = Invoke-PolicyPreflightCase -Policies (New-TestPolicyList -MachinePolicy Restricted) -Consent 'yes'
Assert-Equal $groupPolicy.Ready $false 'MachinePolicy Restricted must remain a blocking policy'
Assert-Equal $groupPolicy.State.PromptCalls 0 'Group Policy restrictions must not offer a local override'
Assert-Equal $groupPolicy.State.SetCalls 0 'Bootstrap must not attempt to override Group Policy'
Assert-Equal (($groupPolicy.Warnings -join ' ') -match 'Ask your administrator to review the policy') $true 'Group Policy warning must direct the user to an administrator'

$userGroupPolicy = Invoke-PolicyPreflightCase -Policies (New-TestPolicyList -UserPolicy AllSigned) -Consent 'yes'
Assert-Equal $userGroupPolicy.Ready $false 'UserPolicy AllSigned must remain a blocking policy'
Assert-Equal $userGroupPolicy.State.PromptCalls 0 'User Policy restrictions must not offer a local override'
Assert-Equal $userGroupPolicy.State.SetCalls 0 'Bootstrap must not attempt to override User Policy'

$machinePolicyWins = Invoke-PolicyPreflightCase -Policies (New-TestPolicyList -MachinePolicy RemoteSigned -UserPolicy Restricted) -Consent 'no'
Assert-Equal $machinePolicyWins.Ready $true 'MachinePolicy must take precedence over UserPolicy'
Assert-Equal $machinePolicyWins.State.PromptCalls 0 'An acceptable MachinePolicy must prevent unnecessary prompts'

$originalToken = $env:OP_SERVICE_ACCOUNT_TOKEN
try {
    $promptCount = 0
    $env:OP_SERVICE_ACCOUNT_TOKEN = 'inherited-test-token'
    $inherited = Set-OpServiceAccountTokenForProcess -Prompt { $script:promptCount++; throw 'Prompt should not run for inherited token.' }
    Assert-Equal $inherited $true 'An inherited token should be reused'
    Assert-Equal $promptCount 0 'An inherited token should not prompt'

    Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN -ErrorAction SilentlyContinue
    $promptedSecureString = ConvertTo-SecureString 'bootstrap-test-token' -AsPlainText -Force
    $prompted = Set-OpServiceAccountTokenForProcess -Prompt { $promptedSecureString }
    Assert-Equal $prompted $true 'A token entered at the prompt should be accepted'
    Assert-Equal $env:OP_SERVICE_ACCOUNT_TOKEN 'bootstrap-test-token' 'A prompted token should be available in the current process'

    Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN -ErrorAction SilentlyContinue
    $emptySecureString = New-Object System.Security.SecureString
    $warnings = @()
    $provided = Set-OpServiceAccountTokenForProcess -Prompt { $emptySecureString } -WarningVariable warnings
    Assert-Equal $provided $false 'An empty token should not be treated as authenticated'
    Assert-Equal ([string]::IsNullOrEmpty($env:OP_SERVICE_ACCOUNT_TOKEN)) $true 'An empty token should not be set'
    Assert-Equal (($warnings -join ' ') -match 'need authentication before review or apply') $true 'An empty token must warn that secret-dependent configs need authentication'
    $emptySecureString.Dispose()

    $scriptText = Get-Content -LiteralPath $scriptPath -Raw
    $tokenFunction = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-OpServiceAccountTokenForProcess'
    }, $true) | Select-Object -First 1
    $policyFunction = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Ensure-PersistentProfileExecutionPolicy'
    }, $true) | Select-Object -First 1
    Assert-Equal ($tokenFunction.Extent.Text -match 'SetEnvironmentVariable') $false 'The token helper must not persist credentials'
    Assert-Equal ($policyFunction.Extent.Text.Contains('Get-ExecutionPolicy -List')) $true 'Preflight must inspect persistent policy scopes'
    Assert-Equal ($policyFunction.Extent.Text.Contains("'Process'")) $false 'Process Bypass must not count as persistent policy'
    Assert-Equal ($policyFunction.Extent.Text.Contains('Set-ExecutionPolicy -ExecutionPolicy $ExecutionPolicy -Scope $Scope -Force')) $true 'Policy changes must use the requested explicit scope'
    Assert-Equal ($scriptText -match '(?im)^\s*&\s*chezmoi\.exe\s+apply\b') $false 'Bootstrap must not run apply automatically'

    $onePasswordPackage = [regex]::Match($scriptText, "(?m)^\s*@\{ Id = 'AgileBits\.1Password\.CLI'; Name = '1Password CLI'; Command = 'op\.exe' \}")
    Assert-Equal $onePasswordPackage.Success $true 'WinGet must install the verified 1Password CLI package when op.exe is missing'
    $packageLoopStart = $scriptText.IndexOf('foreach ($package in @(')
    $policyPreflight = $scriptText.IndexOf('$profilePolicyReady = Ensure-PersistentProfileExecutionPolicy')
    Assert-Equal ($policyPreflight -lt $packageLoopStart) $true 'Execution policy preflight must run before package installation'
    $commandChecksStart = $scriptText.IndexOf('foreach ($command in @(', $packageLoopStart)
    $packageLoop = $scriptText.Substring($packageLoopStart, $commandChecksStart - $packageLoopStart)
    Assert-Equal ($packageLoop.Contains('if (-not (Get-Command $package.Command -ErrorAction SilentlyContinue))')) $true 'The 1Password CLI must follow the normal missing-command install path'
    Assert-Equal ($packageLoop.Contains('& $winget.Source install --id $package.Id')) $true 'Missing op.exe must install through WinGet'
    Assert-Equal ($packageLoop.IndexOf('& $winget.Source install --id $package.Id') -lt $packageLoop.LastIndexOf('Update-ProcessPath')) $true 'PATH must refresh after installing op.exe'
    Assert-Equal ($scriptText.Contains("foreach (`$command in @('git.exe', 'chezmoi.exe', 'op.exe'))")) $true 'Bootstrap must validate op.exe before continuing'
    Assert-Equal ($scriptText.Contains("Join-Path `$env:LOCALAPPDATA 'Microsoft\WinGet\Links'")) $true 'PATH refresh must include WinGet portable command links'
    $helperPath = "Join-Path `$target '.chezmoitemplates\windows-op-token.ps1'"
    Assert-Equal ($scriptText.Contains($helperPath)) $true 'Bootstrap must locate the shared source-owned token helper'
    $tokenSetup = $scriptText.IndexOf('& $tokenHelper -Setup')
    $fallbackSetup = $scriptText.IndexOf('[void](Set-OpServiceAccountTokenForProcess)')
    $tokenStatus = $scriptText.IndexOf('$hasOpToken = -not [string]::IsNullOrWhiteSpace($env:OP_SERVICE_ACCOUNT_TOKEN)')
    $init = $scriptText.IndexOf('& chezmoi.exe init --source $target')
    Assert-Equal ($commandChecksStart -lt $tokenSetup) $true 'The CLI prerequisite must be checked before token-dependent setup'
    Assert-Equal ($tokenSetup -lt $init -and $fallbackSetup -lt $init) $true 'The helper and legacy fallback must run before chezmoi init'
    Assert-Equal ($tokenSetup -lt $tokenStatus -and $fallbackSetup -lt $tokenStatus) $true 'Token status must be read from the process environment after setup'
    Assert-Equal ($scriptText.Contains('Token storage will remain process-only until the source is updated.')) $true 'Missing source helper must warn that durable storage is unavailable'

    $readme = Get-Content -LiteralPath $readmePath -Raw
    $downloadLine = [regex]::Matches($readme, '(?m)^& \{.*Invoke-WebRequest.*$')
    Assert-Equal $downloadLine.Count 1 'README must provide one physical download/run command'
    Assert-Equal ($downloadLine[0].Value.Contains('-ErrorAction Stop')) $true 'Download failure must stop before launching a stale script'
    Assert-Equal ($downloadLine[0].Value.Contains('powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File')) $true 'The command must keep the authenticated process open with process-scoped execution-policy bypass'
    Assert-Equal ($downloadLine[0].Value.IndexOf('Remove-Item') -lt $downloadLine[0].Value.IndexOf('Invoke-WebRequest')) $true 'A stale temporary script must be removed before download'
    Assert-Equal ($downloadLine[0].Value.Contains('dotfiles-bootstrap/fix/windows-bootstrap-first-run/install-windows.ps1')) $true 'The Windows test command must download this feature branch, not public main'
    Assert-Equal ($downloadLine[0].Value.Contains('-File $script -SourceRef feature/windows-op-token')) $true 'The Windows test command must initialize the source branch containing the token helper'
    Assert-Equal ($readme.Contains('$secureToken = Read-Host')) $false 'README should not require a second token-prompt snippet'
    Assert-Equal ($readme.Contains('the 1Password CLI')) $true 'Windows setup docs must list the added CLI prerequisite'
    Assert-Equal ($readme.Contains('unpublished bootstrap branch')) $true 'README must distinguish this test branch from public main'
    Assert-Equal ($readme.Contains('%LOCALAPPDATA%\Dotfiles\op-token.dpapi')) $true 'README must document the DPAPI-protected token location'
    Assert-Equal ($readme.Contains('Rerun bootstrap before your first apply')) $true 'README must explain how to reload a saved token before the first apply'
    Assert-Equal ($readme.Contains('fresh PowerShell 5.1 and 7 profiles')) $true 'README must explain that fresh profiles load the token after manual apply'
    Assert-Equal ($readme.Contains('Apply never runs automatically.')) $true 'README must state that apply is always manual'
    Assert-Equal ($readme.Contains('`-ExecutionPolicy Bypass` for this process only')) $true 'README must distinguish process bypass from persistent policy'
    Assert-Equal ($readme.Contains('Group Policy restrictions are reported')) $true 'README must state that Group Policy is never overridden'
} finally {
    if ($null -eq $originalToken) {
        Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN -ErrorAction SilentlyContinue
    } else {
        $env:OP_SERVICE_ACCOUNT_TOKEN = $originalToken
    }
}

Write-Output 'Windows bootstrap regression checks passed.'
