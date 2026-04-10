---
name: Deterministic Logic Review
description: Ensure critical logic remains explicit and testable
---

Fail if:
- scoring, warnings, gates, or safety behavior were moved into opaque prompt logic
- critical branches are no longer explicit in code
- tests are missing for changed critical logic
- a broad refactor hides the actual behavior change
