# Text-scale audit at the 1.4x cap (2026-10-02)

The app clamps the system text scale to 1.4x (`lib/app.dart`). This audit checked
every screen and widget the test suite renders at that cap.

## Method

The full suite (3,742 tests) was run four extra times through a temporary
`test/flutter_test_config.dart` (not committed) that set the platform text scale
and surface for every test:

| Surface | 1.0x overflow events | 1.4x before fixes | 1.4x after fixes |
|---|---|---|---|
| 390 x 1333 pt (tall phone; no below-the-fold artifacts) | 8 | 82 | 6 |
| 375 x 667 pt (iPhone SE, smallest supported) | 7 | 69 | 15 |

Only failures that appear at 1.4x and not at 1.0x on the same surface count as
text-scale defects. Finder misses that disappear on the tall surface are content
below the fold of lazily built lists (still reachable by scrolling), not defects.

## Fixed (each overflowed only at 1.4x)

| Site | Worst overflow | Fix |
|---|---|---|
| `stack_share_sheet.dart` options | 474 pt bottom (SE) | sheet body scrolls |
| `camera_permission_v2_screen.dart` | 106 pt bottom (SE, keyboard) | spacer layout kept when it fits; scrolls when it does not |
| `synergy_section.dart` header | 102 pt right | title flexes |
| `pg_score_line.dart` | 88 pt right | score scales down to fit; never truncated |
| `pg_severity_banner.dart` action | 78 pt right | action label wraps |
| `nutrient_progress_bar.dart` | 139 pt right (also at 1.0x on SE) | amount + UL group capped at 60% and scaled down only when needed; pixel-identical when it fits (goldens unchanged) |
| `missing_product_submission_sheet.dart` sort buttons, add row | 71 / 30 pt right | buttons stack (`OverflowBar`); Add button flexes |
| `pg_depletion_card.dart` eyebrow, details link | 43 / 33 pt right | text flexes |
| `pg_transparency_footer.dart` (centered) | 35 pt right | sources line flexes with ellipsis |
| `product_version_picker_sheet.dart` | 18 pt bottom | header and candidates scroll together |
| `magic_link_sheet.dart` | 3 pt bottom | sheet body scrolls |
| home recent-scan cards | 35 pt right | score line fix |

Regression: `test/a11y/large_text_layout_test.dart` renders the banner, score
line, footer, nutrient bar, camera gate and bottle picker at 1.4x on 375 x 667;
the banner, footer, nutrient bar and camera gate cases fail without the fixes.
Full suite after the fixes: 3,748 passed (goldens unchanged); analyze clean.

## Not fixed (recorded)

- Transient: four overflows reported on already-disposed elements during
  sheet/dialog close animations (health-history visit completion, stack action
  buttons, label-mismatch sheet, search). No content stays clipped.
- Narrow width, present at 1.0x too on the SE: `pg_severity_pill` compact row
  (test fixture width), health-history add action (152 pt), stack action buttons
  "already in stack" state (157 pt). Width issues, not text scale; worth a
  separate small-screen pass.
- Test artifacts: probiotic section test pumps the section without a scroll view;
  add-product sheet's camera path is stacked below the fold at 1.4x by design and
  reachable (the sheet scrolls).
- `nutrient_accumulation_panel.dart:208` surfaced once on the SE at 1.4x after the
  nutrient-bar fix (one event); not yet fixed.
