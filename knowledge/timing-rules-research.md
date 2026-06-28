# Timing Optimizations — Evidence Research (2026-06-27)

Citable knowledge base for the Stack → "Timing optimizations" feature
(`timing_rules.json` + `TimingEvaluationService`). Every claim carries a
confidence label and ≥1 citation (PMID / DOI / NIH ODS / FDA label). Use this
when auditing or editing timing rules — fix one rule at a time, verify against
the cited source, test.

**Two framing rules that govern everything:**
1. **Drug-efficacy interactions outrank supplement↔supplement optimizations.**
   A mineral that blunts levothyroxine / an antibiotic / a bisphosphonate is a
   *hard* rule at *any* dose. Two supplements competing for absorption is
   usually a *soft*, dose-gated nudge.
2. **"Take X with X" is always a logic bug.** Canonicalize + resolve aliases
   (ascorbic acid = vitamin C, cholecalciferol = D3, MK-7 = K2) before emitting
   any co-admin tip. Reject `a == b`.

---

## Corrections owed to the CURRENT `timing_rules.json`

| Rule id | Issue | Action | Evidence |
|---|---|---|---|
| `timing_calcium_magnesium_separate` | **FOLKLORE.** Ca & Mg use different transporters; "they compete" is unsupported at supplement doses; NIH ODS does not recommend separation. | **Remove** (or downgrade to a dose-splitting note, not a separation). | Brannan 1976 **PMID 965905**; Fine 1991 **PMID 2040711**; NIH ODS Magnesium |
| `timing_zinc_copper_separate` | **Mis-framed as timing.** Separating by hours does nothing — it's a *chronic cumulative-dose* rule (sustained Zn ≥40 mg/d depletes copper). | Reframe as a dose-safety flag (Zn ≥40 mg/d), not a "space apart" tip. | PMID 18525032; IOM Zn UL 40 mg/d; NIH ODS Zinc |
| `timing_magnesium_evening` | Daily Mg-for-sleep is MODERATE-WEAK; **evening timing specifically is folklore** (no RCT shows evening > morning). | Downgrade / reframe: "take whenever you'll be consistent." | Schuster 2025 DOI 10.2147/NSS.S524348; Mah 2022 PMID 35184264 |
| `timing_vitamin_d_morning` | "Evening D suppresses melatonin / ruins sleep" is **folklore** (cites a hypothesis paper; D half-life ~2–3 wk, no acute mechanism). | Remove or mark explicitly weak. | NIH ODS Vitamin D (silent on timing) |
| `timing_b_vitamins_morning` | "B vitamins for morning energy / disrupt sleep" is **folklore/placebo** in non-deficient people. | Downgrade / mark weak. | Linus Pauling Institute B6 |
| `timing_iron_calcium_separate` & co. | Real but **dose-gated & context-gated** — mainly matters for iron-deficient/pregnant on therapeutic iron, with food; attenuates long-term. | Gate on dose + profile before firing. | Hallberg 1991 PMID 1899425; Minihane 1998 PMID 9701177 |

Self-pairing + duplicate-tip bugs already fixed in `TimingEvaluationService`
(same-product suppression + semantic dedup, 2026-06-27).

---

## 1. SEPARATION pairs (take APART)

- **Ca ↔ non-heme Fe — MODERATE, soft, 2 h.** ~50–60% acute ↓ at 300–600 mg Ca
  *with food*; minimal fasting; attenuates long-term (ferritin unchanged at 6 mo).
  Hallberg 1991 **PMID 1899425**; Cook 1991 **PMID 1850574**; Minihane 1998 **PMID 9701177**.
- **Ca ↔ Mg — FOLKLORE, no separation.** Different transporters. Brannan 1976
  **PMID 965905**; Fine 1991 **PMID 2040711**.
- **Ca ↔ Zn — WEAK→MODERATE.** Driven by *phytate*, not calcium; ODS doesn't
  recommend separating. Lönnerdal 2000 **PMID 10801948**.
- **Zn ↔ Cu — STRONG but CHRONIC DOSE, not timing.** Sustained Zn ≥40 mg/d →
  copper depletion/myelopathy. PMID 18525032; IOM UL 40 mg/d.
- **Zn ↔ Fe — MODERATE, 2 h, only ≥25 mg Fe fasting.** Food abolishes it.
  O'Brien 2000 **PMID 10801955**.
- **Fe ↔ tea/coffee/polyphenols — STRONG, 1 h.** Coffee −39%, tea −64%; no
  inhibition if coffee 1 h before. Morck 1983 **PMID 6402915**; Ahmad Fuzi 2017 **PMID 28615254**.
- **Ca/Fe/Mg ↔ levothyroxine — STRONG, 🔴 HARD, 4 h.** Synthroid label: not
  within 4 h. Zamfirescu 2011 **PMID 21595516**; Skelin 2017 **PMID 28153426**.
  Mg lower tier (MODERATE): ThyroMag 2025 **PMID 41221788**.
- **Ca/Fe/Mg/Zn ↔ tetracyclines & fluoroquinolones — STRONG, 🔴 HARD, per-drug:**
  cipro 2 h before / 6 h after; levo 2 h / 2 h; **moxi 4 h / 8 h (asymmetric)**;
  tetracyclines: label gives no explicit window ("2 h before/4–6 h after" is
  Sanford convention). Store windows **per drug**. FDA labels.
- **Mg/Al antacids ↔ bisphosphonates — STRONG, 🔴 HARD.** Empty stomach, ≥30 min
  before anything (ibandronate 60 min); bioavailability <1%. Alendronate FDA label.

## 2. SYNERGY pairs (take TOGETHER) — mostly adequacy, not co-timing

- **Non-heme Fe + Vitamin C — STRONG per-meal / WEAK long-term.** 2–6× per-meal
  absorption; does NOT reliably raise stores. Hallberg 1986 **PMID 3700141**;
  Cook & Reddy 2001 DOI 10.1093/ajcn/73.1.93. Non-heme only.
- **Vitamin D + K2 — THEORETICAL.** Co-*adequacy*, not co-*timing*. Do NOT
  generate "take D with K2 for absorption." Marketing-flavored.
- **Calcium + Vitamin D — STRONG but STATUS, not same-pill timing.** "Being
  D-replete helps absorb calcium," not "take both pills together."
- **Fat-soluble A/D/E/K + dietary fat — STRONG (D,E)/MOD (K).** Pair with *fat*,
  never another vitamin. D with largest meal +57% 25(OH)D. Mulligan 2010 DOI 10.1002/jbmr.67.

## 3. MEAL timing

- Fat-soluble A/D/E/K → with food + fat (STRONG).
- Iron → empty stomach for absorption; with food if GI upset (tradeoff, MOD/STRONG).
- Magnesium → with food (reduces osmotic diarrhea, STRONG).
- Levothyroxine (drug) → empty stomach, 60 min before breakfast or bedtime ≥3 h
  after dinner (STRONG). Jonklaas 2014 **PMID 25266247**.
- Probiotics → with/≤30 min before a meal (WEAK, in-vitro only). Tompkins 2011 **PMID 22146689**.

## 4. TIME-OF-DAY

- **Melatonin — evening: EVIDENCE-BASED.** 0.5–3 mg, 30–60 min before bed.
  Brzezinski 2005 DOI 10.1016/j.smrv.2004.06.004.
- **Iron — alternate-day single morning > consecutive (EVIDENCE-BASED; lever is
  frequency, not hour).** 21.8% vs 16.3% absorption. Stoffel 2017 DOI 10.1016/S2352-3026(17)30182-5.
- **Magnesium evening / Vitamin D morning / B-vitamins morning — FOLKLORE.**

## 5. DOSE-SPLITTING

- Calcium ≤500 mg elemental/dose (saturable; Heaney/Weaver 1996 DOI 10.1093/jn/126.1.303; ODS).
- Vitamin C: <50% absorbed >1 g/d → split (ODS).
- **Iron: BID same-day split is WORSE** (hepcidin) — prefer single morning /
  alternate-day. Stoffel 2017/2020.
- Magnesium: supplemental UL 350 mg/d; split larger for GI tolerance.

## 6. PRIORITIZATION TIERS (rank tips descending)

1. **Drug efficacy at risk (HARD, any dose):** levothyroxine, fluoroquinolones/
   tetracyclines, bisphosphonates, HIV integrase inhibitors, gabapentin.
2. **Cumulative-dose safety (HARD, not timing):** Zn→Cu ≥40 mg/d; Mg >350 mg/d.
3. **Meaningful absorption for at-risk users (SOFT, conditional):** Fe↔Ca/tea/Zn;
   Fe+C synergy. Gate on iron deficiency / pregnancy / dose / fasting.
4. **Optimization niceties (INFO):** Ca ≤500 mg split; C split; fat-soluble with
   fat; alternate-day iron; Mg with food.
5. **Folklore/placebo (SUPPRESS or label weak):** Ca↔Mg; evening-Mg; D-at-night;
   B-for-energy; D+K2 co-timing.

**Anti-overwhelm:** cap visible 3–5, highest tier first; one tip per pair
(dedup both directions); context-gate Tier 3–4 before generating; calm-advisory
voice; always show evidence strength + drug directionality.

## 7. Engine pitfalls

Self-pairing (X with X) · contradictory tips (separate AND combine same pair) ·
both-direction double-counting · trivial-as-important · ignoring dose thresholds
· status/adequacy treated as timing · one-size drug windows · missing exceptions
(dolutegravir+Ca/Fe OK *with food*; raltegravir+antacid is avoid-not-separate) ·
inhibitory-pair confused with synergy.
