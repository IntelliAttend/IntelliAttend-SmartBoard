# IntelliAttend - Project Structure Documentation

This document provides a comprehensive overview of the IntelliAttend project directory structure and organization.

---

## 📂 Root Directory Structure

```
IntelliAttend/
├── backend/                    # Backend server (Node.js + Express)
├── mobile-student/            # Student mobile app (React Native)
├── mobile-faculty/            # Faculty mobile app (React Native)
├── smartboard-portal/         # SmartBoard web portal (React + Vite)
├── shared/                    # Shared utilities and types
├── docs/                      # Documentation
├── tests/                     # System-level tests
├── docker-compose.yml         # Development environment
├── .env.example               # Environment variables template
├── .gitignore                 # Git ignore rules
└── README.md                  # Project overview
```

---

## 🖥️ Backend Server (`/backend`)

**Purpose**: Core API server handling authentication, session management, multi-factor verification, and data persistence.

```
backend/
├── src/
│   ├── models/                # Sequelize ORM models
│   │   ├── Student.js         # Student entity with device_id, biometric hash
│   │   ├── Faculty.js         # Faculty authentication
│   │   ├── Class.js           # Class schedules and room assignments
│   │   ├── Session.js         # Active session tracking
│   │   ├── Attendance.js      # Attendance records with confidence scores
│   │   ├── Device.js          # Device whitelist
│   │   ├── Room.js            # Classroom metadata (BLE, Wi-Fi, GPS)
│   │   └── ScanLog.js         # Audit trail
│   │
│   ├── services/              # Business logic layer
│   │   ├── auth.service.js    # JWT token generation, password hashing
│   │   ├── session.service.js # Session creation, QR generation
│   │   └── verification.service.js # Multi-factor validation engine
│   │
│   ├── routes/                # API route definitions
│   │   ├── auth.routes.js     # /api/auth/*
│   │   ├── student.routes.js  # /api/student/*
│   │   ├── faculty.routes.js  # /api/faculty/*
│   │   ├── attendance.routes.js # /api/attendance/*
│   │   └── analytics.routes.js # /api/analytics/*
│   │
│   ├── controllers/           # Request handlers
│   ├── middleware/            # Auth, validation, error handling
│   ├── config/                # Configuration files
│   │   ├── database.config.js # MySQL connection
│   │   ├── jwt.config.js      # JWT settings
│   │   └── verification.config.js # Verification thresholds
│   │
│   ├── database/
│   │   ├── migrations/        # Database schema migrations
│   │   ├── seeders/           # Demo data seeders
│   │   └── init.js            # Database initialization
│   │
│   ├── utils/                 # Helper functions
│   └── server.js              # Main entry point
│
├── tests/                     # Backend tests
│   ├── unit/                  # Unit tests
│   ├── integration/           # Integration tests
│   └── routes/                # API endpoint tests
│
├── package.json               # Dependencies and scripts
├── .env.example               # Environment variables template
└── Dockerfile.dev             # Docker development image
```

**Key Dependencies**:
- `express` - Web framework
- `sequelize` + `mysql2` - ORM and database driver
- `jsonwebtoken` + `bcrypt` - Authentication
- `socket.io` - Real-time communication
- `qrcode` - QR code generation
- `helmet` + `cors` - Security middleware

---

## 📱 Student Mobile App (`/mobile-student`)

**Purpose**: Student-facing application for attendance submission with biometric verification and sensor data collection.

```
mobile-student/
├── src/
│   ├── screens/               # React Native screens
│   │   ├── LoginScreen.js     # Student authentication
│   │   ├── TimetableScreen.js # Class schedule with countdown
│   │   ├── ScannerScreen.js   # QR code scanning interface
│   │   └── ProfileScreen.js   # Student profile and settings
│   │
│   ├── services/              # Sensor & API services
│   │   ├── ble.service.js     # Bluetooth beacon scanning
│   │   ├── wifi.service.js    # Wi-Fi SSID/BSSID detection
│   │   ├── gps.service.js     # GPS location tracking
│   │   ├── prewarm.service.js # Background warm scan scheduler
│   │   └── scanner.service.js # QR scan processing
│   │
│   ├── navigation/            # React Navigation setup
│   ├── api/                   # Backend API integration
│   ├── store/                 # Context API state management
│   ├── components/            # Reusable UI components
│   ├── utils/                 # Helper functions
│   └── assets/                # Images, fonts, icons
│
├── android/                   # Android native code
├── ios/                       # iOS native code
├── __tests__/                 # Mobile app tests
├── package.json               # Dependencies
└── App.js                     # Root component
```

**Key Dependencies**:
- `@react-navigation/native` - Navigation
- `react-native-camera` - Camera access
- `react-native-qrcode-scanner` - QR scanning
- `react-native-touch-id` - Biometric authentication
- `react-native-ble-manager` - Bluetooth LE
- `react-native-wifi-reborn` - Wi-Fi detection
- `@react-native-community/geolocation` - GPS
- `axios` - HTTP client
- `@react-native-async-storage/async-storage` - Local storage

---

## 📱 Faculty Mobile App (`/mobile-faculty`)

**Purpose**: Faculty-facing application for session management and live attendance monitoring.

```
mobile-faculty/
├── src/
│   ├── screens/
│   │   ├── LoginScreen.js          # Faculty authentication
│   │   ├── DashboardScreen.js      # Class selection
│   │   ├── StartSessionScreen.js   # Session initiation with OTP
│   │   └── LiveAttendanceScreen.js # Real-time attendance monitor
│   │
│   ├── services/
│   │   └── api.service.js          # Backend API integration
│   │
│   ├── navigation/                 # React Navigation
│   ├── components/                 # UI components
│   ├── store/                      # State management
│   └── assets/                     # Assets
│
├── android/
├── ios/
├── __tests__/
├── package.json
└── App.js
```

**Key Dependencies**:
- Similar to student app
- `react-native-otp-textinput` - OTP display

---

## 🖥️ SmartBoard Portal (`/smartboard-portal`)

**Purpose**: Web application for displaying dynamic QR codes and live attendance dashboard on classroom SmartBoards.

```
smartboard-portal/
├── src/
│   ├── pages/                      # Main pages
│   │   ├── OTPEntry.jsx            # OTP entry screen
│   │   ├── QRDisplay.jsx           # Dynamic QR display
│   │   └── Dashboard.jsx           # Live attendance dashboard
│   │
│   ├── components/                 # Reusable components
│   │   ├── DynamicQR.jsx           # Pixel-based QR animation
│   │   └── LiveDashboard.jsx       # Real-time attendance stats
│   │
│   ├── services/
│   │   └── socket.service.js       # Socket.IO integration
│   │
│   ├── hooks/                      # Custom React hooks
│   ├── styles/                     # CSS modules
│   ├── assets/                     # Static assets
│   ├── main.jsx                    # React entry point
│   └── App.jsx                     # Root component
│
├── public/                         # Static files
├── index.html                      # HTML template
├── vite.config.js                  # Vite configuration
├── package.json                    # Dependencies
└── .env.example                    # Environment variables
```

**Key Dependencies**:
- `react` + `react-dom` - UI framework
- `react-router-dom` - Client-side routing
- `socket.io-client` - WebSocket client
- `qrcode.react` - QR code rendering
- `axios` - HTTP client
- `vite` - Build tool

---

## 🔗 Shared Code (`/shared`)

**Purpose**: Common utilities and type definitions used across multiple components.

```
shared/
├── types/                          # TypeScript interfaces
│   └── index.ts                    # API contracts (Student, Faculty, etc.)
│
└── utils/                          # Shared utilities
    ├── qr-validator.js             # QR token signature verification
    ├── geo-utils.js                # Geofencing distance calculations
    ├── confidence.js               # Confidence score calculation
    └── constants.js                # Shared constants
```

---

## 📚 Documentation (`/docs`)

**Purpose**: Comprehensive project documentation.

```
docs/
├── api/                            # API documentation
│   ├── openapi.yaml                # OpenAPI/Swagger spec
│   ├── authentication.md           # Auth flow documentation
│   └── endpoints/                  # Individual endpoint docs
│
├── architecture/                   # System architecture
│   ├── system-overview.md          # High-level architecture
│   ├── database-schema.md          # Database design
│   ├── verification-flow.md        # Multi-factor verification
│   └── deployment-guide.md         # Production deployment
│
├── guides/                         # How-to guides
│   ├── backend-setup.md            # Backend development setup
│   ├── mobile-setup.md             # Mobile app development setup
│   └── testing.md                  # Testing guide
│
├── PRD.md                          # Product Requirements Document
├── SETUP.md                        # Quick setup guide
└── CONTRIBUTING.md                 # Contribution guidelines
```

---

## 🧪 Tests (`/tests`)

**Purpose**: System-level and load testing.

```
tests/
└── load/                           # Load testing scripts
    ├── attendance-submit.yml       # Artillery load test config
    └── session-management.yml      # Session load test
```

---

## 🚀 Development Workflow

### 1. Initial Setup
```bash
# Clone repository
git clone <repo-url>
cd IntelliAttend

# Copy environment variables
cp .env.example .env

# Start database
docker-compose up -d mysql

# Setup backend
cd backend
npm install
npm run migrate
npm run seed
npm run dev

# Setup SmartBoard portal
cd ../smartboard-portal
npm install
npm run dev

# Setup mobile apps
cd ../mobile-student
npm install
npx react-native run-android
```

### 2. Development Cycle
- Backend: `npm run dev` (auto-reload with nodemon)
- SmartBoard: `npm run dev` (Vite hot reload)
- Mobile: Metro bundler + React Native developer menu

### 3. Testing
- Backend: `npm test`
- Integration: `npm run test:integration`
- Load: `artillery run tests/load/attendance-submit.yml`

---

## 📝 File Naming Conventions

- **Models**: PascalCase (e.g., `Student.js`, `Session.js`)
- **Services**: camelCase with `.service.js` suffix (e.g., `auth.service.js`)
- **Routes**: camelCase with `.routes.js` suffix (e.g., `attendance.routes.js`)
- **Components (React)**: PascalCase with `.jsx` extension (e.g., `DynamicQR.jsx`)
- **Screens (React Native)**: PascalCase with `Screen` suffix (e.g., `LoginScreen.js`)
- **Utils**: camelCase with `.js` extension (e.g., `geo-utils.js`)
- **Config**: camelCase with `.config.js` suffix (e.g., `database.config.js`)

---

## 🔐 Environment Variables

Each component has its own `.env` file:
- **Backend**: `/backend/.env`
- **SmartBoard**: `/smartboard-portal/.env`
- **Mobile Apps**: React Native environment variables via config

See `.env.example` for complete list of required variables.

---

## 📦 Build & Deployment

### Development
```bash
docker-compose up -d
```

### Production
```bash
# Backend build
cd backend && npm run build

# SmartBoard build
cd smartboard-portal && npm run build

# Mobile apps
cd mobile-student && npx react-native build-android --release
cd mobile-faculty && npx react-native build-ios --release
```

See [Deployment Guide](architecture/deployment-guide.md) for full instructions.
