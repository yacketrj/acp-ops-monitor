#!/usr/bin/env bash
# install.sh — Idempotent setup for acp-ops-monitor: installs notify-discord.sh
# to ~/.local/bin, verifies prerequisites, and prints the crontab line to add.
#
# This does NOT modify crontab automatically — cron entries are sensitive
# enough (they run unattended, with force-push access to real repos) that
# an explicit, reviewed `crontab -e` paste is safer than a script silently
# mutating the user's crontab. Idempotent re-runs are safe.
#
# Usage: bash install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo "=== acp-ops-monitor install ==="
echo

fail=0

echo "--- Checking prerequisites ---"
for cmd in git gh bash; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo -e "  ${GREEN}OK:${NC} $cmd found"
  else
    echo -e "  ${RED}MISSING:${NC} $cmd — required, install it before continuing"
    fail=1
  fi
done

if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    echo -e "  ${GREEN}OK:${NC} gh is authenticated"
  else
    echo -e "  ${YELLOW}WARN:${NC} gh is not authenticated — run 'gh auth login' before relying on cron jobs"
  fi
fi

echo
echo "--- Installing notify-discord.sh ---"
mkdir -p "$BIN_DIR"
install -m 0755 "${SCRIPT_DIR}/notify-discord.sh" "${BIN_DIR}/notify-discord.sh"
echo -e "  ${GREEN}OK:${NC} installed to ${BIN_DIR}/notify-discord.sh"

echo
echo "--- Checking Discord webhook configuration ---"
if [ -n "${DISCORD_DEV_WEBHOOK_URL:-}" ]; then
  echo -e "  ${GREEN}OK:${NC} DISCORD_DEV_WEBHOOK_URL is set in this shell's environment"
  echo -e "  ${YELLOW}NOTE:${NC} cron runs with a minimal environment — add this export to"
  echo "        your crontab (see below) or a file cron sources, not just your shell rc."
else
  echo -e "  ${YELLOW}WARN:${NC} DISCORD_DEV_WEBHOOK_URL is not set."
  echo "        Set it before running under cron, either via:"
  echo "          export DISCORD_DEV_WEBHOOK_URL=https://discord.com/api/webhooks/..."
  echo "        in the crontab entry itself, or by creating the legacy fallback file"
  echo "        notify-discord.sh reads if the env var is unset (see README)."
fi

echo
echo "--- Checking monitored local clones ---"
CORE_DIR="${ACP_CORE_DIR:-${HOME}/dune-awakening-selfhost-docker}"
CATALOG_DIR="${ACP_CATALOG_DIR:-${HOME}/dune-docker-addon/dune-docker-addons}"
if [ -d "$CORE_DIR/.git" ]; then
  echo -e "  ${GREEN}OK:${NC} core fork clone found at $CORE_DIR"
  if git -C "$CORE_DIR" remote get-url upstream >/dev/null 2>&1; then
    echo -e "  ${GREEN}OK:${NC} 'upstream' remote configured"
  else
    echo -e "  ${RED}MISSING:${NC} 'upstream' remote not configured in $CORE_DIR"
    echo "        run: git -C \"$CORE_DIR\" remote add upstream https://github.com/Red-Blink/dune-awakening-selfhost-docker.git"
    fail=1
  fi
else
  echo -e "  ${RED}MISSING:${NC} core fork clone not found at $CORE_DIR"
  echo "        set ACP_CORE_DIR if it lives elsewhere, or clone it there."
  fail=1
fi

if [ -d "$CATALOG_DIR/.git" ]; then
  echo -e "  ${GREEN}OK:${NC} catalog fork clone found at $CATALOG_DIR"
else
  echo -e "  ${YELLOW}SKIP:${NC} catalog fork clone not found at $CATALOG_DIR (optional; validate-and-report.sh skips it gracefully if absent)"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo -e "${RED}Install incomplete — resolve the MISSING items above before enabling cron.${NC}"
else
  echo -e "${GREEN}Prerequisites look good.${NC}"
fi

echo
echo "--- Suggested crontab entry ---"
echo "Run 'crontab -e' and add (adjust the env exports for your webhook/paths):"
echo
echo "  DISCORD_DEV_WEBHOOK_URL=https://discord.com/api/webhooks/REDACTED"
echo "  0 * * * * bash ${SCRIPT_DIR}/check-upstream-prs.sh >> /tmp/acp-cron.log 2>&1; bash ${SCRIPT_DIR}/validate-and-report.sh >> /tmp/acp-cron.log 2>&1"
echo
echo "Cron does not read your shell's rc files, so environment variables set in"
echo "\$HOME/.bashrc will NOT be visible to these scripts unless also set directly in"
echo "the crontab (as shown above) or in a file sourced by the cron job itself."
