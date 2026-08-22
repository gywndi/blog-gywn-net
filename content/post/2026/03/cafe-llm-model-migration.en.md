---
title: Local LLM Comment Moderation — A Model Swap Story
subtitle: A scrappy adventure fixing sluggish comment moderation on an unmanned café's site
author: gywndi
type: post
date: 2026-03-27T22:15:02+09:00
url: 2026/03/cafe-llm-model-migration
categories:
  - IT
  - Small Talk
tags:
  - AI
  - LLM
  - Cafe
---

## Comments Were Piling Up

When someone leaves a comment on my café's guestbook, a human doesn't review it first — a local LLM does. It decides whether the comment is abusive, an ad, or just a nice review, and handles it automatically.

>> https://cafepurplemint.com (a tiny bit of shameless promotion)

Then one day, while going through the logs, I noticed something odd.

```
[MOD] Processing 5 pending entries...
[MOD] Processing 5 pending entries...
[MOD] Processing 5 pending entries...
```

The same log line kept repeating. The next poll was kicking off before the previous batch had finished processing.

The cause was simple. **Moderating a single comment took 5.6 seconds on average.** The polling interval was 1 second. Mathematically, even a small burst of comments was guaranteed to back up the processing queue. (I'd actually just built the café's homepage and — not really an ad, but kind of an ad — asked a group chat of friends to try leaving a comment.)

---

## Something Was Off With the Prompt From the Start

Before swapping models, I first took a hard look at the prompt.

The original approach looked like this:

```
Judge pass: false if the comment matches any of the following criteria:
- Profanity or abusive language
- Advertising, spam, or external links
- Defamation of a specific person or business, or false claims
- Personal information (phone number, address, email, etc.)
- Hate speech or discriminatory remarks
```

It was a denylist-style approach. But given what a café guestbook actually is, the range of comments that *should* get through is much narrower than that. Visit reviews, compliments, thank-you notes. That's basically it.

So I flipped the policy.

```
❌ Before: "Reject these" (denylist)
✅ After:  "Only allow these" (allowlist)
```

I also broke the categories down further.

| category | handling |
|----------|----------|
| `clean` | auto-approve |
| `profanity`, `spam`, `advertising`, `defamation` | auto-reject |
| `negative`, `meaningless`, `other` | send to admin via Telegram |

`meaningless` is a category I added this time. Comments like `lolololol`, `abcde`, or just emoji. Not bad, not good — just meaningless. Auto-rejecting felt a bit unfair, so those get routed to the admin instead.

I also added a line at the end of the prompt explicitly listing the valid category values. While testing smaller models, I noticed some of them were returning out-of-spec values like `"offensive"`.

```
category must be exactly one of the following:
"clean", "profanity", "spam", "advertising", "defamation", "negative", "meaningless", "other"
```

---

## Lining Up Three Models

Once the prompt was cleaned up, I tested three candidate models against the same 8 cases. I hit each one directly with curl and compared response time, accuracy, and token counts.

### Accuracy

| Case | gpt-oss:20b | gemma3:4b-it-qat | qwen2.5:3b-instruct |
|--------|:-----------:|:----------------:|:-------------------:|
| clean (normal review) | ✅ | ✅ | ✅ |
| profanity (abuse) | ✅ | ✅ | ✅ |
| spam (spam link) | ✅ | ✅ | ❌ advertising |
| advertising (promoting another business) | ✅ | ❌ clean | ❌ clean |
| defamation | ✅ | ❌ negative | ❌ negative |
| negative (negative opinion) | ✅ | ✅ | ✅ |
| meaningless (lolol) | ✅ | ❌ clean | ❌ other |
| other (asking for the restroom code?) | ✅ | ✅ | ❌ **profanity** |
| **Total** | **8/8** | **5/8** | **3/8** |

qwen2.5:3b classified "What's the restroom door code?" as `profanity`. As in, abusive language. That model is simply unusable.

### Speed and Tokens

| | gpt-oss:20b | gemma3:4b | qwen2.5:3b |
|---|---:|---:|---:|
| Avg. response time | 5,584ms | 1,394ms | 1,187ms |
| Avg. prompt tokens | 594 | 359 | 402 |
| Avg. completion tokens | 23 | 37 | 31 |

The smaller models are 4–5x faster. But they get it wrong. In particular, `advertising` slipped through both of them.

---

## I Tried a Two-Stage Pipeline, But...

"If the small model is fast, why not use it as a first pass, and have gpt-oss re-check anything it flags?"

It sounded reasonable. First, I checked the false-positive rate on `clean` — if a small model wrongly rejects good comments, the whole approach is dead on arrival.

I fed it 10 normal comments, and both gemma3:4b and qwen2.5:3b came back with **0% false positives**. A good sign.

But the opposite direction was the problem. If a small model waves a bad comment through as `clean`, **it gets published without ever passing through gpt-oss.** I measured this "miss risk."

| | gemma3:4b | qwen2.5:3b |
|---|:---:|:---:|
| Bad-comment detection rate | 4/7 (57%) | 6/7 (85%) |
| Bad comments published without gpt-oss | 3 | 1 |

qwen2.5 did better, but `advertising` was a case neither model could reliably catch, no matter how I varied the prompt. I tried 7 different prompt variants — every single one failed. It seemed like 3–4B models simply couldn't grasp the concept of "a post promoting some business other than this café."

I dropped the two-stage pipeline idea.

---

## gemma3:12b Solved Everything

Last, I tested `gemma3:12b-it-qat`. Being a 12B model, I expected it to beat the 4B version — but the result was far better than I'd anticipated.

It nailed all 12 test cases, including 5 advertising patterns, using the base prompt with no modifications at all.

```
✅ clean         → clean         (normal review)
✅ profanity     → profanity     (abuse)
✅ spam          → spam          (spam link)
✅ advertising   → advertising   (promoting another business) ← what 4b couldn't catch
✅ defamation    → defamation
✅ negative      → negative      (negative opinion)
✅ meaningless   → meaningless   (lolol)
✅ other         → other         (restroom code)
✅ advertising   → advertising   (includes an @social-account handle)
✅ advertising   → advertising   ("come visit my shop too")
✅ advertising   → advertising   (external link)
✅ advertising   → advertising   (implicit promotion)
```

And it's fast.

| | gpt-oss:20b | gemma3:12b-it-qat |
|---|---:|---:|
| Avg. response time | 5,584ms | **3,072ms** |
| Accuracy | 8/8 | **12/12** |
| Avg. prompt tokens | 594 | **371** |

It's **45% faster than the old model, more accurate, and uses fewer tokens.** No need for a complicated two-stage pipeline either.

### Comparing the gemma3 Model Family

It was interesting to see how big the gap was between 4B and 12B within the same gemma3 family.

| | gemma3:4b-it-qat | gemma3:12b-it-qat |
|---|:---:|:---:|
| Overall accuracy | 5/8 | **12/12** |
| Advertising detection | 2/5 | **5/5** |
| Clean false-positive rate | 0% | 0% |
| Avg. response time | 1,394ms | 3,072ms |
| Prompt tuning required | Still didn't work even with it | **Not needed** |

No matter how much I tuned the prompt, the 4B model never reliably caught `advertising`. The 12B model got it right out of the box, with the base prompt. This test made it very clear that the gap between model sizes isn't just about speed — it's a **difference in the model's level of conceptual understanding.**

---

## Conclusion — One Line in `.env`

No two-stage pipeline, no prompt tuning needed.

```bash
# before
LLM_MODEL=gpt-oss:20b

# after
LLM_MODEL=gemma3:12b-it-qat
```

One line changed.

Response time: 5.6s → 3.1s. Accuracy: 8/8 → 12/12. And the comment queue backing up? Gone.

This confirmed once again that with local LLMs, model choice is basically everything. There's a limit to what prompt engineering can do — if the model doesn't grasp the underlying concept, no amount of prompting will get you there. Once I hit that wall, the answer turned out to be simpler than expected: a bigger model.

There's still room to improve on the trickier `advertising` cases — implicit promotion like "this place is nice, but you should also check out my shop..." — probably with a rule-based pre-filter. But that's a story for another day. For now, this is good enough.
