---
description: statusLine(상태바)를 ~/.claude에 설치 — 번들된 setup-statusline.sh 실행 (Claude Code 전용)
disable-model-invocation: true
---

이 플러그인에 번들된 statusLine 설치기를 실행해 상태바를 설치한다. 상태바는 Claude Code만 읽는 `~/.claude/settings.json`과 `~/.claude/statusline.py`를 쓰므로 Codex·Antigravity에는 효과가 없다 — 그래서 스킬이 아니라 Claude 전용 커맨드로 둔다.

1. Bash로 실행한다:
   ```bash
   SCRIPT_PATH="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/setup-statusline.sh}"
   # 환경변수가 없으면 설치된 플러그인 중 가장 높은 버전을 쓴다 (옛 버전 캐시가 여러 개 남아 있을 수 있다)
   [ -f "$SCRIPT_PATH" ] || SCRIPT_PATH="$(ls "$HOME"/.claude/plugins/cache/agent-system/agent-system/*/setup-statusline.sh 2>/dev/null | sort -V | tail -1)"
   [ -f "$SCRIPT_PATH" ] || { echo "setup-statusline.sh를 찾을 수 없습니다 — agent-system 플러그인이 설치돼 있는지 확인하세요" >&2; exit 1; }
   bash "$SCRIPT_PATH"
   ```
   - 현재 폴더의 `./setup-statusline.sh`나 `find`로 찾은 첫 파일은 쓰지 않는다. 엉뚱한 스크립트나 옛 버전이 실행될 수 있다.
   - 이 스크립트는 번들된 `statusline/statusline.py`를 `~/.claude/statusline.py`로 심링크하고, `~/.claude/settings.json`에 `statusLine` 키를 머지한다(기존 settings.json은 `~/.claude/backups/`로 백업).
2. 스크립트 출력(심링크 경로 · 설정 경로)을 사용자에게 그대로 전한다.
3. 마지막에 안내한다: **"새 세션 또는 재시작 후 입력창 아래에 상태바가 나타납니다."**

스크립트가 0이 아닌 코드로 종료하면 출력을 보여주고 원인을 설명한다. 그 외 다른 작업은 하지 않는다.
