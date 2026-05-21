# PharmaGuide — Product Strategy

## North Star

**Buying a supplement without PharmaGuide should feel reckless.**

This is the Carfax standard. Buying a used car without a Carfax isn't illegal — it's just considered careless. That norm wasn't built on engagement mechanics. It was built on vivid failure cases, information asymmetry, cultural reinforcement, and being frictionless at the decision moment. That is PharmaGuide's playbook.

The goal is not daily active use. The goal is **reflexive brand recall at the decision moment** — in the store aisle, on Amazon, in the exam room. Target frequency for most users is 1–2 times per week, driven by real supplement decisions.

## Why "habit loop" is the wrong frame

Earlier thinking leaned on daily-habit design (morning check-ins, engagement loops). That framing doesn't fit this product:

- Users' supplement stacks are stable for weeks or months.
- Most users buy supplements roughly monthly — that's the real decision cadence.
- Manufacturing fake daily urgency in a medical-adjacent app burns trust permanently.
- The value isn't engagement — it's **reduction of uncertainty at specific moments that matter**.

PharmaGuide is closer to Yuka + GoodRx + Carfax than to Duolingo. Those tools win on being top-of-mind at the decision moment, not on screen time.

## Two audiences, two decision moments

Every design choice should serve one of these two moments. Anything that serves neither is noise.

### 1. Consumer pre-purchase
In a store aisle, on Amazon, after a TikTok recommendation, when a family member asks for advice. Must be faster and clearer than reading the label. Must make visible what the label doesn't disclose.

### 2. Clinician at prescribing
A doctor reviewing the patient's stack before writing a prescription. A pharmacist dispensing a new medication and checking against known supplements. Must hold up as a clinical artifact, not a consumer summary.

Each audience reinforces the other. Clinician endorsement drives consumer adoption; consumer adoption makes clinician adoption inevitable.

## What the standard demands (four pillars)

If any pillar is weak, the "reckless to skip" norm does not hold.

### 1. Information asymmetry — show what they couldn't otherwise know
- Proprietary-blend dose breakdowns (or explicit "this brand hides dosing").
- Third-party testing status — tested, not tested, or tested and failed.
- Heavy-metal / contamination data when available.
- Manufacturer recall history and quality tier.
- Interactions specific to *this user's* meds, conditions, and existing stack.
- Honest gap disclosure: when `mapped_coverage < 0.3`, say so loudly. Honesty is a trust-builder, not a weakness.

Every scan result must include an expandable "what we checked" section. Not marketing — the receipt. The receipt is what makes users feel reckless buying without it.

### 2. Vivid failure cases — the stories that create the norm
The norm is built on memorable examples. Carfax has flood-damaged cars. PharmaGuide needs equivalents:

- Documented supplement–drug interactions with real consequences.
- Specific brands whose contents didn't match the label.
- Ingredients banned in the EU still sold in the US.
- Depletion interactions between supplements and common medications.

**The "receipt of avoidance":** when the app catches a real problem for a specific user, tell them exactly what they avoided and the severity. *"You just avoided a contraindicated interaction with your warfarin — severity: hospitalization risk."* That screen is the most shareable moment the app will ever produce.

### 3. Cultural reinforcement — mouths other than ours
"Reckless to skip" cannot be self-declared. Other authorities must imply it.

- **Pharmacists are the beachhead.** Supplement-illiteracy in pharmacy is a real gap; pharmacists handle interaction questions daily. If 500 independent pharmacists use it, doctors hear about it from pharmacists.
- **"Share with my doctor"** (PDF/link export) turns every user into a seed in a clinic.
- **Public methodology page** + named, credentialed advisory board. No anonymous "experts."
- **PR moments** when PharmaGuide catches real issues before the FDA announcement. Those headlines build the norm.

### 4. Frictionless at the decision moment — beat "just buy it"
The cost of checking must always be lower than the cost of not checking.

- Barcode scan is solved in-store. Online shopping is not — and most supplement sales are online.
- **iOS/Android share sheet integration** — tap share on any product page, PharmaGuide is an option. Highest-leverage technical bet for online shopping moments.
- Amazon / retailer URL paste → instant verdict.
- Home-screen widget for one-tap scan.
- Clipboard detection when a supplement URL is copied.
- Browser extension (later) that lights up on supplement product pages.

## Where to pour craft

Almost all craft energy concentrates on two surfaces. Everything else is supporting infrastructure.

### Primary: the scan/verdict screen
The Yuka moment, but denser.

- Definitive verdict in the top 20% — severity color + plain-language sentence tied to *this user's* profile.
- Three reasons underneath, evidence-linked, with `evidence_level` visible.
- Interaction callouts naming both substances, mechanism, action (stop / reduce / monitor / OK), and source.
- Honest "we don't know" UI when `mapped_coverage < 0.3`.
- Sub-second verdict from trigger. Feels instant.
- Medical-clean typography. Not consumer-playful.
- Screenshot-worthy: a user should want to send it to a friend or a doctor.

### Primary: the product detail page
The reference artifact.

- Holds up to a doctor's scrutiny and is readable by a layperson on the same surface.
- Evidence citations, sourcing, monograph-style depth available on tap.
- Canonical enough to outrank brand marketing pages on Google — an underrated lever for pre-purchase capture.

### Supporting: the stack as a clinical artifact
The Stack page should be viewable by a doctor without translation. Dense, sortable, exportable.

### Supporting: "Share with my doctor"
One-tap export of stack + profile as a PDF or short link a clinician can open without an account. Low build cost, massive distribution payoff. The single feature most likely to put PharmaGuide in exam rooms.

### Phase 2: clinician-mode view
Optional toggle that swaps consumer phrasing for clinical density — monograph-style, citation-first, mechanisms spelled out. Same data, different surfacing. Seed with pharmacists and functional-medicine practitioners first.

## What PharmaGuide is deliberately NOT

Resisting these is a product discipline, not a concession.

- **No streaks, points, badges, levels, leaderboards.** Infantilizing in a medical context; undermines trust.
- **No daily Morning Check screen.** Fake engagement. Stacks don't change daily.
- **No daily push notifications.** No "since last visit" feed designed for daily use.
- **No feed, no social layer.** Supplement decisions are private.
- **No nagging.** Skip 3 days, say nothing. Silence is a feature.
- **No fake urgency, no dark patterns on permissions.**
- **Remove the Profile Completeness % gauge.** It's soft gamification. Replace with a contextual prompt: *"FitScore accuracy is limited — add your medications to improve."* Same behavioral outcome, no progress bar.

## Notifications: rare, high-value, already built

Existing FDA recall, banned-ingredient, and safety alerts are the correct notification strategy. They fire when the user's *own stack* is materially affected. They are rare (perhaps 3–8 per user per year) and trusted. When they fire, the user is grateful. **Do not add more notification types beyond this category.**

## The real loop (event-driven, not daily)

Still Cue → Action → Reward → Investment — just anchored to external events, not time of day.

- **Cue:** external — a real-world supplement decision (buying, taking, recommending, being prescribed).
- **Action:** reach for PharmaGuide reflexively.
- **Reward:** a definitive, trustworthy answer personalized to this user's profile and stack.
- **Investment:** stack and profile deepen → next answer is sharper → reinforces the reflex.

Retention comes from the reflex, not from time-of-day engineering.

## Build order

### Phase 1 — make the decision moment unbeatable
- Redesign scan/verdict screen around the four-pillar standard (information asymmetry surfaced, evidence-level visible, user-specific interaction callouts, honest coverage disclosure).
- Redesign product detail page as a reference artifact.
- Add "what we checked" receipt section on every scan result.
- Build "Share with my doctor" PDF/link export.
- Remove Profile Completeness % gauge; replace with contextual FitScore-accuracy prompts.

### Phase 2 — win the online purchase moment
- iOS/Android share sheet integration.
- URL paste → instant verdict.
- Home-screen widget.
- Clipboard detection.

### Phase 3 — institutional credibility
- Public methodology page.
- Named advisory board surface.
- Clinician-mode toggle on product detail and stack.
- Pharmacist beachhead outreach (partnerships, training materials).

### Phase 4 — pre-purchase presence
- Browser extension on supplement product pages.
- SEO/canonical product detail pages with schema markup.
- Influencer/creator tooling to show a PharmaGuide verdict alongside their recommendation.

## Measurement

- **Scan-before-purchase rate** — of users who added a product to their stack, what % scanned or looked it up first? Target: >60%.
- **"Share with my doctor" uses per month** — leading indicator of clinician adoption.
- **Organic / word-of-mouth new-user share** — rises when the "receipt of avoidance" is doing its job.
- **Verdict trust pulse** — one-tap *"Did this help you decide?"* on scan result screens.
- **Coverage honesty rate** — % of scans that correctly disclosed low `mapped_coverage`. Transparency is a tracked metric, not just a principle.
- **Anti-metric: do not optimize DAU.** If DAU rises and trust-pulse falls, something is wrong.

## Summary

PharmaGuide's strategy is not to be engaging. It is to become **the reference tool for a category** — the standard that purchasing a supplement, or prescribing alongside one, without consulting PharmaGuide is considered careless. That standard is built on information asymmetry, vivid failure cases, cultural reinforcement, and friction-free access at the decision moment — not on daily habit loops.
