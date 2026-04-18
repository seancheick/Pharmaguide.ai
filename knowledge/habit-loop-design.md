# Habit Loop Design — PharmaGuide

A behavioral-design plan for making PharmaGuide part of users' routines **without gamification** (no streaks, points, badges, or leaderboards). Grounded in the features already shipped; no speculative dependencies.

---

## 1. Psychology of the Supplement User

Understanding who we're designing for is everything. Supplement users are a distinct behavioral profile:

- **Aspirational-buyer curve.** Motivation peaks at purchase (doctor visit, health scare, New Year, a trend) and drops fast. Within ~30 days most users are on autopilot or have quit. The habit-formation window is short.
- **Existing-ritual advantage.** Most supplement users already have a daily anchor — morning coffee, pill organizer, breakfast. We don't need a new habit; we need to **attach to an existing one** (BJ Fogg, *Tiny Habits*). Cheapest behavioral win available.
- **The "problem solved" trap.** Scan-and-verdict apps die because the user's question ("is this safe?") is answered on the first scan. No open question = no return visit. PharmaGuide will die the same way unless it manufactures a *new* valuable question for each day.
- **The real daily question.** Users don't want gamified health. They want **reassurance and course-correction**. The renewable question is: *"Given what I'm taking and what's changed about me, should I still be taking it?"* That question is perpetually answerable — profile evolves, meds change, interaction data updates.
- **Anxiety-reassurance cycle.** The emotional core of medical-adjacent apps isn't achievement — it's **reduction of uncertainty**. Users return when an app resolves a small anxiety. If every visit ends in "you're good" or "here's one thing worth knowing," we've earned tomorrow's visit.
- **Trust is the moat.** In medical-adjacent software, trust compounds slower than engagement but lasts longer. Anything that feels manipulative (streak shaming, fake urgency, vanity metrics) burns trust permanently.

## 2. The Core Insight for PharmaGuide

PharmaGuide is already close to habit-viable. It just isn't *positioned* as a daily tool. Scan-first framing makes it episodic.

**Reframe it as a Morning Stack Check:** *"30 seconds before your supplements to know what's changed."*

The Stack + FitScore + interaction engine + evolving profile are already personalized, always-fresh, always-relevant content. That's the raw material for a daily loop — we don't need streaks.

## 3. The Habit Loop (No Gamification)

Classic **Cue → Routine → Reward → Investment**, tuned for medical trust:

- **Cue (morning).** One opt-in push notification aligned with the user's supplement time. Not "don't lose your streak!" — instead: *"Morning stack check ready."* The user picks the time during onboarding (a sixth step in profile setup: "When do you usually take your supplements?").
- **Routine (~20 seconds).** A single screen — *Today's Stack Check*. Shows: (1) the stack, (2) **one** surfaced insight (new interaction, nutrient ceiling breached, profile-drift prompt, refill-soon), (3) one-tap *Looks good* or *Adjust stack*.
- **Reward.** Informational, not dopaminergic. *"You're good — no new concerns"* or *"One thing to check."* Peak-end rule: the last screen gives a concrete takeaway, never a score or animation.
- **Investment.** Each check refines the system. Thumbs on insights. Periodic profile confirmation. Each input makes tomorrow's check more tailored — the user builds their own system, which is the retention engine.

## 4. Concrete Features (All Use Existing Data)

### 4.1 Morning Stack Check (core new feature)
- New screen, entry from home CTA and optional push.
- Pulls current stack + FitScore + interaction engine output.
- **At most one insight per day.** If nothing material changed: *"No new concerns — everything still checks out."* That honesty *is* the feature.
- Insight types, priority-ordered:
  1. New contraindicated/avoid-severity interaction
  2. Nutrient UL breach (you already compute M1 totals)
  3. Refill <7 days remaining (you already compute refill estimate)
  4. Profile-drift prompt (>3 weeks since any profile confirmation)
  5. Ingredient flag update from pipeline (`pharmaguide_core.db` OTA)
  6. Nothing — show "you're good"

### 4.2 "Since last visit" rail on home
- Replace/upgrade the *Recent Scans* rail with *Since last visit*: new interaction data on your items, pipeline updates, profile drift. A 3-days-absent user sees 3 days of change — the app worked for them while they were away.
- Data already available: scan events have timestamps; add `last_seen_at` on stack items and snapshot the pipeline version per check.

### 4.3 Profile drift prompts
- Every 2–4 weeks, a 10-second prompt: *"Still taking metformin? Any new meds?"* Single-tap yes/no per listed condition/med. Not re-onboarding — a confirmation.
- Why it matters: FitScore accuracy silently decays as profile ages. This surfaces that invisible value and respects the "NEVER display safe when coverage < 0.3" rule from `CLAUDE.md`.

### 4.4 Dose-timing-aware refill nudges
- Refill estimate already exists on product detail. Promote it: when <7 days remain on any stack item, surface on the Morning Check. Real-world utility = real-world reason to open the app.

### 4.5 Morning-context Quick Check entry
- *Quick Check* already exists. Expose it prominently on the Morning Check screen: *"About to try something new? Check it against your stack."* Catches the high-intent "I just bought this" moment.

### 4.6 Remove the Profile Completeness % gauge
- It's soft gamification and conflicts with the stated intent. Replace with a **contextual trust prompt**: *"FitScore accuracy is limited — add your medications to improve."* Same behavioral outcome (profile completion) without a progress bar.

## 5. What NOT to Do

- **No streaks.** Infantilizing in a medical context; creates anxiety that undermines trust.
- **No points, badges, levels.** Same reason.
- **No feed, no social.** Wrong genre — supplement decisions are private.
- **No daily goal counter.** Health is not a Duolingo lesson.
- **Don't nag.** Skip 3 days = say nothing. Skip 7 days *and* a material interaction change has landed = send one notification. **Silence is a feature.**
- **No dark-pattern permissions.** Push is opt-in, framed as utility, with a clear "only when there's something worth telling you" promise.

## 6. Measurement

- **D7 / D30 retention** — primary.
- **Sessions-per-week** — target 3–5 (every-other-day is realistic; daily is aspirational).
- **Insight-surface ratio** — % of Morning Checks that show a real insight vs. "you're good." Both valid; ratio tells us whether the data model is rich enough.
- **Trust pulse** — periodic one-tap: *"Does this app help you feel confident about what you take?"* Not NPS.
- **Anti-metric: do not optimize DAU by nagging.** If retention rises and trust-pulse falls, roll back.

## 7. Sequencing (Smallest Viable Build)

**Phase 1 — ship first.** Morning Stack Check screen + opt-in morning notification + "Since last visit" rail. 100% existing data; no new pipeline dependencies.

**Phase 2.** Profile-drift prompts + refill nudges inside the Morning Check. Remove the Profile Completeness %.

**Phase 3 — content investment.** Curate the *kinds* of insights the app can surface — short, evidence-linked notes tied to specific stack items (new research, monograph updates from the pipeline). This is where the app stops being a scanner and becomes indispensable.

---

## Summary

The strategy isn't to make PharmaGuide *engaging*. It's to make it **the 30-second companion to an existing daily act** — taking your supplements — that resolves a small, renewable uncertainty. Habit comes from utility + ritual attachment + genuine novelty, not from points. Every design choice should either (a) reduce the user's uncertainty about what they're putting in their body, or (b) stay out of the way.
