#!/usr/bin/env bash
# agent-system 공통 초기화 스크립트 (Claude Code, Antigravity, Codex 공통)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_SYSTEM_DIR="$HOME/.agent-system"
CLAUDE_DIR="$HOME/.claude"

# 기존 ~/.claude/agent-system 호환 심링크 생성
if [ -d "$CLAUDE_DIR/agent-system" ] && [ ! -e "$AGENT_SYSTEM_DIR" ]; then
  echo "• 기존 Claude Code 핸드오프 데이터를 발견하여 ~/.agent-system 으로 심링크 연결합니다."
  ln -s "$CLAUDE_DIR/agent-system" "$AGENT_SYSTEM_DIR"
fi

mkdir -p "$AGENT_SYSTEM_DIR/bin" "$AGENT_SYSTEM_DIR/handoffs"
chmod +x "$SCRIPT_DIR/scripts/handoff-index.sh"
ln -sf "$SCRIPT_DIR/scripts/handoff-index.sh" "$AGENT_SYSTEM_DIR/bin/handoff-index.sh"

echo "✓ agent-system 공통 환경 설정 완료!"
echo "  저장소: $AGENT_SYSTEM_DIR/handoffs"
echo "  도구:   $AGENT_SYSTEM_DIR/bin/handoff-index.sh"

if [ -d "$CLAUDE_DIR" ] && [ "${1:-}" != "--from-statusline" ]; then
  echo ""
  echo "※ Claude Code 상태바(statusLine)도 설정하시려면 아래 스크립트를 실행하세요:"
  echo "  $SCRIPT_DIR/setup-statusline.sh"
fi
