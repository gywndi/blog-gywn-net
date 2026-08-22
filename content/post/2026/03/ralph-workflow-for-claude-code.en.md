---
title: Claude Code Writing Code Before You've Even Defined Requirements?
subtitle: Tame the AI before it runs ahead of you — with the Ralph Wiggum workflow!
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
## The problem you run into with Claude Code

These days, more and more developers are using **Claude Code**.

Claude Code is Anthropic's AI coding tool — you describe what you want in the terminal, and it writes the actual code for you. It's genuinely powerful.

But if you've used it for a while, you've probably run into something like this.

> "Build me a sign-up feature."

That's all you said, and Claude starts churning out everything from database design to API code. At first it feels like "wow, that's fast!" — but look closer, and it's often not what you actually wanted.

- You said email verification wasn't needed, but it's in there anyway
- You wanted Next.js, but it built the thing in Express
- The planning wasn't even done yet, and it's already built an overly complex structure

**Once code piles up in the wrong direction**, fixing it later costs more than building it from scratch would have. And Claude doesn't stop. It just keeps building.

Giving instructions every single time only goes so far. There's also a real desire to gather requirements thoroughly, while still trying to conserve context, and so on. **ralph-claude-code** is a tool built to get Claude to produce a good spec first.

---

## What is the "Ralph Wiggum Technique"?

The name might sound a little odd, but the origin is actually simple.

There's a character named **Ralph Wiggum** in the American animated show **The Simpsons** — the police chief's son, who does whatever he's told without thinking, with no grasp of context or purpose. He just does it.

Claude Code diving straight into code without understanding the requirements looks a lot like Ralph.

The **Ralph Wiggum Technique** is a methodology proposed by a developer named [Geoffrey Huntley](https://github.com/ghuntley/how-to-ralph-wiggum), and its core idea is this:

![](/img/2026/03/ralph-workflow.jpg)

> **Before writing any code, force a clear definition of "what needs to be built."**

It changes Claude's actual behavior so that it never moves into implementation until the spec (the requirements document) is complete.

---

## ralph-claude-code: a tool that applies this technique directly in Claude Code

[ralph-claude-code](https://github.com/abcyon/ralph-claude-code) packages the technique above into config files you can use directly in Claude Code.

I wanted to more or less follow the Ralph workflow and code in style, but at some point Claude kept trying to jump straight to implementation. Even when I set a rule every time saying "don't implement first," the spec would often end up built without enough requirements gathered.

Once installed, you get two slash commands inside Claude Code.

| Command | What it does |
|--------|---------|
| `/ralph-spec` | Talks through requirements with Claude and automatically writes up a spec document |
| `/ralph-setup` | Generates all the files needed for the automated build loop in one shot |

`/ralph-spec` is the key one. Run this command, and instead of writing code, Claude **asks you questions.**

---

## Installation (it's just one line!)

Open your terminal and paste in the command below.

```bash
curl -fsSL https://raw.githubusercontent.com/abcyon/ralph-claude-code/main/install.sh | bash
```

> 💡 **New to the terminal?** On Mac, open the `Terminal` app; on Windows, open `PowerShell` or `WSL`.

Once installation finishes, you'll find these files under `~/.claude/`.

```
~/.claude/
├── CLAUDE.md                  ← Claude's overall behavior rules
├── commands/
│   ├── ralph-spec.md          ← definition of the /ralph-spec command
│   └── ralph-setup.md         ← definition of the /ralph-setup command
└── ralph/
    ├── spec-principles.md     ← spec-writing principles
    ├── prompt-templates.md    ← prompt templates
    ├── loop-scripts.md        ← automated build loop scripts
    ├── backpressure.md        ← overload-prevention settings
    └── slc-release.md         ← release-related settings
```

It's fine if you already have a `CLAUDE.md` file — your existing content is preserved, and only the Ralph-related settings get added.

---

## How do you actually use it? — A new project from start to finish

### Step 1. Create a project folder

```bash
mkdir my-project && cd my-project
git init
git commit --allow-empty -m "initial commit"
```

> 💡 If you don't have `git`, install it first from the [official Git site](https://git-scm.com).

### Step 2. Open Claude Code

```bash
claude
```

### Step 3. Define requirements first ← the most important step!

Inside Claude Code, type the command below.

```
/ralph-spec
```

Instead of writing code, Claude **starts asking questions** like this:

```
Who is trying to do what with this feature?
Under what circumstances will it be used?
What does "success" look like?
```

Answer these conversationally, and Claude writes up a requirements document in the `specs/` folder on its own. If anything is missing, it keeps asking follow-up questions until the spec is complete.

**It won't move on to writing code until the spec is complete.** That's the whole point.

### Step 4. Auto-generate the build files

```
/ralph-setup
```

This automatically generates the `loop.sh`, `PROMPT_*.md`, and `AGENTS.md` files needed to run the loop.

### Step 5. Draw up an implementation plan

Run this in your terminal (outside Claude Code).

```bash
./loop.sh plan
```

Based on the spec you created earlier, this produces an `IMPLEMENTATION_PLAN.md` — a document laying out what gets built, in what order.

### Step 6. Run the automated build

```bash
./loop.sh
```

From here, Claude implements everything autonomously according to the plan. No human intervention needed.

---

## The whole flow at a glance

```
❌ The old way:   "Build it" → code pours out → wrong direction → fix it over and over → give instructions

✅ The Ralph way:  conversation → write spec → verify → implementation plan → automated build
```

Implementation always comes **last**. And before that, "what to build" is left behind as a document.

If direction ever drifts later, you can look at the spec file and get back to square one.

---

## Who should try this

- Anyone using Claude Code whose results keep coming out in the wrong direction
- Anyone who tends to jump straight into development without planning or gathering requirements first
- Anyone stuck in a loop of fixing and re-fixing AI-generated code
- Anyone developing solo or on a small team, working alongside AI

---

## Wrapping up

The biggest trap with AI coding tools is **"the wrong direction that looks fast."**

Claude Code is undeniably a powerful tool. But without direction, that power goes to the wrong place. ralph-claude-code's job is to point that power in the right direction first.

Installation is a single line, and you can apply it starting with your very next project.

```bash
curl -fsSL https://raw.githubusercontent.com/abcyon/ralph-claude-code/main/install.sh | bash
```

There's still room for improvement, but we've arrived at a genuinely fantastic era — one where you lock in a clear spec, hit enter, and see the results the next day, putting AI to work even while you sleep.

Give it a try. It's a whole new world.

---

**Reference links**
- 📦 GitHub: [abcyon/ralph-claude-code](https://github.com/abcyon/ralph-claude-code)
- 📖 Original technique: [Ralph Wiggum Technique by Geoffrey Huntley](https://github.com/ghuntley/how-to-ralph-wiggum)
