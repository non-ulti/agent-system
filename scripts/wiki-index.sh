#!/usr/bin/env bash
# 위치 기반 LLM Wiki 경로 탐색 및 색인(wiki.tsv / index.md / log.md) 관리
# 위키 하나 = 적용 범위 하나: <폴더>/docs/wiki는 그 폴더 아래 전체, ~/.agent-system/wiki는 어디서나. 위키 바로 아래는 카테고리 폴더.
# 사용:
#   wiki-index.sh resolve [기준경로=.]                                  # 위로 올라가며 만나는 위키(WIKI=, 가까운 순)와 전역 위키(GLOBAL_WIKI=) 출력 (읽기 전용)
#   wiki-index.sh init <경로> [제목] [--ignore local|shared]            # <경로>/docs/wiki 초기화 및 등록
#     --ignore local  : .git/info/exclude에 위키 폴더 추가 (이 기기에서만 무시, repo 파일 변경 없음)
#     --ignore shared : repo 루트 .gitignore에 위키 폴더 추가 (팀 전체 무시, 커밋 필요)
#     생략            : 무시 설정 안 함 (위키를 repo에 커밋하는 경우). 이미 만든 위키에 다시 실행하면 무시 설정만 추가된다
#   wiki-index.sh upsert <위키루트> <카테고리/문서> <시각> <제목> <요약> [태그]  # 색인 갱신 + index.md 재빌드 + log.md 기록
#   wiki-index.sh remove <위키루트> <카테고리/문서> [사유]               # 색인에서 제거 + index.md 재빌드 + log.md 기록
#   wiki-index.sh rebuild <위키루트> [제목]                              # wiki.tsv 기준으로 index.md 재생성
#   wiki-index.sh list [기준경로=.]                                     # 현재 위치에서 조회되는 위키들과 전역 위키의 문서 목록
#   wiki-index.sh search <키워드> [기준경로=.]                          # 조회되는 위키들(+등록된 다른 위키)의 본문에서 키워드 검색
#   wiki-index.sh lint <위키루트>                                       # 색인 누락(고아 파일)·파일 실종 점검
#   wiki-index.sh link <경로> <위키루트>                                # <경로> 아래에서 이 위키도 조회하도록 연결 등록 (git에서 뺀 위키를 worktree에서 쓸 때)
#   wiki-index.sh unlink <경로>                                         # 연결 해제
#   wiki-index.sh links                                                 # 등록된 연결 목록
set -euo pipefail

if [ -z "${AGENT_SYSTEM_HOME:-}" ]; then
  if [ -d "$HOME/.claude/agent-system" ] && [ ! -e "$HOME/.agent-system" ]; then
    ln -s "$HOME/.claude/agent-system" "$HOME/.agent-system" 2>/dev/null || :
  fi
  AS_HOME="$HOME/.agent-system"
else
  AS_HOME="$AGENT_SYSTEM_HOME"
fi

GLOBAL_WIKI_ROOT="$AS_HOME/wiki"
ROOTS_TSV="$GLOBAL_WIKI_ROOT/roots.tsv"
# 연결 등록부 (컬럼: 경로 \t 위키루트, 경로는 실제 경로 pwd -P 기준)
LINKS_TSV="$GLOBAL_WIKI_ROOT/links.tsv"

one_line() {
  printf '%s' "${1:-}" | tr '\t\r\n' '   ' | sed -E 's/  +/ /g; s/^ //; s/ $//'
}

slugify() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._/-]+/-/g; s/^-+//; s/-+$//'
}

die() { echo "$*" >&2; exit 2; }

# 슬러그 검증: <카테고리>/<문서> 형식('/' 필수), 빈 값·절대경로·'.'/'..'·빈 경로 조각 금지
check_slug() {
  local value="$1"
  [ -n "$value" ] || die "슬러그 값이 비어 있습니다"
  case "/$value/" in
    *//*|*/./*|*/../*) die "슬러그에 빈 경로 조각이나 '.', '..'를 쓸 수 없습니다: $value" ;;
  esac
  case "$value" in
    */*) ;;
    *) die "슬러그는 <카테고리>/<문서> 형식이어야 합니다: $value" ;;
  esac
}

# 마크다운 표 칸 안의 '|' 이스케이프
md_cell() {
  one_line "${1:-}" | sed 's/|/\\|/g'
}

phys_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

# init 인자 분리: --ignore 값은 IGNORE_MODE, 나머지 위치 인자는 INIT_POS 배열
parse_init_args() {
  IGNORE_MODE=""
  INIT_POS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --ignore)
        [ $# -ge 2 ] || die "--ignore 값이 필요합니다: local 또는 shared"
        IGNORE_MODE="$2"; shift 2 ;;
      --ignore=*) IGNORE_MODE="${1#--ignore=}"; shift ;;
      --) shift; while [ $# -gt 0 ]; do INIT_POS+=("$1"); shift; done ;;
      -*) die "알 수 없는 옵션: $1" ;;
      *) INIT_POS+=("$1"); shift ;;
    esac
  done
  case "$IGNORE_MODE" in
    ""|local|shared) ;;
    *) die "--ignore 값은 local 또는 shared만 쓸 수 있습니다: $IGNORE_MODE" ;;
  esac
}

# 위키 폴더를 git 무시 목록에 추가한다 (git repo 밖이면 건너뜀, 같은 줄이 있으면 다시 넣지 않음)
#   local  → <repo>/.git/info/exclude : 이 기기에서만 적용, repo 파일은 바뀌지 않음
#   shared → <repo>/.gitignore        : 팀 전체에 적용, 이 변경은 커밋해야 함
apply_ignore() {
  local wiki_root="$1" mode="$2"
  [ -n "$mode" ] || return 0

  local top
  if ! top="$(git -C "$wiki_root" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "· git repo 밖이라 무시 설정을 건너뜁니다: $wiki_root"
    return 0
  fi

  local top_p wiki_p rel pattern file
  top_p="$(phys_dir "$top")"
  wiki_p="$(phys_dir "$wiki_root")"
  rel="${wiki_p#"$top_p"/}"
  pattern="/$rel/"

  if [ "$mode" = "local" ]; then
    file="$(git -C "$top" rev-parse --git-path info/exclude)"
    case "$file" in /*) ;; *) file="$top/$file" ;; esac
    mkdir -p "$(dirname "$file")"
  else
    file="$top/.gitignore"
  fi

  if [ -f "$file" ] && grep -qxF -- "$pattern" "$file"; then
    echo "· 이미 무시 목록에 있습니다: $pattern ($file)"
  else
    if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then
      printf '\n' >> "$file"
    fi
    printf '%s\n' "$pattern" >> "$file"
    echo "✓ 무시 목록에 추가: $pattern ($file)"
  fi
  if [ "$mode" = "shared" ]; then
    echo "  → .gitignore 변경은 커밋해야 팀에 적용됩니다"
  fi

  if [ -n "$(git -C "$top" ls-files -- "$rel")" ]; then
    echo "⚠ git이 이미 추적 중인 위키 파일이 있어 무시가 적용되지 않습니다. 추적을 끊으려면: git -C \"$top\" rm -r --cached -- \"$rel\"" >&2
  fi
}

ensure_wiki_root() {
  local root="$1"
  local title="${2:-Wiki}"
  mkdir -p "$root" 2>/dev/null || return 0
  [ -f "$root/wiki.tsv" ] || : > "$root/wiki.tsv" 2>/dev/null || :
  [ -f "$root/.gitignore" ] || printf '# wiki-index.sh 임시·백업 파일\n*.bak\n*.tmp\n' > "$root/.gitignore" 2>/dev/null || :
  if [ ! -f "$root/log.md" ]; then
    cat > "$root/log.md" <<EOF 2>/dev/null || :
# $title 변경 이력 (Log)

| 시각 | 동작 | 문서 | 내용 |
|---|---|---|---|
EOF
  fi
  if [ ! -f "$root/index.md" ]; then
    rebuild_index "$root" "$title" 2>/dev/null || :
  fi
}

register_ws_root() {
  local wiki_root="$1"
  local ws_dir
  ws_dir="$(cd "$(dirname "$(dirname "$wiki_root")")" && pwd)"
  local ws_name="${2:-$(basename "$ws_dir")}"
  mkdir -p "$GLOBAL_WIKI_ROOT" 2>/dev/null || return 0
  touch "$ROOTS_TSV" 2>/dev/null || return 0
  awk -F'\t' -v p="$wiki_root" '$1!=p' "$ROOTS_TSV" > "$ROOTS_TSV.tmp" 2>/dev/null && mv "$ROOTS_TSV.tmp" "$ROOTS_TSV" 2>/dev/null || :
  printf '%s\t%s\t%s\n' "$wiki_root" "$ws_dir" "$ws_name" >> "$ROOTS_TSV" 2>/dev/null || :
}

# wiki.tsv (컬럼: 슬러그(<카테고리>/<문서>) \t 갱신시각 \t 제목 \t 요약 \t 태그) → index.md 자동 컴파일
rebuild_index() {
  local root="$1"
  local title="${2:-}"
  local idx_tsv="$root/wiki.tsv"
  local idx_md="$root/index.md"
  touch "$idx_tsv" 2>/dev/null || :

  if [ -z "$title" ]; then
    if [ "$(phys_dir "$root")" = "$(phys_dir "$GLOBAL_WIKI_ROOT")" ]; then
      title="Global Wiki"
    else
      title="$(basename "$(dirname "$(dirname "$root")")") Wiki"
    fi
  fi

  {
    printf '# %s\n\n' "$title"
    printf '> 이 목차는 `wiki-index.sh`가 `wiki.tsv` 색인으로부터 자동 생성합니다. 문서를 찾을 때 이 파일을 가장 먼저 읽으세요.\n\n'

    if [ ! -s "$idx_tsv" ]; then
      printf '_등록된 위키 문서가 없습니다._\n'
    else
      # 카테고리(슬러그 첫 조각) 알파벳순
      local cats
      cats="$(awk -F'\t' 'NF>=4 { split($1, p, "/"); print p[1] }' "$idx_tsv" | sort -u)"
      for cat in $cats; do
        printf '## %s\n\n' "$cat"
        printf '| 문서 | 요약 | 태그 | 갱신 |\n'
        printf '|---|---|---|---|\n'
        awk -F'\t' -v c="$cat" '
          NF >= 4 && index($1, c "/") == 1 {
            slug = $1; updated = $2; doc_title = $3; summary = $4; tags = ($5 != "" ? $5 : "-");
            gsub(/\|/, "\\|", doc_title); gsub(/\|/, "\\|", summary); gsub(/\|/, "\\|", tags);
            printf "| [%s](%s.md) | %s | `%s` | %s |\n", doc_title, slug, summary, tags, substr(updated, 1, 10);
          }
        ' "$idx_tsv"
        printf '\n'
      done
    fi
  } > "$idx_md.tmp" && mv "$idx_md.tmp" "$idx_md"
}

append_log() {
  local root="$1"
  local ts="$2"
  local action="$3"
  local slug="$4"
  local note="$5"
  ensure_wiki_root "$root"
  printf '| %s | %s | `%s.md` | %s |\n' \
    "$(md_cell "$ts")" "$action" "$slug" "$(md_cell "$note")" >> "$root/log.md"
}

# 위키 중복 판별 키: git 안이면 "<공통 git 폴더>:<레포 안 상대경로>", 밖이면 실제 경로
# 같은 레포를 다른 폴더에 펼친 worktree의 같은 위키는 키가 같다 (레포 안의 서로 다른 위키는 다르다)
wiki_key() {
  local wiki_p top common
  wiki_p="$(phys_dir "$1")" || { printf '%s\n' "$1"; return 0; }
  if top="$(git -C "$wiki_p" rev-parse --show-toplevel 2>/dev/null)" \
     && common="$(cd "$wiki_p" && cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)"; then
    top="$(phys_dir "$top")"
    printf '%s:%s\n' "$common" "${wiki_p#"$top"/}"
  else
    printf '%s\n' "$wiki_p"
  fi
}

# 위키 사슬: 기준 경로에서 위로 올라가며 만나는 docs/wiki를 가까운 순으로 모으고, link로 연결한 위키 1개를 뒤에 붙인다
# 결과는 전역 변수 R_CHAIN(배열, 전역 위키 제외)과 R_GLOBAL에 담는다 (읽기 전용 — 파일을 만들지 않는다)
resolve_chain() {
  local target="${1:-.}" abs_target
  abs_target="$(cd "$target" 2>/dev/null && pwd || pwd)"
  R_GLOBAL="$GLOBAL_WIKI_ROOT"
  R_CHAIN=()

  local cands=() cur="$abs_target"
  while [ "$cur" != "/" ] && [ "$cur" != "$HOME" ]; do
    [ -d "$cur/docs/wiki" ] && cands+=("$cur/docs/wiki")
    cur="$(dirname "$cur")"
  done

  # 상위 탐색은 $HOME에서 멈추므로, git repo 바로 위가 $HOME이고 거기에 docs/wiki가 있는 경우를 따로 본다
  local git_top
  git_top="$(git -C "$abs_target" rev-parse --show-toplevel 2>/dev/null || :)"
  if [ -n "$git_top" ] && [ "$(dirname "$git_top")" = "$HOME" ] && [ -d "$HOME/docs/wiki" ]; then
    cands+=("$HOME/docs/wiki")
  fi

  # link로 등록한 연결 (여러 개가 겹치면 가장 긴 경로 우선)
  # 예: git에서 뺀 위키가 들어오지 않는 작업용 복사본(git worktree)에서 원래 폴더의 위키를 쓰는 경우
  if [ -f "$LINKS_TSV" ]; then
    local target_p link_wiki
    target_p="$(cd "$abs_target" 2>/dev/null && pwd -P || printf '%s' "$abs_target")"
    link_wiki="$(awk -F'\t' -v t="$target_p" '
      NF >= 2 && (t == $1 || index(t, $1 "/") == 1) {
        if (length($1) > best) { best = length($1); w = $2 }
      }
      END { if (w != "") print w }
    ' "$LINKS_TSV")"
    [ -n "$link_wiki" ] && [ -d "$link_wiki" ] && cands+=("$link_wiki")
  fi

  local keys=() c k seen dup global_key=""
  [ -d "$GLOBAL_WIKI_ROOT" ] && global_key="$(wiki_key "$GLOBAL_WIKI_ROOT")"
  for c in "${cands[@]+"${cands[@]}"}"; do
    k="$(wiki_key "$c")"
    dup=0
    [ "$k" = "$global_key" ] && dup=1
    for seen in "${keys[@]+"${keys[@]}"}"; do
      [ "$seen" = "$k" ] && { dup=1; break; }
    done
    [ "$dup" -eq 1 ] && continue
    keys+=("$k")
    R_CHAIN+=("$c")
  done
}

# 위키 하나의 문서 목록 출력
list_wiki() {
  local w="$1"
  echo "=== $w ==="
  if [ -s "$w/wiki.tsv" ]; then
    awk -F'\t' 'NF >= 4 { printf "  %s — %s (%s) [%s]\n", $1, $3, $4, substr($2, 1, 10) }' "$w/wiki.tsv"
  else
    echo "(등록된 문서 없음)"
  fi
}

cmd="${1:-}"
[ -n "$cmd" ] && shift

case "$cmd" in
  resolve)
    resolve_chain "${1:-.}"
    for w in "${R_CHAIN[@]+"${R_CHAIN[@]}"}"; do
      printf 'WIKI=%s\n' "$w"
    done
    printf 'GLOBAL_WIKI=%s\n' "$R_GLOBAL"
    ;;

  init)
    parse_init_args "$@"
    [ "${#INIT_POS[@]}" -ge 1 ] || die "사용법: wiki-index.sh init <경로> [제목] [--ignore local|shared]"
    base_dir="$(cd "${INIT_POS[0]}" && pwd)"
    wiki_title="${INIT_POS[1]:-$(basename "$base_dir") Wiki}"
    wiki_root="$base_dir/docs/wiki"
    ensure_wiki_root "$wiki_root" "$wiki_title"
    register_ws_root "$wiki_root" "$(basename "$base_dir")"
    echo "✓ 위키 초기화 완료: $wiki_root"
    apply_ignore "$wiki_root" "$IGNORE_MODE"
    ;;

  upsert)
    { [ $# -ge 5 ] && [ $# -le 6 ]; } || { echo "upsert 인자 5~6개 필요: <위키루트> <카테고리/문서> <갱신시각> <제목> <요약> [태그]" >&2; exit 2; }
    wiki_root="$(cd "$1" && pwd)"
    slug="$(slugify "$2")"
    slug="${slug%.md}"
    ts="$(one_line "$3")"
    title="$(one_line "$4")"
    summary="$(one_line "$5")"
    tags="$(one_line "${6:--}")"
    check_slug "$slug"

    ensure_wiki_root "$wiki_root"
    if [ "$(phys_dir "$wiki_root")" != "$(phys_dir "$GLOBAL_WIKI_ROOT")" ]; then
      register_ws_root "$wiki_root"
    fi
    idx="$wiki_root/wiki.tsv"
    [ -f "$idx" ] && cp "$idx" "$idx.bak"

    action="생성"
    if awk -F'\t' -v sl="$slug" '$1==sl { found=1 } END { exit !found }' "$idx"; then
      action="갱신"
    fi

    awk -F'\t' -v sl="$slug" '$1!=sl' "$idx" > "$idx.tmp" && mv "$idx.tmp" "$idx"
    printf '%s\t%s\t%s\t%s\t%s\n' "$slug" "$ts" "$title" "$summary" "$tags" >> "$idx"

    rebuild_index "$wiki_root"
    append_log "$wiki_root" "$ts" "$action" "$slug" "$title — $summary"
    echo "✓ 위키 색인 $action 완료: $slug ($wiki_root/index.md)"
    ;;

  remove)
    { [ $# -ge 2 ] && [ $# -le 3 ]; } || { echo "remove 인자 2~3개 필요: <위키루트> <카테고리/문서> [사유]" >&2; exit 2; }
    wiki_root="$(cd "$1" && pwd)"
    slug="$(slugify "$2")"
    slug="${slug%.md}"
    reason="${3:-문서 삭제/통합}"
    check_slug "$slug"
    ts="$(date '+%Y-%m-%d %H:%M')"

    idx="$wiki_root/wiki.tsv"
    [ -f "$idx" ] && cp "$idx" "$idx.bak"
    awk -F'\t' -v sl="$slug" '$1!=sl' "$idx" > "$idx.tmp" && mv "$idx.tmp" "$idx"

    rebuild_index "$wiki_root"
    append_log "$wiki_root" "$ts" "삭제" "$slug" "$reason"
    echo "✓ 위키 색인 제거 완료: $slug"
    ;;

  rebuild)
    [ $# -ge 1 ] || { echo "rebuild 인자 1개 필요: <위키루트>" >&2; exit 2; }
    wiki_root="$(cd "$1" && pwd)"
    rebuild_index "$wiki_root" "${2:-}"
    echo "✓ index.md 재생성 완료: $wiki_root/index.md"
    ;;

  list)
    resolve_chain "${1:-.}"
    for w in "${R_CHAIN[@]+"${R_CHAIN[@]}"}"; do
      list_wiki "$w"
      echo ""
    done
    list_wiki "$R_GLOBAL"
    ;;

  search)
    [ $# -ge 1 ] || { echo "search 인자 필요: <키워드> [기준경로=.]" >&2; exit 2; }
    kw="$1"
    resolve_chain "${2:-.}"
    roots=("${R_CHAIN[@]+"${R_CHAIN[@]}"}" "$R_GLOBAL")
    # roots.tsv에 등록된 다른 위키도 포함
    if [ -f "$ROOTS_TSV" ]; then
      while IFS=$'\t' read -r r_path _ _; do
        [ -d "$r_path" ] || continue
        skip=0
        for existing in "${roots[@]}"; do
          [ "$(phys_dir "$existing")" = "$(phys_dir "$r_path")" ] && skip=1 && break
        done
        [ "$skip" -eq 0 ] && roots+=("$r_path")
      done < "$ROOTS_TSV"
    fi

    for r in "${roots[@]}"; do
      echo "── 검색 대상: $r ──"
      [ -d "$r" ] || { echo "  (위키 폴더 없음)"; continue; }
      grep -rn -i --include="*.md" -e "$kw" -- "$r" 2>/dev/null || echo "  (일치 항목 없음)"
    done
    ;;

  link)
    [ $# -eq 2 ] || die "사용법: wiki-index.sh link <경로> <위키루트>"
    [ -d "$1" ] || die "경로가 없습니다: $1"
    [ -f "$2/wiki.tsv" ] || die "위키 루트가 아닙니다(wiki.tsv 없음): $2 — init으로 먼저 만드세요"
    link_path="$(phys_dir "$1")"
    link_wiki="$(phys_dir "$2")"
    mkdir -p "$GLOBAL_WIKI_ROOT"
    touch "$LINKS_TSV"
    awk -F'\t' -v p="$link_path" '$1 != p' "$LINKS_TSV" > "$LINKS_TSV.tmp" && mv "$LINKS_TSV.tmp" "$LINKS_TSV"
    printf '%s\t%s\n' "$link_path" "$link_wiki" >> "$LINKS_TSV"
    echo "✓ 연결 등록: $link_path 아래 → $link_wiki"
    echo "  (그 경로 위쪽에서 찾은 docs/wiki 다음 순서로 조회됩니다)"
    ;;

  unlink)
    [ $# -eq 1 ] || die "사용법: wiki-index.sh unlink <경로>"
    link_path="$(phys_dir "$1" || :)"
    [ -n "$link_path" ] || link_path="$1"
    if [ -f "$LINKS_TSV" ] && awk -F'\t' -v p="$link_path" '$1 == p { f = 1 } END { exit !f }' "$LINKS_TSV"; then
      awk -F'\t' -v p="$link_path" '$1 != p' "$LINKS_TSV" > "$LINKS_TSV.tmp" && mv "$LINKS_TSV.tmp" "$LINKS_TSV"
      echo "✓ 연결 해제: $link_path"
    else
      echo "· 등록된 연결이 없습니다: $link_path"
    fi
    ;;

  links)
    if [ -s "$LINKS_TSV" ]; then
      while IFS=$'\t' read -r l_path l_wiki _; do
        [ -n "$l_path" ] || continue
        mark=""
        [ -d "$l_wiki" ] || mark=" ⚠ 위키 폴더 없음"
        [ -d "$l_path" ] || mark="$mark ⚠ 경로 없음"
        echo "$l_path → $l_wiki$mark"
      done < "$LINKS_TSV"
    else
      echo "(등록된 연결 없음)"
    fi
    ;;

  lint)
    [ $# -ge 1 ] || { echo "lint 인자 필요: <위키루트>" >&2; exit 2; }
    wiki_root="$(cd "$1" && pwd)"
    idx="$wiki_root/wiki.tsv"
    [ -f "$idx" ] || idx=/dev/null
    issues=0

    echo "=== 위키 점검 (Lint): $wiki_root ==="
    # 1. 색인에는 있으나 실제 파일이 없는 경우
    while IFS=$'\t' read -r sl _ title _ _; do
      [ -z "$sl" ] && continue
      f="$wiki_root/$sl.md"
      if [ ! -f "$f" ]; then
        echo "✘ [파일 없음] 색인에 등록된 파일이 존재하지 않습니다: $sl.md ($title)"
        issues=$((issues + 1))
      fi
    done < "$idx"

    # 2. 실제 .md 파일은 있으나 색인(wiki.tsv)에 없는 고아 문서 점검 (index.md, log.md 제외)
    while IFS= read -r md_file; do
      [ -z "$md_file" ] && continue
      rel="${md_file#"$wiki_root"/}"
      [ "$rel" = "index.md" ] || [ "$rel" = "log.md" ] && continue
      sl="${rel%.md}"
      if ! awk -F'\t' -v l="$sl" '$1==l { found=1 } END { exit !found }' "$idx"; then
        echo "⚠ [색인 누락] 파일은 존재하나 wiki.tsv 색인에 없습니다: $rel"
        issues=$((issues + 1))
      fi
    done < <(find "$wiki_root" -type f -name "*.md" 2>/dev/null | sort)

    if [ "$issues" -eq 0 ]; then
      echo "✓ 이상 없음 (색인과 마크다운 문서가 모두 일치합니다)"
    else
      echo "→ 총 ${issues}건의 불일치가 발견되었습니다."
    fi
    ;;

  *)
    sed -n '2,/^set -euo/p' "$0" | sed '$d' >&2
    exit 2
    ;;
esac
