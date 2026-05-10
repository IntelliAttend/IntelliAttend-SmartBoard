# ADR 0002: Structured JSON Logging in Production

**Status:** Accepted  
**Date:** 2026-05-09  

## Context
Operational visibility requires machine-parseable logs that can be shipped to a central aggregator (e.g., Loki, CloudWatch, ELK). The previous PrettyPrinter format was human-readable only.

## Decision
In `kReleaseMode`, the `Log` class switches to `_JsonPrinter`, which emits one JSON object per line:
```json
{"timestamp":"2026-05-09T23:30:00.000Z","level":"info","message":"...","logger":"intelliattend"}
```
Error and stackTrace fields are included when present.

In debug mode, the existing PrettyPrinter with colors and emojis is retained for developer experience.

## Consequences
- Easier: log shipping, filtering, and alerting in production.
- Harder: slightly larger log volume; sensitive data must still be redacted (handled by `_RedactingOutput`).
