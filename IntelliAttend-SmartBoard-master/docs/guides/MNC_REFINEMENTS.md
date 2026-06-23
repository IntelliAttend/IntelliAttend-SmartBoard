# 🏗️ MNC Architectural Refinements

> **Verdict:** 85-90% MNC Compliance.
> **Strategy:** Keep current structure, apply surgical upgrades for maturity.

## 1️⃣ Domain-Driven Structure (Gradual Evolution)
**Goal:** Prevent service bloating and improve ownership.
**Action:** Group related Service + Repository + Schema under `backend/app/domains/`.

```txt
backend/app/
├── api/            # Interfaces (HTTP/WebSockets)
├── core/           # Platform & Security
├── domains/        # [NEW] Business Modules
│   ├── tenants/
│   ├── infrastructure/
│   ├── sessions/
│   └── ...
└── shared/         # Utilities
```

## 2️⃣ Centralized RBAC Policy
**Goal:** Avoid role logic duplication and permission drift.
**Action:** Move individual role checks into a central policy layer.

```txt
backend/app/core/rbac/
├── policies.py
├── permissions.py
└── dependencies.py
```

## 3️⃣ Infrastructure Mode as a Capability
**Goal:** "Infra Mode" is a state/mode, not just a role.
**Action:** explicit mode switching and audit tagging.
- **Audit Tag:** `mode=INFRA`
- **Enforcement:** `require_mode("INFRA")` dependencies.

## 4️⃣ Boundary Testing (Security)
**Goal:** Test what *cannot* happen.
**Action:** Add explicit negative tests.
- `test_super_admin_cannot_mark_attendance`
- `test_admin_cannot_provision_rooms`

---
These refinements will be applied iteratively, starting with **Infrastructure Mode** in Phase 2.
