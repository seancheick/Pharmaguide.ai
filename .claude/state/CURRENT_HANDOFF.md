# Current handoff — Dose V4.1 app batch (D4) on claude/dose-v41, October 17

valid_for_head: dcf3768b
written_at: 2026-10-17

Goal: app half of the pipeline plan docs/plans/DOSE_V41_PLAN.md §4.1 (Sean D4: app and pipeline
both done before Sean's run). Pipeline branch: dsld_clean claude/dose-v41 (handoff in its worktree
.claude/state/CURRENT_HANDOFF.md; review packet docs/plans/DOSE_V41_REVIEW_PACKET.md).

Owner: lib/services/stack/stack_ul_checker.dart (one exposure against one reference; adult-only
fallbacks flagged not personal); stack_nutrient_aggregator.dart::PipelineUlVerdict (pct/ul pair,
`> 100`); nutrient_accumulation_panel.dart::_LimitsNotPersonalNotice; nutrient_progress_bar.dart
("% UL*"). Will NOT create an app-side Dose calculation, status or threshold; receipts render the
recorded pipeline result.

Commits: 09e49d75 checker defects, 1fb22683 "not assessed" notice, e3c47f57/2c0027d2/25b77bb4
receipt parity fixture (regenerated from pipeline 369f93aa8), dcf3768b dart format.
Draft PR seancheick/Pharmaguide.ai#128. Local: flutter analyze clean; full flutter test 3,940 pass
(on 2c0027d2; later commits are a fixture regen and formatting, both re-tested in their files).
CI on 2c0027d2 failed only the changed-file dart-format check; CI 39084866574 on dcf3768b green.

Open for Sean: no-profile panel shows the adult-limit % with * and a "not assessed for you" notice
(plan says "not assessed"); no device screenshot of that panel yet (AGENTS asks for one on
rendering changes). Attempted 2026-10-17: `flutter run` with SCREENSHOT_MODE=true and
SCREENSHOT_ROUTE=/stack (seeded stack, no profile) failed to build. The only iPhone runtime is
iOS 27.0, which Xcode says doesn't match Runner.app's supported platforms; the 18.5/26.5 runtimes
are rejected on architecture. Host Xcode setup, not app code. `pod install` in this worktree's ios/
needed LANG=en_US.UTF-8. Merge with the pipeline branch, after Sean approves the packet.
