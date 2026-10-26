# Current handoff — product image sizes

2026-10-26. Goal: resolve Sean's screenshots showing small product images. Branch codex/product-image-sizing, baseline94d77bda, candidate5c0e852b818c84e2575908a7d192251341181cb8, PR147.

Owner: lib/features/home/v2/home_v2_screen.dart::_RecentScanCard; lib/core/components/pg_hero_section.dart::PGHeroSection and lib/features/product_detail/v2/sections/hero_section.dart::buildHeroSection. Evidence: existing caller trace and constraints (home photo56/frame72/card156; detail child84 forced by parent80). Will NOT create: another image widget, score, clinical rule, public field or data correction.

Fix: home photo120/frame130 with4px inset and1px borders accounted for; height308 preserves previous text space. Detail image112 at both parent and child. Existing image resolver, fallback, tap/zoom, safety/score and data selection untouched. Fail-first tests observed actual72 vs expected132 and actual80 vs expected112. A combined check reproduced a6px overflow with intermediate card288; corrected308 and affected scored/unknown/blocked consumers pass. Golden hero baseline visually inspected and updated solely for intentional image area.

Validation: analysis clean.67 focused home/detail/decision cases pass, including updated hero golden and320px narrow-screen regression. Final non-golden entire app suite4015 passed. Initial make check (before last card-height fix) had2 reproduced overflow cases and6 unrelated tiny renderer golden differences in nutrient/probiotic/med-nutrient screens after toolchain upgrade; no unrelated goldens rewritten. Final CI Analyze & Test40273880078 is pending; not yet merge-qualified.

Simulator: QA device DB137D33-E2D6-4D15-92E4-F65E2A737A9B, iOS26.5, configured Make launch. Actual Maximum CLA detail inspected (image larger,49/Poor/dose/safety unchanged); home photo inspected through Device Hub. Private screenshots/logs .claude/state/image-sizing. Home QA empty scan table received one temporary1059 row for visual verification, exact row ID in qa_test_row.txt and whole DB backup qa_before.db. Temporary QA row removed after capture; original empty scan history restored; no profile/stack changes. Final exact-candidate simulator rebuild in progress.

Pipeline primary is now preserved and aligned main (receipt5a2ff81e), old Batch11 source copies retained in backup and stash, private submissions untouched.125 named pipeline source/consumer tests pass. All114 Clean/Enrich/Score manifests stale; no new corpus/import/release started. Full rebuilt corpus/app-data validation and clinical holds remain open.

Review follow-up: actual rendered-size regression reproduced a130x132 frame despite declared132x132 constraints. Border insets are now included at both card/frame levels, preserving card width156 and producing square130 frame/120 photo. The regression asserts actual frame and ProductImage sizes.
