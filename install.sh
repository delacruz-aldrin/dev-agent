#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/delacruz-aldrin/dev-agent.git"
GLOBAL_DIR="$HOME/.claude/skills/dev-agent"
PROJECT_DIR="$(pwd)/.claude/skills/dev-agent"

echo "Where do you want to install dev-agent?"
echo "  1) Global  — $GLOBAL_DIR (available in all projects)"
echo "  2) Project — $PROJECT_DIR (this project only)"
echo ""
read -rp "Choice [1/2]: " choice

case "$choice" in
  2)
    SKILL_DIR="$PROJECT_DIR"
    SCOPE="project"
    ;;
  *)
    SKILL_DIR="$GLOBAL_DIR"
    SCOPE="global"
    ;;
esac

if [ -d "$SKILL_DIR/.git" ]; then
  echo "dev-agent is already installed at $SKILL_DIR. Updating..."
  git -C "$SKILL_DIR" pull
  echo "✅ Updated to latest version."
else
  echo "Installing dev-agent ($SCOPE)..."
  mkdir -p "$(dirname "$SKILL_DIR")"
  git clone "$REPO_URL" "$SKILL_DIR"
  echo "✅ Installed to $SKILL_DIR"
  echo ""
  if [ "$SCOPE" = "project" ]; then
    echo "Tip: add .claude/skills/ to your .gitignore if you don't want to commit this."
  fi
  echo "Restart Claude Code, then run /dev-agent <mode> to get started."
fi
