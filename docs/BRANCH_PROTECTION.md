# Branch Protection Configuration

## Overview

This document specifies the required branch protection rules for the `school-main` and `main` branches. These rules **cannot be enforced from code** — they must be configured manually in GitHub Settings.

## Repository Settings

Navigate to **Settings > Branches > Add branch protection rule** and configure for both `school-main` and `main`:

### Required Rules

| # | Rule | Setting |
|---|------|---------|
| 1 | Require pull request reviews before merging | At least 1 approval |
| 2 | Dismiss stale pull request approvals when new commits are pushed | Enabled |
| 3 | Require status checks to pass before merging | `flutter analyze`, `CI` |
| 4 | Require branches to be up to date before merging | Enabled |
| 5 | Do not allow bypassing the above settings | Include administrators |
| 6 | Restrict push access | Only CI/CD bots via GitHub Actions |

### Status Checks to Require

These must pass before any PR can be merged:

- `CI` — from `.github/workflows/ci.yml`
- Any future test workflows

### Restricted Push Access

Direct pushes to `main` / `school-main` should be blocked for all users. The only exceptions:

- GitHub Actions bots (for automated deployment)
- Release managers (for emergency hotfixes, via `workflow_dispatch`)

## Verification

To verify branch protection is active:

1. Attempt a direct push to `main` — it should be rejected
2. Open a PR without status checks passing — it should be blocked
3. Check **Settings > Branches** to confirm rules are listed

## Rollback

If branch protection needs to be temporarily disabled (e.g., emergency deployment):

1. Only administrators can disable protection
2. Re-enable immediately after the emergency
3. Log the reason and duration in the incident report

## Audit Trail

| Date | Change | Approved By |
|------|--------|-------------|
| Phase 1 | Initial documentation | — |
| Phase 2 | Enhanced with verification steps | — |
