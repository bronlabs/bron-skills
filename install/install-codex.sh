#!/usr/bin/env bash
#
# Symlink every skill under skills/ into ~/.codex/skills/ and AGENTS.md into
# ~/.codex/AGENTS.md so Codex picks them up. Idempotent — re-running updates
# the symlinks.
#
# Usage:
#   ./install/install-codex.sh                # install
#   ./install/install-codex.sh --dry-run      # show what would change
#   ./install/install-codex.sh --uninstall    # remove the symlinks
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"
AGENTS_SRC="$REPO_ROOT/AGENTS.md"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SKILLS_DEST="$CODEX_HOME/skills"
AGENTS_DEST="$CODEX_HOME/AGENTS.md"

mode=install
case "${1:-}" in
  --dry-run)   mode=dry ;;
  --uninstall) mode=uninstall ;;
  --help|-h)
    sed -n '2,11p' "$0"
    exit 0
    ;;
esac

if [ ! -d "$SKILLS_SRC" ]; then
  echo "error: $SKILLS_SRC not found — are you running from the repo root?" >&2
  exit 1
fi

mkdir -p "$SKILLS_DEST"

link_one() {
  local src="$1"
  local dest="$2"
  local label="$3"

  case "$mode" in
    dry)
      if [ -L "$dest" ]; then
        local current
        current="$(readlink "$dest")"
        if [ "$current" = "$src" ]; then
          echo "skip   $label -> already linked"
        else
          echo "update $label (current: $current)"
        fi
      elif [ -e "$dest" ]; then
        echo "warn   $label -> $dest exists and is not a symlink (won't touch)"
      else
        echo "link   $label -> $src"
      fi
      ;;
    install)
      if [ -L "$dest" ]; then
        rm "$dest"
      elif [ -e "$dest" ]; then
        echo "warn: $dest exists and is not a symlink — skipping" >&2
        return 0
      fi
      ln -s "$src" "$dest"
      echo "linked $label"
      ;;
    uninstall)
      if [ -L "$dest" ]; then
        rm "$dest"
        echo "removed $label"
      elif [ -e "$dest" ]; then
        echo "warn: $dest exists and is not a symlink — leaving alone" >&2
      else
        echo "skip   $label -> not installed"
      fi
      ;;
  esac
}

for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  name="$(basename "$skill_dir")"
  link_one "${skill_dir%/}" "$SKILLS_DEST/$name" "$name"
done

if [ -f "$AGENTS_SRC" ]; then
  link_one "$AGENTS_SRC" "$AGENTS_DEST" "AGENTS.md"
fi

case "$mode" in
  install)
    echo
    echo "Installed bron skills into $SKILLS_DEST"
    echo "Installed AGENTS.md at $AGENTS_DEST"
    echo "Restart Codex to pick up the new skills."
    ;;
  uninstall)
    echo
    echo "Removed bron skills from $SKILLS_DEST"
    echo "Removed AGENTS.md from $AGENTS_DEST (if it was a symlink)"
    ;;
esac
