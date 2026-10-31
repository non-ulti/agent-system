#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/statusline/statusline.py"
CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/statusline.py"
SETTINGS="$CLAUDE_DIR/settings.json"
BACKUP_DIR="$CLAUDE_DIR/backups"

mkdir -p "$CLAUDE_DIR" "$BACKUP_DIR"
chmod +x "$SRC"
ln -sf "$SRC" "$DEST"

# 공통 agent-system 환경 초기화 실행
if [ -f "$SCRIPT_DIR/setup.sh" ]; then
  bash "$SCRIPT_DIR/setup.sh" --from-statusline
fi

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$BACKUP_DIR/settings.json.bak.$(date +%Y%m%d%H%M%S)"
fi

python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data["statusLine"] = {"type": "command", "command": "~/.claude/statusline.py"}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo "✓ statusLine 설치 완료. 새 세션 또는 재시작에서 반영됩니다."
echo "  심링크: $DEST -> $SRC"
echo "  설정:   $SETTINGS (statusLine 키 머지)"
