---
name: setup-statusline
description: Claude Code 전용 — 입력창 아래 상태바(statusLine)를 ~/.claude에 설치한다(statusline.py 심링크 + settings.json 등록). 사용자가 /agent-system:setup-statusline 으로 직접 부를 때만 실행한다. Codex·Antigravity에서는 쓰지 않는다.
disable-model-invocation: true
---

# Setup Statusline (Claude Code 전용 상태바 설치)

이 플러그인에 번들된 statusLine 설치기를 실행해 상태바를 설치한다. 전역 `~/.claude/settings.json`을 고치는 작업이라 사용자가 슬래시로 직접 부를 때만 실행되게 해 두었다(`disable-model-invocation`). "상태바가 이상하다" 같은 대화에서 저절로 설치가 돌면 안 된다.

## 실행 절차

1. 플러그인의 `setup-statusline.sh`를 실행한다:
   ```bash
   SCRIPT_PATH="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/setup-statusline.sh}"
   # 환경변수가 없으면 설치된 플러그인 중 가장 높은 버전을 쓴다 (옛 버전 캐시가 여러 개 남아 있을 수 있다)
   [ -f "$SCRIPT_PATH" ] || SCRIPT_PATH="$(ls "$HOME"/.claude/plugins/cache/agent-system/agent-system/*/setup-statusline.sh 2>/dev/null | sort -V | tail -1)"
   [ -f "$SCRIPT_PATH" ] || { echo "setup-statusline.sh를 찾을 수 없습니다 — agent-system 플러그인이 설치돼 있는지 확인하세요" >&2; exit 1; }
   bash "$SCRIPT_PATH"
   ```
   현재 폴더의 `./setup-statusline.sh`나 `find`로 찾은 첫 파일은 쓰지 않는다. 엉뚱한 스크립트나 옛 버전이 실행될 수 있다.

2. 스크립트 출력(심링크 경로 · 설정 경로)을 사용자에게 그대로 전한다.
3. 마지막에 안내한다: **"새 세션 또는 재시작 후 입력창 아래에 상태바가 나타납니다."**

스크립트가 0이 아닌 코드로 종료하면 출력을 보여주고 원인을 설명한다. 그 외 다른 작업은 하지 않는다.
