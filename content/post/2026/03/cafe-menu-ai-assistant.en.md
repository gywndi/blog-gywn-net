---
title: How AI Helped Me Clean Up a Cafe Menu
subtitle: A story of renewing a 3-year-old cafe homepage together with AI
author: gywndi
type: post
date: 2026-03-14T22:37:02+09:00
url: 2026/03/cafe-menu-ai-assistant
categories:
  - IT
  - Small Talk
tags:
  - AI
  - LLM
  - Cafe
---

# Fixing a Homepage After 3 Years

My wife currently runs an unmanned cafe. And three years ago, I built the cafe's homepage on WordPress.

Since then, I'd barely touched it. Menus changed, images changed, but the homepage just sat there. Maintaining it was too much of a hassle. One day I opened it up and it was completely out of sync with reality — discontinued items were still listed, and current items were missing.

That wasn't going to fly anymore. So I decided to renew it. (Actually, I'd been meaning to since last year...)

This time I decided to rebuild it from scratch with a structure that would be easy to maintain. And along the way, I decided to lean heavily on AI.

---

## Challenge 1: Sorting Out 90 Menu Images

The first wall showed up as soon as I started the renewal.

There were 90 menu image files (just for the grind-type machine). All the filenames were in Korean, and the sizes were all over the place. To put them on the web, I needed English filenames, and they needed resizing too. Opening 90 files one by one, renaming them, resizing them — just thinking about it was overwhelming. And one mistake in the middle meant starting over.

I asked the AI:

> "Make me a mapping table from Korean filenames to English ones. All 90."

The AI read each menu name and built a mapping table with English-style slugs.

Then, based on that table, it wrote a Python script that handled resizing and renaming in one pass. I ran the script, and all 90 files were sorted out at once. I didn't even have to open the images individually. What would've taken half a day by hand — no, probably a full week — was done in a few exchanges.

---

## Challenge 2: Rebuilding the Menu Data from Scratch

Once the images were sorted, the next problem showed up: the menu data. The menu had changed a lot over three years. Some items were new, some were gone. I had to rebuild the names, prices, categories, and temperature options for 25 drinks from scratch.

But the current menu was already fully displayed on the kiosk screen.

I showed the AI a photo of the kiosk.

> "Based on this photo, turn the menu into JSON data."

The AI analyzed the photo, sorted the 25 drinks into categories, and extracted structured data.

- 4 Americano-family drinks
- 5 Cafe Latte-family drinks
- 5 Specialty Lattes
- 5 Milk Teas
- 6 Ades & Teas

It commented out items only available on a specific machine, and stripped out details unnecessary for the web, like origin labeling. Hot/iced distinctions were sorted too. I just dropped a single photo into the chat, and the menu data was done.

---

## Challenge 3: How Do You Describe the Flavor of a Non-Coffee Drink?

Once the menu data existed, I had to figure out how to describe the flavor of each drink. The old homepage used the same flavor axes for every drink: **body, acidity, bitterness.**

But a bitterness gauge on a strawberry latte is awkward. Body on a grapefruit ade? That was a problem I'd just glossed over when I first built the homepage three years ago.

This time, I decided to get it right. I asked the AI:

> "What flavor axes would fit non-coffee drinks?"

The AI analyzed the characteristics of fruit drinks, milk teas, and latte-family drinks, and proposed alternatives. The answer was **sweetness, acidity, refreshment.**

We also settled on the classification rules together.

| Condition | Category | Flavor axes |
|------|------|---------|
| Name contains "Cafe" | Coffee | Body / Acidity / Bitterness |
| Contains only "Latte" | Not coffee | Sweetness / Acidity / Refreshment |
| Choco Latte, Double Choco, Caramel Latte | Latte without coffee | Sweetness / Acidity / Refreshment |

![Menu detail — flavor profile](/img/2026/03/cafe-menu-detail.png)

The whole rule was settled with one line: "a plain 'latte' just means it doesn't have coffee in it." A problem I'd glossed over three years ago got resolved in a single conversation.

---

## Challenge 4: Finding the Right Voice for an Unmanned Cafe

Once the flavor system was in place, I had to write intro copy for each drink.

The old homepage had lines like this:

> "A body-forward latte, gently foamed with steam"

Cafe Purple Mint is an unmanned vending machine. There's no steam. There's no barista. For three years, we'd been running an inaccurate description.

I explained the situation to the AI:

> "Our cafe is an unmanned vending machine. A machine makes the drinks, no barista involved.
> Write copy that keeps that in mind while still making the drinks sound appealing."

Here's what the AI rewrote it as:

> "Precision-extracted espresso meets fresh milk for a deep, smooth latte,
> consistently delivered by machine every time."

The unmanned aspect turned into a strength instead of a weakness. That one word, "consistently," turned into a sense of trust — the same taste, every single time. I described the cafe's character, and the AI found the language that matched it.

---

## Challenge 5: This Time, Building for Easy Maintenance

![Cafe menu list page](/img/2026/03/cafe-menu-list.png)

The biggest goal of this renewal was maintainability. The reason I'd left it untouched for three years was that it was "too much of a hassle." (Try WordPress sometime. It's hell. Absolute hell.)

While building the UI with the AI, I focused first on a structure that would make it easy to add and edit menu items going forward. Along the way, a bunch of small and not-so-small problems came up.

#### Too many items, so the page scrolls forever.
```
→ Switched to a sliding carousel showing 5 items at a time, auto-advancing every 5 seconds.
```

#### Can't tell an ade from a milk tea at a glance.
```
→ Analyzed the naming patterns and added automatic badges.
`Grapefruit Ade` gets an Ade badge, `Earl Grey Milk Tea` gets a Milk Tea badge.
```

#### Images get cropped top and bottom in the modal.
```
→ Changed `object-fit: cover` to `object-fit: contain`.
```

```
#### The flavor gauge doesn't render properly on mobile.
→ The culprit was `align-items: flex-start`. Fixed it to `stretch`.
```

Whenever I described a problem, the AI pinpointed the cause and fixed the code.
Each time a bug got squashed, the page got a little more finished.

---

## Conclusion: I Built a Homepage Through Conversation

The reason it sat untouched for three years was simple: it was just too much manual work.

This renewal was different. Batch-processing 90 images, generating menu data from a single kiosk photo, designing a flavor system, writing copy, building the UI — **all of it was worked out by talking with AI.**

The AI didn't decide the direction. The person who knows the cafe best set the direction, and the AI quickly drafted along that direction. If I'd been on my own, I don't think I would've even attempted it. Or rather, I probably would've put it off for another three years.

Give it a try. It's a lower bar than you'd think — anyone can clear it.
