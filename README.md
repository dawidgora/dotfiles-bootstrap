# dotfiles-bootstrap

Bootstrap a machine for my [chezmoi](https://www.chezmoi.io/) dotfiles source.
This public repository installs prerequisites, sets up source access, and initializes chezmoi.
It does not run `chezmoi apply` or install packages selected by your dotfiles configuration.
Packages, feature flags, and managed config live in [`dawidgora/dotfiles`](https://github.com/dawidgora/dotfiles).

**Release status:** This checkout's workflow changes are not published to public `main`.
Publish the script updates before using this workflow from `main`.
Public `main` currently does not include the Windows bootstrap script.

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
Download the bootstrap script, review it, then run it in PowerShell:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/dawidgora/dotfiles-bootstrap/main/install-windows.ps1 -OutFile "$env:TEMP\install-windows.ps1"
& "$env:TEMP\install-windows.ps1"
```

The script installs PowerShell 7, Git, and chezmoi with Winget.
It initializes the dotfiles source when needed and stops without applying dotfiles.
You need GitHub access to the private source before it can clone.
Use `-Source` for an SSH remote, or `-SourcePath` for another checkout path.
Use `-SourceRef` to test a dotfiles branch before it reaches `main`.

Before your first apply, run `chezmoi edit-config` to choose features.
Review the configuration with `chezmoi diff --skip-secrets`.
Review the dotfiles package scripts separately because the diff is not a package plan.
Run `chezmoi apply` only after reviewing both the configuration and package scripts.
Open a new PowerShell or SSH session after installation to pick up PATH changes.

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
