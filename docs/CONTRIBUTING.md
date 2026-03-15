# Contributing to IntelliAttend

Thank you for your interest in contributing to IntelliAttend! This document provides guidelines and standards for development.

---

## 🚀 Getting Started

### Prerequisites
- Node.js 18+ and npm
- MySQL 8.0
- React Native development environment (Xcode for iOS, Android Studio for Android)
- Git

### Development Environment Setup
1. Fork and clone the repository
2. Copy `.env.example` to `.env` and configure your environment
3. Start development environment: `docker-compose up -d`
4. Run database migrations: `cd backend && npm run migrate`
5. Seed demo data: `npm run seed`

---

## 📝 Code Standards

### JavaScript/Node.js (Backend)
- **Style Guide**: Airbnb JavaScript Style Guide
- **Linting**: ESLint with Airbnb config
- **Formatter**: Prettier
- **Naming**:
  - Variables/Functions: camelCase (`getUserById`, `studentName`)
  - Classes/Models: PascalCase (`Student`, `AttendanceService`)
  - Constants: UPPER_SNAKE_CASE (`JWT_SECRET`, `MAX_RETRIES`)
  - Files: camelCase with suffix (`.service.js`, `.routes.js`)

### React/React Native (Frontend)
- **Style Guide**: Airbnb React/JSX Style Guide
- **Components**: Functional components with hooks
- **Naming**:
  - Components: PascalCase (`LoginScreen`, `DynamicQR`)
  - Hooks: `use` prefix (`useAuth`, `useScanner`)
  - Props: camelCase
- **File Structure**: One component per file

### Database
- **Migrations**: Always create migrations for schema changes
- **Seeders**: Update seeders for new demo data
- **Models**: Use Sequelize associations and validations

---

## 🌿 Git Workflow

### Branch Naming
- `feature/description` - New features (e.g., `feature/qr-animation`)
- `fix/description` - Bug fixes (e.g., `fix/ble-scanning`)
- `refactor/description` - Code refactoring
- `docs/description` - Documentation updates
- `test/description` - Test additions/updates

### Commit Messages
Follow Conventional Commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code formatting (no logic change)
- `refactor`: Code refactoring
- `test`: Adding/updating tests
- `chore`: Build process, dependencies

**Examples**:
```
feat(backend): add QR token signature verification

Implement cryptographic signing for QR tokens to prevent replay attacks.
Uses HMAC-SHA256 with server secret.

Closes #42
```

```
fix(mobile-student): resolve BLE scan crash on Android 12

Updated react-native-ble-manager to 8.x to fix permission handling
on Android 12+.

Fixes #58
```

### Pull Request Process
1. Create feature branch from `main`
2. Make changes with clear commits
3. Write/update tests for new functionality
4. Ensure all tests pass: `npm test`
5. Update documentation if needed
6. Submit PR with clear description and linked issues
7. Wait for CI checks and code review
8. Address review feedback
9. Squash commits if requested

---

## 🧪 Testing Standards

### Backend Tests
- **Unit Tests**: All services must have unit tests (≥80% coverage)
- **Integration Tests**: Test API endpoints with real database
- **Location**: `backend/tests/`

```javascript
// Example: backend/tests/unit/verification.service.test.js
describe('VerificationService', () => {
  describe('calculateConfidence', () => {
    it('should return 1.0 for all valid factors', () => {
      const result = VerificationService.calculateConfidence({
        qrValid: true,
        bleHits: 3,
        wifiMatch: true,
        gpsDistance: 10
      });
      expect(result).toBe(1.0);
    });
  });
});
```

### Mobile App Tests
- **Component Tests**: Test UI components with React Testing Library
- **Service Tests**: Mock native modules and test logic

```javascript
// Example: mobile-student/src/__tests__/services/ble.service.test.js
jest.mock('react-native-ble-manager');

describe('BLEService', () => {
  it('should detect classroom beacon', async () => {
    const beacons = await BLEService.scanForBeacons();
    expect(beacons).toContainEqual(
      expect.objectContaining({ uuid: CLASSROOM_UUID })
    );
  });
});
```

### Test Commands
```bash
# Backend
cd backend
npm test                    # All tests
npm run test:unit          # Unit tests only
npm run test:integration   # Integration tests
npm run test:coverage      # With coverage report

# Mobile apps
cd mobile-student
npm test
```

---

## 📚 Documentation

### Code Documentation
- **JSDoc**: Document all public functions and classes
- **Inline Comments**: Explain complex logic, not obvious code

```javascript
/**
 * Calculate confidence score for attendance verification
 * @param {Object} factors - Verification factors
 * @param {boolean} factors.qrValid - QR token is valid
 * @param {number} factors.bleHits - Number of BLE beacon hits
 * @param {boolean} factors.wifiMatch - Wi-Fi BSSID matches
 * @param {number} factors.gpsDistance - Distance from classroom (meters)
 * @returns {number} Confidence score (0.0 - 1.0)
 */
function calculateConfidence(factors) {
  // Implementation
}
```

### README Updates
- Update component READMEs for new features
- Include setup instructions for new dependencies
- Add examples for new API endpoints

### API Documentation
- Update OpenAPI/Swagger spec for new endpoints
- Document request/response schemas
- Include example requests

---

## 🔒 Security Guidelines

### Never Commit
- Environment variables (`.env` files)
- Secret keys or passwords
- Database credentials
- API tokens
- Private keys

### Best Practices
- **Secrets**: Use environment variables for all secrets
- **Input Validation**: Validate and sanitize all user input
- **SQL Injection**: Use parameterized queries (Sequelize handles this)
- **Authentication**: Always verify JWT tokens in protected routes
- **Rate Limiting**: Don't disable rate limiting without good reason
- **HTTPS**: Ensure all production deployments use HTTPS

---

## 🐛 Bug Reports

### When Reporting Bugs
Include:
1. **Description**: Clear description of the issue
2. **Steps to Reproduce**: Exact steps to reproduce
3. **Expected Behavior**: What should happen
4. **Actual Behavior**: What actually happens
5. **Environment**:
   - OS and version
   - Node.js version
   - Database version
   - Mobile device/simulator details
6. **Logs**: Relevant error messages and stack traces
7. **Screenshots**: If UI-related

### Bug Report Template
```markdown
## Description
[Clear description]

## Steps to Reproduce
1. [First step]
2. [Second step]
3. [...]

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Environment
- OS: macOS 13.0
- Node.js: 18.16.0
- MySQL: 8.0.32
- Device: iPhone 14 Pro (iOS 16.4)

## Logs
```
[Paste relevant logs]
```

## Screenshots
[Attach screenshots if applicable]
```

---

## ✨ Feature Requests

### When Requesting Features
Include:
1. **Problem Statement**: What problem does this solve?
2. **Proposed Solution**: How should it work?
3. **Alternatives Considered**: Other approaches considered
4. **Impact**: Who benefits? How critical is it?
5. **Additional Context**: Mockups, examples, references

---

## 📋 Code Review Checklist

### For Reviewers
- [ ] Code follows style guide
- [ ] Tests are included and pass
- [ ] Documentation is updated
- [ ] No sensitive data committed
- [ ] Error handling is appropriate
- [ ] Performance impact considered
- [ ] Security implications reviewed
- [ ] API changes are backward compatible

### For Authors
Before requesting review:
- [ ] Self-review your code
- [ ] Run all tests locally
- [ ] Update relevant documentation
- [ ] Resolve all linting errors
- [ ] Add clear PR description
- [ ] Link related issues

---

## 🎯 Development Phases

When contributing, align your work with the current development phase:

### Phase 1: Core Infrastructure (Current)
- Backend server setup
- Database models and migrations
- Authentication service

### Phase 2: Session Management
- QR generation
- SmartBoard portal foundation

### Phase 3: Verification Engine
- Multi-factor validation
- Confidence scoring

### Phase 4: Student App
- Mobile app development
- Sensor integration

### Phase 5: Faculty App & Portal
- Faculty mobile app
- SmartBoard UI completion

### Phase 6: Testing & Optimization
- Load testing
- Performance optimization

---

## 💬 Communication

- **Questions**: Open a GitHub Discussion
- **Bugs**: Create an issue with bug report template
- **Features**: Create an issue with feature request template
- **Security**: Email security@intelliattend.dev (do NOT create public issue)

---

## 📜 License

By contributing, you agree that your contributions will be licensed under the same license as the project.

---

## 🙏 Thank You!

Every contribution helps make IntelliAttend better. We appreciate your time and effort!
