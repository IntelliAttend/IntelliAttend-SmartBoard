/// Thrown when local secure storage has no board_email/board_password.
/// The board has never completed registration, or credentials were wiped.
/// Route to the setup/onboarding view — not a crash.
class NoCredentialsException implements Exception {
  final String message;
  NoCredentialsException([
    this.message = 'Kiosk credentials not found. Route to onboarding.',
  ]);

  @override
  String toString() => message;
}

/// Thrown when credentials exist locally but the Firebase Identity Toolkit
/// rejected them (revoked password, disabled account, etc.).
/// The board WAS registered but authentication is broken — route to recovery.
class InvalidCredentialsException implements Exception {
  final String message;
  InvalidCredentialsException([
    this.message = 'Hardware authentication credentials rejected by authority server.',
  ]);

  @override
  String toString() => message;
}
