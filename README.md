# dotfiles-bootstrap

Bootstrap a new machine to use my private [chezmoi](https://www.chezmoi.io/) dotfiles repository.

This repository contains **only** the bootstrap logic — it installs prerequisites, generates an SSH key, configures access, signs in to 1Password, and initializes chezmoi. The actual dotfiles (including feature flags, secrets, and machine-specific config) live in a private repository: [`dawidgora/dotfiles`](https://github.com/dawidgora/dotfiles).

## One-line install

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/dawidgora/dotfiles-bootstrap/main/install.sh)"
```

## Manual install

```sh
git clone https://github.com/dawidgora/dotfiles-bootstrap.git
cd dotfiles-bootstrap
./install.sh
```

## What the script does

1. **Detects the OS** — macOS or apt-based Linux.
2. **Installs dependencies** — `git`, `curl`, `ssh`, `chezmoi`, and `op` (1Password CLI).
3. **Generates an SSH key** — asks first, then generates `~/.ssh/github-dotfiles` (ed25519) if confirmed.
4. **Configures an SSH host alias** — `github-dotfiles` in `~/.ssh/config`.
5. **Tests SSH access** — pauses for you to add the Deploy Key to GitHub (skipped if no key was generated).
6. **Initializes chezmoi** — clones the private dotfiles repo.
7. **Configures 1Password** — prompts for a service account token, saved to `~/.secrets`.
8. **Applies dotfiles** — `chezmoi apply -v`.

After bootstrap, configure machine-specific features with `chezmoi edit-config`. See the private dotfiles repo README for details.

## 1Password

Dotfiles uses a **1Password service account** to resolve secrets without Touch ID prompts. The service account token is stored in `~/.secrets` (not tracked by chezmoi).

To create a service account:
1. Go to https://start.1password.com/service-accounts/
2. Create a service account and grant it access to the required vaults (see private dotfiles repo README)
3. The bootstrap script will prompt you for the token, or add it manually: `echo 'export OP_SERVICE_ACCOUNT_TOKEN="<token>"' >> ~/.secrets`

## Security notes

- This repository is **public** and must never contain secrets, tokens, hostnames, vault names, or internal infrastructure details.
- The SSH key is generated locally and never leaves your machine — you add only the public key to GitHub.
- The Deploy Key is configured as **read-only** (no write access).
- All secrets are stored in 1Password and resolved at `chezmoi apply` time via a service account — they never appear in the git repository.
- The service account token is stored in `~/.secrets` (chmod 600), which is excluded from chezmoi management.

## License

MIT