/// Alphanumeric roll number generator for seat identification.
///
/// Supports 359 unique 2-character codes:
///   - 01-99 (numeric, 99 codes)
///   - 0A-9A, 0B-9B, ... 0Z-9Z (digit + letter, 260 codes)
///
/// Sequence: 01, 02, ..., 99, 0A, 1A, ..., 9A, 0B, 1B, ..., 9B, ... 0Z, 1Z, ..., 9Z
///
/// For classes with >359 students, 3-character codes are generated:
///   - A00-Z99 pattern
class RollNumberUtils {
  static const String _digits = '0123456789';
  static const String _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Generate a 2-character alphanumeric code for a given seat index (0-based).
  ///
  /// Examples:
  ///   index 0  -> "01"
  ///   index 1  -> "02"
  ///   index 98 -> "99"
  ///   index 99 -> "0A"
  ///   index 108 -> "9A"
  ///   index 109 -> "0B"
  ///   index 358 -> "9Z"
  static String generateSeatCode(int index) {
    if (index < 0) return '??';

    // Numeric range: 01-99 (99 codes instead of 00-99)
    if (index < 99) {
      return (index + 1).toString().padLeft(2, '0');
    }

    // Alphanumeric range: 0A-9Z (260 codes)
    final adjustedIndex = index - 99;
    if (adjustedIndex < 260) {
      final letterIndex = adjustedIndex ~/ 10;
      final digitIndex = adjustedIndex % 10;
      return '${_digits[digitIndex]}${_letters[letterIndex]}';
    }

    // Extended range: 3-character codes for >359 students
    final extendedIndex = index - 359;
    if (extendedIndex < 2600) {
      final letterIndex = extendedIndex ~/ 100;
      final remainder = extendedIndex % 100;
      return '${_letters[letterIndex]}${remainder.toString().padLeft(2, '0')}';
    }

    // Absolute fallback
    return 'SE${(index + 1).toString().padLeft(3, '0')}';
  }

  /// Generate a list of roll numbers for a given capacity.
  static List<String> generateRollNumbers(int capacity) {
    return List.generate(capacity, (index) => generateSeatCode(index));
  }

  /// Parse a 2-character roll code back to its seat index.
  /// Returns -1 if the code is invalid.
  static int parseSeatCode(String code) {
    if (code.length < 2) return -1;

    final upper = code.toUpperCase();

    // Numeric: 01-99
    if (RegExp(r'^\d{2}$').hasMatch(upper)) {
      final num = int.tryParse(upper) ?? -1;
      return num > 0 ? num - 1 : -1;
    }

    // Digit + Letter: 0A-9Z
    if (RegExp(r'^\d[A-Z]$').hasMatch(upper)) {
      final digit = int.tryParse(upper[0]) ?? -1;
      final letterIdx = _letters.indexOf(upper[1]);
      if (digit < 0 || letterIdx < 0) return -1;
      return 99 + (letterIdx * 10) + digit;
    }

    // Letter + 2 digits: A00-Z99
    if (RegExp(r'^[A-Z]\d{2}$').hasMatch(upper)) {
      final letterIdx = _letters.indexOf(upper[0]);
      final digits = int.tryParse(upper.substring(1)) ?? -1;
      if (letterIdx < 0 || digits < 0) return -1;
      return 359 + (letterIdx * 100) + digits;
    }

    return -1;
  }

  /// Normalize a roll number string for comparison.
  static String normalize(String rollNumber) {
    return rollNumber.trim().toUpperCase();
  }

  /// Check if a roll number matches any in a list (case-insensitive).
  static bool matches(String rollNumber, List<String> candidates) {
    final normalized = normalize(rollNumber);
    return candidates.any((c) => normalize(c) == normalized);
  }
}
