#!/usr/bin/env bash
# wiki-index.sh 회귀 테스트 — 임시 폴더 안에서만 동작하며 실제 ~/.agent-system은 건드리지 않는다
# 사용: scripts/tests/wiki-index-test.sh [샌드박스경로=mktemp]
set -u
W="$(cd "$(dirname "$0")/.." && pwd)/wiki-index.sh"
S="${1:-$(mktemp -d)}"
rm -rf "$S"; mkdir -p "$S"
S="$(cd "$S" && pwd -P)"
export AGENT_SYSTEM_HOME="$S/ash"; mkdir -p "$AGENT_SYSTEM_HOME/wiki/common"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
pass=0; fail=0
ok(){ if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
snap(){ find "$S" -not -path '*/.git/*' | sort; }

# 워크스페이스(git 모노레포 형태)
mkdir -p "$S/ws/proj/src" "$S/ws/docs/wiki"; git -C "$S/ws" init -q
# 단일 프로젝트 + 공백 경로
mkdir -p "$S/My Solo/src"; git -C "$S/My Solo" init -q
# 위키 없는 repo
mkdir -p "$S/bare/sub"; git -C "$S/bare" init -q

before="$(snap)"
"$W" resolve "$S/ws/proj/src" >/dev/null; "$W" list "$S/ws/proj" >/dev/null; "$W" search foo "$S/ws/proj" >/dev/null; "$W" lint "$S/ws/docs/wiki" >/dev/null
ok "T1 resolve/list/search/lint는 파일을 만들지 않음" '[ "$before" = "$(snap)" ]'

wikis(){ "$W" resolve "$1" | sed -n 's/^WIKI=//p'; }
ok "T2 워크스페이스 하위 → 워크스페이스 위키 1개" '[ "$(wikis "$S/ws/proj/src")" = "$S/ws/docs/wiki" ]'
mkdir -p "$S/ws/proj/docs/wiki"
ok "T3 레포 안 하위 폴더 위키 + 위쪽 위키, 가까운 순" '[ "$(wikis "$S/ws/proj/src")" = "$(printf "%s\n%s" "$S/ws/proj/docs/wiki" "$S/ws/docs/wiki")" ]'
ok "T4 위키 없음 → WIKI 줄 없음, GLOBAL_WIKI는 있음" '[ -z "$(wikis "$S/bare/sub")" ] && "$W" resolve "$S/bare/sub" | grep -q "^GLOBAL_WIKI="'
mkdir -p "$S/My Solo/docs/wiki"
ok "T5 공백 경로 사슬" '[ "$(wikis "$S/My Solo/src")" = "$S/My Solo/docs/wiki" ]'
ok "T6 공백 경로 list" '"$W" list "$S/My Solo/src" | grep -qF "=== $S/My Solo/docs/wiki ==="'
# 메인 체크아웃 안의 worktree (Claude Code .claude/worktrees 형태)
mkdir -p "$S/ws/r/docs/wiki"; git -C "$S/ws/r" init -q; echo x > "$S/ws/r/docs/wiki/k.md"
git -C "$S/ws/r" add -A; git -C "$S/ws/r" -c user.name=t -c user.email=t@example.invalid commit -qm i
git -C "$S/ws/r" worktree add -q "$S/ws/r/.claude/worktrees/w" -b w 2>/dev/null
ok "T-dup 같은 레포의 같은 위키는 가장 가까운 하나만" '[ "$(wikis "$S/ws/r/.claude/worktrees/w")" = "$(printf "%s\n%s" "$S/ws/r/.claude/worktrees/w/docs/wiki" "$S/ws/docs/wiki")" ]'

mkdir -p "$S/ws/docs/wiki/t"; echo "needle -x here" > "$S/ws/docs/wiki/t/a.md"
"$W" upsert "$S/ws/docs/wiki" t/a "2026-11-05 00:00" "A | B" "s | t" "x|y" >/dev/null
ok "T7 index.md 표의 | 이스케이프 + 범위 없는 경로" 'grep -qF "[A \| B](t/a.md) | s \| t | \`x\|y\`" "$S/ws/docs/wiki/index.md"'
ok "T7b 카테고리 제목" 'grep -qx "## t" "$S/ws/docs/wiki/index.md"'
ok "T8 log.md 이스케이프 + 4칸" 'grep -qF "| \`t/a.md\` | A \| B — s \| t |" "$S/ws/docs/wiki/log.md"'
ok "T9 upsert가 워크스페이스를 roots.tsv에 등록" 'grep -q "$S/ws/docs/wiki" "$AGENT_SYSTEM_HOME/wiki/roots.tsv"'
ok "T10 .gitignore로 .bak 제외" '[ -z "$(git -C "$S/ws" status --porcelain -- docs/wiki | grep bak)" ] && [ -f "$S/ws/docs/wiki/wiki.tsv.bak" ]'
ok "T11 '-'로 시작하는 검색어를 패턴으로 처리" '(cd "$S/bare" && "$W" search "-x" "$S/ws/proj") | grep -q "needle -x here"'
ok "T12 슬러그 경로 탈출(..) 거부" '! "$W" upsert "$S/ws/docs/wiki" "../../evil" t E s 2>/dev/null && ! grep -q evil "$S/ws/docs/wiki/wiki.tsv"'
ok "T13 옛 형식 호출(범위 인자) 거부" 'cp "$S/ws/docs/wiki/wiki.tsv" "$S/t13"; ! "$W" upsert "$S/ws/docs/wiki" common infra/x t E s G 2>/dev/null && cmp -s "$S/t13" "$S/ws/docs/wiki/wiki.tsv"'
ok "T14 기존 워크스페이스 위키에 init-project 거부" '! "$W" init-project "$S/ws" 2>/dev/null && [ ! -f "$S/ws/docs/wiki/.project" ]'
ok "T15 전역 위키 upsert는 roots.tsv에 등록 안 함" 'mkdir -p "$AGENT_SYSTEM_HOME/wiki/g"; echo g > "$AGENT_SYSTEM_HOME/wiki/g/x.md"; "$W" upsert "$AGENT_SYSTEM_HOME/wiki" g/x t G s >/dev/null && ! grep -q "^$AGENT_SYSTEM_HOME/wiki	" "$AGENT_SYSTEM_HOME/wiki/roots.tsv"'
ok "T16 lint 정상" '"$W" lint "$S/ws/docs/wiki" | grep -q "이상 없음"'
ok "T17 인자 없이 실행 시 사용법 출력" '"$W" 2>&1 | grep -q init-project'

# --ignore
ok "T18 옵션 생략 시 무시 설정 안 함" '"$W" init-ws "$S/ws" >/dev/null && ! grep -q docs/wiki "$S/ws/.git/info/exclude" 2>/dev/null && [ ! -f "$S/ws/.gitignore" ]'
"$W" init-ws "$S/ws" --ignore local >/dev/null
ok "T19 --ignore local: exclude에 추가, repo 파일 변경 없음, git status 깨끗" 'grep -qxF "/docs/wiki/" "$S/ws/.git/info/exclude" && [ ! -f "$S/ws/.gitignore" ] && [ -z "$(git -C "$S/ws" status --porcelain -- docs)" ]'
"$W" init-ws "$S/ws" --ignore=local >/dev/null
ok "T20 다시 실행해도 중복 추가 안 함" '[ "$(grep -cxF "/docs/wiki/" "$S/ws/.git/info/exclude")" = 1 ]'
ok "T21 기존 위키 내용 유지" 'grep -q "t/a" "$S/ws/docs/wiki/wiki.tsv"'

mkdir -p "$S/sh"; git -C "$S/sh" init -q; printf 'node_modules/' > "$S/sh/.gitignore"
"$W" init-project "$S/sh" --ignore shared >/dev/null
ok "T22 --ignore shared: .gitignore에 추가(마지막 줄바꿈 없던 파일도 줄 분리)" 'grep -qxF "node_modules/" "$S/sh/.gitignore" && grep -qxF "/docs/wiki/" "$S/sh/.gitignore" && git -C "$S/sh" check-ignore -q docs/wiki/index.md'
ok "T23 init-project 재실행 + shared 중복 없음" '"$W" init-project "$S/sh" --ignore shared >/dev/null && [ "$(grep -cxF "/docs/wiki/" "$S/sh/.gitignore")" = 1 ]'

mkdir -p "$S/mono/team/a"; git -C "$S/mono" init -q
"$W" init-ws "$S/mono/team" --ignore local >/dev/null
ok "T24 repo 하위 폴더 워크스페이스: 경로 기준으로 무시" 'grep -qxF "/team/docs/wiki/" "$S/mono/.git/info/exclude" && git -C "$S/mono" check-ignore -q team/docs/wiki/index.md'

mkdir -p "$S/nogit"
ok "T25 git repo 밖이면 건너뜀(실패 아님)" '"$W" init-ws "$S/nogit" --ignore local | grep -q "건너뜁니다"'
ok "T26 잘못된 --ignore 값 거부" '! "$W" init-ws "$S/nogit" --ignore everyone 2>/dev/null'
ok "T27 알 수 없는 옵션 거부" '! "$W" init-ws "$S/nogit" --force 2>/dev/null'

mkdir -p "$S/tr/docs/wiki"; git -C "$S/tr" init -q; echo x > "$S/tr/docs/wiki/old.md"
git -C "$S/tr" add docs >/dev/null; git -C "$S/tr" -c user.name=t -c user.email=t@example.invalid commit -qm init
ok "T28 이미 추적 중인 위키면 경고" '"$W" init-ws "$S/tr" --ignore local 2>&1 >/dev/null | grep -q "rm -r --cached"'

# link (위키가 없는 위치를 기존 위키·프로젝트에 연결)
mkdir -p "$S/hub/docs/wiki" "$S/hub2/docs/wiki" "$S/wt/apps/web" "$S/wt/inner/x" "$S/wtab" "$S/Spaced WT/a"
"$W" init-ws "$S/hub" >/dev/null; "$W" init-ws "$S/hub2" >/dev/null
before_link="$(snap)"
ok "T29 link 등록 전에는 위키 없음" '[ -z "$(wikis "$S/wt/apps/web")" ]'
"$W" link "$S/wt" "$S/hub/docs/wiki" >/dev/null
ok "T30 link: 하위 폴더에서 연결된 위키" '[ "$(wikis "$S/wt/apps/web")" = "$S/hub/docs/wiki" ]'
ok "T31 link: 경로 자체에서도 적용" '[ "$(wikis "$S/wt")" = "$S/hub/docs/wiki" ]'
ok "T32 link: 이름만 비슷한 옆 폴더(wtab)는 제외" '[ -z "$(wikis "$S/wtab")" ]'
"$W" link "$S/wt/inner" "$S/hub2/docs/wiki" >/dev/null
ok "T33 link: 겹치면 더 긴 경로 우선" '[ "$(wikis "$S/wt/inner/x")" = "$S/hub2/docs/wiki" ] && [ "$(wikis "$S/wt/apps")" = "$S/hub/docs/wiki" ]'
"$W" link "$S/wt" "$S/hub2/docs/wiki" >/dev/null
ok "T34 link: 같은 경로 재등록은 교체(중복 없음)" '[ "$(grep -c "^$S/wt	" "$AGENT_SYSTEM_HOME/wiki/links.tsv")" = 1 ] && [ "$(wikis "$S/wt/apps")" = "$S/hub2/docs/wiki" ]'
mkdir -p "$S/wt/docs/wiki"
ok "T35 위쪽 docs/wiki 다음에 link 위키" '[ "$(wikis "$S/wt/apps")" = "$(printf "%s\n%s" "$S/wt/docs/wiki" "$S/hub2/docs/wiki")" ]'
rm -rf "$S/wt/docs"
ln -s "$S/wt" "$S/wt-link"
ok "T36 바로가기(심링크) 경로로 들어와도 연결 적용" '[ "$(wikis "$S/wt-link/apps")" = "$S/hub2/docs/wiki" ]'
"$W" link "$S/Spaced WT" "$S/hub/docs/wiki" >/dev/null
ok "T37 공백 경로 link + list 동작" '[ "$(wikis "$S/Spaced WT/a")" = "$S/hub/docs/wiki" ] && "$W" list "$S/Spaced WT/a" | grep -qF "=== $S/hub/docs/wiki ==="'
ok "T38 위키가 아닌 폴더로 link 거부" '! "$W" link "$S/wt" "$S/wtab" 2>/dev/null'
ok "T39 link 인자 3개(옛 형식) 거부" '! "$W" link "$S/wt" "$S/hub/docs/wiki" cjs 2>/dev/null'
ok "T40 links 목록 출력" '"$W" links | grep -qF "$S/wt/inner → $S/hub2/docs/wiki"'
snap_before_read="$(snap)"; "$W" resolve "$S/wt/apps" >/dev/null; "$W" list "$S/wt/apps" >/dev/null; "$W" links >/dev/null
ok "T41 link 적용 상태에서도 resolve/list/links는 파일을 만들지 않음" '[ "$snap_before_read" = "$(snap)" ]'
"$W" unlink "$S/wt" >/dev/null
ok "T42 unlink 후 해당 경로는 연결 해제(다른 연결은 유지)" '[ -z "$(wikis "$S/wt/apps")" ] && [ "$(wikis "$S/wt/inner/x")" = "$S/hub2/docs/wiki" ]'
ok "T43 없는 연결 unlink는 실패 아님" '"$W" unlink "$S/nowhere" | grep -q "없습니다"'
mv "$S/hub2/docs/wiki" "$S/hub2/docs/wiki-moved"
ok "T44 연결된 위키 폴더가 사라지면 무시하고 links에 표시" '[ -z "$(wikis "$S/wt/inner/x")" ] && "$W" links | grep -q "위키 폴더 없음"'
mv "$S/hub2/docs/wiki-moved" "$S/hub2/docs/wiki"

echo "결과: PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
