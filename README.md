# dotfiles-bootstrap

Bootstrap a machine for my [chezmoi](https://www.chezmoi.io/) dotfiles source.
This public repository installs prerequisites, sets up source access, and initializes chezmoi.
It does not run `chezmoi apply` or install packages selected by your dotfiles configuration.
Packages, feature flags, and managed config live in [`dawidgora/dotfiles`](https://github.com/dawidgora/dotfiles).

## macOS and apt-based Linux

Review the script before running it. The macOS and Linux flow needs access to the private dotfiles source.

```sh
git clone https://github.com/dawidgora/dotfiles-bootstrap.git
cd dotfiles-bootstrap
./install.sh
```

The script installs Git, curl, SSH, chezmoi, and the 1Password CLI when needed.
It can create a local SSH key and alias for private source access.
It initializes chezmoi and can save a 1Password service account token for a later manual apply.
It stops without applying dotfiles or installing packages selected by your configuration.

Before your first apply, run `chezmoi edit-config` to choose features.
If you saved a 1Password token, load it into your current shell before reviewing templates or applying:

```sh
if [ -f "$HOME/.op-env" ]; then . "$HOME/.op-env"; fi
```

Review the configuration with `chezmoi diff --skip-secrets`.
Review the dotfiles package scripts separately because the diff is not a package plan.
Run `chezmoi apply` only after reviewing both the configuration and package scripts.
Open a new shell if installed commands are missing from PATH.

For the existing one-line flow, review [`install.sh`](install.sh) first:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/dawidgora/dotfiles-bootstrap/main/install.sh)"
```

## Windows without WSL

Windows includes PowerShell 5.1. Install App Installer if `winget` is missing.
Review `install-windows.ps1` before running this test-branch command:

```powershell
& { $script = Join-Path $env:TEMP 'install-windows.ps1'; Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dawidgora/dotfiles-bootstrap/fix/windows-bootstrap-first-run/install-windows.ps1' -OutFile $script -ErrorAction Stop; if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Bootstrap download did not create the script.' }; & powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File $script -SourceRef feature/windows-op-token; if ($LASTEXITCODE -ne 0) { throw "Bootstrap failed with exit code $LASTEXITCODE." } }
```

This command tests an unpublished bootstrap branch. It does not represent the
public `main` branch. It initializes source branch `feature/windows-op-token`,
which includes the required Windows token helper. The script installs PowerShell 7, Git, chezmoi, and the
1Password CLI with WinGet when needed. It refreshes PATH from persisted Machine
and User values, including WinGet command links, then checks that `op.exe` is
available. It initializes chezmoi without applying dotfiles. GitHub access to
the private source is required. Use `-Source` for an SSH remote, `-SourcePath`
for another checkout path, or `-SourceRef` to test a dotfiles branch.
For an existing checkout on another branch, inspect its changes, then fetch and
switch deliberately. The bootstrap refuses branch switches and never resets
existing checkout changes.

The command uses `-ExecutionPolicy Bypass` for this process only. Bootstrap
checks persistent scopes separately and asks before setting only CurrentUser to
`RemoteSigned` when persistent `Restricted` or `AllSigned` policy blocks unsigned
local profiles. Group Policy restrictions are reported and never overridden.

The command uses `-NoExit`, so continue in the child PowerShell session after
bootstrap. Its PATH is refreshed, and its token remains available for review.
The dotfiles source helper stores the token encrypted with Windows DPAPI at
`%LOCALAPPDATA%\Dotfiles\op-token.dpapi`. It loads the token only during setup.
Rerun bootstrap before your first apply to reload the saved token.

Before your first apply, run `chezmoi edit-config` to choose features.
The helper reuses an inherited token, loads a saved token, or prompts securely.
Older dotfiles sources without the helper use a process-only prompt and warn that
durable storage is unavailable until the source is updated. If you skip the
prompt, rerun bootstrap before reviewing or applying secret-dependent templates.
Review the configuration with `chezmoi diff --skip-secrets`.
Review the dotfiles package scripts separately because the diff is not a package plan.
Run `chezmoi apply` only after reviewing both configuration and package scripts.
Apply never runs automatically. After manual apply, fresh PowerShell 5.1 and 7
profiles can load the saved token. Open a new PowerShell or SSH session to pick
up persisted PATH changes.

## 1Password on macOS and Linux

The Unix script can prompt for a service account token at runtime.
It stores the token locally in `~/.op-env` with owner-only permissions.
The script does not upload the token to this repository or apply dotfiles automatically.
Create an account at https://start.1password.com/service-accounts/ and grant it access to the required vaults.
The private dotfiles README lists the required vault access.

## Security boundary

- This repository is **public**. Never add credentials, tokens, private infrastructure details, or internal hostnames.
- The bootstrap creates an SSH key locally if you choose that access method. Only its public key goes to GitHub.
- Grant the deploy key read-only access to the private dotfiles source.
- Secret references, package choices, and machine-specific config belong in the dotfiles source, not here.
- Review downloaded scripts before running them. Do not store a service account token in a public checkout.

## License

MIT
