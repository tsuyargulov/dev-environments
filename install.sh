#!/usr/bin/env bash
# dev-environments bootstrap (Phase 1).
# Checks prerequisites, installs the devcontainer CLI, and wires `devenv` onto PATH.
# Safe to re-run: the shell-profile block is marker-guarded.
#
# NOTE: this will be reworked when the single-port SSH gateway (sshpiper) lands.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

# --- shell profile detection ------------------------------------------------
case "${SHELL##*/}" in
  zsh)  PROFILE="$HOME/.zshrc" ;;
  bash) PROFILE="$HOME/.bash_profile" ;;
  *)    PROFILE="$HOME/.profile" ;;
esac
say "Using shell profile: $PROFILE"

# Make Homebrew-installed tools (node, etc.) visible even if this shell hasn't re-sourced the
# profile yet — e.g. running install.sh right after bootstrap.sh in the same shell.
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$b" ] && eval "$("$b" shellenv)" && break
done

# --- prerequisites ----------------------------------------------------------
say "Checking prerequisites…"

command -v git >/dev/null 2>&1 || die "git not found — install Xcode command line tools (xcode-select --install)"
ok "git"

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then ok "docker (daemon running)"; else warn "docker found but the daemon isn't running — start Docker Desktop"; fi
else
  die "docker not found — install Docker Desktop: https://www.docker.com/products/docker-desktop/"
fi

if ! command -v node >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then say "Installing Node via Homebrew…"; brew install node; else die "node not found — install Node.js (https://nodejs.org) or Homebrew, then re-run"; fi
fi
ok "node $(node --version)"

if ! command -v devcontainer >/dev/null 2>&1; then
  say "Installing @devcontainers/cli…"
  npm install -g @devcontainers/cli
fi
ok "devcontainer CLI"

# --- PATH + DEVENV_HOME (marker-guarded, idempotent) ------------------------
MARKER_BEGIN="# >>> dev-environments >>>"
MARKER_END="# <<< dev-environments <<<"

if grep -qF "$MARKER_BEGIN" "$PROFILE" 2>/dev/null; then
  say "Profile block already present — leaving it."
else
  say "Adding devenv to PATH in $PROFILE"
  {
    echo ""
    echo "$MARKER_BEGIN"
    echo "export DEVENV_HOME=\"$SCRIPT_DIR\""
    echo "export PATH=\"\$DEVENV_HOME/bin:\$PATH\""
    echo "# Fill these in for cloning your repos into containers (never commit them):"
    echo "# export GIT_TOKEN=...            # GitHub token, repo scope"
    echo "# export GIT_USER_EMAIL=..."
    echo "# export GIT_USER_NAME=..."
    echo "$MARKER_END"
  } >> "$PROFILE"
fi

# --- verify -----------------------------------------------------------------
say "Verifying…"
"$SCRIPT_DIR/bin/devenv" templates || warn "devenv ran but listed no templates (unexpected)"

echo
ok "Installed."
echo "  1. Open a new shell (or: source $PROFILE)"
echo "  2. Set GIT_TOKEN / GIT_USER_EMAIL / GIT_USER_NAME in $PROFILE (see the commented lines)"
echo "  3. Create your first project:  devenv new myapp --template python"
