# Contributing to IntelliAttend SmartBoard

## Branch Model

```
school-main  ← production (auto-deploys to server, SmartBoard devices auto-update)
school-dev   ← staging (CI runs tests, no production deploy)
main         ← legacy (unused)
```

## How to Contribute

1. **Create a feature branch** from `school-dev`:
   ```bash
   git checkout school-dev
   git pull
   git checkout -b feat/your-feature-name
   ```

2. **Push your branch** — CI runs automatically:
   ```bash
   git push -u origin feat/your-feature-name
   ```

3. **Create a Pull Request** targeting `school-dev`

4. **After review and merge** to `school-dev`, the project owner promotes to `school-main`

## Push to `school-main` = Production Deploy

When code is pushed to `school-main`, the following happens **automatically**:

1. CI builds the Windows MSI installer
2. Creates a GitHub Release with version tag
3. Uploads MSI to the production server
4. Admin Panel download page shows the new version
5. Existing SmartBoard devices auto-update on next heartbeat

**Only the project owner should push to `school-main`.**

## Rules

- Never push directly to `school-main` without review
- All changes go through `school-dev` first
- Feature branches must branch from `school-dev`
- Keep commit messages clear and concise
- Test locally before pushing
