# agent-system

여러 AI 에이전트 CLI에서 함께 쓰는 공통 플러그인. **Claude Code**, **Antigravity (Google)**, **Codex CLI (OpenAI)** 등 다양한 AI 플랫폼에서 공통으로 공유하는 작업 컨벤션과 세션 핸드오프를 제공합니다.

어느 AI CLI에서든 작업을 멈출 때 저장하고, 다른 AI CLI에서 이어서 작업할 수 있습니다.

## 담긴 것

- **save-context** — 현재 세션을 `~/.agent-system/handoffs/<슬러그>.md`로 저장. 자동 압축과 달리 다음 세션이 다시 알아낼 수 없는 것(사용자 지시, 해봤는데 안 된 방법, 조사로 확인한 사실)을 `놓치면 안 되는 것`으로 골라 그대로 남기고, repo 상태는 `handoff-index.sh baseline` 기준값으로 기록. 완료(`--done`) 시 장기 보존할 지식은 `wiki` 편입을 제안
- **load-context** — 저장된 핸드오프를 현재 repo 상태와 대조해 브리핑. `놓치면 안 되는 것`은 요약 없이 그대로 전하고, 작업 중 압축되면 핸드오프를 다시 읽는다
- **wiki** — 위치 기반 LLM Wiki 지식베이스. 위키 하나가 적용 범위 하나다: repo 전용은 `<repo>/docs/wiki`, 여러 repo 공통은 상위 폴더의 `docs/wiki`, 어디서나 쓰는 지식은 `~/.agent-system/wiki`이고, 위키 바로 아래가 카테고리 폴더다. 조회할 때는 현재 위치에서 위로 올라가며 만나는 위키를 가까운 순으로 모두 보고 전역 위키를 본다. `wiki-index.sh`를 통해 `wiki.tsv` 색인·`index.md` 목차·`log.md` 변경 이력을 일관되게 유지하며 아키텍처·도메인·트러블슈팅 지식을 누적·조회·점검(lint)한다. 위키는 `init`으로 만들고, git에서 뺀 위키가 들어오지 않는 작업 폴더(예: git worktree)는 `link`로 연결한다(git repo 안이면 `--ignore local`로 이 기기에서만, `--ignore shared`로 팀 전체에서 위키를 git 무시 목록에 넣을 수 있다)
- **/agent-system:setup-statusline** (커맨드) — Claude CLI 입력창 아래에 브랜치·토큰·비용을 표시하는 커스텀 상태바. Claude Code 전용이라 스킬이 아닌 `commands/`에 두며, Codex·Antigravity에서는 로드되지 않는다

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
git clone https://github.com/non-ulti/agent-system.git   # 이미 받아 둔 repo가 있으면 생략
agy plugin install /path/to/agent-system
```
(`agy plugin install`은 GitHub 주소를 받지 않고 로컬 폴더만 받는다. 폴더를 복사해 설치하므로 repo를 `git pull`한 뒤 다시 실행해야 업데이트된다.)

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
- **컨텍스트가 차기 전에 저장한다.** 자동 압축이 먼저 일어나면 압축 이전의 디테일은 save도 되살릴 수 없다(그 경우 save가 빠졌을 수 있는 부분을 알려 준다).
- **repo 규칙은 AGENTS.md로.** 작업이 끝나도 유효한 규칙(테스트 명령의 함정 등)을 찾으면 save가 그 repo의 `AGENTS.md`에 옮기자고 제안한다. AGENTS.md는 세 CLI가 공통으로 읽지만, Claude Code는 `CLAUDE.md`가 있으면 AGENTS.md를 읽지 않으므로 CLAUDE.md에 `@AGENTS.md` 한 줄을 함께 제안한다(2026-11 실측).
- **GitHub·GitLab 모두 쓸 수 있다.** 기준값에 원격 종류가 남아, PR/MR 상태를 확인할 때 `gh`/`glab` 중 맞는 도구를 고른다(조회는 사용자가 원할 때만).

어느 CLI에서 저장하든 공통 저장소(`~/.agent-system`)에 기록되므로, **Claude Code에서 저장하고 Codex나 Antigravity에서 복원하여 이어서 작업**할 수 있습니다.

## 업데이트 (내용 수정 후)

1. `skills/` 등 수정
2. 버전 bump — `.claude-plugin/plugin.json`, `marketplace.json`, 그리고 루트 `plugin.json` 3곳의 `version` 일치
3. 검증: `agy plugin validate .`
4. `git commit` & `git push`
5. 각 머신에서 플러그인 업데이트:
   - Claude: `/plugin marketplace update agent-system` → `/plugin update agent-system`
   - Codex: `codex plugin marketplace upgrade agent-system`
   - Antigravity: repo에서 `git pull` 후 `agy plugin install /path/to/agent-system`

## 개발/로컬 테스트

push 전 로컬 작업 트리로 검증:
```
claude plugin marketplace add ~/agent-system
claude plugin install agent-system@agent-system
```
주의: install은 커밋 SHA로 스냅샷을 뜬다. 파일을 고쳤다면 커밋 + 버전 bump 후 marketplace update / plugin update 하고 세션을 재시작해야 반영된다.

`scripts/wiki-index.sh`를 고쳤다면 `scripts/tests/wiki-index-test.sh`를 실행해 기존 동작이 그대로인지 확인한다(임시 폴더에서만 동작, 실제 `~/.agent-system`은 건드리지 않음).

## statusLine (커스텀 상태바)

Claude CLI 입력창 아래에 브랜치 · 모델 · effort · 비용 / 컨텍스트막대 · 토큰 · 레이트리밋을 표시하는 상태바.

설치 (머신당 1회) — 둘 중 하나:

- **플러그인으로 쓰는 경우 (권장):** Claude Code에서 `/agent-system:setup-statusline`
- **repo에서 직접:** `./setup-statusline.sh`

- `statusline/statusline.py`를 `~/.claude/statusline.py`로 심링크하고,
  `~/.claude/settings.json`에 `statusLine` 키만 머지한다(기존 설정은 `~/.claude/backups/`에 백업).
- 시스템 `python3`만 사용(외부 의존성 없음). 새 세션/재시작에서 반영된다.
