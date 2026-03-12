#!/usr/bin/env bash
# a2a preflight — verify local CLI/auth state for adversarial review
# Usage: preflight.sh [--json] [--refresh] [--ttl-seconds N]
#
# Exit codes: 0=READY, 2=PARTIAL, 3=MISSING, 64=bad args
# Default cache TTL: 900 seconds. Use --refresh to bypass cache once.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: preflight.sh [--json] [--refresh] [--ttl-seconds N]

Options:
  --json            Print JSON
  --refresh         Ignore cached result for this run
  --ttl-seconds N   Cache TTL in seconds (default: 900, 0 disables cache)
EOF
  exit 64
}

JSON_MODE="false"
FORCE_REFRESH="false"
TTL_SECONDS="${A2A_PREFLIGHT_TTL_SECONDS:-900}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_MODE="true"
      shift
      ;;
    --refresh)
      FORCE_REFRESH="true"
      shift
      ;;
    --ttl-seconds)
      [[ $# -lt 2 ]] && usage
      TTL_SECONDS="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ "$TTL_SECONDS" =~ ^[0-9]+$ ]] || usage

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

now_epoch() { date +%s; }
now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/a2a"
CACHE_FILE="$CACHE_DIR/preflight.json"
CACHE_SOURCE="fresh"
CACHE_AGE_SECONDS=0

_run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 5 "$@" 2>&1
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 5 "$@" 2>&1
  else
    "$@" 2>&1
  fi
}

_probe_cli() {
  local cli="$1"
  local raw=""

  raw=$(_run_with_timeout "$cli" --version || true)
  raw=$(printf '%s' "$raw" | sed 's/\x1b\[[0-9;]*m//g; s/\x1b\[[0-9;]*[A-Za-z]//g')
  printf '%s' "$raw" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

_probe_claude_auth() {
  local raw=""

  raw=$(_run_with_timeout claude auth status || true)
  [[ -z "$raw" ]] && { printf 'unknown'; return; }

  python3 - "$raw" <<'PYEOF'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    print("unknown")
    raise SystemExit(0)

status = data.get("loggedIn")
if status is True:
    print("true")
elif status is False:
    print("false")
else:
    print("unknown")
PYEOF
}

_probe_codex_auth() {
  local raw=""

  raw=$(_run_with_timeout codex login status || true)
  raw=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')

  if [[ "$raw" == *"logged in"* ]]; then
    printf 'true'
  elif [[ "$raw" == *"not logged in"* || "$raw" == *"logged out"* ]]; then
    printf 'false'
  else
    printf 'unknown'
  fi
}

_is_ready() {
  local available="$1"
  local authenticated="$2"

  [[ "$available" == "true" && "$authenticated" != "false" ]]
}

_set_mode_flags() {
  local claude_ready="$(_is_ready "$_claude_ok" "$_claude_auth" && printf 'true' || printf 'false')"
  local codex_ready="$(_is_ready "$_codex_ok" "$_codex_auth" && printf 'true' || printf 'false')"

  _can_review=false
  _cross_model=false

  [[ "$claude_ready" == "true" || "$codex_ready" == "true" ]] && _can_review=true
  [[ "$claude_ready" == "true" && "$codex_ready" == "true" ]] && _cross_model=true

  if [[ "$_cross_model" == "true" ]]; then
    EXIT_CODE=0
  elif [[ "$_can_review" == "true" ]]; then
    EXIT_CODE=2
  else
    EXIT_CODE=3
  fi
}

_load_cache() {
  [[ "$TTL_SECONDS" == "0" ]] && return 1
  [[ "$FORCE_REFRESH" == "true" ]] && return 1
  [[ -f "$CACHE_FILE" ]] || return 1

  local shell_assignments=""
  shell_assignments="$(
    python3 - "$CACHE_FILE" "$TTL_SECONDS" "$(now_epoch)" <<'PYEOF'
import json
import pathlib
import shlex
import sys

cache_path = pathlib.Path(sys.argv[1])
ttl = int(sys.argv[2])
now = int(sys.argv[3])

try:
    data = json.loads(cache_path.read_text())
except Exception:
    raise SystemExit(1)

checked_at = int(data.get("checked_at_epoch", -1))
if checked_at < 0:
    raise SystemExit(1)

age = now - checked_at
if age < 0 or age > ttl:
    raise SystemExit(1)

def fmt_bool(value):
    return "true" if value else "false"

def fmt_auth(value):
    if value is None:
        return "unknown"
    return "true" if value else "false"

def emit(name, value):
    print(f"{name}={shlex.quote(str(value))}")

emit("_claude_ok", fmt_bool(bool(data.get("claude", {}).get("available", False))))
emit("_claude_ver", data.get("claude", {}).get("version", ""))
emit("_claude_auth", fmt_auth(data.get("claude", {}).get("authenticated")))
emit("_codex_ok", fmt_bool(bool(data.get("codex", {}).get("available", False))))
emit("_codex_ver", data.get("codex", {}).get("version", ""))
emit("_codex_auth", fmt_auth(data.get("codex", {}).get("authenticated")))
emit("_jq_ok", fmt_bool(bool(data.get("jq", False))))
emit("_can_review", fmt_bool(bool(data.get("can_review", False))))
emit("_cross_model", fmt_bool(bool(data.get("cross_model", False))))
emit("EXIT_CODE", data.get("exit_code", 3))
emit("CACHE_AGE_SECONDS", age)
PYEOF
  )" || return 1

  eval "$shell_assignments"
  CACHE_SOURCE="cached"
  return 0
}

_write_cache() {
  [[ "$TTL_SECONDS" == "0" ]] && return 0

  mkdir -p "$CACHE_DIR"
  python3 - "$CACHE_FILE" "$(now_epoch)" "$(now_iso)" \
    "$_claude_ok" "$_claude_ver" "$_claude_auth" \
    "$_codex_ok" "$_codex_ver" "$_codex_auth" \
    "$_jq_ok" "$_can_review" "$_cross_model" "$EXIT_CODE" <<'PYEOF'
import json
import pathlib
import sys

_, cache_file, checked_epoch, checked_at, claude_ok, claude_ver, claude_auth, \
    codex_ok, codex_ver, codex_auth, jq_ok, can_review, cross_model, exit_code = sys.argv

def b(value):
    return value == "true"

def auth(value):
    if value == "unknown":
        return None
    return value == "true"

data = {
    "checked_at": checked_at,
    "checked_at_epoch": int(checked_epoch),
    "claude": {
        "available": b(claude_ok),
        "version": claude_ver,
        "authenticated": auth(claude_auth),
    },
    "codex": {
        "available": b(codex_ok),
        "version": codex_ver,
        "authenticated": auth(codex_auth),
    },
    "jq": b(jq_ok),
    "can_review": b(can_review),
    "cross_model": b(cross_model),
    "exit_code": int(exit_code),
}

path = pathlib.Path(cache_file)
path.write_text(json.dumps(data, indent=2) + "\n")
PYEOF
}

_detect_fresh() {
  _claude_ok=false
  _claude_ver=""
  _claude_auth="unknown"
  _codex_ok=false
  _codex_ver=""
  _codex_auth="unknown"
  _jq_ok=false

  if command -v claude >/dev/null 2>&1; then
    _claude_ver=$(_probe_cli claude)
    if [[ -n "$_claude_ver" ]]; then
      _claude_ok=true
      _claude_auth=$(_probe_claude_auth)
    fi
  fi

  if command -v codex >/dev/null 2>&1; then
    _codex_ver=$(_probe_cli codex)
    if [[ -n "$_codex_ver" ]]; then
      _codex_ok=true
      _codex_auth=$(_probe_codex_auth)
    fi
  fi

  command -v jq >/dev/null 2>&1 && _jq_ok=true
  _set_mode_flags
  _write_cache
}

_status_suffix() {
  local authenticated="$1"
  case "$authenticated" in
    true) printf 'auth ok' ;;
    false) printf 'login required' ;;
    *) printf 'auth unknown' ;;
  esac
}

_print_cli_line() {
  local name="$1"
  local available="$2"
  local version="$3"
  local authenticated="$4"
  local install_hint="$5"
  local login_hint="$6"

  if [[ "$available" != "true" ]]; then
    fail "${name}  not installed"
    info "Install: ${install_hint}"
    return
  fi

  local status
  status=$(_status_suffix "$authenticated")

  case "$authenticated" in
    true)
      ok "${name}  v${version} (${status})"
      ;;
    false)
      warn "${name}  v${version} (${status})"
      info "Login: ${login_hint}"
      ;;
    *)
      warn "${name}  v${version} (${status})"
      ;;
  esac
}

_print_json() {
  python3 - "$_claude_ok" "$_claude_ver" "$_claude_auth" \
    "$_codex_ok" "$_codex_ver" "$_codex_auth" \
    "$_jq_ok" "$_can_review" "$_cross_model" "$EXIT_CODE" \
    "$CACHE_SOURCE" "$CACHE_FILE" "$CACHE_AGE_SECONDS" "$TTL_SECONDS" <<'PYEOF'
import json
import sys

_, claude_ok, claude_ver, claude_auth, codex_ok, codex_ver, codex_auth, jq_ok, \
    can_review, cross_model, exit_code, cache_source, cache_path, cache_age, ttl_seconds = sys.argv

def b(value):
    return value == "true"

def auth(value):
    if value == "unknown":
        return None
    return value == "true"

print(json.dumps({
    "claude": {
        "available": b(claude_ok),
        "version": claude_ver,
        "authenticated": auth(claude_auth),
    },
    "codex": {
        "available": b(codex_ok),
        "version": codex_ver,
        "authenticated": auth(codex_auth),
    },
    "jq": b(jq_ok),
    "can_review": b(can_review),
    "cross_model": b(cross_model),
    "exit_code": int(exit_code),
    "cache": {
        "source": cache_source,
        "path": cache_path,
        "age_seconds": int(cache_age),
        "ttl_seconds": int(ttl_seconds),
    },
}, indent=2))
PYEOF
}

_print_human() {
  printf "\n${C_BOLD}${C_CYAN}┌─────────────────────────────────────────┐${C_RESET}\n"
  printf "${C_BOLD}${C_CYAN}│  a2a preflight — env & auth check       │${C_RESET}\n"
  printf "${C_BOLD}${C_CYAN}└─────────────────────────────────────────┘${C_RESET}\n\n"

  if [[ "$CACHE_SOURCE" == "cached" ]]; then
    info "Using cached result (${CACHE_AGE_SECONDS}s old, ttl ${TTL_SECONDS}s). Run --refresh to bypass."
  elif [[ "$TTL_SECONDS" == "0" ]]; then
    info "Cache disabled for this run."
  else
    info "Fresh check completed. Cache ttl: ${TTL_SECONDS}s"
  fi
  info "Preflight checks local CLI/auth state only. It does not send a review request."
  printf "\n${C_DIM}  Checking available CLIs...${C_RESET}\n\n"

  _print_cli_line "Claude CLI" "$_claude_ok" "$_claude_ver" "$_claude_auth" \
    "npm install -g @anthropic-ai/claude-code" "claude auth login"
  _print_cli_line "Codex CLI " "$_codex_ok" "$_codex_ver" "$_codex_auth" \
    "npm install -g @openai/codex" "codex login"

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
    warn "One side is missing or logged out. Cross-model adversarial review unavailable."
  else
    printf "${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    printf "${C_RED}${C_BOLD}  MISSING — cannot run reviews${C_RESET}\n"
    printf "${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n\n"
    fail "At least one reviewer CLI with usable auth is required."
  fi

  echo ""
}

if ! _load_cache; then
  _detect_fresh
fi

if [[ "$JSON_MODE" == "true" ]]; then
  _print_json
else
  _print_human
fi

exit "$EXIT_CODE"
