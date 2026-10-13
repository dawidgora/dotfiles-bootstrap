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
To test this branch, review `install-windows.ps1`, then download and run it in PowerShell:

```powershell
& { $script = Join-Path $env:TEMP 'install-windows.ps1'; Remove-Item -LiteralPath $script -Force -ErrorAction SilentlyContinue; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/dawidgora/dotfiles-bootstrap/fix/windows-bootstrap-first-run/install-windows.ps1' -OutFile $script -ErrorAction Stop; if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Bootstrap download did not create the script.' }; & powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File $script; if ($LASTEXITCODE -ne 0) { throw "Bootstrap failed with exit code $LASTEXITCODE." } }
```

The script installs PowerShell 7, Git, chezmoi, and the 1Password CLI with
Winget when needed. It refreshes PATH from the newly persisted Machine and User
values, including WinGet's portable command links, and checks that `op.exe` is
available before continuing.
It initializes the dotfiles source when needed and stops without applying dotfiles.
You need GitHub access to the private source before it can clone.
Use `-Source` for an SSH remote, or `-SourcePath` for another checkout path.
Use `-SourceRef` to test a dotfiles branch before it reaches `main`.

The command uses `-NoExit`, so after bootstrap finishes, continue in this same
open child PowerShell session. Its PATH is refreshed, and a token entered at the
prompt remains available there for `chezmoi edit-config` and review/apply. You do
not need to enter it again in that session. The token is process-only and is not
saved or inherited by the PowerShell process that launched the child. If you
close this session, another shell needs its own authentication.

Before your first apply, run `chezmoi edit-config` to choose features.
The bootstrap reuses an inherited `OP_SERVICE_ACCOUNT_TOKEN` or prompts for it
without echoing input. If you skip the prompt, secret-dependent configurations
need authentication before review or apply; rerun the bootstrap in this still-open
session to prompt again.
Review the configuration with `chezmoi diff --skip-secrets`.
Review the dotfiles package scripts separately because the diff is not a package plan.
Run `chezmoi apply` only after reviewing both the configuration and package scripts.
No apply runs automatically. Open a new PowerShell or SSH session after installation
to pick up persisted PATH changes.

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
