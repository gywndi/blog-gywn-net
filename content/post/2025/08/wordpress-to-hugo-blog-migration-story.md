---
title: 워드프레스 블로그 휴고 전환 스토리
subtitle: 하루 꼬박 노가다로 이루어낸. 눈물없이 읽을 수 없는.. 이루었도다.
author: admin
type: post
date: 2025-08-20T11:27:18+09:00
url: 2025/08/wordpress-to-hugo-blog-migration-story
categories:
  - IT
tags:
  - wordpress
  - hugo
  - netlify
---

# Overview
벌써 15년이 훌쩍 넘었던 워드프레스 블로그. 
워낙에 레거시 태그들이 내부적으로 많았고. 스킨을 몇번 변경하다 보니. 이미 덕지덕지 오염(?)이 되어있던 상태. 그 와중 hugo를 접하면서 이쪽으로 넘어오면 좋겠다는 생각만을 마음속으로만 했었는데. 어제 겸사겸사 마음을 잡고 이 대사작업을 진행을 해보았습니다.

hugo가 생소하신 분들도 있으실텐데.. **hugo는 정적 사이트 생성기**로. golang로 만들어져 있으며. 속도도 빠르고, **마크다운 기반 컨텐츠를 HTML/JS/CSS 등으로 변환**해주는 녀석입니다. hugo로 글을 쓰면 좋은 것은. 굳이 GUI툴을 사용하지 않더라도. md 파일을 syntax를 적절히 넣어서 작성하면 되고. 모든 것을 git으로 관리하며. netify와 연계를 하면 기존 도메인도 제대로 활용할 수 있다는 점입니다. 로컬에서 서술하듯 글을 쓰다 보니. 가볍고, 생산적이고. 기타 등등.. 

서비스는 **netlify 플랫폼**을 활용합니다. Netlify는 정적 사이트와 프론트엔드 앱을 빠르게 배포·호스팅하는 플랫폼으로, CI/CD와 CDN을 통해 자동화된 웹 개발 환경을 제공합니다. github에 연동만 시키면. 서비스 배포에서 큰 고민을 하지 않아도 되는 것이죠. 무료 플랜은 월 125시간 빌드, 월 100GB 대역폭, 팀원 1명 제한이 있으며, 추가 리소스 사용 시 유료 플랜 업그레이드가 필요하기는 하지만. 개인 블로그 운영 입장에서는 넉넉한 리소스가 아닐지..??

레거시 블로그를 어떤 과정의 삽질을 거쳐. **hugo and netlify**로 최종 안착을 했는지. 오늘 경험담 풀어보도록 하겠습니다. ^^

# Export contents
첫번째 단계로는 당연히도 데이터를 추출하는 단계입니다. 워드프레스로 돌고 있는 현재 블로그에서 그동안 누적한 데이터들을 내리는 첫번째 단계이죠. 

전용 변환 툴인 [wordpress-to-hugo-exporter](https://github.com/SchumacherFM/wordpress-to-hugo-exporter)를 사용해볼 것인데. 아쉽게도. 현재 제 블로그 서버에서는 PHP zip 확장(extension=zip) 미설치로. 이것을 직접 사용해볼 수가 없더군요. ㅠㅠ (심지어.. OS도 centos6. 오래 썼다. 진짜.)
그래서. 전체 데이터를 xml로 추출한 후. Docker를 경유한 후 여기서 변환 툴을 사용해보고자 합니다.

## Step1) 블로그 컨텐츠 XML 추출
wp-admin에 들어가서. Tools->Export (/wp-admin/export.php)에 접속하여. 아래 그림과 같이 전체 컨텐츠를 다운로드 받습니다.
![블로그 컨텐츠 XML 추출](/img/2025/08/wp-export-01.png)

`gywndi039sdatabase.WordPress.2025-08-19.xml`라는 이름으로 추출이 되었고. 이 파일을 바로 다음에 구성할 도커 워드프레스에 올리고. 해당 환경에서 실제 변환툴을 돌려 추출을 진행합니다.

## Step2) Docker 환경 구성
MariaDB + WordPress + WP-CLI + Adminer 구성을 위한 docker-compose 구성입니다. 
```bash
$ mkdir -p ~/wp2hugo && cd ~/wp2hugo
$ echo '
services:
  db:
    image: mariadb:10.6
    restart: unless-stopped
    environment:
      MARIADB_DATABASE: wp
      MARIADB_USER: wp
      MARIADB_PASSWORD: wp
      MARIADB_ROOT_PASSWORD: root
    volumes:
      - db_data:/var/lib/mysql

  wordpress:
    image: wordpress:php8.2-apache
    depends_on:
      - db
    restart: unless-stopped
    ports:
      - "8080:80"                 # http://localhost:8080 으로 접속
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wp
      WORDPRESS_DB_PASSWORD: wp
      WORDPRESS_DB_NAME: wp
    volumes:
      - wp_data:/var/www/html     # WP 파일 보존(플러그인/업로드 등)

  wpcli:
    image: wordpress:cli
    depends_on:
      - wordpress
    user: "33:33"                 # www-data (파일 권한 맞추기)
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wp
      WORDPRESS_DB_PASSWORD: wp
      WORDPRESS_DB_NAME: wp
    volumes:
      - wp_data:/var/www/html     # WP 파일 시스템 접근
      - ./tmp:/tmp                # 임시 파일/결과 zip 저장

  adminer:
    image: adminer
    depends_on:
      - db
    restart: unless-stopped
    ports:
      - "8081:8080"               # http://localhost:8081 (DB 웹툴, 선택)

volumes:
  db_data:
  wp_data:
' > docker-compose.yml
```

이제 Docker 환경을 올리고. open(Mac) 또는 xdg-open(Linux) 툴로 초기 설치 진행을 합니다. 브라우저에서 워드프레스 초기 설치 진행(사이트명/계정)을 하도록 합니다.
```bash
$ docker compose up -d                    # # 컨테이너 기동
$ open http://localhost:8080 2>/dev/null || xdg-open http://localhost:8080
  ## 브라우저에서 워드프레스 초기 설치 진행 (사이트명/계정 생성)
```

## Step3) Upload & Export
이제 모든 준비가 완료되었습니다. `Step1`에서 받은 xml파일을 도커 환경에 업로드를 합니다. 업로드 후 글들이 정상적으로 잘 보이는지 체크해보고. 도커에 wordpress-to-hugo-exporter 플러그인 설치를 한 후 바로 컨텐츠를 추출해봅니다.

```bash
docker compose cp ~/Downloads/gywndi039sdatabase.WordPress.2025-08-19.xml wordpress:/var/www/html/blog.xml  # # XML 업로드
docker compose run --rm wpcli sh -lc \
  'wp plugin install wordpress-importer --activate && \
   wp import /var/www/html/blog.xml --authors=create --skip=attachment'

# # Exporter 플러그인 설치/활성화 (GitHub ZIP 직접 설치)
docker compose run --rm wpcli sh -lc \
  'wp plugin install https://github.com/SchumacherFM/wordpress-to-hugo-exporter/archive/refs/heads/master.zip --activate'

docker compose run --rm wpcli sh -lc \  
  'cd wp-content/plugins/wordpress-to-hugo-exporter && \
   php -d memory_limit=-1  hugo-export-cli.php /tmp/' 

```
이제 wp2hugo/tmp/wp-hugo.zip 파일이 정상적으로 잘 생성된 것을 확인해볼 수 있겠습니다. ^^


# Import contents
앞서 추출한 데이터를 올리기 전에. hugo 환경 구성을 해야겠죠. 참고로. 저는 [beautifulhugo 템플릿](https://github.com/halogenica/beautifulhugo)을 이용하였습니다.

Step1) Hugo 환경 구성
외부 css 주입이 가능하도록 일부 소스 수정이 필요하기에. `git submodule`보다는 직접 다운로드 받아서 themes/ 하단에 위치해놓습니다.
```bash
$ hugo new site blog-gywn-net
$ cd blog-gywn-net
$ cp ~/Downloads/beautifulhugo themes 
$ cp -r themes/beautifulhugo/exampleSite/* .
$ git init
```
빠른 활용을 위해. 예제 샘플 사이트로 올려보고. 설정 변경 및 기존 컨텐츠는 일괄 제거하였습니다.
```bash
$ cp -r themes/beautifulhugo/exampleSite/* .
$ rm -rf content/page/* content/post/*
```
참고로. 하단은 제가 올린 사이트 설정입니다. 긁어다 붙여봅니다.\
```bash
echo 'baseurl = "/"
DefaultContentLanguage = "en"
title = "gywn'"'"'s tech"
theme = "beautifulhugo"
pygmentsStyle = "trac"
pygmentsUseClasses = true
pygmentsCodeFences = true
pygmentsCodefencesGuessSyntax = true
enableGitInfo = true

[Services]
  [Services.googleAnalytics]
    id = "G-XXXXXXXX"

[Params]
  subtitle = "Innovating, Analyzing, Sharing"
  mainSections = ["post","posts"]
  logo = "img/avatar-sdc-angry.png"
  favicon = "img/favicon-sdc.ico"
  dateFormat = "2006-01-02"
  commit = false
  rss = true
  comments = true
  readingTime = true
  wordCount = false
  useHLJS = true
  socialShare = true
  delayDisqus = true
  showRelatedPosts = true
  since = "2011"
  customCSS = ["css/custom.css"]

[Params.author]
  name = "gywndi"
  website = "https://gywn.net"
  email = "gywndi@gmail.com"
  facebook = "dongchan.sung"
  github = "gywndi"

[[menu.main]]
    name = "Blog"
    url = ""
    weight = 1

[[menu.main]]
    name = "About"
    url = "page/about/"
    weight = 3

[[menu.main]]
    name = "Tags"
    url = "tags"
    weight = 3
' > hugo.toml
```
customCSS 기반으로 스타일 제어를 하기 위해 템플릿 헤더 파일(`themes/beautifulhugo/layouts/partials/head.html`) 중간 어딘가에 아래 코드를 추가합니다.
```html
  {{ range .Site.Params.customCSS }}
  <link rel="stylesheet" href="{{ . | absURL }}">
  {{ end }}
```

그러면. 앞서 `Params`에서 지정한 customCSS으로 스타일을 원하는대로 제어해볼 수 있습니다. 그렇다고 제가 뭘 거창하게 수정한 것은 아니고. 폰트와 폰트 사이즈 정도??
```css
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap');
body {
  font-size: 16px;
  font-family: 'Noto Sans KR', sans-serif;
}
```

## Step2) Copy to hugo
`wp-hugo.zip`로 다운받은 파일을 압축 해제 후 보면. posts 하단에 그동안 누적해서 작성해온 블로그들이 있습니다. (물론 다른 페이지들도 있지만. 스킵!)
```bash
ls -al tmp/hugo-export/posts
-rw-r--r-- 1 8 20 05:44 2011-12-02-gywndi-blog-open.md
-rw-r--r-- 1 8 20 05:44 2011-12-05-mysql-three-features.md
-rw-r--r-- 1 8 20 05:44 2011-12-07-om-mani-batme-hum.md
-rw-r--r-- 1 8 20 05:44 2011-12-09-airvideo-on-cento.md
-rw-r--r-- 1 8 20 05:44 2011-12-11-centos-apache-php-mysql.md
-rw-r--r-- 1 8 20 05:44 2011-12-20-mysql-installation-on-linux.md
-rw-r--r-- 1 8 20 05:44 2011-12-21-mysql-db-migration.md
-rw-r--r-- 1 8 20 05:44 2011-12-28-mysql-replication-1.md
-rw-r--r-- 1 8 20 05:44 2012-01-02-mysql-tuning-strategy-bagic.md
-rw-r--r-- 1 8 20 05:44 2012-01-30-mysql-table-lock.md
-rw-r--r-- 1 8 20 05:44 2012-02-10-mysql-replication-2.md
-rw-r--r-- 1 8 20 05:44 2012-03-08-new-tweet-store.md
```

이것들을 content/post 하단에 놓고 hugo 구동을 해보면. 일단 잘 올라옵니다만.. (박수 치고 절망에 빠짐)
```bash
$ hugo serve
```
뭔가 이미지가 보이지 않고. 예쁘지가 않네요. 링크도 이상하고................. 이제. 노가다 수작업이 시작할 순간입니다.

## Step3) Correct contents
총 85개의 페이지를 한땀한땀 이 작업을 수했했습니다. 일부 sed 기반으로 변환을 했지만... 이미지 및 링크 정보는 각 사이트마다 제각각 태그가 생성이 되어버린지라. 마음 비우고. 4시간동안 노가다..ㅠㅠ
* 링크 변경
  - `url: /?p=3084`를 `2024/09/tc-latency-on-linux` 원래 링크로 변경
* 태그 제거 및 마크다운 문법으로 변환
  - `<P>`, `<DIV>`, `[CODE]` 제거
  - `<strong>`은 `**내용**` 형태로 변경
  - 기타 특수문자 보이는대로 제거
* 링크, 이미지, 동영상 관련 태그 수정
  - 링크: `[링크명](링크주소)` 
      ex) `[구글](https://google.com)`
  - 이미지: `![](이미지절대경로)` 
      ex) `![](/img/2025/08/xxx.png)`
  - 동영상: `[![Video Label](이미지주소)](동영상경로)`
      ex) `[![Video Label](http://img.youtube.com/vi/8pplUghEeK8/0.jpg)](https://youtu.be/8pplUghEeK8)`

참고로. 이미지 경우 워드프레스의 `wp-content/uploads` 하단 구조를 그대로 가져왔기에. hugo의 static 내 이미지 경로만 잘 지정해주면 되었습니다.

# Run on netlify

앞서 이야기를 한 것처럼. 서비스는 netlify 플랫폼을 활용해보겠습니다. netlify에 생소하신 분들도 가입 후 조금만 둘러보면. 쉽게 적응 가능하실꺼예요. ^^

## Step1) Import project
[netlify.com](netlify.com)의 `Add new project`->`Import an existing project`로 들어가서. 현재 사용중인 레파지토리 선택을 하고 netlify로 가져옵니다. Import 전 netlify를 위한 설정(`netlify.toml`)이 필요한데. 빌드 방법과 타겟. 그리고 버전 정도만 명시하는 정도입니다. (하단은 제가 사용 중인 설정)
```toml
[build]
  publish = "public"
  command = "hugo"

[context.production.environment]
  HUGO_VERSION = "0.147.8"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200
``` 
이렇게 큰 문제없이 프로젝트를 가져오면. `프로젝트명.netlify.app` 주소로 배포한 사이트에 접속을 해볼 수 있습니다. 
참고로, 제 주소는 [https://gywn.netlify.app/](https://gywn.netlify.app/)

## Step2) Domain setting
netlify는 상용 도메인(`.com`, `.net`, `.io`, etc) 기반으로 연결을 해볼 수 있습니다. 즉. 기존에 ddns으로 운영할 필요가 없어진 것이죠. 이것이야말로 제 입장에서는 혁신(?)이었습니다. 

`Domains` -> `Add or register domain` -> `Add a domain you already own`에 가서 현재 소유 중인 도메인을 등록합니다. 
![Add a domain to Netlify DNS](/img/2025/08/add-a-domain-to-netlify-dns.png)

참고로, Netlify DNS를 사용하기 위해서는 도메인의 네임서버를 아래로 변경해놓아야 합니다.

**Netlify DNS**
- dns1.p05.nsone.net
- dns2.p05.nsone.net
- dns3.p05.nsone.net
- dns4.p05.nsone.net

설정에 큰 문제가 없다면 아래와 같이 최종적으로 `Netlify DNS`로 체크가 되고. 외부 도메인 기반으로 문제없이 서비스가 제공됩니다.
![Domain on netlify DNS](/img/2025/08/domain-on-netlify-dns.png)

추가로. 사이트에 큰 문제가 없다면. `let's encryption` 인증서를 발급해줍니다. 

# Appendix
`hugo new content post/2025/08/xxx-xxx-xxx.md` 이렇게 사용하기에는 너무 불편하기에. 그리고. title도 동적으로 제어하고 싶은 욕망이 샘솟아 간단한 쉘 스크립트를 작성해보았습니다. `post` 타입인 경우, 현재 날짜 기준으로 디렉토리가 만들어지고. url도 그것에 맞게 세팅이 됩니다. `page` 경우에는 기존대로 그대로 만들어집니다.

### hugo-new.sh
```bash
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
```

스크립트 내부에서는 `--kind` 기반으로 archetypes를 채택(`post.md` / `page.md`)합니다. 

한글 제목을 비롯해 카테고리, 태그 등, 다양한 변수를 어떻게 전달할까 고민했었는데. go template에서 os환경 변수 접근을 하는 방법을 활용하여. 템플릿 내부에서 변수값을 읽을 수 있게 md 파일을 구성해보았고요. ^^

### archetypes/post.md
```yaml
---
title: {{ getenv "HUGO_TITLE" | default (replace .Name "-" " " | title) }}
subtitle: 
author: {{ getenv "HUGO_AUTHOR" | default "admin" }}
type: post
date: {{ .Date }}
url: {{ .Date |  time.Format "2006/01" }}/{{ .File.ContentBaseName }}
categories:
{{- range (split (getenv "HUGO_CATEGORY" | default "Uncategorized") ",") }}
  - {{ trim . " " }}
{{- end }}
tags:
{{- range (split (getenv "HUGO_TAG" | default "Untagged") ",") }}
  - {{ trim . " " }}
{{- end }}
---
```

### archetypes/page.md
```yaml
---
title: {{ getenv "HUGO_TITLE" | default (replace .Name "-" " " | title) }}
subtitle: 
author: {{ getenv "HUGO_AUTHOR" | default "admin" }}
type: page
date: {{ .Date }}
tags:
{{- range (split (getenv "HUGO_TAG" | default "Untaged") ",") }}
  - {{ trim . " " }}
{{- end }}
---
```

### example
```bash
$ ./hugo-new.sh --title="워드프레스에서 휴고로 블로그 전환기" --type="post" --tag="tag01, tag02" --category="small talk"  my-test-post.md 
Content "/Users/chan/git/blog-gywn-net/content/post/2025/08/my-test-post.md" created
$ cat /Users/chan/git/blog-gywn-net/content/post/2025/08/my-test-post.md
---
title: 워드프레스에서 휴고로 블로그 전환기
subtitle: 
author: admin
type: post
date: 2025-08-20T16:45:27+09:00
url: 2025/08/my-test-post
categories:
  - small talk
tags:
  - tag01
  - tag02
---
```


# Conclusion
15년을 훌쩍 넘게 사용을 해왔던 블로그를 드디어. 정리하였습니다. 정적인 페이지의 단점은 게시판이 없다는 것이긴 하지만. 어차피 개인블로그를 운영하면서 굳이 댓글을 사용하지는 않았습니다. (스팸만 덕지덕지)

하단 과정을 통해 작업을 하였고. 꼬박 8/19 하루가 걸리고 말았네요. 
* Export contents(XML)
* Import contents on Docker
* Export contents md files(wordpress-to-hugo-exporter)
* Correct contents
* Domain setting

그래도 깔끔해진 컨텐츠를 보며. 마음이 시원합니다. 기존 워드프레스는 며칠 두고 보고. 백업 후 내리려합니다.
이 기회에. 무인카페 홈페이지도 hugo 기반으로 변경해볼 생각 :-)