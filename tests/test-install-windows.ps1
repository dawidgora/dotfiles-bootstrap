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

foreach ($functionName in @('Get-MergedPathEntries', 'Set-OpServiceAccountTokenForProcess')) {
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

$merged = @(Get-MergedPathEntries -MachinePath 'C:\Machine' -UserPath 'C:\User' -ProcessPath 'C:\Old;C:\machine' -PathHints @('C:\Hint'))
Assert-Equal ($merged -join ';') 'C:\Machine;C:\User;C:\Old;C:\Hint' 'PATH refresh must include persisted Machine/User entries, process PATH, and hints without case-insensitive duplicates'
$emptyPath = @(Get-MergedPathEntries -MachinePath '' -UserPath $null -ProcessPath '' -PathHints @())
Assert-Equal $emptyPath.Count 0 'Empty PATH inputs must remain empty'

# Model an install that adds a command directory to persisted PATH after the
# process PATH was created. The refreshed merge must make it immediately usable.
$afterInstall = @(Get-MergedPathEntries -MachinePath 'C:\Windows;C:\NewInstall' -UserPath '' -ProcessPath 'C:\Old' -PathHints @())
Assert-Equal ($afterInstall -contains 'C:\NewInstall') $true 'A newly persisted command directory must be available immediately'

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
    Assert-Equal ($tokenFunction.Extent.Text -match 'SetEnvironmentVariable') $false 'The token helper must not persist credentials'
    Assert-Equal ($scriptText -match '(?im)^\s*&\s*chezmoi\.exe\s+apply\b') $false 'Bootstrap must not run apply automatically'

    $readme = Get-Content -LiteralPath $readmePath -Raw
    $downloadLine = [regex]::Matches($readme, '(?m)^& \{.*Invoke-WebRequest.*$')
    Assert-Equal $downloadLine.Count 1 'README must provide one physical download/run command'
    Assert-Equal ($downloadLine[0].Value.Contains('-ErrorAction Stop')) $true 'Download failure must stop before launching a stale script'
    Assert-Equal ($downloadLine[0].Value.Contains('powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File')) $true 'The command must keep the authenticated process open with process-scoped execution-policy bypass'
    Assert-Equal ($downloadLine[0].Value.IndexOf('Remove-Item') -lt $downloadLine[0].Value.IndexOf('Invoke-WebRequest')) $true 'A stale temporary script must be removed before download'
    Assert-Equal ($downloadLine[0].Value.Contains('dotfiles-bootstrap/fix/windows-bootstrap-first-run/install-windows.ps1')) $true 'The Windows test command must download this feature branch, not public main'
    Assert-Equal ($readme.Contains('$secureToken = Read-Host')) $false 'README should not require a second token-prompt snippet'
} finally {
    if ($null -eq $originalToken) {
        Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN -ErrorAction SilentlyContinue
    } else {
        $env:OP_SERVICE_ACCOUNT_TOKEN = $originalToken
    }
}

Write-Output 'Windows bootstrap regression checks passed.'
