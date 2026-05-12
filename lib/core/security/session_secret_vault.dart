/// In-memory session secret store.
///
/// Per the IntelliAttend contract, the SmartBoard never persists the
/// derived session secret. It lives in this RAM-only vault for the
/// lifetime of the ignited session and is wiped on:
///   - session end (manual, timeout, capacity reached, Firestore "ended")
///   - app restart / board reboot (process death drops the vault)
///
/// After any of those, the faculty must re-ignite via OTP. There is no
/// disk-resume path on purpose — keeping the full secret off-disk
/// closes the memory-scrape / disk-image attack surface the contract
/// calls out.
class SessionSecretVault {
  SessionSecretVault._();

  static final Map<String, String> _vault = {};

  static void put(String sessionId, String secret) {
    _vault[sessionId] = secret;
  }

  static String? read(String sessionId) => _vault[sessionId];

  static void clear(String sessionId) {
    _vault.remove(sessionId);
  }

  static void clearAll() {
    _vault.clear();
  }
}
