# B1 controlled beta monitoring

Status: active for controlled beta.

PharmaGuide's structured beta-feedback sheet now emits one consent-gated,
PHI-free Sentry feedback event for each report. The payload contains only the
selected category, impact, app release/environment, and catalog version. It
does not include medication names, stack contents, conditions, doses, profile
data, or free text.

## Clinical categories

| What to track | `feedback.category` |
|---|---|
| False positives | `clinical_false_positive` |
| Suspected false negatives | `clinical_false_negative` |
| Medications that fail normalization | `clinical_identity_normalization_failure` |
| User confusion about wording | `clinical_wording_confusion` |
| Clinician report interpretation | `clinician_report_interpretation` |
| Searches producing no result | `search_no_result` |
| A drug that should map to a class but does not | `clinical_class_mapping_missing` |

Impact is recorded separately as `blocks_me`, `frustrating`, or `minor`.
Catalog version is attached as `pg.catalog_version`, allowing a report to be
correlated with the exact clinical artifact without collecting health data.

## Triage cadence

- Review beta feedback daily during the first controlled cohort, then weekly
  once the category counts are stable.
- Group by category, app release, catalog version, and impact.
- Treat a `blocks_me` clinical false positive, false negative, normalization
  failure, or class-mapping miss as same-day triage.
- Ask for identifying detail only through the support-email route chosen by
  the user. Never add a free-text field to Sentry.
- Reproduce against the exact catalog version and the packaged interaction
  database before changing clinical data.
- Verify any RxCUI/CUI and citation through the live authoritative API before
  promotion.

## Disposition

For every confirmed issue, record one outcome:

- false positive — suppress or narrow the record/class;
- false negative — repair normalization, direct identity, or class membership;
- wording — revise consumer copy without changing the clinical claim;
- report interpretation — revise report status/limitations;
- no result — distinguish a legitimate no-match from a normalization failure;
- class-mapping miss — repair the packaged taxonomy and add positive/negative
  bridge tests;
- not reproducible — retain the event with catalog/app version for trend review.

No issue is closed on a synthetic test alone. Re-run the representative
scenario release gate and the affected full Flutter suite before shipping.
