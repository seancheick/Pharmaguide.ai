# Sprint Execution Rules

SPRINT_TRACKER.md is the source of truth.

Required workflow:

1. Read SPRINT_TRACKER.md
2. Identify the current sprint
3. Identify the next incomplete task, unless the user explicitly names a different task
4. Extract:
   - task description
   - dependencies
   - definition of done
   - acceptance criteria
   - blockers / risks
5. Identify exact files before editing
6. Implement the smallest safe change
7. Run required verification commands
8. Only mark complete if all checks pass

Never:

- Mark a task complete without fresh verification
- Skip tests or analyze
- Assume completion
- Modify unrelated files
- “Batch-finish” multiple tasks without separate verification evidence
