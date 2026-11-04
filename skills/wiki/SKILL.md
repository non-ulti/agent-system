---
name: wiki
description: Use when the user wants to query, record, update, or lint the hierarchical LLM Wiki knowledge base — e.g., asking "위키에서 찾아봐", "위키에 정리해줘", "wiki", "지식베이스", "트러블슈팅 위키에 기록", or when archiving a completed handoff that contains reusable domain/architecture/troubleshooting knowledge. Manages 3-tier knowledge scopes (Project, Workspace Common, Global Common) via index.md and wiki-index.sh.
---

# LLM Wiki (계층형 지식베이스 조회 · 편입 · 관리)

코드·아키텍처·도메인 정책·트러블슈팅·외부 연동 스펙처럼 **단일 작업(티켓)이 끝나도 계속 참조해야 하는 장기 지식**을 마크다운 위키로 컴파일하고 조회한다.

## 기존 시스템과의 역할 분담 (중요)

[agent-system](../../README.md) 안에서 지식은 수명과 성격에 따라 세 곳으로 나뉜다:

| 구분 | 담당 도구 | 무엇을 담는가 | 수명 |
|---|---|---|---|
| 진행 중인 작업 상태 | `save-context` / `load-context` | 지금 하던 티켓의 진행 상황, 실패한 시도, 당장 다음 할 일 | 단기 (끝나면 `archive/`) |
| 짧은 작업/코드 규칙 | repo 루트 `AGENTS.md` | "dev 서버 띄운 채 e2e 금지"처럼 항상 지켜야 할 1~2줄 행동 수칙 | 영구 (항상 자동 로드) |
| **도메인·아키텍처·트러블슈팅** | **`wiki` (이 스킬)** | **왜 그렇게 설계했는지, 시스템 흐름, 깊은 버그 원인과 해결 과정, 외부 연동 스펙** | **장기 (목차 기반으로 필요할 때 조회·갱신)** |

---

## 3계층 위키 스코프 구조

위키는 작업 위치에 따라 자동으로 3계층으로 나뉘어 관리된다:

1. **프로젝트 위키 (`<WS_WIKI>/<프로젝트>/`)**
   - 특정 repo/서비스(예: `shop-api`, `admin-web`, `my-blog`)에만 해당하는 아키텍처·API·트러블슈팅.
2. **워크스페이스 공통 위키 (`<WS_WIKI>/common/`)**
   - 같은 상위 워크스페이스(예: 회사 폴더 `company/docs/wiki/common/`, 개인 모노레포 `personal/docs/wiki/common/`) 안의 여러 프로젝트가 함께 공유하는 도메인 정책·공통 DB·인프라·인증 구조.
   - 회사 개별 repo(`company/shop-api` 등) 바깥인 상위 워크스페이스(`company/docs/wiki/`)에 놓이므로 개별 repo의 `git status`를 더럽히지 않으면서 회사 프로젝트 전체가 지식을 공유한다.
3. **전역 공통 위키 (`~/.agent-system/wiki/common/`)**
   - 회사·개인 구분 없이 어디서나 재사용하는 범용 기술·클라우드(OCI, Cloudflare, Supabase 등)·언어·개발 환경 지식.

---

## 준비 — 스크립트와 현재 위치의 위키 경로 확인

모든 작업(조회·편입·점검) 전에 먼저 한 번 실행해 현재 위치의 3계층 경로를 확인한다:

```bash
WIKI_SH="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/wiki-index.sh}"
[ -f "$WIKI_SH" ] || WIKI_SH="$HOME/.agent-system/bin/wiki-index.sh"
[ -f "$WIKI_SH" ] || { echo "wiki-index.sh를 찾을 수 없습니다 — 플러그인 폴더에서 ./setup.sh를 먼저 실행하세요" >&2; exit 1; }
"$WIKI_SH" resolve .
```

출력되는 4개 값(`GLOBAL_WIKI`, `WS_ROOT`, `WS_WIKI`, `PROJECT`)을 확인한다. `resolve`·`list`·`search`·`lint`는 읽기 전용이라 어떤 파일도 만들지 않는다 — 위키 파일은 `init-ws`·`init-project`·`upsert`·`remove`·`rebuild`에서만 생긴다.

- `WS_WIKI`가 `-`이면 현재 위치 위쪽에 `docs/wiki`가 없는 상태다. 새 문서를 기록하기 전에 어디에 만들지 사용자에게 확인한 뒤 둘 중 하나로 초기화한다:
  - 여러 프로젝트를 묶는 상위 폴더(예: `company/`, `personal/`): `"$WIKI_SH" init-ws <워크스페이스경로>` — 바로 아래 1단계 폴더명이 프로젝트 스코프가 된다.
  - 프로젝트 하나만 쓰는 repo: `"$WIKI_SH" init-project <프로젝트경로>` — `docs/wiki/.project` 표식이 생기고, repo 안 어느 하위 폴더에서든 프로젝트 스코프가 그 repo 이름으로 고정된다.
- 워크스페이스 루트 자체에서 실행하면 `PROJECT=common`이다.

---

## 동작 1: 조회 (Query — 위키에서 지식 찾기)

사용자가 질문하거나 과거 구현/트러블슈팅/도메인 지식을 찾을 때 수행한다.

1. **목차(`index.md`)와 목록부터 본다 (전체 문서 무작정 읽기 금지).**
   ```bash
   "$WIKI_SH" list .
   ```
   - 필요하면 키워드로 검색한다:
     ```bash
     "$WIKI_SH" search "<키워드>" .
     ```
2. **관련된 문서 1~3개만 골라 읽는다.**
   - `<WS_WIKI>/<PROJECT>/<슬러그>.md` (현재 프로젝트 전용)
   - `<WS_WIKI>/common/<슬러그>.md` (워크스페이스 공통)
   - `<GLOBAL_WIKI>/common/<슬러그>.md` (전역 공통)
3. **답변할 때 참조한 위키 문서 경로를 함께 안내한다.**
   - 코드와 대조가 필요한 내용이면 위키 내용을 바탕으로 실제 코드 파일이 현재도 같은지 빠르게 확인한다.

---

## 동작 2: 기록·편입 (Ingest & Compile — 위키에 지식 쌓기)

새로 알아낸 아키텍처, 트러블슈팅 해결 과정, 도메인 스펙, 또는 완료된 핸드오프(`save-context --done`)에서 건져 올린 지식을 위키에 반영할 때 수행한다.

### 1단계: 어느 계층(스코프)에 넣을지 결정한다
- **이 프로젝트(`PROJECT`)에만 해당하는가?** → ` 위키루트 = <WS_WIKI>`, `스코프 = <PROJECT>`
- **같은 워크스페이스(예: 회사 `company` 폴더 내 여러 repo)에서 공통으로 쓰이는 도메인/인프라인가?** → `위키루트 = <WS_WIKI>`, `스코프 = common`
- **회사·개인 무관하게 어디서나 쓰는 범용 기술/인프라 지식인가?** → `위키루트 = <GLOBAL_WIKI>`, `스코프 = common`
- 애매하면 사용자에게 한 줄로 어느 스코프에 넣을지 확인한다.

### 2단계: 기존 문서가 있는지 먼저 확인한다 (컴파일 원칙)
- **LLM Wiki의 핵심은 "무작정 새 파일로 쌓지 않고 기존 문서를 최신 상태로 컴파일(병합·갱신)하는 것"이다.**
- `"$WIKI_SH" list .`로 같은 주제의 문서가 이미 있는지 본다:
  - **이미 있으면**: 기존 `.md` 파일을 먼저 읽고, 새로운 내용을 기존 구조에 자연스럽게 병합·갱신한다. 시대에 뒤떨어진 옛 설명은 고친다.
  - **없으면**: `<위키루트>/<스코프>/<카테고리>/<문서명>.md` (예: `troubleshooting/cdn-cache-miss.md`, `architecture/auth-flow.md`, `infra/oci-setup.md`) 경로로 새 파일을 만든다. 카테고리 폴더는 `architecture`, `troubleshooting`, `domain`, `infra`, `guides` 등 직관적인 영문 소문자를 쓴다.

### 3단계: 위키 문서 작성 양식
문서 상단에 핵심 요약과 갱신일을 두고, 본문은 나중에 읽는 에이전트와 사람이 즉시 이해할 수 있게 구조화한다:

```markdown
# <문서 제목>

- **스코프**: `<스코프>`
- **갱신일**: <YYYY-MM-DD>
- **태그**: `<태그1>`, `<태그2>`
- **요약**: <이 문서가 다루는 핵심 내용 한 줄 요약>

---

## 배경 / 핵심 요약
<왜 이 구조/문제가 생겼고 결론이 무엇인지 3~5줄 이내로 요약>

## 상세 내용
<아키텍처 흐름, 설정값, 코드 위치(`경로:줄번호` 또는 파일 경로), 원인 분석, 해결 단계 등>

## 주의사항 · 관련 문서
- <건드리면 안 되는 설정이나 함정>
- 관련 문서: [다른 위키 문서](../common/xxx.md)
```

### 4단계: 색인(`wiki.tsv`), 목차(`index.md`), 변경 이력(`log.md`) 동기화
문서 파일을 저장한 뒤 **반드시** 아래 명령을 실행해 색인과 `index.md`, `log.md`를 자동 갱신한다 (`index.md`를 수동으로 편집하지 않는다). 스코프에는 `/`를 쓸 수 없고, 슬러그에는 `.`·`..` 경로 조각을 쓸 수 없다(스크립트가 거부한다). 워크스페이스 위키에 처음 `upsert`하면 다른 위치에서도 `search`되도록 전역 목록(`roots.tsv`)에 등록된다:

```bash
NOW="$(date '+%Y-%m-%d %H:%M')"
"$WIKI_SH" upsert "<위키루트>" "<스코프>" "<슬러그(확장자 제외, 예: troubleshooting/cdn-cache-miss)>" "$NOW" "<제목>" "<한 줄 요약>" "<쉼표로 구분한 태그>"
```

---

## 동작 3: 점검·정리 (Lint)

사용자가 "위키 점검해줘", "wiki lint"를 요청하거나 문서를 대거 이동·삭제한 뒤 실행한다:

```bash
"$WIKI_SH" lint "<WS_WIKI>"
"$WIKI_SH" lint "<GLOBAL_WIKI>"
```

- **색인 누락(고아 파일)**: 파일은 있는데 `wiki.tsv`에 빠진 문서는 내용을 읽어 `upsert`로 색인에 등록할지 묻는다.
- **파일 실종**: 파일이 삭제·이동됐는데 색인에만 남은 항목은 `"$WIKI_SH" remove "<위키루트>" "<스코프>" "<슬러그>"`로 정리한다.

---

## 작성 원칙

- **검증된 사실만 단정형으로 적는다.** 실제 확인한 설정값·포트·파일 경로·원인만 적고, 추측은 넣지 않는다.
- **시크릿(API 키·비밀번호·개인 토큰 원문)과 개인정보·계정 식별자(이메일, 계정 ID, 테넌시 이름 등)는 위키에 적지 않는다.** 위키는 git으로 공유될 수 있다. 환경변수 이름(`CLOUDFLARE_API_TOKEN` 등), 설정 파일 경로(`~/.oci/config`), 값을 확인하는 명령(`wrangler whoami`)만 적는다.
- **커밋은 자동으로 하지 않는다.** 위키 파일과 색인만 갱신하고, 경로와 변경 요약을 사용자에게 보고한다.
