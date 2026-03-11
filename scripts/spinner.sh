#!/usr/bin/env bash
# a2a (Agent-to-Agent) spinner — animated progress indicator
# Usage: spinner.sh <step/total> <message> <by>
# Example: spinner.sh "4/6" "Reviewers working" "codex"
#
# Run in background, kill when step is done:
#   ~/.claude/skills/a2a/scripts/spinner.sh "4/6" "Reviewers working" "codex" &
#   SPINNER_PID=$!
#   # ... do work ...
#   kill $SPINNER_PID 2>/dev/null; printf "\n"

STEP="${1:-?/?}"
MSG="${2:-Working}"
BY="${3:-}"

# Colors
C_RESET=$'\033[0m'
C_RED=$'\033[1;31m'
C_CYAN=$'\033[1;36m'
C_YELLOW=$'\033[1;33m'
C_GREEN=$'\033[1;32m'
C_DIM=$'\033[2m'

# Pick color by step number
STEP_NUM="${STEP%%/*}"
case "$STEP_NUM" in
  1) COLOR="$C_CYAN"   ;;
  2) COLOR="$C_CYAN"   ;;  # was magenta but \033[1;35m often unclear
  3) COLOR="$C_YELLOW" ;;
  4) COLOR="$C_RED"    ;;
  5) COLOR="$C_CYAN"   ;;
  6) COLOR="$C_GREEN"  ;;
  *) COLOR="$C_CYAN"   ;;
esac

# Braille spinner frames (smooth rotation effect)
FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
BY_LABEL=""
[[ -n "$BY" ]] && BY_LABEL="${C_DIM}  (by: ${BY})${C_RESET}"

i=0
while true; do
  FRAME="${FRAMES[$((i % 10))]}"
  printf "\r${COLOR}  ${FRAME} [${STEP}] ${MSG}...${C_RESET}${BY_LABEL}  " >&2
  sleep 0.1
  ((i++)) || true
done
