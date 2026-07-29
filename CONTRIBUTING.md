# Contributing to IntelliAttend SmartBoard

## Quick Start

1. Fork and clone the repo
2. Install Flutter SDK (>=3.44.0)
3. Create a branch from `school-dev`: `git checkout -b feat/your-feature`
4. Run the app: `flutter run`
5. Run tests: `flutter test`
6. Format code: `dart format .`
7. Commit and push
8. Create a PR to `school-main`

## Code Conventions

### File Naming
- Screens: `*_screen.dart` (e.g., `workspace_screen.dart`)
- Services: `*_service.dart` (e.g., `websocket_service.dart`)
- Controllers: `*_controller.dart` (e.g., `dashboard_controller.dart`)
- Models: `*_model.dart` or Isar schemas

### Widget Structure
```dart
class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  // State variables
  // Controllers
  
  @override
  void initState() {
    super.initState();
    // Initialize
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Build UI
    );
  }
}
```

### State Management
- Use Controllers (GetX pattern)
- Keep controllers in `lib/controllers/`
- Use reactive state (`.obs` variables)

## Testing

```bash
flutter test             # Run all tests
flutter test --coverage  # Run with coverage
dart analyze             # Static analysis
dart format .           # Format code
```

## Commit Messages

Format: `type(scope): description`

Examples:
- `feat(workspace): add real-time attendance display`
- `fix(websocket): handle reconnection on network change`
- `ui(timetable): improve slot card styling`
