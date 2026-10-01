#!/usr/bin/env bash
# dev-environments — brand-new-Mac bootstrap (the uncommon, from-zero path).
# Installs OS-level prerequisites, then hands off to ./install.sh.
#
# Day-to-day you do NOT need this — only install.sh. Run this once on a fresh Mac.
# Some steps are interactive (Homebrew asks for your password) or GUI/web and are
# flagged [MANUAL]; the script does what it safely can and instructs the rest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

case "${SHELL##*/}" in
  zsh)  PROFILE="$HOME/.zshrc" ;;
  bash) PROFILE="$HOME/.bash_profile" ;;
  *)    PROFILE="$HOME/.profile" ;;
esac
say "Shell profile: $PROFILE   (a fresh Mac defaults to zsh → ~/.zshrc)"

# 1. Xcode Command Line Tools (git + compilers)
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools present"
else
  say "Triggering Command Line Tools install…"
  xcode-select --install || true
  die "Complete the Command Line Tools dialog, then re-run ./bootstrap.sh"
fi

# 2. Homebrew (+ shellenv for this arch)
if [[ "$(uname -m)" == "arm64" ]]; then BREW_PREFIX=/opt/homebrew; else BREW_PREFIX=/usr/local; fi
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew (interactive — will ask for your password)…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW_PREFIX/bin/brew" shellenv)"
if ! grep -qF "brew shellenv" "$PROFILE" 2>/dev/null; then
  echo "eval \"\$($BREW_PREFIX/bin/brew shellenv)\"" >> "$PROFILE"
  ok "added brew to $PROFILE"
fi
ok "Homebrew $(brew --version | head -1)"

# 3. Node (for @devcontainers/cli)
if ! command -v node >/dev/null 2>&1; then say "Installing Node…"; brew install node; fi
ok "node $(node --version)"

# 4. Docker Desktop
if [[ -d "/Applications/Docker.app" ]] || command -v docker >/dev/null 2>&1; then
  ok "Docker Desktop present"
else
  say "Installing Docker Desktop…"
  brew install --cask docker
fi
say "Launching Docker Desktop…"
open -a Docker 2>/dev/null || warn "launch Docker Desktop manually"
warn "[MANUAL] In Docker Desktop: accept terms, and set Settings → Resources → Memory"
warn "         to suit this Mac's RAM (too low → OOM during JVM/Gradle syncs)."
printf '  waiting for the Docker daemon'
for _ in $(seq 1 30); do if docker info >/dev/null 2>&1; then echo; ok "Docker daemon running"; break; fi; printf '.'; sleep 2; done
docker info >/dev/null 2>&1 || { echo; warn "daemon not up yet — finish Docker Desktop setup, then continue"; }

# 5. SSH key (devenv bakes your public key into each container)
if ls "$HOME"/.ssh/*.pub >/dev/null 2>&1; then
  ok "SSH public key present ($(ls "$HOME"/.ssh/*.pub | head -1))"
else
  say "Generating an ed25519 SSH key (no passphrase)…"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f "$HOME/.ssh/id_ed25519" -N ""
  ok "created ~/.ssh/id_ed25519 (add a passphrase later with: ssh-keygen -p -f ~/.ssh/id_ed25519)"
fi

# 6. GitHub token — web/manual
echo
warn "[MANUAL] Create a GitHub Personal Access Token for cloning your project repos:"
echo "         GitHub → Settings → Developer settings → Personal access tokens"
echo "         (fine-grained, Contents: Read). You'll set it as GIT_TOKEN after install.sh."

echo
ok "Prerequisites done."
echo "  Next:  cd $SCRIPT_DIR && ./install.sh"
