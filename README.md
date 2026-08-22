# blog-gywn-net

[gywn.net](https://gywn.net) 블로그 소스. [Hugo](https://gohugo.io) 정적 사이트 생성기 + [beautifulhugo](https://github.com/halogenica/beautifulhugo) 테마로 만들며, Netlify에서 자동 빌드/배포됩니다.

## 구조

```
content/         글과 페이지 (마크다운)
  post/YYYY/MM/  연/월 단위로 정리된 포스트
  page/          About 등 고정 페이지
static/          이미지 등 정적 에셋 (img/, css/ ...)
layouts/         테마 커스터마이징용 partial (head, footer 등)
archetypes/      hugo new 시 사용하는 글 템플릿
themes/beautifulhugo/  블로그 테마 (vendored, submodule 아님)
hugo.toml        Hugo 설정 (메뉴, 테마 파라미터 등)
netlify.toml     Netlify 빌드 설정
hugo-new.sh      새 글/페이지 생성 스크립트
```

## 글 작성

`hugo-new.sh`로 새 글을 생성합니다. `content/post/{연도}/{월}/` 아래에 오늘 날짜 기준으로 파일이 생성됩니다.

```bash
./hugo-new.sh --title="글 제목" --category="분류1,분류2" --tag="태그1,태그2" my-post.md
```

- `--type=page`를 주면 `content/page/`에 고정 페이지로 생성됩니다.
- 이미지는 `static/img/`에 넣고 글에서 상대 경로로 참조합니다.

## 로컬 미리보기

```bash
hugo server -D
```

## 배포

`main` 브랜치에 push하면 Netlify가 자동으로 `hugo` 빌드 후 배포합니다. 별도 수동 배포 절차 없음.

```bash
git add .
git commit -m "..."
git push origin main
```
