#!/usr/bin/env bash
#
# Symlink every skill under skills/ into ~/.claude/skills/ so Claude Code
# loads them. Idempotent — re-running updates the symlinks.
#
# Usage:
#   ./install/install-claude.sh                # install
#   ./install/install-claude.sh --dry-run      # show what would change
#   ./install/install-claude.sh --uninstall    # remove the symlinks
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"
SKILLS_DEST="${CLAUDE_HOME:-$HOME/.claude}/skills"

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

for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  name="$(basename "$skill_dir")"
  src="$skill_dir"
  dest="$SKILLS_DEST/$name"

  case "$mode" in
    dry)
      if [ -L "$dest" ]; then
        current="$(readlink "$dest")"
        if [ "$current" = "${src%/}" ]; then
          echo "skip   $name -> already linked"
        else
          echo "update $name (current: $current)"
        fi
      elif [ -e "$dest" ]; then
        echo "warn   $name -> $dest exists and is not a symlink (won't touch)"
      else
        echo "link   $name -> ${src%/}"
      fi
      ;;
    install)
      if [ -L "$dest" ]; then
        rm "$dest"
      elif [ -e "$dest" ]; then
        echo "warn: $dest exists and is not a symlink — skipping" >&2
        continue
      fi
      ln -s "${src%/}" "$dest"
      echo "linked $name"
      ;;
    uninstall)
      if [ -L "$dest" ]; then
        rm "$dest"
        echo "removed $name"
      elif [ -e "$dest" ]; then
        echo "warn: $dest exists and is not a symlink — leaving alone" >&2
      else
        echo "skip   $name -> not installed"
      fi
      ;;
  esac
done

case "$mode" in
  install)
    echo
    echo "Installed bron skills into $SKILLS_DEST"
    echo "In Claude Code: /skills reload  (or restart Claude Code)"
    ;;
  uninstall)
    echo
    echo "Removed bron skills from $SKILLS_DEST"
    ;;
esac
