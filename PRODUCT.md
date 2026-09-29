# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

One Flutter app for iPhone and Android that follows each OS's conventions (Sean, 2026-09-29). On iOS 26+ the
tab bar is Apple's own Liquid Glass `UITabBar` (ADR-008); Android and iOS 18–25 get the frosted Material bar.
Glass belongs only on the functional layer (navigation, scanner controls, segmented controls, floating
toolbar actions), never on content, warnings or evidence.

## Users

Two primary jobs, weighted equally (Sean, 2026-09-29):

- **"Is this a good product?"** People comparing supplement quality, often at the shelf or before buying
  online.
- **"Is it right for me?"** People who take supplements alongside prescription medications or health
  conditions and want to know what is worth a conversation with their doctor or pharmacist.

Guests (no account) get 3 scans a day and keep a stack and wishlist on the device. An account adds backup
and sync of the supplement stack only.

## Product Purpose

Scan a barcode or search by name to see the product's PG Score (0–100 product quality) and, next to it,
checks against the person's own stack, medications, conditions and allergies, each with its evidence level
and sources. Success means the person knows what they take and what to raise with a clinician. PharmaGuide
never diagnoses and never issues a medical verdict.

## Positioning

- **Reads the whole stack, not one product at a time:** interactions, dose accumulation across products,
  timing conflicts, and the nutrient depletions common prescriptions cause.
- **Verified data, not marketing claims:** products come from NIH DSLD labels, scored by the PharmaGuide
  pipeline. The app renders the pipeline's verdicts and never recomputes or overrides them.
- **Clinician-reviewed:** interaction rules and catalog content are reviewed by a clinical pharmacist and a
  nurse practitioner (see Evidence on Hand).
- **Private by default:** the health profile lives and is evaluated on the phone.

## Operating Context

- In a store aisle, scanning a bottle one-handed; at home, reviewing the whole stack; before an appointment,
  sharing a clinician report PDF.
- "Check two together" (Quick Check) compares any two supplements or medications.
- **Works offline:** scan, search, scores, interaction checks and the stack.
- **Needs a connection:** full product details the first time they open, medication name search (RxNorm, U.S.
  National Library of Medicine), sign-in and sync, and catalog updates.

## Capabilities and Constraints

- **Stack:** Flutter (Riverpod, GoRouter, Drift). A read-only catalog DB, updated over the air; an
  interaction DB; and a read-write `user_data.db`. Detail blobs, auth and supplement-stack sync go through
  Supabase.
- **Medical-grade accuracy:** the pipeline decides and the app renders. Severity order is sacred:
  contraindicated > avoid > caution > monitor > safe. Every interaction warning shows its evidence level. An
  unavailable or incomplete check is never presented as a clean result.
- **Copy voice:** calm and advisory, e.g. "Worth a conversation with your doctor", "PharmaGuide does not
  recommend".
  - No "Stop", "Avoid", "Do not" or all-caps in app-authored text.
  - Clinician- and pipeline-authored text renders verbatim.
- **Words the app never uses about itself:**
  - "safe" as an affirmation (ADR-007);
  - "pharmacist" as the app's own role (a protected title under state pharmacy acts);
  - an unsubstantiated "first".
- **Colour semantics:** safety colours are reserved for clinical risk. Non-clinical emphasis uses the brand
  accent.
- **App Store rules:**
  - no placeholder features in primary navigation (2.1(a));
  - medical apps get extra scrutiny (1.4.1);
  - explicit consent before any personal data goes to a third-party AI (5.1.2(i)).
- **Undecided:** "Ask PharmaGuide" (AI chat) is previewed under Profile › Coming later, and its copy
  promises answers on the device. Two things are still open:
  - the model: Apple Foundation Models on-device, optionally Private Cloud Compute;
  - the Android path: Gemma on-device, or a cloud model with consent.

## Brand Commitments

- **Name:** PharmaGuide. **Tagline:** "Know what you take."
- **Voice:** calm, precise, never alarming, and always pointing to a clinician conversation rather than a
  verdict.
- **Assets:** app icon and splash assets live in `assets/`. Bundled type faces: Geist, Geist Mono and
  Newsreader (OFL).

## Evidence on Hand

- **Clinical review:** Laurie Pham, PharmD (clinical review) and Miriam Farez, NP (patient-education review),
  as named on the website (`PharmaGuide Website/src/lib/people.ts`).
- **Sources shown in the app:** NIH ODS, PubMed, FDA.
- **Catalog, interaction and research-pair counts:** query `assets/db/` at the time of writing, and never
  hard-code them. They change with every catalog release.
- **Approved trust claims** (Sean, 2026-09-29):
  - clinician-reviewed;
  - health data on the device;
  - "HIPAA-aligned", worded exactly that way and never "HIPAA-compliant" or "certified".
- **Encryption:** health data is protected by the phone's built-in encryption (iOS Data Protection, Android
  file-based encryption). The app's own database is plain SQLite. Do not claim that PharmaGuide itself
  encrypts with AES-256 until it adds database encryption.
- **Absent, never fabricate:** user counts, ratings, reviews, testimonials, press quotes and outcomes. The
  app is in beta and not yet on the App Store.

## Product Principles

1. **Unverified is never clean.** Show what was checked, what was not, and why.
2. **The pipeline decides, the app renders.** One source of truth for every score and verdict.
3. **Private by default.** Health data stays on the phone. Anything that leaves it is disclosed and
   consented to first.
4. **Calm, not alarming.** Every concern leads to a clinician conversation, not fear.
5. **Both jobs, one flow.** Product quality and personal fit sit side by side and are never merged into
   one number.

## Accessibility & Inclusion

- Text follows the system size, clamped to 0.9–1.4×. Raising the cap to 2× is pending fixes to about five
  layouts (docs/PRODUCT_UX_AUDIT_2026-09-28.md §12.2).
- Reduce Motion, Increase Contrast and Reduce Transparency are honoured. Flutter has no Reduce Transparency
  flag, so it comes through the iOS bridge.
- Touch targets are at least 44 pt, and every control has a VoiceOver/TalkBack label and state.
