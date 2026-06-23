# Administrative Authentication & Auditing System

This document describes the design and implementation of the IntelliAttend Admin/Super Admin authentication system, identity recovery flows, and immutable audit logging.

## Architecture Overview

Unlike students and faculty who use Firebase Phone Authentication, Admins and Super Admins utilize a customID/Password system. This allows for dedicated, professional identities (e.g., `sysadmin_mrcet`) that are managed directly within the IntelliAttend ecosystem.

### Components
1.  **Hashed Security**: Passwords are never stored in plain text. We use `bcrypt` via the `app.core.security` module to generate secure hashes.
2.  **Repository Integration**: Administrative data is stored in the `users` collection within Firestore, alongside student/faculty profiles for unified RBAC (Role-Based Access Control).
3.  **Audit Service**: A dedicated `AuditService` captures every sensitive action and authentication event, providing an immutable trail for security compliance.

## Authentication Flow

1.  **Login**: User provides their Admin ID and Password.
2.  **Verification**: The backend retrieves the `password_hash` from Firestore and validates it using `bcrypt.verify`.
3.  **Audit**:
    *   **Success**: Logged as `LOGIN_SUCCESS`.
    *   **Failure**: Logged as `LOGIN_FAILED` with the reason (e.g., "Invalid password").
4.  **JWT Issue**: Upon success, a JWT is returned containing the user's role and unique ID.

## Identity Recovery

### Forgot Username
Recovers the Admin ID associated with a verified email address.
- **Endpoint**: `POST /api/v1/auth/forgot-username`
- **Logic**: Searches for administrative roles associated with the email and logs the recovery event (simulated email sending in development).

### Forgot Password
Handles secure password resets via time-limited tokens.
1.  **Initiation**: `POST /api/v1/auth/forgot-password` (Admin ID + Email).
2.  **Token Generation**: A cryptographically secure 32-byte token is generated and stored in a `password_resets` collection with a 1-hour expiry.
3.  **Completion**: `POST /api/v1/auth/reset-password` (Token + New Password). Updates the `password_hash` and marks the token as used.

## Audit Logs

All logs are stored in the `audit_logs` collection. Each entry includes:
- `actor_id`: Who performed the action.
- `action_type`: e.g., `CREATE`, `UPDATE`, `LOGIN_SUCCESS`.
- `resource`: The entity type (e.g., `TENANT`, `USER`).
- `resource_id`: Specific ID of the resource.
- `details`: Contextual information (e.g., which fields were updated).
- `timestamp`: Server-side timestamp for immutability.

## Management API

### Super Admin Only Endpoints
- `POST /api/v1/super-admin/admins`: Onboard new administrators.
- `GET /api/v1/super-admin/admins`: View current administrative user list.
- `GET /api/v1/super-admin/audit-logs`: Review system-wide audit trails.

## Setup & Bootstrapping

Since creating a Super Admin requires existing Super Admin privileges, use the bootstrap script for the first account:
```bash
python3 backend/scripts/bootstrap_super_admin.py
```
After the first account is created, all subsequent admins should be managed via the Web Admin Portal or API.
