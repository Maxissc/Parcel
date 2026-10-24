import 'dart:convert';
import 'dart:io';

/// Lee un fixture JSON de `test/fixtures/` (los tests corren desde
/// `packages/core`).
Map<String, dynamic> fixture(String name) {
  final text = File('test/fixtures/$name').readAsStringSync();
  return jsonDecode(text) as Map<String, dynamic>;
}

/// Texto crudo de un fixture.
String fixtureText(String name) =>
    File('test/fixtures/$name').readAsStringSync();
