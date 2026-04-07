# Lessons Learned

> Running log of mistakes, surprises, and hard-won knowledge.  
> **Rule:** Every non-trivial bug fix or unexpected behavior gets an entry here.  
> **Format:** Table rows, newest at top.

---

| Date | Category | Lesson | Root Cause | Prevention |
|------|----------|--------|------------|------------|
| 2026-04-07 | data | 9 of 14 conditions in clinical_risk_taxonomy had zero interaction rules. Never claim a feature works without verifying data coverage. | Assumed all taxonomy entries had corresponding interaction data written. Only 5 conditions (diabetes, hypertension, kidney disease, liver disease, pregnancy) had rules. | Before building UI for a data-driven feature, query the actual data and count non-null entries. Add a coverage gate test that fails if coverage drops below expected threshold. |
| 2026-04-07 | arch | Drug class checklist must stay in profile setup for V1.0. The E2c scoring section in ScoreFitCalculator needs drug classes to compute interaction penalties. Cannot derive from stack until V1.1 when stack-to-drug-class mapping is built. | Suggestion to remove manual drug class entry to simplify profile UX. But no automated alternative existed yet. | Tag profile fields with their consumers. Before removing any profile field, grep for all references and verify each consumer has an alternative data source. |
| 2026-04-07 | data | Never batch-fix JSON data files. Fix one entry at a time, verify each change, run targeted tests after each edit. Batch operations skip entries and introduce silent errors. | Batch update script processed entries sequentially, hit an error on entry 47, continued without reporting, leaving entries 48-143 in an inconsistent state. | Use single-entry update functions. Run the targeted test for that entry immediately after writing. Never use loops that continue-on-error for medical data. |
| 2026-04-07 | data | Always verify API enrichment results case-by-case before writing to data files. Bulk application of API results causes plant/compound collapses and preparation mismatches. | UMLS CUI verification returned the parent compound CUI instead of the specific preparation CUI. Bulk write applied the wrong CUI to 12 entries before anyone noticed. | API enrichment results go into a staging file first. Each entry is reviewed (by human or verification script) before promoting to the canonical data file. |

---

## Category Legend

| Code | Meaning | Examples |
|------|---------|----------|
| data | Data files, pipeline, JSON schemas | Wrong CUI, missing entries, schema mismatch |
| ui | Flutter UI, widgets, layout | Overflow, wrong color, missing state |
| arch | Architecture, design decisions | Wrong abstraction, premature optimization |
| perf | Performance, memory, latency | Slow queries, memory leaks, jank |
| testing | Test infrastructure, coverage gaps | Flaky tests, missing edge cases |
| security | Auth, permissions, data privacy | PHI leak, missing RLS, hardcoded keys |
| sync | Data sync, offline queue, OTA | Conflict resolution, lost updates |
