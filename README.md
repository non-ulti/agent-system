# agent-system

NonUlti 개인 공통 Claude Code 플러그인. 여러 프로젝트·머신에서 공유하는 작업 컨벤션을 담는다.
단일 repo가 플러그인이자 자기 마켓플레이스(`source: "./"`)다.

## 담긴 것

- **save-context** — 현재 세션 작업 상태를 `.claude/HANDOFF.md`로 저장 (세션 핸드오프)
- **load-context** — `.claude/HANDOFF.md`를 읽고 현재 상태와 대조해 복원 브리핑
- **sync-ai** — 공통 마스터(`~/.agents/mcp.json`, `~/.agents/skills/`)와 Claude 플러그인 스킬을 Antigravity(Gemini) · Claude · Codex(GPT) 3개 플랫폼에 동기화

두 스킬은 슬래시(`/agent-system:save-context` — `agent-system`이 플러그인 이름 접두사)로도, 자연어("컨텍스트 저장해줘")로도 호출된다.

> 명령 표기: `/plugin ...`은 Claude Code 세션 안에서 쓰는 슬래시 커맨드, `claude plugin ...`은 셸에서 쓰는 CLI다. 같은 동작의 두 인터페이스이며 편한 쪽을 쓰면 된다.

## 설치 (각 머신에서)

```
/plugin marketplace add NonUlti/agent-system
/plugin install agent-system@agent-system
```

설치 후 Claude Code를 재시작하면 적용된다. (user scope가 기본)

## 사용

- 작업을 멈출 때: `/agent-system:save-context`
- 이어서 할 때(새 세션): `/agent-system:load-context`

`save-context`는 `.claude/HANDOFF.md`만 쓰고 커밋하지 않는다. 다른 머신으로 옮기려면 그 파일을 직접 커밋·push 하고, 받는 머신에서 `git pull` 한다.

## 업데이트 (내용 수정 후)

1. `skills/` 등 수정
2. 버전 bump — `.claude-plugin/plugin.json`과 `marketplace.json`의 `version` **둘 다** 같은 값으로
3. 권장: `claude plugin validate . --strict`
4. `git commit`
5. `git push` — 브랜치를 push 한다. `source: "./"`가 기본 브랜치를 추적하므로 **이 push가 실제 전파 경로**다.
6. (선택) `claude plugin tag --push` — 두 매니페스트의 버전 일치를 검증하고 `agent-system--v<버전>` 릴리스 태그를 남긴다. 전파용이 아니라 릴리스 마킹용.
7. 각 머신: `/plugin marketplace update agent-system` → `/plugin update agent-system` → 재시작

## 개발/로컬 테스트

push 전 로컬 작업 트리로 검증:
```
claude plugin marketplace add ~/agent-system
claude plugin install agent-system@agent-system
```
주의: install은 커밋 SHA로 스냅샷을 뜬다. 파일을 고쳤다면 커밋 + 버전 bump 후 marketplace update / plugin update 하고 세션을 재시작해야 반영된다.

## statusLine (커스텀 상태바)

Claude CLI 입력창 아래에 브랜치 · 모델 · effort · 비용 / 컨텍스트막대 · 토큰 · 레이트리밋을 표시하는 상태바.

설치 (머신당 1회) — 둘 중 하나:

- **플러그인으로 쓰는 경우 (권장):** Claude Code에서 `/agent-system:setup-statusline`
- **repo에서 직접:** `./setup-statusline.sh`

- `statusline/statusline.py`를 `~/.claude/statusline.py`로 심링크하고,
  `~/.claude/settings.json`에 `statusLine` 키만 머지한다(기존 설정은 `~/.claude/backups/`에 백업).
- 시스템 `python3`만 사용(외부 의존성 없음). 새 세션/재시작에서 반영된다.
- 설계: `docs/specs/2026-06-13-statusline-design.md`

## sync-ai (멀티 AI 설정 동기화)

공통 마스터(`~/.agents/mcp.json`, `~/.agents/skills/`)와 Claude 플러그인 스킬을 **Antigravity(Gemini) · Claude Code · Codex(GPT)** 3개 플랫폼에 한 번에 동기화한다.

설치 (머신당 1회):
```bash
./setup-sync-ai.sh
```

사용:
- 터미널: `sync-ai` (또는 `sync-ai --workspace ~/my-workspace`)
- 채팅창: `/sync-ai` (또는 `/agent-system:sync-ai`)
- 머신별 워크스페이스 목록은 `~/.agents/sync-ai.json`에 `{"workspaces": ["~/path/to/workspace"]}` 형태로 저장한다.
