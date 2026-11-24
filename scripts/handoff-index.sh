#!/usr/bin/env bash
# 핸드오프 색인(handoffs.tsv) 갱신·보관과 repo 기준값 출력
# 사용:
#   handoff-index.sh init                      # 저장소를 준비하고 그 경로를 출력
#   handoff-index.sh upsert <슬러그> <저장시각> <목표> <상태> <관련repo>
#   handoff-index.sh remove <슬러그>
#   handoff-index.sh archive <슬러그> [<슬러그> ...]
#   handoff-index.sh stale [일수=30]
#   handoff-index.sh baseline <repo경로> [<repo경로> ...]   # 브랜치·커밋·원격·미커밋 파일별 줄 수
# 저장 위치는 AGENT_SYSTEM_HOME(기본 ~/.agent-system, 기존 ~/.claude/agent-system 자동 호환)
set -euo pipefail

if [ -z "${AGENT_SYSTEM_HOME:-}" ]; then
  if [ -d "$HOME/.claude/agent-system" ] && [ ! -e "$HOME/.agent-system" ]; then
    ln -s "$HOME/.claude/agent-system" "$HOME/.agent-system" 2>/dev/null || :
  fi
  HOME_DIR="$HOME/.agent-system"
else
  HOME_DIR="$AGENT_SYSTEM_HOME"
fi
IDX="$HOME_DIR/handoffs.tsv"
DIR="$HOME_DIR/handoffs"

one_line() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

backup() {
  [ -f "$IDX" ] && cp "$IDX" "$IDX.bak"
  return 0
}

drop_row() {
  awk -F'\t' -v s="$1" '$1!=s' "$IDX" > "$IDX.tmp" && mv "$IDX.tmp" "$IDX"
}

# git 상태 글자 → 낱말 (awk 함수 정의, baseline에서 앞에 붙여 쓴다)
STATUS_WORDS='function word(s) { return s == "M" ? "수정" : s == "A" ? "추가" : s == "D" ? "삭제" : s == "T" ? "유형 변경" : s == "U" ? "충돌" : s }'

# git이 한글 경로를 \354\225… 로 바꾸지 않게 한다
g() {
  local dir="$1"; shift
  git -c core.quotePath=false -C "$dir" "$@"
}

# 원격 주소를 "호스트/경로 (종류)"로 줄인다. 주소에 든 계정·토큰은 지운다.
remote_label() {
  local url host kind
  url="$(g "$1" remote get-url origin 2>/dev/null)" || { echo "없음"; return 0; }
  url="$(printf '%s' "$url" | sed -E 's#^[a-z+]+://##; s#^[^/]*@##; s#^([^/:]+):([^0-9/])#\1/\2#; s#\.git$##')"
  host="${url%%/*}"
  case "$host" in
    *github*) kind="GitHub" ;;
    *gitlab*) kind="GitLab" ;;
    *) kind="기타 — GitHub·GitLab 여부 확인 필요" ;;
  esac
  printf '%s (%s)\n' "$url" "$kind"
}

# repo 하나의 기준값. save는 이 출력을 그대로 붙이고, load는 같은 명령을 다시 실행해 줄 단위로 비교한다.
# CLI(모델)마다 형식이 달라지면 비교가 흔들리므로 형식은 여기서만 정한다.
baseline_repo() {
  local root branch head changes untracked summary n_untracked limit=40
  if ! g "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf -- '- %s · (git 아님)\n' "$1"
    return 0
  fi
  root="$(g "$1" rev-parse --show-toplevel)"
  branch="$(g "$root" symbolic-ref --short -q HEAD || echo '(detached)')"
  head="$(g "$root" log -1 --pretty='%h %s' 2>/dev/null || true)"
  printf -- '- %s · %s · %s\n' "$root" "$branch" "${head:-(커밋 없음)}"
  printf -- '  - 원격: %s\n' "$(remote_label "$root")"

  if g "$root" rev-parse -q --verify HEAD >/dev/null; then
    # 스테이징 여부와 상관없이 HEAD 기준. 이름 바꾸기는 삭제+추가로 풀어 경로 하나로 두 목록을 잇는다.
    # 상태는 낱말로 적는다 — "M  경로"는 git status의 '스테이징됨' 표기와 같아 잘못 읽힌다
    changes="$(awk -F'\t' "$STATUS_WORDS"'
                           NR == FNR { n[$3] = ($1 == "-") ? "바이너리" : ("+" $1 " −" $2); next }
                           { printf "%s %s (%s)\n", word($1), $2, n[$2] }' \
      <(g "$root" diff HEAD --no-renames --numstat) <(g "$root" diff HEAD --no-renames --name-status))"
    # git 요약문(--shortstat)은 로케일 따라 번역되므로 직접 센다
    summary="$(g "$root" diff HEAD --no-renames --numstat \
      | awk -F'\t' '{ f++; if ($1 != "-") { a += $1; d += $2 } } END { if (f) printf "파일 %d개 (+%d −%d)", f, a, d }')"
  else
    changes="$(g "$root" diff --cached --name-status | awk -F'\t' "$STATUS_WORDS"'{ printf "%s %s (첫 커밋 전)\n", word($1), $2 }')"
    summary=""
  fi
  untracked="$(g "$root" ls-files --others --exclude-standard --directory | awk '{ printf "추적 안 함 %s\n", $0 }')"
  n_untracked="$(printf '%s' "$untracked" | awk 'END { print NR }')"

  if [ -z "$changes$untracked" ]; then
    printf -- '  - 미커밋: 없음\n'
    return 0
  fi
  if [ "$n_untracked" -gt 0 ]; then
    summary="${summary:+$summary · }추적 안 함 ${n_untracked}개"
  fi
  printf -- '  - 미커밋: %s\n' "$summary"
  printf '%s\n%s\n' "$changes" "$untracked" \
    | awk -v max="$limit" 'NF { if (++i <= max) print "    - " $0 } END { if (i > max) printf "    … 외 %d개\n", i - max }'
}

cmd="${1:-}"
[ -n "$cmd" ] && shift
mkdir -p "$DIR"
touch "$IDX"

case "$cmd" in
  upsert)
    [ $# -eq 5 ] || { echo "upsert 인자 5개 필요: 슬러그 저장시각 목표 상태 관련repo" >&2; exit 2; }
    slug="$(one_line "$1")"
    backup
    drop_row "$slug"
    printf '%s\t%s\t%s\t%s\t%s\n' "$slug" "$(one_line "$2")" "$(one_line "$3")" "$(one_line "$4")" "$(one_line "$5")" >> "$IDX"
    ;;
  remove)
    [ $# -eq 1 ] || { echo "remove 인자 1개 필요: 슬러그" >&2; exit 2; }
    backup
    drop_row "$1"
    ;;
  archive)
    [ $# -ge 1 ] || { echo "archive 인자 필요: 슬러그 1개 이상" >&2; exit 2; }
    mkdir -p "$DIR/archive"
    backup
    for slug in "$@"; do
      if [ -f "$DIR/$slug.md" ]; then
        mv "$DIR/$slug.md" "$DIR/archive/$slug.md"
        echo "보관: $slug"
      else
        echo "핸드오프 파일 없음(색인 줄만 지움): $slug"
      fi
      drop_row "$slug"
    done
    ;;
  stale)
    days="${1:-30}"
    cutoff="$(date -v-"${days}"d '+%Y-%m-%d' 2>/dev/null || date -d "-${days} days" '+%Y-%m-%d')"
    awk -F'\t' -v c="$cutoff" 'substr($2,1,10) < c { print $1 "\t" $2 "\t" $4 }' "$IDX"
    ;;
  init)
    echo "$HOME_DIR"
    ;;
  baseline)
    [ $# -ge 1 ] || { echo "baseline 인자 필요: repo 경로 1개 이상" >&2; exit 2; }
    for repo in "$@"; do
      baseline_repo "$repo"
    done
    ;;
  *)
    sed -n '2,10p' "$0" >&2
    exit 2
    ;;
esac
