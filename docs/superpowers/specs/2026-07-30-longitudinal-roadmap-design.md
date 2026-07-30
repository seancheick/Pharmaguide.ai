# Longitudinal Health Organization — Three-Phase Roadmap

**Date:** 2026-07-30
**Status:** Implemented (code) — 2026-07-30. Phase 1 and Phase 2 ship end to
end; Phase 3's resolver is complete and tested but has no UI surface yet.
Phase 1 is inert until a clinical reviewer authors `watch_threshold_days`,
which remains a clinician-owned change and is deliberately NOT part of the
code implementation.

**Divergences from this spec, decided during implementation:**
- `DepletionChecker.check()` was NOT refactored to thread stack-entry ids.
  It flattens identities into shared lookup sets, so threading ids would mean
  operating on the identity matcher. The watch instead replays the same pure
  `check()` once per medication, keeping the checker the sole matching
  authority and the identity guard untouched.
- "Promote `monitoring_tip_short`" means raising emphasis on a line the card
  already renders unconditionally (`pg_depletion_card.dart`), not adding one.
- Rows predating the v10 event log fall back to the stack row's own
  `added_at`; without it every long-tenured user would be invisible to the
  watch.
**Scope:** Enhance three existing subsystems (depletion, timing, visit) into a
longitudinal loop. No new subsystems.

---

## Premise

PharmaGuide already has all three engines. Verified in code on 2026-07-30:

| Capability | Exists | Where | Gap |
|---|---|---|---|
| Depletion | Yes | `depletion_checker.dart`, `pg_depletion_card.dart`, 80 curated entries | Point-in-time only; no time dimension |
| Timing | Yes | `timing_evaluation_service.dart` (610 lines, inverted index), 32 rules | Pairwise advice; never resolved into a daily plan |
| Visit | Yes | `user_health_event_service.dart`, `clinician_pdf_builder.dart` | Two halves exist but are not connected |

This roadmap connects what is already built. It is deliberately not a
feature-expansion plan — the research finding that drove it is that
notification fatigue is the top complaint against the category leader, and
that plain reminders are the *weakest* adherence lever (interactive
strategies SMD=1.367 vs. plain push far behind). More surface would hurt.

### The governing constraint

`CLAUDE.md`: **one brain — the pipeline decides, the app renders.**

This is the single hardest constraint on Phase 1 and it shapes the whole
design. The app may render *elapsed time* (a device fact) against a
*threshold the pipeline authored* (a clinical fact). The app must never
derive its own clinical timing. "You have been on this medication 14 months"
is rendering. "You should have your B12 tested now" is a clinical judgment
and must originate in curated data.

---

## Phase 1 — Depletion watch

**Goal:** make depletion risk time-aware, so the same entry reads differently
at month 1 and month 14.

### Why first

- Both inputs already exist: `user_stacks_local.added_at` and the curated
  `onset_timeline`. They are simply never connected today.
- It is the only one of the three that is *inherently* longitudinal — it
  changes on its own as time passes, which is what produces a reason to
  return that a scanner cannot.
- Evidence base is strong: metformin→B12 has 87% prescriber awareness but
  only 39% annual testing.

### The blocking data problem

`onset_timeline` is a coarse bucket (`days` | `weeks` | `months` | `years`).
It is currently consumed for *copy framing only* — the checker uses it to
ensure "chronic risk is understood as chronic."

A bucket cannot drive a watch. "Years" cannot answer *is this user due yet?*

**Therefore Phase 1 requires a pipeline-side data addition before any Flutter
work.** Proposed curated field, authored per entry alongside the existing
clinically-reviewed copy:

```json
"watch_threshold_days": 730,
"watch_basis": "Lam 2017: risk elevation observed at >=2 years of use"
```

`watch_basis` is mandatory and must cite the same source set already on the
entry. An entry without `watch_threshold_days` is simply not watched — the
feature degrades to today's behavior rather than inventing a threshold.

This keeps the clinical judgment in curated data where a reviewer signs it,
and leaves the app doing arithmetic on dates.

### Behavior

For each active medication with a depletion entry that has a threshold:

- **Below threshold:** unchanged from today. No new surface.
- **At/over threshold:** the existing `pg_depletion_card` gains a duration
  line and the entry's existing `monitoring_tip_short` is promoted.
- **Never:** a notification. Depletion crossing a threshold is not urgent
  news; it belongs in the app and in the visit report, not on a lock screen.

### Reuse, not re-derivation

- Publication gating: `medNutrientPublicationPolicy` is the SSOT and already
  fails closed. The watch consumes its result; it must not re-read
  `citation_review_status` itself.
- Severity ordering: existing `Severity` helpers.
- Duration source: `added_at`. Note it records when the item entered *this
  device's* stack, not when the prescription began — copy must say "tracked
  here for 14 months", never "you have taken this for 14 months".

### Edge cases

- Item removed and re-added: the append-only health event log holds
  `stack_item_removed` / `stack_item_restored`. Duration is computed from the
  log, not from the current row, so a re-add does not reset the clock
  incorrectly.
- Clock skew / backdated device time: clamp negative durations to zero.
- Threshold crossed while the app was closed: crossing is evaluated at read
  time, not by a scheduler. No background job.

---

## Phase 2 — Close the visit loop

**Goal:** connect the appointment lifecycle to the clinician report. Both
halves exist and never meet.

### Today

`ShareClinicianReportButton` lives on the stack screen
(`stack_v2_screen.dart:228`). Appointments live in health history with a full
lifecycle (`appointmentScheduled` / `Rescheduled` / `Completed` / `Cancelled`).
Nothing links them.

### Behavior

1. **Before:** when a `doctorVisit` event is upcoming, the health history
   surface offers the existing report. No new report code — it is the same
   `clinician_report_document_provider` path.
2. **After:** on `appointmentCompleted`, offer a single optional capture:
   what changed. Writes an ordinary user-authored event via the existing
   `UserHealthEventService`. Skippable, never blocking, never a required form.

### Why this ordering

The research showing ~70% of supplement users never disclose to a clinician,
and that disclosure is only 33.9% complete when it does happen, is the
strongest evidence in the set. But the report is only worth carrying if there
is something new to say — which is what Phase 1 produces. Building Phase 2
first would ship a loop with an empty payload.

### Non-goals

- No clinician-side accounts, portals, or transmission. The report remains a
  user-initiated share of a locally-built document.
- No PHI leaves the device except through the existing, audited share path.

---

## Phase 3 — Sequencing engine

**Goal:** upgrade the timing engine from pairwise advice to a resolved daily
plan.

### Today

`TimingEvaluationService.evaluateStack()` returns `TimingOptimization`
objects — individual pairwise findings ("separate iron and calcium"). Correct
and well-built, but with several supplements the user receives a set of
overlapping constraints and must solve the schedule themselves.

The service documentation intentionally avoids hard-coding a rule count; the
bundled rule artifact and its release gates remain the source of truth.

### Behavior

Add a resolver layer *above* the existing engine — the engine is not
modified. It takes the emitted constraint set and assigns items to a small
fixed set of slots (morning / with food / evening / bedtime), reporting any
constraint it could not satisfy rather than silently dropping it.

### Why last

Highest build cost, and its value compounds with the other two: a daily plan
is more useful once the plan reflects duration-aware depletion (Phase 1) and
is worth showing a clinician (Phase 2). It is also the phase most likely to
need new curated data (slot eligibility per ingredient), so it benefits from
the Phase 1 precedent of adding a reviewed field to curated data.

### Hard constraint

The resolver must be a pure function over pipeline-emitted constraints. If it
cannot satisfy a constraint it must surface that, never invent a compromise.
An unsatisfiable set is a legitimate output.

---

## Sequencing rationale

```
Phase 1 (watch)  →  produces something new to say
       ↓
Phase 2 (visit)  →  delivers it to the person who can act
       ↓
Phase 3 (plan)   →  makes the daily routine actionable
```

Each phase ships independently and is useful alone. Phase 1 is the smallest
diff and the only one that requires curated-data work before Flutter work
starts.

---

## Testing

Per repo convention, each phase adds to the existing suites:

- Phase 1: duration arithmetic incl. remove/re-add from the event log, clamp
  on skew, entries without a threshold are not watched, publication policy is
  consumed rather than re-derived.
- Phase 2: report offer appears only for upcoming `doctorVisit`; capture is
  skippable; no medication row reaches a sync path.
- Phase 3: resolver output satisfies every emitted constraint or reports the
  conflict; determinism under reordered input.

Release-gate tests belong in `test/release_gate/` alongside the existing
bundled-DB and notification-permission gates.

---

## Open questions for the owner

1. **Who authors `watch_threshold_days`?** It is a clinical judgment and
   needs the same reviewer path as the rest of `medication_depletions.json`.
   Phase 1 is blocked on this, not on Flutter work.
2. **Which entries get a threshold first?** Recommend the highest-evidence
   chronic ones (metformin→B12, PPI→iron at the documented 2-year mark)
   rather than all 80 at once, per the one-entry-at-a-time rule.
3. **Slot vocabulary for Phase 3** — fixed four slots, or per-user wake/sleep
   anchoring? Fixed is simpler and matches the "anchor to existing routine"
   habit-formation evidence.
