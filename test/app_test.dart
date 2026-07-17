import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App version is valid', () {
    const version = '5.5.0';
    expect(version.isNotEmpty, true);
  });
}
