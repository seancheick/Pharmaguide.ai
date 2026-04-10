---
name: Flutter Task Scope Review
description: Ensure the patch stayed focused and did not create architectural drift
---

Fail if:
- the patch touched unrelated widgets, services, or models
- new dependencies were introduced without necessity
- state management became less explicit
- persistence and UI concerns were mixed together
- file changes are broader than the sprint task requires
