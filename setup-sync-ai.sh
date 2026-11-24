#!/usr/bin/env bash
# sync-ai CLI 설치 스크립트 (머신당 1회)
# scripts/sync-ai.py를 ~/.local/bin/sync-ai로 심링크합니다.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$REPO_DIR/scripts/sync-ai.py"
BIN_DIR="$HOME/.local/bin"
DST="$BIN_DIR/sync-ai"

chmod +x "$SRC"
mkdir -p "$BIN_DIR"

if [ -e "$DST" ] && [ ! -L "$DST" ]; then
  mv "$DST" "$DST.bak"
  echo "[backup] 기존 파일 백업 -> $DST.bak"
fi

ln -sf "$SRC" "$DST"
echo "[ok] $DST -> $SRC"
echo "터미널에서 'sync-ai'를 실행해 동기화할 수 있습니다."
