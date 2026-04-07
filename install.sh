#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/dev-agent"
REPO_URL="https://github.com/delacruz-aldrin/dev-agent.git"

if [ -d "$SKILL_DIR/.git" ]; then
  echo "dev-agent is already installed. Updating..."
  git -C "$SKILL_DIR" pull
  echo "✅ Updated to latest version."
else
  echo "Installing dev-agent..."
  mkdir -p "$HOME/.claude/skills"
  git clone "$REPO_URL" "$SKILL_DIR"
  echo "✅ Installed to $SKILL_DIR"
  echo ""
  echo "Restart Claude Code, then run /dev-agent <mode> in any project to get started."
fi
