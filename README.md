# agent-system

NonUlti 개인 공통 AI 에이전트 플러그인. **Claude Code**, **Antigravity (Google)**, **Codex CLI (OpenAI)** 등 다양한 AI 플랫폼에서 공통으로 공유하는 작업 컨벤션과 세션 핸드오프를 제공합니다.

어느 AI CLI에서든 작업을 멈출 때 저장하고, 다른 AI CLI에서 이어서 작업할 수 있습니다.

## 담긴 것

- **save-context** — 현재 세션 작업 상태(브랜치, 커밋, 미커밋 파일/규모)를 `~/.agent-system/handoffs/<슬러그>.md`로 저장
- **load-context** — 저장된 핸드오프를 읽고 현재 repo 상태와 대조해 복원 브리핑
- **setup-statusline** — Claude CLI 입력창 아래에 브랜치·토큰·비용을 표시하는 커스텀 상태바 (Claude 전용)

스킬은 슬래시 커맨드(`/agent-system:save-context` 등) 또는 자연어("컨텍스트 저장해줘", "이어서 하자")로 자유롭게 호출됩니다.

## 플랫폼별 설치 (머신당 1회)

### 1. Claude Code
```bash
/plugin marketplace add NonUlti/agent-system
/plugin install agent-system@agent-system
```
(또는 셸에서 `claude plugin marketplace add NonUlti/agent-system && claude plugin install agent-system@agent-system`)

### 2. OpenAI Codex CLI
```bash
codex plugin marketplace add NonUlti/agent-system
codex plugin add agent-system@agent-system
```

### 3. Google Antigravity
```bash
agy plugin install NonUlti/agent-system
```
(로컬 레포지토리 직접 설치 시: `agy plugin install /path/to/agent-system`)

---

## 공통 초기화 (권장)

플러그인 설치 후 로컬 환경에 공통 핸드오프 디렉토리(`~/.agent-system`) 및 스크립트 도구를 심링크합니다:
```bash
./setup.sh
```
*기존 `~/.claude/agent-system`에 저장된 이전 핸드오프 내역이 있다면 자동으로 심링크되어 보존됩니다.*

## 사용법

- **작업을 멈출 때:** `/agent-system:save-context` (또는 "컨텍스트 저장")
- **이어서 할 때:** `/agent-system:load-context` (또는 "지난번 작업 복원", "이어서 하자")

어느 CLI에서 저장하든 공통 저장소(`~/.agent-system`)에 기록되므로, **Claude Code에서 저장하고 Codex나 Antigravity에서 복원하여 이어서 작업**할 수 있습니다.

## 업데이트 (내용 수정 후)

1. `skills/` 등 수정
2. 버전 bump — `.claude-plugin/plugin.json`, `marketplace.json`, 그리고 루트 `plugin.json` 3곳의 `version` 일치
3. 검증: `agy plugin validate .`
4. `git commit` & `git push`
5. 각 머신에서 플러그인 업데이트:
   - Claude: `/plugin marketplace update agent-system` → `/plugin update agent-system`
   - Codex: `codex plugin marketplace upgrade agent-system`
   - Antigravity: `agy plugin install NonUlti/agent-system`

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
