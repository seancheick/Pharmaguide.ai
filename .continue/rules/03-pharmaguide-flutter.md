# Flutter Project Rules

- Respect the project architecture already in place.
- Prefer feature-local changes.
- Keep widget trees composable and readable.
- Avoid introducing architectural churn during sprint execution.
- Riverpod state should remain explicit and testable.
- Drift models, queries, and persistence logic should stay cleanly separated from UI.
- Supabase initialization and network services should not leak into presentation widgets.
- Add tests for new logic or UI behavior where the sprint requires them.
- Do not introduce package dependencies unless the task clearly needs them.
