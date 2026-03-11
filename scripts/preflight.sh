#!/usr/bin/env bash
# agent-clash preflight — verify CLI environment for cross-model adversarial review
# Usage: preflight.sh [--json]
#
# Exit codes: 0=READY, 2=PARTIAL, 3=MISSING, 64=bad args
# Run this before first use or when onboarding teammates.

set -euo pipefail

# --- Argument parsing ---
JSON_MODE="false"
if [[ $# -eq 0 ]]; then
  : # no args, human-readable mode
elif [[ $# -eq 1 && "$1" == "--json" ]]; then
  JSON_MODE="true"
else
  echo "Usage: preflight.sh [--json]" >&2
  exit 64
fi

# --- Colors ---
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_DIM='\033[2m'

ok()   { printf "${C_GREEN}  ✓${C_RESET} %s\n" "$1"; }
fail() { printf "${C_RED}  ✗${C_RESET} %s\n" "$1"; }
warn() { printf "${C_YELLOW}  ⚠${C_RESET} %s\n" "$1"; }
info() { printf "${C_DIM}  ℹ${C_RESET} %s\n" "$1"; }

# --- Portable timeout + version probe ---
# Captures stdout+stderr, strips ANSI codes, extracts version number via regex.
# Works on macOS (no GNU timeout) and Linux.
_probe_cli() {
  local cli="$1"
  local raw=""

  if command -v timeout >/dev/null 2>&1; then
    raw=$(timeout 5 "$cli" --version 2>&1) || raw=""
  elif command -v gtimeout >/dev/null 2>&1; then
    raw=$(gtimeout 5 "$cli" --version 2>&1) || raw=""
  else
    raw=$("$cli" --version 2>&1) || raw=""
  fi

  # Strip ANSI escape codes (colors, bold, etc.)
  raw=$(printf '%s' "$raw" | sed 's/\x1b\[[0-9;]*m//g; s/\x1b\[[0-9;]*[A-Za-z]//g')

  # Extract first version number (e.g. 2.1.72 or 0.114.0)
  printf '%s' "$raw" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

# --- Detect CLIs ---
_claude_ok=false
_claude_ver=""
_codex_ok=false
_codex_ver=""

if command -v claude >/dev/null 2>&1; then
  _claude_ver=$(_probe_cli claude)
  [[ -n "$_claude_ver" ]] && _claude_ok=true
fi

if command -v codex >/dev/null 2>&1; then
  _codex_ver=$(_probe_cli codex)
  [[ -n "$_codex_ver" ]] && _codex_ok=true
fi

_jq_ok=false
command -v jq >/dev/null 2>&1 && _jq_ok=true

# --- Verdict ---
_can_review=false
_cross_model=false

[[ "$_claude_ok" == "true" || "$_codex_ok" == "true" ]] && _can_review=true
[[ "$_claude_ok" == "true" && "$_codex_ok" == "true" ]] && _cross_model=true

# --- Exit code ---
if [[ "$_cross_model" == "true" ]]; then
  EXIT_CODE=0   # READY
elif [[ "$_can_review" == "true" ]]; then
  EXIT_CODE=2   # PARTIAL
else
  EXIT_CODE=3   # MISSING
fi

# --- JSON output: use python3 for proper serialization (no control char issues) ---
if [[ "$JSON_MODE" == "true" ]]; then
  python3 - "$_claude_ok" "$_claude_ver" "$_codex_ok" "$_codex_ver" \
            "$_jq_ok" "$_can_review" "$_cross_model" <<'PYEOF'
import json, sys
_, claude_ok, claude_ver, codex_ok, codex_ver, jq_ok, can_review, cross_model = sys.argv
def b(v): return v == "true"
print(json.dumps({
  "claude":      {"available": b(claude_ok),  "version": claude_ver},
  "codex":       {"available": b(codex_ok),   "version": codex_ver},
  "jq":          b(jq_ok),
  "can_review":  b(can_review),
  "cross_model": b(cross_model),
}, indent=2))
PYEOF
  exit "$EXIT_CODE"
fi

# --- Human-readable output ---
printf "\n${C_BOLD}${C_CYAN}┌─────────────────────────────────────────┐${C_RESET}\n"
printf "${C_BOLD}${C_CYAN}│  agent-clash preflight — env check      │${C_RESET}\n"
printf "${C_BOLD}${C_CYAN}└─────────────────────────────────────────┘${C_RESET}\n\n"
printf "${C_DIM}  Checking available CLIs...${C_RESET}\n\n"

if [[ "$_claude_ok" == "true" ]]; then
  ok "Claude CLI  v${_claude_ver}"
else
  fail "Claude CLI  not installed"
  info "Install: npm install -g @anthropic-ai/claude-code"
fi

if [[ "$_codex_ok" == "true" ]]; then
  ok "Codex CLI   v${_codex_ver}"
else
  fail "Codex CLI   not installed"
  info "Install: npm install -g @openai/codex"
fi

if [[ "$_jq_ok" == "true" ]]; then
  ok "jq          $(jq --version 2>/dev/null)"
else
  warn "jq          not installed (optional)"
  info "Install: brew install jq"
fi

echo ""

if [[ "$_cross_model" == "true" ]]; then
  printf "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  printf "${C_GREEN}${C_BOLD}  READY — cross-model adversarial review${C_RESET}\n"
  printf "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n\n"
  info "Claude writes → Codex reviews  ✓"
  info "Codex writes  → Claude reviews ✓"
elif [[ "$_can_review" == "true" ]]; then
  printf "${C_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  printf "${C_YELLOW}${C_BOLD}  PARTIAL — single-model-multi-lens only${C_RESET}\n"
  printf "${C_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n\n"
  warn "Missing one CLI. Cross-model adversarial review unavailable."
else
  printf "${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  printf "${C_RED}${C_BOLD}  MISSING — cannot run reviews${C_RESET}\n"
  printf "${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n\n"
  fail "At least one CLI (Claude or Codex) is required."
fi
echo ""

exit "$EXIT_CODE"
