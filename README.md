# dotfiles-bootstrap

Bootstrap a machine for my [chezmoi](https://www.chezmoi.io/) dotfiles source.
This public repository installs prerequisites, sets up source access, and starts `chezmoi apply`.
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
It then initializes chezmoi, asks for the 1Password token needed by your enabled config, and applies the dotfiles.

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
It initializes the dotfiles source when needed, then starts `chezmoi apply`.
You need GitHub access to the private source before it can clone.
Use `-Source` for an SSH remote, or `-SourcePath` for another checkout path.
Use `-SourceRef` to test a dotfiles branch before it reaches `main`.
The dotfiles source installs Node.js, Neovim, OpenCode, WezTerm, and optional tools.

Open a new PowerShell or SSH session after installation to pick up PATH changes.

## 1Password on macOS and Linux

The Unix script can prompt for a service account token at runtime.
It stores the token locally in `~/.op-env` with owner-only permissions.
The script does not upload the token to this repository.
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
