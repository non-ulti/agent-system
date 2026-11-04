#!/usr/bin/env bash
# 계층형 LLM Wiki(프로젝트 · 워크스페이스 공통 · 전역 공통) 경로 탐색 및 색인(wiki.tsv / index.md / log.md) 관리
# 사용:
#   wiki-index.sh resolve [기준경로=.]                                    # 현재 위치 기준 3계층 위키 경로와 프로젝트 슬러그 출력 (읽기 전용)
#   wiki-index.sh init-ws <워크스페이스경로> [제목]                       # 여러 프로젝트를 묶는 <워크스페이스경로>/docs/wiki 초기화 및 등록
#   wiki-index.sh init-project <프로젝트경로> [프로젝트슬러그]            # 단일 프로젝트 전용 <프로젝트경로>/docs/wiki 초기화 (.project 표식)
#   wiki-index.sh upsert <위키루트> <스코프> <슬러그> <시각> <제목> <요약> [태그]  # 색인 갱신 + index.md 재빌드 + log.md 기록
#   wiki-index.sh remove <위키루트> <스코프> <슬러그> [사유]              # 색인에서 제거 + index.md 재빌드 + log.md 기록
#   wiki-index.sh rebuild <위키루트>                                      # wiki.tsv 기준으로 index.md 재생성
#   wiki-index.sh list [기준경로=.]                                       # 현재 위치에서 참조 가능한 모든 계층 위키 목록 출력
#   wiki-index.sh search <키워드> [기준경로=.]                            # 참조 가능한 위키들의 색인·본문에서 키워드 검색
#   wiki-index.sh lint <위키루트>                                         # 색인 누락(고아 파일)·파일 실종 점검
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

one_line() {
  printf '%s' "${1:-}" | tr '\t\r\n' '   ' | sed -E 's/  +/ /g; s/^ //; s/ $//'
}

slugify() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._/-]+/-/g; s/^-+//; s/-+$//'
}

die() { echo "$*" >&2; exit 2; }

# 스코프·슬러그 검증: 빈 값, 절대경로, '.'/'..' 경로 조각 금지 (스코프는 '/'도 금지)
check_slug() {
  local kind="$1" value="$2"
  [ -n "$value" ] || die "$kind 값이 비어 있습니다"
  case "/$value/" in
    *//*|*/./*|*/../*) die "$kind에 빈 경로 조각이나 '.', '..'를 쓸 수 없습니다: $value" ;;
  esac
  if [ "$kind" = "스코프" ]; then
    case "$value" in */*) die "스코프에는 '/'를 쓸 수 없습니다: $value" ;; esac
  fi
}

# 마크다운 표 칸 안의 '|' 이스케이프
md_cell() {
  one_line "${1:-}" | sed 's/|/\\|/g'
}

phys_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

ensure_wiki_root() {
  local root="$1"
  local title="${2:-Wiki}"
  [ -d "$root" ] || mkdir -p "$root/common" 2>/dev/null || return 0
  mkdir -p "$root/common" 2>/dev/null || :
  [ -f "$root/wiki.tsv" ] || : > "$root/wiki.tsv" 2>/dev/null || :
  [ -f "$root/.gitignore" ] || printf '# wiki-index.sh 임시·백업 파일\n*.bak\n*.tmp\n' > "$root/.gitignore" 2>/dev/null || :
  if [ ! -f "$root/log.md" ]; then
    cat > "$root/log.md" <<EOF 2>/dev/null || :
# $title 변경 이력 (Log)

| 시각 | 동작 | 스코프 | 문서 | 내용 |
|---|---|---|---|---|
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

# wiki.tsv (컬럼: 스코프 \t 슬러그 \t 갱신시각 \t 제목 \t 요약 \t 태그) → index.md 자동 컴파일
rebuild_index() {
  local root="$1"
  local title="${2:-}"
  local idx_tsv="$root/wiki.tsv"
  local idx_md="$root/index.md"
  touch "$idx_tsv" 2>/dev/null || :

  if [ -z "$title" ]; then
    if [ "$root" = "$GLOBAL_WIKI_ROOT" ]; then
      title="Global Wiki (전역 공통 지식베이스)"
    else
      local ws_dir
      ws_dir="$(basename "$(dirname "$(dirname "$root")")")"
      title="$ws_dir Wiki (워크스페이스 지식베이스)"
    fi
  fi

  {
    printf '# %s\n\n' "$title"
    printf '> 이 목차는 `wiki-index.sh`가 `wiki.tsv` 색인으로부터 자동 생성합니다. 문서를 찾을 때 이 파일을 가장 먼저 읽으세요.\n\n'

    if [ ! -s "$idx_tsv" ]; then
      printf '_등록된 위키 문서가 없습니다._\n'
    else
      # common 먼저 출력 후 나머지 스코프 알파벳순 출력
      local scopes
      scopes="$(awk -F'\t' 'NF>=5 { print $1 }' "$idx_tsv" | sort -u | awk '$0=="common"{print "0\t"$0; next} {print "1\t"$0}' | sort | cut -f2)"
      for sc in $scopes; do
        if [ "$sc" = "common" ]; then
          printf '## 공통 (common)\n\n'
        else
          printf '## %s\n\n' "$sc"
        fi
        printf '| 문서 | 요약 | 태그 | 갱신 |\n'
        printf '|---|---|---|---|\n'
        awk -F'\t' -v s="$sc" '
          $1 == s && NF >= 5 {
            slug = $2; updated = $3; doc_title = $4; summary = $5; tags = ($6 != "" ? $6 : "-");
            gsub(/\|/, "\\|", doc_title); gsub(/\|/, "\\|", summary); gsub(/\|/, "\\|", tags);
            path = s "/" slug ".md";
            printf "| [%s](%s) | %s | `%s` | %s |\n", doc_title, path, summary, tags, substr(updated, 1, 10);
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
  local scope="$4"
  local slug="$5"
  local note="$6"
  ensure_wiki_root "$root"
  printf '| %s | %s | `%s` | `%s/%s.md` | %s |\n' \
    "$(md_cell "$ts")" "$action" "$scope" "$scope" "$slug" "$(md_cell "$note")" >> "$root/log.md"
}

# 기준 경로에서 상위 폴더를 따라 올라가며 docs/wiki 탐색 + 프로젝트 슬러그 판별 (읽기 전용 — 파일을 만들지 않는다)
# 결과는 전역 변수 R_GLOBAL, R_WS_ROOT, R_WS_WIKI, R_PROJECT에 담는다 (eval 없이 사용 — 공백 경로 안전)
resolve_paths() {
  local target="${1:-.}"
  local abs_target
  abs_target="$(cd "$target" 2>/dev/null && pwd || pwd)"

  R_GLOBAL="$GLOBAL_WIKI_ROOT"
  R_WS_ROOT=""
  R_WS_WIKI=""
  R_PROJECT="common"

  local cur="$abs_target"
  while [ "$cur" != "/" ] && [ "$cur" != "$HOME" ]; do
    if [ -d "$cur/docs/wiki" ]; then
      R_WS_WIKI="$cur/docs/wiki"
      R_WS_ROOT="$cur"
      break
    fi
    cur="$(dirname "$cur")"
  done

  local git_top=""
  git_top="$(git -C "$abs_target" rev-parse --show-toplevel 2>/dev/null || :)"

  # 상위 탐색은 $HOME에서 멈추므로, git repo 바로 위가 $HOME이고 거기에 docs/wiki가 있는 경우를 따로 본다
  local via_git_parent=0
  if [ -z "$R_WS_WIKI" ] && [ -n "$git_top" ] && [ -d "$(dirname "$git_top")/docs/wiki" ]; then
    R_WS_ROOT="$(dirname "$git_top")"
    R_WS_WIKI="$R_WS_ROOT/docs/wiki"
    via_git_parent=1
  fi

  # 프로젝트 슬러그 결정:
  # 1) 찾은 위키에 .project 표식이 있으면 단일 프로젝트 위키 → 표식의 슬러그
  # 2) 워크스페이스 위키 하위 폴더에서 실행 → 워크스페이스 바로 아래 1단계 폴더명 (워크스페이스 루트 자체·docs는 common)
  # 3) 위키를 못 찾았으면 git toplevel 이름
  if [ -n "$R_WS_WIKI" ] && [ -f "$R_WS_WIKI/.project" ]; then
    R_PROJECT="$(slugify "$(head -n 1 "$R_WS_WIKI/.project")")"
    [ -n "$R_PROJECT" ] || R_PROJECT="$(slugify "$(basename "$R_WS_ROOT")")"
  elif [ "$via_git_parent" -eq 1 ]; then
    R_PROJECT="$(slugify "$(basename "$git_top")")"
  elif [ -n "$R_WS_WIKI" ]; then
    if [ "$abs_target" != "$R_WS_ROOT" ]; then
      local rel="${abs_target#"$R_WS_ROOT"/}"
      local first_seg="${rel%%/*}"
      case "$first_seg" in
        ""|docs|.*) : ;;
        *) R_PROJECT="$(slugify "$first_seg")" ;;
      esac
    fi
  elif [ -n "$git_top" ]; then
    R_PROJECT="$(slugify "$(basename "$git_top")")"
  fi
  [ -n "$R_PROJECT" ] || R_PROJECT="common"
}

cmd="${1:-}"
[ -n "$cmd" ] && shift

case "$cmd" in
  resolve)
    resolve_paths "${1:-.}"
    printf 'GLOBAL_WIKI=%s\n' "$R_GLOBAL"
    printf 'WS_ROOT=%s\n' "${R_WS_ROOT:--}"
    printf 'WS_WIKI=%s\n' "${R_WS_WIKI:--}"
    printf 'PROJECT=%s\n' "$R_PROJECT"
    ;;

  init-ws)
    [ $# -ge 1 ] || { echo "사용법: wiki-index.sh init-ws <워크스페이스경로> [제목]" >&2; exit 2; }
    ws_dir="$(cd "$1" && pwd)"
    ws_name="${2:-$(basename "$ws_dir") Wiki}"
    wiki_root="$ws_dir/docs/wiki"
    ensure_wiki_root "$wiki_root" "$ws_name"
    register_ws_root "$wiki_root" "$(basename "$ws_dir")"
    echo "✓ 워크스페이스 위키 초기화 완료: $wiki_root"
    ;;

  init-project)
    [ $# -ge 1 ] || die "사용법: wiki-index.sh init-project <프로젝트경로> [프로젝트슬러그]"
    proj_dir="$(cd "$1" && pwd)"
    proj_slug="$(slugify "${2:-$(basename "$proj_dir")}")"
    check_slug "스코프" "$proj_slug"
    [ "$proj_slug" != "common" ] || die "프로젝트 슬러그로 common은 쓸 수 없습니다"
    wiki_root="$proj_dir/docs/wiki"
    if [ -s "$wiki_root/wiki.tsv" ] && [ ! -f "$wiki_root/.project" ]; then
      die "이미 워크스페이스 위키로 쓰이는 폴더입니다(.project 표식 없음): $wiki_root"
    fi
    ensure_wiki_root "$wiki_root" "$(basename "$proj_dir") Wiki"
    printf '%s\n' "$proj_slug" > "$wiki_root/.project"
    register_ws_root "$wiki_root" "$(basename "$proj_dir")"
    echo "✓ 단일 프로젝트 위키 초기화 완료: $wiki_root (프로젝트 스코프: $proj_slug)"
    ;;

  upsert)
    [ $# -ge 6 ] || { echo "upsert 인자 6~7개 필요: <위키루트> <스코프> <슬러그> <갱신시각> <제목> <요약> [태그]" >&2; exit 2; }
    wiki_root="$(cd "$1" && pwd)"
    scope="$(slugify "$2")"
    slug="$(slugify "$3")"
    slug="${slug%.md}"
    ts="$(one_line "$4")"
    title="$(one_line "$5")"
    summary="$(one_line "$6")"
    tags="$(one_line "${7:--}")"
    check_slug "스코프" "$scope"
    check_slug "슬러그" "$slug"

    ensure_wiki_root "$wiki_root"
    if [ "$(phys_dir "$wiki_root")" != "$(phys_dir "$GLOBAL_WIKI_ROOT")" ]; then
      register_ws_root "$wiki_root"
    fi
    idx="$wiki_root/wiki.tsv"
    [ -f "$idx" ] && cp "$idx" "$idx.bak"

    action="생성"
    if awk -F'\t' -v sc="$scope" -v sl="$slug" '$1==sc && $2==sl { found=1 } END { exit !found }' "$idx"; then
      action="갱신"
    fi

    awk -F'\t' -v sc="$scope" -v sl="$slug" '!($1==sc && $2==sl)' "$idx" > "$idx.tmp" && mv "$idx.tmp" "$idx"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$scope" "$slug" "$ts" "$title" "$summary" "$tags" >> "$idx"

    rebuild_index "$wiki_root"
    append_log "$wiki_root" "$ts" "$action" "$scope" "$slug" "$title — $summary"
    echo "✓ 위키 색인 $action 완료: [$scope] $slug ($wiki_root/index.md)"
    ;;

  remove)
    [ $# -ge 3 ] || { echo "remove 인자 3~4개 필요: <위키루트> <스코프> <슬러그> [사유]" >&2; exit 2; }
    wiki_root="$(cd "$1" && pwd)"
    scope="$(slugify "$2")"
    slug="$(slugify "$3")"
    slug="${slug%.md}"
    reason="${4:-문서 삭제/통합}"
    check_slug "스코프" "$scope"
    check_slug "슬러그" "$slug"
    ts="$(date '+%Y-%m-%d %H:%M')"

    idx="$wiki_root/wiki.tsv"
    [ -f "$idx" ] && cp "$idx" "$idx.bak"
    awk -F'\t' -v sc="$scope" -v sl="$slug" '!($1==sc && $2==sl)' "$idx" > "$idx.tmp" && mv "$idx.tmp" "$idx"

    rebuild_index "$wiki_root"
    append_log "$wiki_root" "$ts" "삭제" "$scope" "$slug" "$reason"
    echo "✓ 위키 색인 제거 완료: [$scope] $slug"
    ;;

  rebuild)
    [ $# -ge 1 ] || { echo "rebuild 인자 1개 필요: <위키루트>" >&2; exit 2; }
    wiki_root="$(cd "$1" && pwd)"
    rebuild_index "$wiki_root" "${2:-}"
    echo "✓ index.md 재생성 완료: $wiki_root/index.md"
    ;;

  list)
    resolve_paths "${1:-.}"
    echo "=== [1] 워크스페이스 위키 (${R_WS_WIKI:--}) · 현재 프로젝트: ${R_PROJECT} ==="
    if [ -n "$R_WS_WIKI" ] && [ -s "$R_WS_WIKI/wiki.tsv" ]; then
      awk -F'\t' -v p="$R_PROJECT" '
        $1 == p || $1 == "common" {
          mark = ($1 == p ? "★" : " ");
          printf "%s [%s] %s — %s (%s) [%s]\n", mark, $1, $2, $4, $5, substr($3,1,10);
        }
      ' "$R_WS_WIKI/wiki.tsv"
    else
      echo "(등록된 문서 없음)"
    fi
    echo ""
    echo "=== [2] 전역 공통 위키 (${R_GLOBAL}) ==="
    if [ -s "$R_GLOBAL/wiki.tsv" ]; then
      awk -F'\t' '{ printf "  [%s] %s — %s (%s) [%s]\n", $1, $2, $4, $5, substr($3,1,10) }' "$R_GLOBAL/wiki.tsv"
    else
      echo "(등록된 문서 없음)"
    fi
    ;;

  search)
    [ $# -ge 1 ] || { echo "search 인자 필요: <키워드> [기준경로=.]" >&2; exit 2; }
    kw="$1"
    resolve_paths "${2:-.}"
    roots=("$R_GLOBAL")
    if [ -n "$R_WS_WIKI" ] && [ "$R_WS_WIKI" != "$R_GLOBAL" ]; then
      roots=("$R_WS_WIKI" "$R_GLOBAL")
    fi
    # roots.tsv에 등록된 다른 워크스페이스도 포함
    if [ -f "$ROOTS_TSV" ]; then
      while IFS=$'\t' read -r r_path _ _; do
        [ -d "$r_path" ] || continue
        skip=0
        for existing in "${roots[@]}"; do
          [ "$existing" = "$r_path" ] && skip=1 && break
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

  lint)
    [ $# -ge 1 ] || { echo "lint 인자 필요: <위키루트>" >&2; exit 2; }
    wiki_root="$(cd "$1" && pwd)"
    idx="$wiki_root/wiki.tsv"
    [ -f "$idx" ] || idx=/dev/null
    issues=0

    echo "=== 위키 점검 (Lint): $wiki_root ==="
    # 1. 색인에는 있으나 실제 파일이 없는 경우
    while IFS=$'\t' read -r sc sl _ title _ _; do
      [ -z "$sc" ] && continue
      f="$wiki_root/$sc/$sl.md"
      if [ ! -f "$f" ]; then
        echo "✘ [파일 없음] 색인에 등록된 파일이 존재하지 않습니다: $sc/$sl.md ($title)"
        issues=$((issues + 1))
      fi
    done < "$idx"

    # 2. 실제 .md 파일은 있으나 색인(wiki.tsv)에 없는 고아 문서 점검 (index.md, log.md 제외)
    while IFS= read -r md_file; do
      [ -z "$md_file" ] && continue
      rel="${md_file#"$wiki_root"/}"
      [ "$rel" = "index.md" ] || [ "$rel" = "log.md" ] && continue
      sc="${rel%%/*}"
      rest="${rel#*/}"
      sl="${rest%.md}"
      if ! awk -F'\t' -v s="$sc" -v l="$sl" '$1==s && $2==l { found=1 } END { exit !found }' "$idx"; then
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
