# evals

스킬을 고친 뒤 이전 버전과 비교해 보는 테스트. 형식은 skill-creator의 `evals.json`을 따른다. 데이터는 전부 가상이다 — 실제 핸드오프는 개인·고객 프로젝트 내용이 들어 있어 여기에 넣지 않는다.

## load-context

`evals/load-context/` — 새 양식 핸드오프(`놓치면 안 되는 것` 5개, 기준값, GitLab MR)를 불러왔을 때 브리핑이 무엇을 전하는지 본다.

1. 가상 repo와 핸드오프를 만든다. 비교할 두 버전이 같은 데이터를 보게 작업 폴더 하나를 같이 쓴다(load는 읽기만 한다).
   ```bash
   evals/load-context/setup-demo-cart.sh /tmp/lc-eval
   ```
2. 이전 버전 스킬을 따로 꺼내 둔다: `git archive <이전 커밋> skills scripts | tar -x -C /tmp/lc-old`
3. 각 버전으로 "demo-cart 이어서 하자"를 실행한다. 셸 명령마다 `AGENT_SYSTEM_HOME=/tmp/lc-eval/store`와 `CLAUDE_PLUGIN_ROOT=<그 버전의 루트>`를 붙이고, 읽기 전용으로 돌리고, 사용자에게 보일 브리핑만 파일로 남긴다.
4. `evals.json`의 expectations로 두 브리핑을 채점한다.

2026-11-01 첫 비교에서는 이 가상 데이터와 함께 실제 옛 양식 핸드오프 2개(로컬에서만)도 썼다.
