#!/usr/bin/env bash
# dev-environments uninstaller — interactive, confirm-each-step.
#
#   ./uninstall.sh           Reverses what install.sh added: the shell-profile block and the
#                            devenv entries in ~/.ssh/config.
#   ./uninstall.sh --purge   Additionally offers to stop devenv containers and remove the
#                            runtime project configs in $DEVENV_HOME/projects.
#
# Every mutating step prints a FINDINGS block (what's there now + the exact change) and asks
# for confirmation, defaulting to NO. This script NEVER deletes your workspaces
# (~/dev/<p>, ~/projects/<p>) or this repo clone — those are only reported at the end.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVENV_HOME="${DEVENV_HOME:-$HOME/.devenv}"
WORKSPACES_DIR="${DEVENV_WORKSPACES:-$HOME/dev}"
PROJECTS_DIR="$DEVENV_HOME/projects"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

say()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
rule() { printf '  %s\n' "----------------------------------------------------------------"; }

confirm() {                       # default NO
  local ans
  read -r -p "  Confirm? (y/N) " ans || true
  [[ "$ans" == [yY] || "$ans" == [yY][eE][sS] ]]
}

case "${SHELL##*/}" in
  zsh)  PROFILE="$HOME/.zshrc" ;;
  bash) PROFILE="$HOME/.bash_profile" ;;
  *)    PROFILE="$HOME/.profile" ;;
esac

# ── Step 1: shell-profile block ──────────────────────────────────────────────
echo
say "STEP 1 — shell profile block ($PROFILE)"
if [[ -f "$PROFILE" ]] && grep -qF "# >>> dev-environments >>>" "$PROFILE"; then
  echo "  FINDINGS — these lines are present (line numbers on the left):"
  rule
  grep -nF -e "# >>> dev-environments >>>" -e "# <<< dev-environments <<<" "$PROFILE" | sed 's/^/    /'
  awk 'BEGIN{n=0} /# >>> dev-environments >>>/{s=1} s{printf "    %d| %s\n", NR, $0} /# <<< dev-environments <<</{s=0}' "$PROFILE"
  tmp="$(mktemp)"
  sed '/# >>> dev-environments >>>/,/# <<< dev-environments <<</d' "$PROFILE" > "$tmp"
  echo "  CHANGE (diff — '<' lines will be removed):"
  rule
  diff "$PROFILE" "$tmp" | sed 's/^/    /' || true
  rule
  if confirm; then mv "$tmp" "$PROFILE"; ok "block removed (open a new shell to apply)"; else rm -f "$tmp"; warn "skipped"; fi
else
  warn "no dev-environments block found — nothing to do"
fi

# ── Step 2: ~/.ssh/config devenv entries ─────────────────────────────────────
echo
say "STEP 2 — devenv entries in ~/.ssh/config"
SSHC="$HOME/.ssh/config"
if [[ -f "$SSHC" ]] && grep -qE '^# devenv:' "$SSHC"; then
  echo "  FINDINGS — these Host entries are present:"
  rule
  awk '/^# devenv:/{s=1} s{printf "    %d| %s\n", NR, $0} s&&/^$/{s=0}' "$SSHC"
  tmp="$(mktemp)"
  awk '/^# devenv:/{skip=1} skip&&/^$/{skip=0;next} !skip' "$SSHC" > "$tmp"
  echo "  CHANGE (diff — '<' lines will be removed):"
  rule
  diff "$SSHC" "$tmp" | sed 's/^/    /' || true
  rule
  if confirm; then mv "$tmp" "$SSHC"; ok "ssh entries removed"; else rm -f "$tmp"; warn "skipped"; fi
else
  warn "no devenv entries in ~/.ssh/config — nothing to do"
fi

# ── Step 3 (--purge): containers + runtime configs ───────────────────────────
if [[ $PURGE -eq 1 ]]; then
  echo
  say "STEP 3 — running devenv containers (--purge)"
  if command -v docker >/dev/null 2>&1 && [[ -d "$PROJECTS_DIR" ]]; then
    found=0
    for cfg in "$PROJECTS_DIR"/*/config.env; do
      [[ -f "$cfg" ]] || continue
      name="$(basename "$(dirname "$cfg")")"
      ws=$(grep -E '^WORKSPACE=' "$cfg" | cut -d= -f2- | tr -d '"')
      cid=$(docker ps -q --filter "label=devcontainer.local_folder=$ws" 2>/dev/null | head -1 || true)
      if [[ -n "$cid" ]]; then
        found=1
        echo "  FINDINGS — project '$name' → container $cid"
        echo "  CHANGE — docker stop + docker rm $cid"
        if confirm; then docker stop "$cid" >/dev/null && docker rm "$cid" >/dev/null && ok "removed $name"; else warn "skipped $name"; fi
      fi
    done
    [[ $found -eq 0 ]] && warn "no running devenv containers"
  else
    warn "docker not available or no projects dir — skipping"
  fi

  echo
  say "STEP 4 — runtime project configs (--purge)"
  if [[ -d "$PROJECTS_DIR" ]]; then
    echo "  FINDINGS — $PROJECTS_DIR contains:"
    rule
    ls -1 "$PROJECTS_DIR" 2>/dev/null | sed 's/^/    /' || true
    rule
    echo "  CHANGE — rm -rf $PROJECTS_DIR   (config.env + secrets.env for each project)"
    if confirm; then rm -rf "$PROJECTS_DIR"; ok "removed $PROJECTS_DIR"; else warn "skipped"; fi
  else
    warn "no runtime configs at $PROJECTS_DIR"
  fi
fi

# ── Report what is intentionally left in place ───────────────────────────────
echo
say "Left in place (review, then remove manually if you want):"
echo "  • Your workspaces:   $WORKSPACES_DIR/<project>  and  \$HOME/projects/<project>"
echo "                       ↑ these hold your cloned code — check before deleting"
echo "  • This repo clone:   $SCRIPT_DIR                (rm -rf to remove)"
echo "  • devcontainer CLI:  npm uninstall -g @devcontainers/cli   (if unwanted)"
echo "  • Built images:      docker images | grep vsc-             (docker rmi to remove)"
echo
ok "Done."
