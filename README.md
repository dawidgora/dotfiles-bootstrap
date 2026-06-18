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
3. **Generates an SSH key** — `~/.ssh/github-dotfiles` (ed25519), skipped if it already exists.
4. **Configures an SSH host alias** — `github-dotfiles` in `~/.ssh/config`.
5. **Tests SSH access** — pauses for you to add the Deploy Key to GitHub.
6. **Initializes chezmoi** — clones the private dotfiles repo.
7. **Signs in to 1Password** — signs in to the CLI so chezmoi can resolve secrets.
8. **Applies dotfiles** — `chezmoi apply -v`.

After bootstrap, configure machine-specific features with `chezmoi edit-config`. See the private dotfiles repo README for details.

## 1Password

Dotfiles uses 1Password to manage secrets. The required vaults and items are documented in the **private** dotfiles repository README — they are not listed here to avoid exposing infrastructure details in a public repo.

## Security notes

- This repository is **public** and must never contain secrets, tokens, hostnames, vault names, or internal infrastructure details.
- The SSH key is generated locally and never leaves your machine — you add only the public key to GitHub.
- The Deploy Key is configured as **read-only** (no write access).
- All secrets are stored in 1Password and resolved at `chezmoi apply` time — they never appear in the git repository.

## License

MIT