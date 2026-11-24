---
name: sync-ai
description: >-
  공통 AI 설정 마스터(~/.agents/mcp.json, ~/.agents/skills/)와 Claude 플러그인 스킬을
  Antigravity(Gemini), Claude Code, Codex(GPT) 3개 플랫폼에 동기화한다.
  사용자가 "/sync-ai", "AI 설정 동기화", "MCP 동기화", "스킬 동기화", "새 MCP 추가해줘"를 요청할 때 사용한다.
---

# sync-ai — Gemini · Claude · Codex 통합 설정 동기화

## 단일 원본 (Single Source of Truth)

- **공통 MCP 마스터**: `~/.agents/mcp.json`
- **머신별 워크스페이스 설정 (선택)**: `~/.agents/sync-ai.json` (`{"workspaces": ["~/path/to/workspace"]}`)
- **공통 직접 스킬**: `~/.agents/skills/<skill-name>/SKILL.md`
- **실행 스크립트**: `~/.local/bin/sync-ai` (미설치 시 플러그인의 `scripts/sync-ai.py` 직접 실행 또는 `./setup-sync-ai.sh`)

## 실행 절차

1. **MCP 추가·수정 요청이 함께 있는 경우**
   - `~/.agents/mcp.json`의 `mcpServers`에 항목을 추가하거나 수정한다.
   - `targets`를 생략하면 `["antigravity", "claude", "codex"]` 3개 플랫폼 모두에 반영된다.
   - 특정 플랫폼에 이미 플러그인으로 로드된 MCP라면 중복 방지를 위해 `targets`를 필요한 플랫폼으로 제한한다.
   - 사내 프록시/사설 CA 환경에서 HTTPS를 호출하는 Stdio MCP는 필요 시 `env`에 `NODE_EXTRA_CA_CERTS` 또는 `SSL_CERT_FILE`을 포함한다.
2. **동기화 실행**
   ```bash
   sync-ai
   ```
   *(PATH에 없으면 `python3 ~/.local/bin/sync-ai` 또는 플러그인 경로의 `scripts/sync-ai.py` 실행)*
3. **검증 및 보고**
   - 출력된 플랫폼별 MCP/스킬 반영 건수를 확인한다.
   - `~/.codex/config.toml`이 존재하면 TOML 파싱 오류 여부를 확인한다:
     ```bash
     python3 -c 'import tomllib, pathlib; tomllib.load(open(pathlib.Path.home()/".codex/config.toml", "rb")); print("TOML OK")'
     ```
   - 결과를 플랫폼별(Antigravity · Claude · Codex)로 간결하게 요약 보고하고, 변경 사항은 새 세션/재시작부터 적용됨을 안내한다.
