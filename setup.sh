#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SKILLS_DIR="$SCRIPT_DIR/skills"
TARGET_DIR="$HOME/.claude/skills"

if [ ! -d "$REPO_SKILLS_DIR" ]; then
  echo "Error: skills/ directory not found at $REPO_SKILLS_DIR"
  exit 1
fi

mkdir -p "$TARGET_DIR"

created=0
skipped=0
removed=0

# Sync: create or update symlinks for each skill in the repo
for skill_dir in "$REPO_SKILLS_DIR"/*/; do
  [ -f "$skill_dir/SKILL.md" ] || continue

  skill_name="$(basename "$skill_dir")"
  link_path="$TARGET_DIR/$skill_name"

  if [ -L "$link_path" ] && [ "$(readlink "$link_path")" = "$skill_dir" ]; then
    echo "  skip  $skill_name (already linked)"
    skipped=$((skipped + 1))
  else
    rm -rf "$link_path"
    ln -s "$skill_dir" "$link_path"
    echo "  link  $skill_name -> $skill_dir"
    created=$((created + 1))
  fi
done

# Cleanup: remove stale symlinks that point into this repo but no longer match a skill
for link_path in "$TARGET_DIR"/*/; do
  [ -L "${link_path%/}" ] || continue

  link_target="$(readlink "${link_path%/}")"

  # Only manage symlinks that point into this repo's skills/ directory
  case "$link_target" in
    "$REPO_SKILLS_DIR"/*) ;;
    *) continue ;;
  esac

  skill_name="$(basename "${link_path%/}")"

  if [ ! -f "$REPO_SKILLS_DIR/$skill_name/SKILL.md" ]; then
    rm "$TARGET_DIR/$skill_name"
    echo "  clean $skill_name (skill removed from repo)"
    removed=$((removed + 1))
  fi
done

echo ""
echo "Done: $created created, $skipped skipped, $removed removed"
