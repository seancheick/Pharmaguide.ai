---
name: Sprint DoD Review
description: Check whether the patch actually satisfies the Sprint Tracker task
---

Review this diff against the task's Definition of Done and Acceptance Criteria.

Fail if:
- required verification evidence is missing
- a task appears marked complete without proof
- key requirements were only partially implemented
- the patch changed unrelated files
- the implementation skipped a dependency or blocker that should have been addressed
