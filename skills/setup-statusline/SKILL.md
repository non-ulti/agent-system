---
name: setup-statusline
description: Claude Code CLI 상태바(statusLine)를 ~/.claude에 설치 — statusline.py 심링크 및 settings.json 등록
---

# Setup Statusline (Claude Code 전용 상태바 설치)

> [!NOTE]
> 이 기능은 Claude Code CLI 전용 상태 표시바(`~/.claude/settings.json`의 `statusLine` 설정)입니다.
> Antigravity 및 Codex 등 타 CLI에서는 무시해도 됩니다.

이 플러그인에 번들된 statusLine 설치기를 실행해 상태바를 설치한다.

## 실행 절차

1. 플러그인 루트의 `setup-statusline.sh`를 실행한다:
   ```bash
   SCRIPT_PATH=""
   if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/setup-statusline.sh" ]; then
     SCRIPT_PATH="$CLAUDE_PLUGIN_ROOT/setup-statusline.sh"
   elif [ -f "./setup-statusline.sh" ]; then
     SCRIPT_PATH="./setup-statusline.sh"
   else
     SCRIPT_PATH="$(find "$HOME/.claude" "$HOME/.codex" "$HOME/.gemini" -name "setup-statusline.sh" 2>/dev/null | head -1)"
   fi
   if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
     bash "$SCRIPT_PATH"
   else
     echo "setup-statusline.sh 스크립트를 찾을 수 없습니다." >&2
     exit 1
   fi
   ```

2. 스크립트 출력(심링크 경로 · 설정 경로)을 사용자에게 그대로 전한다.
3. 마지막에 안내한다: **"새 세션 또는 재시작 후 입력창 아래에 상태바가 나타납니다."**

스크립트가 0이 아닌 코드로 종료하면 출력을 보여주고 원인을 설명한다. 그 외 다른 작업은 하지 않는다.
