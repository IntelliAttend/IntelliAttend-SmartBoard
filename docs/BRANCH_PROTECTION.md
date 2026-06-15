# Branch Protection Configuration (O13 / AUDIT-8.3)

## Repository Settings

Enable the following rules on the `main` branch via **Settings > Branches > Add branch protection rule**:

1. **Require pull request reviews before merging** — at least 1 approval
2. **Dismiss stale pull request approvals when new commits are pushed**
3. **Require status checks to pass before merging**:
   - `flutter analyze lib/ test/` (from CI)
   - `flutter test` (from CI)
4. **Require branches to be up to date** before merging
5. **Do not allow bypassing** the above settings (include administrators)
6. **Restrict push access** to `main` — only CI/CD or release managers may push directly

## Enforcement

- All changes to `main` must go through a pull request.
- Direct pushes to `main` are blocked for all users including admins.
- CI must pass before merge.
- At least one reviewer must approve changes.
