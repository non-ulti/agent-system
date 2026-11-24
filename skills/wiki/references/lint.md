# 동작 3: 점검·정리 (Lint)

사용자가 "위키 점검해줘", "wiki lint"를 요청하거나 문서를 대거 이동·삭제한 뒤 실행한다. [SKILL.md](../SKILL.md)의 "준비"를 마쳐 `$WIKI_SH`와 `WIKI=`·`GLOBAL_WIKI=` 값을 확인한 상태에서 시작한다. `WIKI=` 줄의 위키마다, 그리고 전역 위키에 실행한다:

```bash
"$WIKI_SH" lint "<WIKI= 줄의 위키>"
"$WIKI_SH" lint "<GLOBAL_WIKI>"
```

- **색인 누락(고아 파일)**: 파일은 있는데 `wiki.tsv`에 빠진 문서는 내용을 읽어 `upsert`로 색인에 등록할지 묻는다. 등록 방법은 [ingest.md](ingest.md)의 4단계를 따른다.
- **파일 실종**: 파일이 삭제·이동됐는데 색인에만 남은 항목은 `"$WIKI_SH" remove "<위키루트>" "<카테고리/문서>"`로 정리한다.
