---
name: wiki
description: Use when the user wants to query, record, update, or lint the location-based LLM Wiki knowledge base — e.g., asking "위키에서 찾아봐", "위키에 정리해줘", "wiki", "지식베이스", "트러블슈팅 위키에 기록", or when archiving a completed handoff that contains reusable domain/architecture/troubleshooting knowledge. Each wiki's location is its scope (a repo's docs/wiki, a parent folder's docs/wiki, or the global wiki), with category folders directly inside; managed via index.md and wiki-index.sh.
---

# LLM Wiki (위치 기반 지식베이스 조회 · 편입 · 관리)

코드·아키텍처·도메인 정책·트러블슈팅·외부 연동 스펙처럼 **단일 작업(티켓)이 끝나도 계속 참조해야 하는 장기 지식**을 마크다운 위키로 컴파일하고 조회한다.

## 기존 시스템과의 역할 분담 (중요)

[agent-system](../../README.md) 안에서 지식은 수명과 성격에 따라 세 곳으로 나뉜다:

| 구분 | 담당 도구 | 무엇을 담는가 | 수명 |
|---|---|---|---|
| 진행 중인 작업 상태 | `save-context` / `load-context` | 지금 하던 티켓의 진행 상황, 실패한 시도, 당장 다음 할 일 | 단기 (끝나면 `archive/`) |
| 짧은 작업/코드 규칙 | repo 루트 `AGENTS.md` | "dev 서버 띄운 채 e2e 금지"처럼 항상 지켜야 할 1~2줄 행동 수칙 | 영구 (항상 자동 로드) |
| **도메인·아키텍처·트러블슈팅** | **`wiki` (이 스킬)** | **왜 그렇게 설계했는지, 시스템 흐름, 깊은 버그 원인과 해결 과정, 외부 연동 스펙** | **장기 (목차 기반으로 필요할 때 조회·갱신)** |

---

## 위키 하나 = 적용 범위 하나

위키가 놓인 위치가 곧 그 위키의 적용 범위다. 위키 안에는 범위를 나누는 폴더(공통용·프로젝트별)를 두지 않고, 위키 루트 바로 아래가 카테고리 폴더다(`<위키루트>/<카테고리>/<문서>.md`).

| 위키 위치 | 적용 범위 | 담는 지식 |
|---|---|---|
| `<repo>/docs/wiki/` | 그 repo | 그 repo에서만 쓰는 아키텍처·API·트러블슈팅 |
| `<상위폴더>/docs/wiki/` | 그 폴더 아래 모든 프로젝트 | 여러 repo가 함께 쓰는 도메인 정책·공통 DB·인프라·인증 구조 |
| `~/.agent-system/wiki/` | 어디서나 | 범용 기술·클라우드(OCI, Cloudflare, Supabase 등)·언어·개발 환경 지식 |

조회할 때는 현재 위치에서 위로 올라가며 만나는 `docs/wiki`를 가까운 순으로 모두 보고(위키 사슬), 마지막에 전역 위키를 본다. 같은 repo를 다른 폴더에 펼친 worktree에서는 같은 위키가 두 번 잡히지 않도록 가장 가까운 하나만 쓴다.

- **repo 위키를 git에 커밋하면** 그 repo의 worktree(Orca·Claude Code 작업 폴더 등)에서도 그대로 보인다.
- 위키는 기본으로 git에서 빠지므로(`init` 기본 = local 무시) Orca·git worktree에서는 `link`로 연결해야 조회된다. `--ignore none`으로 커밋한 위키만 worktree에 같이 들어온다. repo 안에 있지만 무시되는 상위 폴더 위키도 마찬가지다.

---

## 준비 — 스크립트와 현재 위치의 위키 사슬 확인

모든 작업(조회·편입·점검) 전에 먼저 한 번 실행해 현재 위치에서 조회되는 위키를 확인한다:

```bash
WIKI_SH="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/wiki-index.sh}"
[ -f "$WIKI_SH" ] || WIKI_SH="$HOME/.agent-system/bin/wiki-index.sh"
[ -f "$WIKI_SH" ] || { echo "wiki-index.sh를 찾을 수 없습니다 — 플러그인 폴더에서 ./setup.sh를 먼저 실행하세요" >&2; exit 1; }
"$WIKI_SH" resolve .
```

출력은 `WIKI=<경로>` 줄 0개 이상(가까운 순)과 `GLOBAL_WIKI=<경로>` 한 줄이다. `resolve`·`list`·`search`·`lint`·`links`는 읽기 전용이라 어떤 파일도 만들지 않는다 — 위키 파일은 `init`·`upsert`·`remove`·`rebuild`에서만 생긴다.

- `WIKI=` 줄이 없으면 현재 위치 위쪽에 `docs/wiki`가 없고 `link`로 연결된 위키도 없는 상태다. 기존 위키에 연결하거나 새로 만드는 절차는 [references/ingest.md](references/ingest.md)의 0단계에 있다.
- `link`로 등록한 연결은 위쪽에서 찾은 위키들 다음 순서로 붙는다(`"$WIKI_SH" links`로 목록 확인).

---

## 동작별 절차 — 요청에 맞는 파일 하나만 읽는다

위의 "준비"를 마친 뒤, 요청에 해당하는 파일만 읽고 그 절차를 따른다 (경로는 이 SKILL.md 기준):

| 요청 | 읽을 파일 |
|---|---|
| 위키에서 찾기 · 과거 구현/트러블슈팅/도메인 지식 질문 | [references/query.md](references/query.md) |
| 위키에 기록 · 갱신 · 핸드오프(`save-context --done`)에서 건진 지식 편입 · 위키 새로 만들기 | [references/ingest.md](references/ingest.md) |
| 위키 점검 · 정리(lint) | [references/lint.md](references/lint.md) |

---

## 작성 원칙

- **검증된 사실만 단정형으로 적는다.** 실제 확인한 설정값·포트·파일 경로·원인만 적고, 추측은 넣지 않는다.
- **시크릿(API 키·비밀번호·개인 토큰 원문)과 개인정보·계정 식별자(이메일, 계정 ID, 테넌시 이름 등)는 위키에 적지 않는다.** 위키는 git으로 공유될 수 있다. 환경변수 이름(`CLOUDFLARE_API_TOKEN` 등), 설정 파일 경로(`~/.oci/config`), 값을 확인하는 명령(`wrangler whoami`)만 적는다.
- **커밋은 자동으로 하지 않는다.** 위키 파일과 색인만 갱신하고, 경로와 변경 요약을 사용자에게 보고한다.
