#!/usr/bin/env bash

# 기본값 초기화
TITLE=""
CATEGORIES=""
TAG=""
TYPE="post"  # 기본값은 post
FILENAME=""

show_help() {
  cat <<EOF
사용법: $0 [옵션] 파일명.md

옵션:
  --title=TITLE       글 제목 지정
  --category=CATS     카테고리(쉼표 구분)
  --tag=TAG           태그(쉼표 구분)
  --type=TYPE         post 또는 page (기본값: post)
  --help              이 도움말 출력
EOF
}

# 현재 날짜 기준 (post일 때만 사용)
YEAR=$(date +"%Y")
MONTH=$(date +"%m")

# 파라미터 파싱
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) show_help; exit 0 ;;
    --title=*) TITLE="${1#*=}"; shift ;;
    --category=*) CATEGORY="${1#*=}"; shift ;;
    --tag=*) TAG="${1#*=}"; shift ;;
    --type=*)
      TYPE="${1#*=}"
      if [[ "$TYPE" != "post" && "$TYPE" != "page" ]]; then
        echo "❌ 잘못된 type: '$TYPE' (허용값: post, page)"
        exit 1
      fi
      shift ;;
    --*) echo "❌ 알 수 없는 옵션: $1"; exit 1 ;;
    *) FILENAME="$1"; shift ;;
  esac
done

# 필수 파일명 확인
if [[ -z "$FILENAME" ]]; then
  echo "❌ 파일명을 지정해 주세요. 예: my-post.md"
  exit 1
fi

# 경로 조립
if [[ "$TYPE" == "post" ]]; then
  HUGO_FILE="post/$YEAR/$MONTH/$FILENAME"
else
  HUGO_FILE="page/$FILENAME"
fi

# 환경변수 설정 (archetype에서 getenv로 참조 가능)
[[ -n "$TITLE" ]] && export HUGO_TITLE="$TITLE"
[[ -n "$CATEGORY" ]] && export HUGO_CATEGORY="$CATEGORY"
[[ -n "$TAG" ]] && export HUGO_TAG="$TAG"
export HUGO_TYPE="$TYPE"

# Hugo 명령 실행
hugo new content "$HUGO_FILE" --kind "$TYPE"
