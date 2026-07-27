# B1 medication–nutrient change control

Status: enforced for controlled beta.

The B1 clinical-content audit reviewed 33 formerly consumer-visible records.
The release contains 31 active records: 18 approved without changes and 13
approved after wording or medication-scope changes. One record is suppressed
pending a defensible combined-oral-contraceptive scope, and one
pregnancy-specific antiseizure/vitamin-K record is removed from release.

The canonical machine-readable sign-off is
`scripts/data/medication_depletions_b1_signoff.json` in the pipeline
repository. It fingerprints every consumer-visible clinical record and the
membership of every drug class referenced by an active record.

## Required review rules

- No active record changes without evidence review and a new clinical
  fingerprint.
- No drug-class expansion without positive and negative runtime scenario
  coverage.
- No citation replacement until the source identifier and source content are
  verified against the live authoritative service.
- No medication artifact update without pipeline-to-app semantic parity and
  matching content-hash pins.
- No suppressed or rejected record may become consumer-visible without a
  recorded clinical disposition.
- A structured-value change requires corresponding consumer-copy review; old
  contradictory wording must be removed.

CI must fail when an active clinical fingerprint, active class membership,
active record set, or artifact parity pin changes without an updated ledger.

## Change packet

Every proposed B1 clinical change must include:

1. affected record IDs and user-visible behavior;
2. exact medication/RxCUI or class membership;
3. content-verified sources supporting scope, mechanism, impact, and advice;
4. reviewer disposition and rationale;
5. positive and negative runtime scenarios;
6. regenerated artifact and parity evidence;
7. affected pipeline and Flutter test results.

The feedback payload remains PHI-free. It may contain structured issue
category, impact, app release, environment, catalog version, and nonclinical
product/catalog identifiers. It must not contain medication names, doses,
conditions, profile data, or free-text health information unless a separately
approved secure clinical-feedback workflow is introduced.

## Release authority

Dr. Pham of the PharmaGuide Clinical Team provided licensed-pharmacist approval
of the bounded B1 corpus for controlled beta on 2026-07-27. The preceding AI
clinical-content audit remains supporting provenance; it is not the release
authority.
