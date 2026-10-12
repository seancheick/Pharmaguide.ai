# AI-assistant sharing, Lane A: AI brief export — October 12, 2026

Plan: /Users/seancheick/.claude/plans/how-can-we-create-purring-beacon.md (revision 3, approved by Sean
2026-10-12). Lanes: A (this worktree, `worktree-ai-brief`), C (ADR-009 + AGENTS.md exception + threat
model, branch `worktree-agent-a44bc6f17531f5fed`, commit f154171), B1a public MCP + pipeline
`catalog_search`, B1b personal MCP + consent page (website branch `feat/ai-connector-consent`), F engine
portability spike (branch `worktree-agent-a3ac37572fd12204f`, commit c3c40f12; answer: dart2js of the
unchanged engine, byte-identical findings, ms-scale CPU). Integrator: this session lands lanes on main in
order A, C, F, B1a, B1b; nothing is pushed.

Goal (Lane A): a plain-text "AI brief" the user scopes, previews and pastes into any assistant. No backend.
Owner: `lib/services/sharing/clinician_report_document_provider.dart::clinicianReportDataProvider` collects
the one snapshot (`ClinicianReportData`); `ai_brief_builder.dart::AiBriefBuilder.build(data, AiShareScope)`
renders it; `report_text.dart` is the single owner of report wording shared with
`clinician_pdf_builder.dart` (migrated, 1486 → 1107 lines, PDF tests unchanged and green).
Evidence: `flutter test test/services/sharing test/release_gate/ai_brief_no_network_test.dart
test/features/stack/widgets` → 94 passed; `make check` log at the session scratchpad `lane-a-check.log`.
Will NOT create: a second scope type for the Phase 2 snapshot (reuse `AiShareScope`), any network call on
this path (release gate `ai_brief_no_network_test.dart`), supplement free-text doses presented as verified.

Scope rules enforced by the builder (tested): medications off ⇒ no medication name and no
medication-derived finding (drug interactions, depletions, medication timing, untyped issues); profile off
⇒ no profile fields, no condition interactions, no % of target; findings never declare "safe"; empty stack
⇒ "nothing to check against yet"; incomplete checks stated before findings; recall/banned stated as facts
when details are withheld.

UI: `stack_share_sheet.dart` third option → `ai_brief_preview_screen.dart` (presets Simple list / Detailed
report, switches, Copy, Share via `ShareService.shareAiBrief`).

Next: commit Lane A after `make check`; simulator screenshot of the preview (needs the uncommitted ML Kit
stub: drop `google_mlkit_text_recognition` from pubspec and stub `readLatinTextFromFile`; revert before
commit); then integrate lanes and append ADR-010 (PROPOSED) from the spike doc. Phase 2 copy to amend
later: `settings_v2_screen.dart:385` and `medication_entry_v2_screen.dart:844` (found by Lane C).
