#!/usr/bin/env bash
# a2a-health — 一键自检 + 自动修复 token bridge
# 用法：直接跑，不需要参数。忘了 preflight 也没事，这个脚本会帮你补上。
#
# Exit codes: 0=全部正常, 1=有问题需要人工介入

set -euo pipefail

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
fix()  { printf "${C_CYAN}  ↻${C_RESET} %s\n" "$1"; }

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/a2a"
TOKEN_FILE="$CACHE_DIR/.claude-token"
PREFLIGHT_CACHE="$CACHE_DIR/preflight.json"
SKILL_DIR=""
HAS_ISSUES=false

# 找到 skill 目录
for candidate in \
  "$(dirname "$(cd "$(dirname "$0")" && pwd)")" \
  "$HOME/.claude/skills/a2a" \
  ; do
  if [[ -f "$candidate/SKILL.md" ]]; then
    SKILL_DIR="$candidate"
    break
  fi
done

printf "\n${C_BOLD}${C_CYAN}┌─────────────────────────────────────────┐${C_RESET}\n"
printf "${C_BOLD}${C_CYAN}│  a2a health check                       │${C_RESET}\n"
printf "${C_BOLD}${C_CYAN}└─────────────────────────────────────────┘${C_RESET}\n\n"

# ============================================================
# 1. Skill 安装
# ============================================================
printf "${C_BOLD}  [1/5] Skill 安装${C_RESET}\n"

if [[ -n "$SKILL_DIR" ]]; then
  ok "SKILL.md found: $SKILL_DIR"
else
  fail "找不到 a2a SKILL.md"
  info "安装: cp -r agent-2-agent ~/.claude/skills/a2a"
  HAS_ISSUES=true
fi

# ============================================================
# 2. CLI 可用性
# ============================================================
printf "\n${C_BOLD}  [2/5] CLI 可用性${C_RESET}\n"

CLAUDE_OK=false
CODEX_OK=false

if command -v claude >/dev/null 2>&1; then
  ver=$(claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
  if [[ -n "$ver" ]]; then
    ok "Claude CLI v$ver"
    CLAUDE_OK=true
  else
    fail "Claude CLI 已安装但无法获取版本"
    HAS_ISSUES=true
  fi
else
  fail "Claude CLI 未安装"
  info "安装: npm install -g @anthropic-ai/claude-code"
  HAS_ISSUES=true
fi

if command -v codex >/dev/null 2>&1; then
  ver=$(codex --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
  if [[ -n "$ver" ]]; then
    ok "Codex CLI v$ver"
    CODEX_OK=true
  else
    fail "Codex CLI 已安装但无法获取版本"
    HAS_ISSUES=true
  fi
else
  warn "Codex CLI 未安装（跨模型 adversarial 不可用，降级为 single-model）"
  info "安装: npm install -g @openai/codex"
fi

# ============================================================
# 3. Auth 状态
# ============================================================
printf "\n${C_BOLD}  [3/5] Auth 状态${C_RESET}\n"

# Claude auth
CLAUDE_AUTH="unknown"
if [[ "$CLAUDE_OK" == "true" ]]; then
  raw=$(claude auth status 2>&1 || true)
  status=$(printf '%s' "$raw" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    v = data.get('loggedIn')
    print('true' if v is True else ('false' if v is False else 'unknown'))
except: print('unknown')
" 2>/dev/null || echo "unknown")

  if [[ "$status" == "true" ]]; then
    ok "Claude auth: logged in"
    CLAUDE_AUTH="true"
  elif [[ "$status" == "false" ]]; then
    warn "Claude auth: not logged in (子进程可能无法访问 Keychain)"
    CLAUDE_AUTH="false"
  else
    warn "Claude auth: unknown"
  fi
fi

# Codex auth
if [[ "$CODEX_OK" == "true" ]]; then
  raw=$(codex login status 2>&1 || true)
  raw_lower=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  if [[ "$raw_lower" == *"logged in"* && "$raw_lower" != *"not logged in"* ]]; then
    ok "Codex auth: logged in"
  elif [[ "$raw_lower" == *"not logged in"* || "$raw_lower" == *"not authenticated"* ]]; then
    warn "Codex auth: not logged in"
    info "登录: codex login"
    HAS_ISSUES=true
  else
    warn "Codex auth: unknown"
  fi
fi

# ============================================================
# 4. Token Bridge
# ============================================================
printf "\n${C_BOLD}  [4/5] Token Bridge${C_RESET}\n"

TOKEN_OK=false

if [[ -s "$TOKEN_FILE" ]]; then
  # 检查 token 文件年龄
  if [[ "$(uname)" == "Darwin" ]]; then
    file_epoch=$(stat -f %m "$TOKEN_FILE" 2>/dev/null || echo 0)
  else
    file_epoch=$(stat -c %Y "$TOKEN_FILE" 2>/dev/null || echo 0)
  fi
  now_epoch=$(date +%s)
  age=$(( now_epoch - file_epoch ))
  age_hours=$(( age / 3600 ))

  if (( age > 86400 )); then
    warn "Token 文件存在但已 ${age_hours}h 未更新（可能过期）"
  else
    ok "Token 文件存在 (${age_hours}h ago, $(wc -c < "$TOKEN_FILE" | tr -d ' ')B)"
    TOKEN_OK=true
  fi

  # 验证 token 是否真的能用
  token_val=$(cat "$TOKEN_FILE" 2>/dev/null)
  if [[ "$token_val" == sk-ant-* ]]; then
    ok "Token 格式正确 (sk-ant-*)"
  else
    fail "Token 格式异常"
    HAS_ISSUES=true
    TOKEN_OK=false
  fi
else
  warn "Token 文件不存在: $TOKEN_FILE"
fi

# 自动修复：尝试从 Keychain 提取
if [[ "$TOKEN_OK" == "false" && "$(uname)" == "Darwin" ]]; then
  fix "尝试从 macOS Keychain 提取 token..."
  raw_cred=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)

  if [[ -n "$raw_cred" ]]; then
    token=$(printf '%s' "$raw_cred" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    t = data.get('claudeAiOauth', {}).get('accessToken', '')
    if t: print(t)
except: pass
" 2>/dev/null || true)

    if [[ -n "$token" ]]; then
      mkdir -p "$CACHE_DIR"
      printf '%s' "$token" > "$TOKEN_FILE"
      chmod 600 "$TOKEN_FILE"
      ok "Token 已从 Keychain 提取并缓存到 $TOKEN_FILE"
      TOKEN_OK=true
    else
      fail "Keychain 中有 credential 但无法提取 accessToken"
      HAS_ISSUES=true
    fi
  else
    fail "macOS Keychain 中未找到 Claude Code credentials"
    info "请先登录: claude auth login"
    HAS_ISSUES=true
  fi
fi

# 实际调用测试
if [[ "$TOKEN_OK" == "true" ]]; then
  token_val=$(cat "$TOKEN_FILE" 2>/dev/null)
  test_result=$(env -u CLAUDECODE ANTHROPIC_API_KEY="$token_val" claude -p "只回复 OK" 2>&1 | head -1 || true)
  test_lower=$(printf '%s' "$test_result" | tr '[:upper:]' '[:lower:]')
  if [[ "$test_lower" == *"ok"* ]]; then
    ok "claude -p 实际调用成功 (token bridge 可用)"
  else
    fail "claude -p 调用失败: $test_result"
    info "Token 可能已过期，尝试重新登录: claude auth login"
    HAS_ISSUES=true
    TOKEN_OK=false
  fi
fi

# ============================================================
# 5. 综合判定
# ============================================================
printf "\n${C_BOLD}  [5/5] 综合判定${C_RESET}\n"

if [[ "$CLAUDE_OK" == "true" && "$CODEX_OK" == "true" && "$TOKEN_OK" == "true" ]]; then
  printf "\n${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  printf "${C_GREEN}${C_BOLD}  ALL GOOD — 双向跨模型 adversarial 就绪${C_RESET}\n"
  printf "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  info "Claude → Codex: codex exec  ✓"
  info "Codex → Claude: claude -p + token bridge  ✓"
  echo ""
  exit 0
elif [[ "$CLAUDE_OK" == "true" && "$CODEX_OK" == "true" ]]; then
  printf "\n${C_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  printf "${C_YELLOW}${C_BOLD}  PARTIAL — Claude→Codex 可用，Codex→Claude 受限${C_RESET}\n"
  printf "${C_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  info "Claude → Codex: codex exec  ✓"
  warn "Codex → Claude: token bridge 不可用"
  info "修复: 在非 sandbox 终端运行本脚本，自动提取 token"
  echo ""
  exit 1
elif [[ "$CLAUDE_OK" == "true" ]]; then
  printf "\n${C_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  printf "${C_YELLOW}${C_BOLD}  PARTIAL — single-model-multi-lens 模式${C_RESET}\n"
  printf "${C_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  info "安装 Codex 解锁跨模型: npm install -g @openai/codex"
  echo ""
  exit 1
else
  printf "\n${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  printf "${C_RED}${C_BOLD}  BLOCKED — 无法运行 review${C_RESET}\n"
  printf "${C_RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  echo ""
  exit 1
fi
