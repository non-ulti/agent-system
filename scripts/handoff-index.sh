#!/usr/bin/env bash
# 핸드오프 색인(handoffs.tsv) 갱신·보관
# 사용:
#   handoff-index.sh upsert <슬러그> <저장시각> <목표> <상태> <관련repo>
#   handoff-index.sh remove <슬러그>
#   handoff-index.sh archive <슬러그> [<슬러그> ...]
#   handoff-index.sh stale [일수=30]
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
  *)
    sed -n '2,8p' "$0" >&2
    exit 2
    ;;
esac
