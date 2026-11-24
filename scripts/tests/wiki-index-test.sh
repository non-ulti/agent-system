#!/usr/bin/env bash
# wiki-index.sh 회귀 테스트 — 임시 폴더 안에서만 동작하며 실제 ~/.agent-system은 건드리지 않는다
# 사용: scripts/tests/wiki-index-test.sh [샌드박스경로=mktemp]
set -u
W="$(cd "$(dirname "$0")/.." && pwd)/wiki-index.sh"
S="${1:-$(mktemp -d)}"
rm -rf "$S"; mkdir -p "$S"
S="$(cd "$S" && pwd -P)"
export AGENT_SYSTEM_HOME="$S/ash"; mkdir -p "$AGENT_SYSTEM_HOME/wiki"
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

# 심링크로 들어온 repo도 실제 경로 위쪽의 위키를 본다
ln -s "$S/ws/proj" "$S/lp"
ok "T-sym 심링크 경로로 들어와도 위쪽 위키 유지(가까운 위키는 들어온 경로로 표시)" '[ "$(wikis "$S/lp/src")" = "$(printf "%s\n%s" "$S/lp/docs/wiki" "$S/ws/docs/wiki")" ]'
# git에서 뺀(추적 안 되는) 위키는 같은 상대경로여도 다른 위키
mkdir -p "$S/ig/docs/wiki" "$S/ig/src"; git -C "$S/ig" init -q; echo x > "$S/ig/src/a"; echo "/docs/wiki/" >> "$S/ig/.git/info/exclude"
git -C "$S/ig" add -A; git -C "$S/ig" -c user.name=t -c user.email=t@example.invalid commit -qm i
git -C "$S/ig" worktree add -q "$S/ig/.claude/worktrees/w2" -b w2 2>/dev/null; mkdir -p "$S/ig/.claude/worktrees/w2/docs/wiki"
ok "T-ign 추적 안 되는 위키 둘은 둘 다 보임" '[ "$(wikis "$S/ig/.claude/worktrees/w2")" = "$(printf "%s\n%s" "$S/ig/.claude/worktrees/w2/docs/wiki" "$S/ig/docs/wiki")" ]'

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
ok "T15 전역 위키 upsert는 roots.tsv에 등록 안 함" 'mkdir -p "$AGENT_SYSTEM_HOME/wiki/g"; echo g > "$AGENT_SYSTEM_HOME/wiki/g/x.md"; "$W" upsert "$AGENT_SYSTEM_HOME/wiki" g/x t G s >/dev/null && ! grep -q "^$AGENT_SYSTEM_HOME/wiki	" "$AGENT_SYSTEM_HOME/wiki/roots.tsv"'
ok "T16 lint 정상" '"$W" lint "$S/ws/docs/wiki" | grep -q "이상 없음"'
ok "T17 사용법에 init" '"$W" 2>&1 | grep -q "init <경로>"'

mkdir -p "$S/ni"
ok "T-init common/·.project를 만들지 않음" '"$W" init "$S/ni" >/dev/null && [ -f "$S/ni/docs/wiki/wiki.tsv" ] && [ ! -e "$S/ni/docs/wiki/common" ] && [ ! -e "$S/ni/docs/wiki/.project" ]'
ok "T-old init-ws는 없는 명령" '! "$W" init-ws "$S/ni" >/dev/null 2>&1'
ok "T-old2 init-project는 없는 명령" '! "$W" init-project "$S/ni" >/dev/null 2>&1'

# --ignore
mkdir -p "$S/dflt"; git -C "$S/dflt" init -q
ok "T18 옵션 생략 시 local 무시" '"$W" init "$S/dflt" >/dev/null && grep -qxF "/docs/wiki/" "$S/dflt/.git/info/exclude" && [ ! -f "$S/dflt/.gitignore" ] && [ -z "$(git -C "$S/dflt" status --porcelain -- docs)" ]'
mkdir -p "$S/nn"; git -C "$S/nn" init -q
ok "T-none --ignore none은 무시 설정 안 함(추적 대상)" '"$W" init "$S/nn" --ignore none >/dev/null && ! grep -q "docs/wiki" "$S/nn/.git/info/exclude" && [ ! -f "$S/nn/.gitignore" ] && git -C "$S/nn" status --porcelain -- docs | grep -q "docs"'
mkdir -p "$S/bd"; git -C "$S/bd" init -q
ok "T-bad --ignore foo는 실패하고 무시 설정을 쓰지 않음" '! "$W" init "$S/bd" --ignore foo >/dev/null 2>&1 && ! grep -q "docs/wiki" "$S/bd/.git/info/exclude" && [ ! -f "$S/bd/.gitignore" ]'
"$W" init "$S/ws" --ignore local >/dev/null
ok "T19 --ignore local: exclude에 추가, repo 파일 변경 없음, git status 깨끗" 'grep -qxF "/docs/wiki/" "$S/ws/.git/info/exclude" && [ ! -f "$S/ws/.gitignore" ] && [ -z "$(git -C "$S/ws" status --porcelain -- docs)" ]'
"$W" init "$S/ws" --ignore=local >/dev/null
ok "T20 다시 실행해도 중복 추가 안 함" '[ "$(grep -cxF "/docs/wiki/" "$S/ws/.git/info/exclude")" = 1 ]'
ok "T21 기존 위키 내용 유지" 'grep -q "t/a" "$S/ws/docs/wiki/wiki.tsv"'

mkdir -p "$S/sh"; git -C "$S/sh" init -q; printf 'node_modules/' > "$S/sh/.gitignore"
"$W" init "$S/sh" --ignore shared >/dev/null
ok "T22 --ignore shared: .gitignore에 추가(마지막 줄바꿈 없던 파일도 줄 분리)" 'grep -qxF "node_modules/" "$S/sh/.gitignore" && grep -qxF "/docs/wiki/" "$S/sh/.gitignore" && git -C "$S/sh" check-ignore -q docs/wiki/index.md'
ok "T23 init 재실행 + shared 중복 없음" '"$W" init "$S/sh" --ignore shared >/dev/null && [ "$(grep -cxF "/docs/wiki/" "$S/sh/.gitignore")" = 1 ]'

mkdir -p "$S/mono/team/a"; git -C "$S/mono" init -q
"$W" init "$S/mono/team" --ignore local >/dev/null
ok "T24 repo 하위 폴더 워크스페이스: 경로 기준으로 무시" 'grep -qxF "/team/docs/wiki/" "$S/mono/.git/info/exclude" && git -C "$S/mono" check-ignore -q team/docs/wiki/index.md'

mkdir -p "$S/nogit"
ok "T25 git repo 밖이면 건너뜀(실패 아님)" '"$W" init "$S/nogit" --ignore local | grep -q "건너뜁니다"'
ok "T26 잘못된 --ignore 값 거부" '! "$W" init "$S/nogit" --ignore everyone 2>/dev/null'
ok "T27 알 수 없는 옵션 거부" '! "$W" init "$S/nogit" --force 2>/dev/null'

mkdir -p "$S/tr/docs/wiki"; git -C "$S/tr" init -q; echo x > "$S/tr/docs/wiki/old.md"
git -C "$S/tr" add docs >/dev/null; git -C "$S/tr" -c user.name=t -c user.email=t@example.invalid commit -qm init
ok "T28 이미 추적 중인 위키면 경고" '"$W" init "$S/tr" --ignore local 2>&1 >/dev/null | grep -q "rm -r --cached"'

# link (위키가 없는 위치를 기존 위키·프로젝트에 연결)
mkdir -p "$S/hub/docs/wiki" "$S/hub2/docs/wiki" "$S/wt/apps/web" "$S/wt/inner/x" "$S/wtab" "$S/Spaced WT/a"
"$W" init "$S/hub" >/dev/null; "$W" init "$S/hub2" >/dev/null
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

# 컨테이너 바깥 worktree를 link로 연결하면 연결된 위키 위쪽(컨테이너) 위키도 본다
mkdir -p "$S/ctr/docs/wiki" "$S/ctr/repo/docs/wiki" "$S/orca/repo/feat/src"
"$W" init "$S/ctr" >/dev/null; "$W" init "$S/ctr/repo" >/dev/null
"$W" link "$S/orca/repo" "$S/ctr/repo/docs/wiki" >/dev/null
ok "T45 link: 바깥 worktree에서 연결 위키 다음에 그 위쪽 위키(정확한 순서)" '[ "$(wikis "$S/orca/repo/feat/src")" = "$(printf "%s\n%s" "$S/ctr/repo/docs/wiki" "$S/ctr/docs/wiki")" ]'
mkdir -p "$S/orca/docs/wiki"
ok "T46 link: 현재 위치 위쪽 위키 → 연결 위키 → 그 위쪽 위키 순" '[ "$(wikis "$S/orca/repo/feat/src")" = "$(printf "%s\n%s\n%s" "$S/orca/docs/wiki" "$S/ctr/repo/docs/wiki" "$S/ctr/docs/wiki")" ]'
rm -rf "$S/orca/docs"

# 옛 형식(0.4.x, 6칸) wiki.tsv는 건드리지 않고 거부
mkdir -p "$S/ow/docs/wiki"; "$W" init "$S/ow" >/dev/null
printf 'common\tinfra/db\t2026-01-01\tDB\ts\tdb\n' > "$S/ow/docs/wiki/wiki.tsv"
cp "$S/ow/docs/wiki/wiki.tsv" "$S/ow-tsv"; cp "$S/ow/docs/wiki/index.md" "$S/ow-idx"; cp "$S/ow/docs/wiki/log.md" "$S/ow-log"
ow_same(){ cmp -s "$S/ow-tsv" "$S/ow/docs/wiki/wiki.tsv" && cmp -s "$S/ow-idx" "$S/ow/docs/wiki/index.md" && cmp -s "$S/ow-log" "$S/ow/docs/wiki/log.md"; }
ok "T47 옛 형식 wiki.tsv에 upsert 거부, 파일 변경 없음" '! "$W" upsert "$S/ow/docs/wiki" infra/new t N s 2>/dev/null && ow_same'
ok "T48 옛 형식 wiki.tsv에 remove·rebuild 거부, 파일 변경 없음" '! "$W" remove "$S/ow/docs/wiki" infra/db 2>/dev/null && ! "$W" rebuild "$S/ow/docs/wiki" 2>/dev/null && ow_same'
ok "T49 옛 형식 거부 메시지는 이전(마이그레이션) 안내" '"$W" upsert "$S/ow/docs/wiki" infra/new t N s 2>&1 | grep -q "0.4"'
printf 'scope\t2026-01-01\tT\ts\tt\n' > "$S/ow/docs/wiki/wiki.tsv"
ok "T50 첫 칸에 /가 없는 줄도 옛 형식으로 거부" '! "$W" upsert "$S/ow/docs/wiki" infra/new t N s 2>/dev/null && [ "$(wc -l < "$S/ow/docs/wiki/wiki.tsv")" -eq 1 ]'

# 이미 커밋한 위키에 init 재실행
mkdir -p "$S/cm"; git -C "$S/cm" init -q; "$W" init "$S/cm" --ignore none >/dev/null
git -C "$S/cm" add docs >/dev/null; git -C "$S/cm" -c user.name=t -c user.email=t@example.invalid commit -qm w
cp "$S/cm/.git/info/exclude" "$S/cm-ex"
cm_out="$("$W" init "$S/cm" 2>&1)"; mkdir -p "$S/cm/docs/wiki/t"; echo n > "$S/cm/docs/wiki/t/new.md"
ok "T51 커밋된 위키 + 옵션 없는 init → 무시 추가 안 함, 새 문서가 git에 보임" 'cmp -s "$S/cm-ex" "$S/cm/.git/info/exclude" && git -C "$S/cm" status --porcelain -- docs | grep -q "docs/wiki/t/"'
ok "T52 커밋된 위키 + 옵션 없는 init → 건너뜀 안내" 'printf "%s" "$cm_out" | grep -q -- "--ignore local"'
mkdir -p "$S/cm2"; git -C "$S/cm2" init -q; "$W" init "$S/cm2" --ignore none >/dev/null
git -C "$S/cm2" add docs >/dev/null; git -C "$S/cm2" -c user.name=t -c user.email=t@example.invalid commit -qm w
cm2_err="$("$W" init "$S/cm2" --ignore local 2>&1 >/dev/null)"
ok "T53 커밋된 위키 + --ignore local → 추가하고 새 파일만 무시된다고 경고" 'grep -qxF "/docs/wiki/" "$S/cm2/.git/info/exclude" && printf "%s" "$cm2_err" | grep -q "새로 만드는" && printf "%s" "$cm2_err" | grep -q "rm -r --cached"'

# 빈 위키 루트 인자는 현재 폴더에 위키를 만들지 않음
mkdir -p "$S/emp"
ok "T54 빈 위키 루트 upsert/remove/rebuild/lint 거부, 현재 폴더에 아무것도 안 만듦" '(cd "$S/emp" && ! "$W" upsert "" t/a t T s 2>/dev/null && ! "$W" remove "" t/a 2>/dev/null && ! "$W" rebuild "" 2>/dev/null && ! "$W" lint "" >/dev/null 2>&1) && [ -z "$(ls -A "$S/emp")" ]'

# init 위치 인자 3개 이상 거부
mkdir -p "$S/x3"
ok "T55 init 위치 인자 초과 거부, 위키 안 만듦" '! "$W" init "$S/x3" "T" extra 2>/dev/null && [ ! -e "$S/x3/docs" ]'

# links.tsv에서 칸 수가 2가 아닌 줄은 쓰지 않고 links에 표시
mkdir -p "$S/old3/a"
printf '%s\t%s\tx\n' "$S/old3" "$S/hub/docs/wiki" >> "$AGENT_SYSTEM_HOME/wiki/links.tsv"
ok "T56 3칸 links.tsv 줄은 resolve에서 쓰지 않음" '[ -z "$(wikis "$S/old3/a")" ]'
ok "T57 3칸 links.tsv 줄은 links에 형식 오류로 표시" '"$W" links | grep -F "$S/old3" | grep -q "형식 오류"'

echo "결과: PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
