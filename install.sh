#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SSH_KEY_PATH="$HOME/.ssh/github-dotfiles"
SSH_HOST_ALIAS="github-dotfiles"
DOTFILES_REPO="dawidgora/dotfiles"
DOTFILES_SSH_URL="git@${SSH_HOST_ALIAS}:${DOTFILES_REPO}.git"
# ───────────────────────────────────────────────────────────────────────────────

info()  { printf "\033[1;34m[INFO]\033[0m  %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m  %s\n" "$*"; }
error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2; }
die()   { error "$@"; exit 1; }

# ── 1. Detect operating system ────────────────────────────────────────────────
info "Detecting operating system..."
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *)      die "Unsupported operating system: $OS" ;;
esac
info "Platform: $PLATFORM"

# ── 2. Install basic dependencies ─────────────────────────────────────────────
install_on_macos() {
  # Homebrew
  if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -d /opt/homebrew/bin ]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  else
    info "Homebrew already installed."
  fi

  # git, curl, ssh, chezmoi, op (1Password CLI)
  local pkgs=()
  command -v git     &>/dev/null || pkgs+=(git)
  command -v curl    &>/dev/null || pkgs+=(curl)
  command -v ssh     &>/dev/null || pkgs+=(openssh)
  command -v chezmoi &>/dev/null || pkgs+=(chezmoi)
  command -v op      &>/dev/null || pkgs+=(1password-cli)

  if [ ${#pkgs[@]} -gt 0 ]; then
    info "Installing via Homebrew: ${pkgs[*]}"
    brew install "${pkgs[@]}"
  else
    info "All dependencies already installed."
  fi
}

install_on_linux() {
  if ! command -v apt-get &>/dev/null; then
    die "Only apt-based Linux distributions are supported."
  fi

  info "Updating package index..."
  sudo apt-get update -qq

  local pkgs=()
  command -v git     &>/dev/null || pkgs+=(git)
  command -v curl    &>/dev/null || pkgs+=(curl)
  command -v ssh     &>/dev/null || pkgs+=(openssh-client)

  if [ ${#pkgs[@]} -gt 0 ]; then
    info "Installing via apt: ${pkgs[*]}"
    sudo apt-get install -y -qq "${pkgs[@]}"
  else
    info "Core dependencies already installed."
  fi

  # chezmoi — use official installer since apt repos may be outdated
  if ! command -v chezmoi &>/dev/null; then
    info "Installing chezmoi..."
    local installer
    installer="$(mktemp)"
    curl -fsSL https://get.chezmoi.io -o "$installer"
    sh "$installer" -d
    rm -f "$installer"
  else
    info "chezmoi already installed."
  fi

  # 1Password CLI
  if ! command -v op &>/dev/null; then
    info "Installing 1Password CLI..."
    curl -sS https://downloads.1password.com/linux/debian/amd64/stable/1password-latest-linux-amd64.deb -o /tmp/1password.deb
    sudo dpkg -i /tmp/1password.deb 2>/dev/null || true
    rm -f /tmp/1password.deb
  else
    info "1Password CLI already installed."
  fi
}

case "$PLATFORM" in
  macos) install_on_macos ;;
  linux) install_on_linux ;;
esac

# ── 3. Generate SSH key for read-only access to dotfiles repo ─────────────────
info "Setting up SSH key..."

# Ensure ~/.ssh exists with correct permissions
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$SSH_KEY_PATH" ]; then
  info "SSH key already exists at $SSH_KEY_PATH — skipping generation."
else
  info "Generating ed25519 SSH key at $SSH_KEY_PATH..."
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "dotfiles-bootstrap"
  chmod 600 "$SSH_KEY_PATH"
  chmod 644 "$SSH_KEY_PATH.pub"
  info "SSH key generated."
fi

printf "\n"
info "Public key:"
cat "$SSH_KEY_PATH.pub"
printf "\n"
info "Add this key as a read-only Deploy Key to GitHub repository $DOTFILES_REPO:"
info "  1. Go to https://github.com/$DOTFILES_REPO/settings/keys"
info "  2. Click 'Add deploy key'"
info "  3. Title:     dotfiles-bootstrap"
info "  4. Key:       paste the public key above"
info "  5. Leave 'Allow write access' unchecked"
info "  6. Click 'Add key'"
printf "\n"

# ── 4. Configure SSH host alias ───────────────────────────────────────────────
info "Configuring SSH host alias '$SSH_HOST_ALIAS'..."

SSH_CONFIG="$HOME/.ssh/config"
HOST_BLOCK="Host ${SSH_HOST_ALIAS}
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-dotfiles
    IdentitiesOnly yes"

# Ensure config file exists with safe permissions
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if grep -qF "Host ${SSH_HOST_ALIAS}" "$SSH_CONFIG" 2>/dev/null; then
  info "SSH host alias '$SSH_HOST_ALIAS' already configured — skipping."
else
  # Append a blank line for separation, then the host block
  printf "\n%s\n" "$HOST_BLOCK" >> "$SSH_CONFIG"
  info "SSH host alias '$SSH_HOST_ALIAS' added to $SSH_CONFIG."
fi

# ── 5. Test SSH access ────────────────────────────────────────────────────────
printf "\n"
info "Once you have added the Deploy Key, press Enter to test SSH access..."
read -r _

info "Testing SSH access to $DOTFILES_REPO..."
if ssh -o BatchMode=yes -o ConnectTimeout=10 "$SSH_HOST_ALIAS" 2>&1 | grep -q "successfully authenticated"; then
  info "SSH access verified."
else
  # GitHub always exits 1 even on success; check if we get the auth success message
  if ssh -T "$SSH_HOST_ALIAS" 2>&1 | grep -qi "successfully authenticated\|Hi"; then
    info "SSH access verified."
  else
    die "SSH access to $DOTFILES_REPO failed. Make sure the Deploy Key is added and try again."
  fi
fi

# ── 6. Initialize chezmoi ─────────────────────────────────────────────────────
CHEZMOI_SOURCE_DIR="$HOME/.local/share/chezmoi"

if [ -d "$CHEZMOI_SOURCE_DIR" ] && [ "$(ls -A "$CHEZMOI_SOURCE_DIR" 2>/dev/null)" ]; then
  info "chezmoi source directory already initialized at $CHEZMOI_SOURCE_DIR — skipping init."
else
  info "Initializing chezmoi from $DOTFILES_SSH_URL..."
  chezmoi init "$DOTFILES_SSH_URL"
fi

# ── 7. Sign in to 1Password ──────────────────────────────────────────────────
printf "\n"
info "═══════════════════════════════════════════════════════════════"
info "  1Password Setup"
info "═══════════════════════════════════════════════════════════════"
info ""
info "Dotfiles uses 1Password to manage secrets. See the private"
info "dotfiles repo README for the required setup."
info ""

if command -v op &>/dev/null; then
  if op account list 2>/dev/null | grep -q "."; then
    info "1Password CLI is installed and has accounts configured."
    info "Signing in..."
    eval "$(op signin)" 2>/dev/null || true
    info "Signed in."
  else
    warn "1Password CLI is installed but no accounts are configured."
    warn "Run 'op account add' to add your account, then re-run this script."
  fi
else
  warn "1Password CLI (op) is not installed."
  warn "Secrets managed by 1Password will not be resolved."
  warn "Install it with: brew install 1password-cli (macOS)"
  warn "  or visit: https://developer.1password.com/docs/cli/get-started/"
fi

# ── 8. Apply dotfiles ─────────────────────────────────────────────────────────
printf "\n"
info "Applying dotfiles..."
chezmoi apply -v

printf "\n"
info "═══════════════════════════════════════════════════════════════"
info "  Bootstrap complete!"
info "═══════════════════════════════════════════════════════════════"
info ""
info "Next steps:"
info "  1. Restart your shell:  exec \$SHELL"
info "  2. Configure features:  chezmoi edit-config"
info "  3. Review changes:      chezmoi diff"
info "  4. Re-apply:            chezmoi apply"
info "  5. Update dotfiles:     chezmoi update"
info ""
info "If 1Password secrets failed to resolve, make sure you're"
info "signed in (op signin) and have set up the required vaults"
info "and items as described in the private dotfiles repo README,"
info "then run: chezmoi apply"