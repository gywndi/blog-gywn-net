---
title: Claude Code, 요구사항도 없이 코드부터 짠다고요?
subtitle: AI가 먼저 달려가기 전에 Ralph Wiggum 워크플로우로 해결하세요! 
author: admin
type: post
date: 2026-03-10T16:16:38+09:00
url: 2026/03/ralph-workflow-for-claude-code
categories:
  - IT
tags:
  - AI
  - LLM
  - Claude
---
## Claude Code를 쓰다 보면 생기는 문제

요즘 개발자들 사이에서 **Claude Code**를 사용하는 분들이 많아지고 있습니다.

Claude Code는 Anthropic이 만든 AI 코딩 도구인데요. 터미널에서 Claude에게 말로 설명하면, 실제 코드를 작성해주는 강력한 도구입니다.

그런데 이걸 써보신 분들이라면 이런 상황을 겪어보셨을 거예요.

> "회원가입 기능 만들어줘."

라고 말했을 뿐인데, Claude가 데이터베이스 설계부터 API 코드까지 주르르 짜기 시작합니다. 처음엔 "와, 빠르다!" 싶지만, 잠깐 들여다보면 내가 원하는 방향이 아닌 경우가 많습니다.

- 이메일 인증이 없어도 된다고 했는데 들어가 있거나
- 프레임워크를 Next.js로 쓰고 싶었는데 Express로 만들거나
- 아직 기획이 안 됐는데 너무 복잡한 구조로 짜버리거나

**방향이 잘못된 채로 코드가 쌓이면**, 나중에 수정하는 비용이 처음부터 다시 만드는 것보다 커집니다. 그리고 Claude는 멈추지 않습니다. 계속 만듭니다.

매번 지침으로 내리기도 한계가 있고.. 요구사항을 풍족하게 모아보고 싶은 욕구도 있고.. 컨텍스트는 아끼고 싶고 등등. Claude에게 좋은 스펙을 만들기 위한 도구가 바로 **ralph-claude-code**입니다.

---

## '랄프 위검 기법'이 뭔가요?

이름이 좀 낯설게 느껴지실 수 있는데요, 사실 유래는 단순합니다.

미국 애니메이션 **심슨 가족**에 **랄프 위검(Ralph Wiggum)**이라는 캐릭터가 나옵니다. 경찰서장 아들인데, 생각 없이 시키는 대로 뭐든 해버리는 캐릭터예요. 전후 사정도 파악 안 하고, 목적도 모르고, 그냥 합니다.

Claude Code가 요구사항도 파악 안 하고 코드부터 짜는 모습이 딱 이 랄프와 닮았습니다.

**Ralph Wiggum Technique**은 [Geoffrey Huntley](https://github.com/ghuntley/how-to-ralph-wiggum)라는 개발자가 제안한 방법론으로, 핵심은 이렇습니다.

![](/img/2026/03/ralph-workflow.jpg)

> **코드를 짜기 전에, 반드시 "무엇을 만들어야 하는가"를 먼저 정의하게 만든다.**

스펙(요구사항 문서)이 완성되기 전까지는 절대로 구현 단계로 넘어가지 않도록 Claude의 행동 방식 자체를 바꾸는 것이죠.

---

## ralph-claude-code: 이 기법을 Claude Code에 바로 적용하는 도구

[ralph-claude-code](https://github.com/abcyon/ralph-claude-code)는 위의 기법을 Claude Code에서 바로 쓸 수 있도록 설정 파일로 패키징한 프로젝트입니다. 

ralph 워크플로우를 나름 따르면서 멋지게 코딩을 하고 싶은데. 어느순간부터 자꾸 구현부터 하려고 하고. 매번 구현부터 하지 말라고 룰을 이야기 해도, 추가적인 요건 수집이 미흡한 상태로 스펙이 만들어지기 일쑤였죠.

설치하면 Claude Code 안에서 두 가지 명령어(슬래시 커맨드)를 사용할 수 있게 됩니다.

| 커맨드 | 하는 일 |
|--------|---------|
| `/ralph-spec` | Claude와 대화하면서 요구사항을 정리하고, 스펙 문서를 자동으로 작성합니다 |
| `/ralph-setup` | 자동 빌드 루프에 필요한 파일들을 한 번에 만들어줍니다 |

특히 `/ralph-spec`이 핵심입니다. 이 커맨드를 실행하면 Claude가 코드를 짜는 게 아니라 **질문을 던집니다.**

---

## 설치 방법 (딱 한 줄이에요!)

터미널을 열고 아래 명령어를 복사해서 붙여넣기 하시면 됩니다.

```bash
curl -fsSL https://raw.githubusercontent.com/abcyon/ralph-claude-code/main/install.sh | bash
```

> 💡 **터미널이 처음이신 분께:** Mac은 `터미널` 앱, Windows는 `PowerShell`이나 `WSL`을 열면 됩니다.

설치가 완료되면 `~/.claude/` 폴더 안에 이런 파일들이 생깁니다.

```
~/.claude/
├── CLAUDE.md                  ← Claude의 전반적인 행동 규칙
├── commands/
│   ├── ralph-spec.md          ← /ralph-spec 커맨드 정의
│   └── ralph-setup.md         ← /ralph-setup 커맨드 정의
└── ralph/
    ├── spec-principles.md     ← 스펙 작성 원칙
    ├── prompt-templates.md    ← 프롬프트 템플릿
    ├── loop-scripts.md        ← 자동 빌드 루프 스크립트
    ├── backpressure.md        ← 과부하 방지 설정
    └── slc-release.md         ← 릴리즈 관련 설정
```

이미 `CLAUDE.md` 파일이 있어도 괜찮습니다. 기존 내용은 유지되고, Ralph 관련 설정만 추가됩니다.

---

## 실제로 어떻게 쓰나요? — 새 프로젝트 처음부터 끝까지

### Step 1. 프로젝트 폴더 만들기

```bash
mkdir my-project && cd my-project
git init
git commit --allow-empty -m "initial commit"
```

> 💡 `git`이 없으신 분은 [Git 공식 사이트](https://git-scm.com)에서 먼저 설치해 주세요.

### Step 2. Claude Code 열기

```bash
claude
```

### Step 3. 요구사항 먼저 정의하기 ← 가장 중요한 단계!

Claude Code 안에서 아래 커맨드를 입력합니다.

```
/ralph-spec
```

그러면 Claude가 코드를 짜는 게 아니라, 이런 식으로 **질문을 시작합니다.**

```
이 기능을 통해 누가 무엇을 하려고 하나요?
어떤 상황에서 사용하게 될까요?
성공했다는 기준은 무엇인가요?
```

이 질문들에 대화하듯 답변하면, Claude가 알아서 `specs/` 폴더에 요구사항 문서를 작성합니다. 내용이 부족하면 추가 질문을 이어가면서 스펙을 완성시킵니다.

**스펙이 완성되기 전까지는 코드 작성으로 넘어가지 않습니다.** 이게 핵심입니다.

### Step 4. 빌드 파일 자동 생성

```
/ralph-setup
```

루프 실행에 필요한 `loop.sh`, `PROMPT_*.md`, `AGENTS.md` 파일들이 자동으로 생성됩니다.

### Step 5. 구현 계획 세우기

터미널(Claude Code 밖)에서 실행합니다.

```bash
./loop.sh plan
```

앞서 만든 스펙을 바탕으로 `IMPLEMENTATION_PLAN.md`(구현 계획서)가 만들어집니다. 어떤 순서로 무엇을 만들지 정리된 문서입니다.

### Step 6. 자동 빌드 실행

```bash
./loop.sh
```

이제부터는 Claude가 계획서대로 자율적으로 구현합니다. 사람이 개입하지 않아도 됩니다.

---

## 전체 흐름을 한눈에 보면

```
❌ 기존 방식:  "만들어줘" → 코드 쏟아짐 → 방향이 틀렸네 → 수정 반복 → 지침

✅ Ralph 방식: 대화 → 스펙 작성 → 검증 → 구현 계획 → 자동 빌드
```

구현은 항상 **마지막**입니다. 그리고 그 전에 "무엇을 만들지"가 문서로 남습니다.

나중에 방향이 흔들려도 스펙 파일을 보면 원점으로 돌아갈 수 있습니다.

---

## 이런 분께 추천드립니다

- Claude Code를 쓰기 시작했는데, 결과물이 자꾸 원하는 방향이 아닌 분
- 기획/요구사항 정리 없이 바로 개발에 뛰어드는 습관이 있는 분
- AI가 만든 코드를 수정하고 또 수정하는 상황이 반복되는 분
- 혼자 또는 소규모 팀에서 AI와 함께 개발하는 분

---

## 마치며

AI 코딩 도구의 가장 큰 함정은 **"빠른 것처럼 보이는 잘못된 방향"**입니다.

Claude Code는 분명 강력한 도구입니다. 하지만 방향이 없으면 그 힘이 엉뚱한 곳으로 향합니다. ralph-claude-code는 그 힘에 방향을 먼저 잡아주는 역할을 합니다.

설치는 딱 한 줄이고, 다음 프로젝트부터 바로 적용할 수 있습니다.

```bash
curl -fsSL https://raw.githubusercontent.com/abcyon/ralph-claude-code/main/install.sh | bash
```

아직 개선이 필요하지만. 스펙을 명확하게 정해놓고. 엔터를 누른 후 다음날 결과물을 볼 수 있는.. 자는 시간에도 AI 일을 시킬 수 있는 그런 환상적인 시대가 도래하였습니다.

한번 시작해보세요. 신세계입니다.

---

**참고 링크**
- 📦 GitHub: [abcyon/ralph-claude-code](https://github.com/abcyon/ralph-claude-code)
- 📖 원본 기법: [Ralph Wiggum Technique by Geoffrey Huntley](https://github.com/ghuntley/how-to-ralph-wiggum)
