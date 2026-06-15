# ADR 0001: Record Architecture Decisions

**Status:** Accepted  
**Date:** 2026-05-09  

## Context
We need a lightweight way to capture architectural decisions made during the development of the IntelliAttend SmartBoard system. Without written records, the rationale behind decisions is lost to tribal knowledge.

## Decision
We will use Architecture Decision Records (ADRs) stored in `docs/adr/`. Each ADR is a short markdown file following the template:

```
# ADR NNNN: Title
**Status:** [Proposed | Accepted | Deprecated | Superseded]
**Date:** YYYY-MM-DD

## Context
Why this decision was needed.

## Decision
What was decided.

## Consequences
What becomes easier or harder.
```

## Consequences
- Easier: onboarding new team members, auditing past decisions.
- Harder: discipline required to write ADRs for every notable decision.
