/// Utilities for safely escaping strings before passing them to PowerShell.
///
/// PowerShell has multiple evaluation contexts:
/// - Single-quoted strings: literal (only `'` → `''` escaping needed)
/// - Double-quoted strings: variable expansion + backtick escape sequences
/// - `-Command` parameter: full PowerShell parsing
/// - `-File` parameter: script file (values passed as arguments)
///
/// This utility provides defense-in-depth escaping for all contexts.
class PowerShellEscape {
  PowerShellEscape._();

  /// Escapes a value for use inside a PowerShell single-quoted string.
  ///
  /// In single-quoted strings, only single quotes need escaping (`''`).
  /// This is the safest context for embedding user-controlled values.
  ///
  /// ```dart
  /// final safe = PowerShellEscape.singleQuote("O'Brien");
  /// // safe == "O''Brien"
  /// ```
  static String singleQuote(String value) {
    return value.replaceAll("'", "''");
  }

  /// Escapes a value for use inside a PowerShell double-quoted string.
  ///
  /// Double-quoted strings interpret:
  /// - `$variables` — escaped with backtick: `` `$ ``
  /// - Backtick escape sequences (`n, `t, etc.) — escaped with double backtick: ` `` `` `
  /// - Double quotes — escaped with backtick: `` `" ``
  ///
  /// ```dart
  /// final safe = PowerShellEscape.doubleQuote('Path "C:\\Test"');
  /// // safe == 'Path `\"C:\\Test`\"'
  /// ```
  static String doubleQuote(String value) {
    // Order matters: escape backticks first, then $, then double quotes.
    // Backtick (\x60) is PowerShell's escape character in double-quoted strings.
    final backtick = String.fromCharCode(0x60);
    final dollar = String.fromCharCode(0x24);
    return value
        .replaceAll(backtick, '$backtick$backtick')
        .replaceAll(dollar, '$backtick$dollar')
        .replaceAll('"', '$backtick"');
  }

  /// Escapes a value for safe interpolation into a PowerShell `-Command` argument.
  ///
  /// `-Command` runs the entire string as PowerShell code. Values must be
  /// wrapped in single quotes and properly escaped. This is the safest way
  /// to pass user-controlled values via `-Command`.
  ///
  /// ```dart
  /// final safe = PowerShellEscape.forCommand("O'Brien's PC");
  /// // safe == "'O''Brien''s PC'"
  /// ```
  static String forCommand(String value) {
    return "'${singleQuote(value)}'";
  }

  /// Validates that a string contains only safe characters for a specific
  /// use case. Returns null if valid, or a description of the issue.
  ///
  /// Use this as a defense-in-depth check before passing values to PowerShell.
  static String? validateSafe(String value, {required String context}) {
    // Block null bytes
    if (value.contains('\x00')) {
      return '$context: contains null byte';
    }
    // Block control characters (except tab, newline)
    final hasControlChars = RegExp(r'[\x01-\x08\x0B\x0C\x0E-\x1F]').hasMatch(value);
    if (hasControlChars) {
      return '$context: contains control characters';
    }
    return null;
  }

  /// Sanitizes a value for use as a netsh SSID or key.
  ///
  /// netsh has its own parsing rules. Values should be alphanumeric +
  /// common punctuation only. Returns the sanitized value or throws.
  static String forNetsh(String value, {required String field}) {
    final sanitized = value.trim();
    if (sanitized.isEmpty) {
      throw ArgumentError('$field cannot be empty');
    }
    if (sanitized.length > 32) {
      throw ArgumentError('$field exceeds maximum length of 32 characters');
    }
    // netsh SSID/key: allow alphanumeric, spaces, and common punctuation
    if (!RegExp(r'^[a-zA-Z0-9 !@#$%^&*()_+\-=\[\]{};:,.<>?/\\|~`]+$').hasMatch(sanitized)) {
      throw ArgumentError('$field contains invalid characters');
    }
    return sanitized;
  }
}
