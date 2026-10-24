import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/accounts_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

/// El tamaño mínimo de la ventana (ver `DesktopWindowService.minimumSize`).
const _minimum = Size(960, 600);

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir());
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> shrink(WidgetTester tester) async {
    tester.view.physicalSize = _minimum;
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('las secciones principales entran en 960×600 sin desbordar', (
    tester,
  ) async {
    final client = mockWorld(defaultRoutes());
    await seedData(
      tester,
      dir,
      client,
      urls: [cinemetaUrl, subtitlesUrl, torrentUrl],
      onboardingCompleted: true,
    );
    await pumpApp(tester, dir, client);
    await shrink(tester);

    for (final digit in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(digit);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 200));
      await pumpIo(tester, ticks: 3);
      expect(
        tester.takeException(),
        isNull,
        reason: 'sección ${digit.keyLabel}',
      );
    }
  });

  testWidgets('los pasos del asistente entran en 960×600 sin desbordar', (
    tester,
  ) async {
    await pumpApp(
      tester,
      dir,
      stremioWorld(
        calls: AccountCalls(),
        addons: [
          for (var i = 0; i < 8; i++)
            stremioEntry(cinemetaUrl, 'id.$i', 'Addon $i'),
        ],
        pendingReads: -1,
      ),
    );
    await shrink(tester);

    // Bienvenida, Stremio (código y email), Nuvio y Pegar lista.
    await tester.tap(find.byKey(const Key('source-stremio')));
    await pumpUntil(tester, find.byKey(const Key('link-code')));
    await tester.tap(find.text('Con email'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Atrás'));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('source-nuvio')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Atrás'));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('source-paste')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const Key('paste-text')),
      [cinemetaUrl, subtitlesUrl, torrentUrl].join('\n'),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('paste-continue')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('import-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-button')));
    await pumpUntil(tester, find.byKey(const Key('go-home')));
    expect(tester.takeException(), isNull);
  });
}
