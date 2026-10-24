import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/platform.dart';

import 'support/pump.dart';
import 'support/test_env.dart';

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir());
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('el primer arranque, sin addons, abre el asistente', (
    tester,
  ) async {
    await pumpApp(tester, dir, mockWorld(defaultRoutes()));

    expect(find.text('Traé tus addons'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('con addons instalados abre la app con la barra lateral', (
    tester,
  ) async {
    final client = mockWorld(defaultRoutes());
    await seedData(tester, dir, client, urls: [cinemetaUrl]);
    await pumpApp(tester, dir, client);

    expect(find.text('Traé tus addons'), findsNothing);
    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    for (final label in ['Inicio', 'Buscar', 'Addons', 'Ajustes']) {
      expect(
        find.descendant(of: rail, matching: find.text(label)),
        findsOneWidget,
      );
    }
    // Inicio y Buscar todavía son marcadores de lugar.
    expect(find.text('Próximamente'), findsOneWidget);
  });

  testWidgets(
    'sin addons pero con el asistente completado no lo vuelve a abrir',
    (tester) async {
      final client = mockWorld(defaultRoutes());
      await seedData(tester, dir, client, onboardingCompleted: true);
      await pumpApp(tester, dir, client);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Traé tus addons'), findsNothing);
    },
  );

  testWidgets('Ctrl+1 a Ctrl+4 cambian de sección', (tester) async {
    final client = mockWorld(defaultRoutes());
    await seedData(tester, dir, client, urls: [cinemetaUrl]);
    await pumpApp(tester, dir, client);

    Future<void> ctrl(LogicalKeyboardKey digit) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(digit);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 100));
    }

    await ctrl(LogicalKeyboardKey.digit4);
    expect(find.text('Idiomas'), findsOneWidget); // sección Ajustes

    await ctrl(LogicalKeyboardKey.digit3);
    expect(find.text('Idiomas'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.extension),
      ),
      findsOneWidget, // el ícono de Addons quedó seleccionado
    );

    await ctrl(LogicalKeyboardKey.digit2);
    expect(
      find.text('Acá vas a buscar películas y series en todos tus addons.'),
      findsOneWidget,
    );

    await ctrl(LogicalKeyboardKey.digit1);
    expect(
      find.text(
        'Acá vas a ver lo que estás mirando y los catálogos de tus addons.',
      ),
      findsOneWidget,
    );
  });

  group('ajustes', () {
    Future<void> openSettings(WidgetTester tester) async {
      final client = mockWorld(defaultRoutes());
      await seedData(tester, dir, client, urls: [cinemetaUrl]);
      await pumpApp(tester, dir, client);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Ajustes'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('el idioma elegido se guarda en disco', (tester) async {
      await openSettings(tester);

      await tester.tap(find.byKey(const Key('audio-language')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Portugués').last);
      await pumpIo(tester);
      await tester.tap(find.byKey(const Key('subtitle-language')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Español').last);
      await pumpIo(tester);

      final saved = File('${dir.path}/settings.json').readAsStringSync();
      expect(saved, contains('"audioLanguage":"por"'));
      expect(saved, contains('"subtitleLanguage":"spa"'));
    });

    testWidgets(
      'muestra versión, licencia y el aviso de que no incluye contenido',
      (tester) async {
        await openSettings(tester);
        await tester.scrollUntilVisible(find.text('Licencia MIT'), 200);

        expect(find.text('Licencia MIT'), findsOneWidget);
        expect(
          find.text('Parcel no incluye contenido ni addons'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Borrar todos los datos pide confirmación y vuelve al asistente',
      (tester) async {
        await openSettings(tester);
        expect(File('${dir.path}/addons.json').existsSync(), isTrue);
        await tester.scrollUntilVisible(
          find.text('Borrar todos los datos'),
          200,
        );

        // Cancelar no borra nada.
        await tester.tap(find.text('Borrar todos los datos'));
        await tester.pumpAndSettle();
        expect(find.text('¿Borrar todos los datos?'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(File('${dir.path}/addons.json').existsSync(), isTrue);

        await tester.tap(find.text('Borrar todos los datos'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Borrar todo'));
        await pumpUntil(tester, find.text('Traé tus addons'));

        expect(File('${dir.path}/addons.json').existsSync(), isFalse);
        expect(find.byType(NavigationRail), findsNothing);
      },
    );

    testWidgets('Volver a correr el asistente lo abre desde el paso 1', (
      tester,
    ) async {
      await openSettings(tester);
      await tester.scrollUntilVisible(
        find.text('Volver a correr el asistente'),
        200,
      );
      await tester.tap(find.text('Volver a correr el asistente'));
      await tester.pumpAndSettle();

      expect(find.text('Traé tus addons'), findsOneWidget);
    });

    testWidgets('Probar reproductor pide la URL y abre el reproductor', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(
        mediaDuration: const Duration(minutes: 1),
      );
      final client = mockWorld(defaultRoutes());
      await seedData(tester, dir, client, urls: [cinemetaUrl]);
      await pumpApp(
        tester,
        dir,
        client,
        overrides: [
          playbackEngineFactoryProvider.overrideWithValue(() => engine),
        ],
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Ajustes'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.scrollUntilVisible(find.text('Probar reproductor'), 200);
      await tester.tap(find.text('Probar reproductor'));
      await tester.pumpAndSettle();

      // Una URL inválida no abre nada y avisa.
      await tester.enterText(find.byKey(const Key('try-url')), 'no es una url');
      await tester.tap(find.text('Reproducir'));
      await tester.pump();
      expect(find.textContaining('http://'), findsWidgets);
      expect(engine.lastSource, isNull);

      await tester.enterText(
        find.byKey(const Key('try-url')),
        'http://localhost/video.mkv',
      );
      await tester.enterText(
        find.byKey(const Key('try-subtitle')),
        'http://localhost/sub.srt',
      );
      await tester.tap(find.text('Reproducir'));
      await tester.pumpAndSettle();

      expect(engine.lastSource?.url, 'http://localhost/video.mkv');
      expect(engine.state.subtitleTracks.single.isExternal, isTrue);
      expect(find.byKey(const Key('player-controls')), findsOneWidget);
    });
  });
}
