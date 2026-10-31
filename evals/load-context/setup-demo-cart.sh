#!/usr/bin/env bash
# load-context 비교 테스트용 가상 데이터를 만든다 (실제 프로젝트 내용 없음).
#   setup-demo-cart.sh <작업 폴더> [플러그인 루트=이 repo]
# 만드는 것:
#   <작업 폴더>/demo-shop                 가상 repo (GitLab 원격). 저장 시점보다 cart.ts가 더 바뀌었고 notes.md가 새로 생긴 상태
#   <작업 폴더>/store/handoffs/demo-cart.md   새 양식 핸드오프 (놓치면 안 되는 것 5개 + 저장 시점 기준값)
#   <작업 폴더>/store/handoffs.tsv
# 실행할 때 AGENT_SYSTEM_HOME=<작업 폴더>/store 로 load-context를 돌린다.
set -euo pipefail

DEST="$(mkdir -p "$1" && cd "$1" && pwd -P)"
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
R="$DEST/demo-shop"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=demo GIT_AUTHOR_EMAIL=demo@example.com GIT_COMMITTER_NAME=demo GIT_COMMITTER_EMAIL=demo@example.com

rm -rf "$R" "$DEST/store"
mkdir -p "$R/src" "$R/api" "$DEST/store/handoffs"
git -C "$R" init -q -b feat/server-total
git -C "$R" remote add origin https://gitlab.example.com/demo/shop.git
printf 'export function renderTotal(items) {\n  const sum = items.reduce((a, i) => a + i.price * i.qty, 0);\n  return new Intl.NumberFormat("ko-KR").format(sum);\n}\n' > "$R/src/cart.ts"
printf 'export async function getCart(id) {\n  return fetch(`/api/cart/${id}`).then((r) => r.json());\n}\n' > "$R/api/cart.ts"
git -C "$R" add . && git -C "$R" commit -q -m "feat: 장바구니 합계 표시 준비"

# 저장 시점 상태 → 기준값을 뜬다 (사용자 파일 줄에는 ← 사용자)
printf 'export function renderTotal(cart) {\n  // 서버 totalDisplay 사용 예정\n  return cart.totalDisplay;\n}\n' > "$R/src/cart.ts"
mkdir -p "$R/fixtures"; printf '{"note":"가상 운영 스냅샷"}\n' > "$R/fixtures/prod-snapshot.json"
BASE="$("$ROOT/scripts/handoff-index.sh" baseline "$R" | sed 's|^\(    - 추적 안 함 fixtures/\)$|\1 ← 사용자|')"

# 저장 이후 누군가 더 만진 상태
printf 'export function renderTotal(cart) {\n  // 서버 totalDisplay 사용\n  if (!cart) return "";\n  const text = cart.totalDisplay;\n  return text;\n}\n' > "$R/src/cart.ts"
printf '메모\n' > "$R/notes.md"

cat > "$DEST/store/handoffs/demo-cart.md" <<EOF
# HANDOFF: demo-cart

- 저장: 2026-10-30 18:20

## 놓치면 안 되는 것
- 사용자 지시: "쿠폰 계산은 서버에서만 해. 프론트에 할인 로직 넣지 마" — 장바구니 합계 표시를 고칠 때 나온 말
- 해봤는데 안 됨: \`Intl.NumberFormat\`으로 통화 반올림 — 원인: 서버 합계와 1원 차이가 남(서버는 원 단위 내림) / 다시 하려면: 서버 \`totalDisplay\` 응답값을 그대로 표시
- 확인한 사실: 장바구니 수량 상한(99)은 코드에 없다 — \`src/cart.ts\`·\`api/cart.ts\` 어디에도 검사 없음. QA 문서의 "상한 99"는 기획안일 뿐
- \`fixtures/prod-snapshot.json\`은 사용자 것 — 커밋·수정 금지 (가상 운영 데이터라 추적 안 함으로 유지)
- 답 대기: 기획 담당에게 "품절 상품을 장바구니에 남길지" 물어봄 — 답 오기 전엔 품절 처리 건드리지 말 것

## 목표
장바구니 합계 표시를 서버 계산값으로 통일하고 MR !42를 머지한다.

## 현재 상태
- 합계 표시를 서버 응답값(\`totalDisplay\`)으로 바꾸는 중. \`src/cart.ts\` 수정 중(미커밋).
- 단위 테스트는 저장 직전 통과 — 다시 확인: \`pnpm test cart\`

## 다음 할 일
1. \`src/cart.ts\`의 \`renderTotal\`이 \`cart\`가 비었을 때도 안전한지 확인하고 커밋 — 왜: 빈 장바구니 화면에서 서버가 \`totalDisplay\`를 빼고 응답한다
2. MR !42 설명에 "프론트 계산 제거 이유" 추가 후 리뷰 요청 — 왜: 리뷰어가 왜 프론트 계산을 없앴는지 물었다

## 작업 repo (기준값)
$BASE

## 외부 참조
- PR/MR: !42 (gitlab.example.com/demo/shop) · 저장 시점 상태: 열림(리뷰 대기)
- Jira: DEMO-123 · 진행 중

## 결정 사항
- 통화 표시는 서버 문자열을 그대로 쓴다 — 프론트와 서버의 반올림 규칙이 달라서

## 주의사항
- 테스트는 \`pnpm test cart\`로 범위를 좁힌다 — 전체 테스트는 e2e까지 돌아 10분 넘게 걸린다 (AGENTS.md 후보)
EOF
printf 'demo-cart\t2026-10-30 18:20\t장바구니 합계 표시를 서버 계산값으로 통일하고 MR !42를 머지한다.\t합계 표시 교체 중 — 다음: 빈 장바구니 확인 후 커밋\tdemo-shop\n' > "$DEST/store/handoffs.tsv"

echo "repo:  $R"
echo "store: $DEST/store   (AGENT_SYSTEM_HOME으로 지정)"
