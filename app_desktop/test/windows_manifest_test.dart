import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el exe de Windows no pide administrador (asInvoker)', () {
    final manifest = File('windows/runner/runner.exe.manifest')
        .readAsStringSync();
    expect(manifest, contains('requestedExecutionLevel'));
    expect(manifest, contains('level="asInvoker"'));
    expect(manifest, isNot(contains('requireAdministrator')));
    expect(manifest, isNot(contains('highestAvailable')));
  });
}
