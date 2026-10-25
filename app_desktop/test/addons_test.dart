import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/pump.dart';
import 'support/test_env.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openAddons(
  WidgetTester tester,
  Directory dir,
  http.Client client, {
  List<String> urls = const [cinemetaUrl, subtitlesUrl, torrentUrl],
  List<Uri>? opened,
}) async {
  await seedData(tester, dir, client, urls: urls, onboardingCompleted: true);
  await pumpApp(tester, dir, client, openedUrls: opened);
  await _tap(
    tester,
    find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('Addons'),
    ),
  );
}

/// Los nombres, de arriba hacia abajo, tal como se ven en la lista.
List<String> _visibleOrder(WidgetTester tester) {
  const names = ['Cinemeta', 'OpenSubtitles v3', 'Torrent'];
  final found = <(double, String)>[];
  for (final name in names) {
    final finder = find.byKey(Key('menu-$name'));
    if (finder.evaluate().isNotEmpty) {
      found.add((tester.getTopLeft(finder).dy, name));
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir());
  tearDown(() => deleteTempDir(dir));

  testWidgets('sin addons muestra el estado vacío con las dos acciones', (
    tester,
  ) async {
    final client = mockWorld(defaultRoutes());
    await _openAddons(tester, dir, client, urls: const []);

    expect(find.text('Todavía no tenés addons'), findsOneWidget);
    expect(find.text('Importar desde Stremio o Nuvio'), findsNWidgets(2));
    expect(find.text('Agregar por URL'), findsNWidgets(2));
  });

  testWidgets('muestra nombre, versión, descripción, tipos y host del addon', (
    tester,
  ) async {
    final client = mockWorld(defaultRoutes());
    await _openAddons(tester, dir, client);

    expect(find.text('Cinemeta'), findsOneWidget);
    expect(find.text('v1.0.0'), findsNWidgets(3));
    expect(find.text('Descripción de Cinemeta'), findsOneWidget);
    expect(find.text('Películas'), findsNWidgets(3));
    expect(find.text('Series'), findsNWidgets(3));
    expect(find.text('v3-cinemeta.strem.io'), findsOneWidget);
    // El host sí; la ruta con el token, nunca.
    expect(find.text('torrent.example.com'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);
  });

  testWidgets(
    'Configurar abre /configure en el navegador solo si corresponde',
    (tester) async {
      final opened = <Uri>[];
      final client = mockWorld(defaultRoutes());
      await _openAddons(tester, dir, client, opened: opened);

      expect(find.byKey(const Key('configure-Cinemeta')), findsNothing);
      await _tap(tester, find.byKey(const Key('configure-Torrent')));

      expect(opened, [
        Uri.parse('https://torrent.example.com/secret-token/configure'),
      ]);
    },
  );

  testWidgets('quitar pide confirmación y Deshacer lo devuelve a su lugar', (
    tester,
  ) async {
    final client = mockWorld(defaultRoutes());
    await _openAddons(tester, dir, client);

    await _tap(tester, find.byKey(const Key('menu-OpenSubtitles v3')));
    await _tap(tester, find.text('Quitar'));
    expect(find.text('¿Quitar OpenSubtitles v3?'), findsOneWidget);

    // Cancelar no quita nada.
    await _tap(tester, find.text('Cancelar'));
    await expectSavedAddons(tester, dir, hasLength(3));

    await _tap(tester, find.byKey(const Key('menu-OpenSubtitles v3')));
    await _tap(tester, find.text('Quitar'));
    await _tap(tester, find.widgetWithText(FilledButton, 'Quitar'));
    await pumpUntil(tester, find.text('Quitaste OpenSubtitles v3.'));

    expect(find.text('Quitaste OpenSubtitles v3.'), findsOneWidget);
    await expectSavedAddons(tester, dir, ['Cinemeta', 'Torrent']);
    expect(_visibleOrder(tester), ['Cinemeta', 'Torrent']);

    await tester.pumpAndSettle(); // que termine de entrar el aviso
    await _tap(tester, find.text('Deshacer'));
    await pumpIo(tester, ticks: 30); // instalar y mover son dos escrituras

    await expectSavedAddons(tester, dir, [
      'Cinemeta',
      'OpenSubtitles v3',
      'Torrent',
    ]);

    expect(_visibleOrder(tester), ['Cinemeta', 'OpenSubtitles v3', 'Torrent']);
  });

  testWidgets('arrastrar cambia el orden y se guarda', (tester) async {
    final client = mockWorld(defaultRoutes());
    await _openAddons(tester, dir, client);

    // Torrent (el último) sube hasta arriba.
    await tester.drag(
      find.byKey(const Key('drag-Torrent')),
      const Offset(0, -400),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await pumpIo(tester);

    await expectSavedAddons(tester, dir, [
      'Torrent',
      'Cinemeta',
      'OpenSubtitles v3',
    ]);

    expect(_visibleOrder(tester), ['Torrent', 'Cinemeta', 'OpenSubtitles v3']);
  });

  testWidgets('Subir y Bajar del menú también reordenan y se guardan', (
    tester,
  ) async {
    final client = mockWorld(defaultRoutes());
    await _openAddons(tester, dir, client);

    await _tap(tester, find.byKey(const Key('menu-Cinemeta')));
    expect(find.text('Subir'), findsNothing); // ya es el primero
    await _tap(tester, find.text('Bajar'));
    await pumpIo(tester);
    await expectSavedAddons(tester, dir, [
      'OpenSubtitles v3',
      'Cinemeta',
      'Torrent',
    ]);

    await _tap(tester, find.byKey(const Key('menu-Torrent')));
    expect(find.text('Bajar'), findsNothing); // ya es el último
    await _tap(tester, find.text('Subir'));
    await pumpIo(tester);
    await expectSavedAddons(tester, dir, [
      'OpenSubtitles v3',
      'Torrent',
      'Cinemeta',
    ]);
  });

  group('agregar por URL', () {
    Future<void> openDialog(WidgetTester tester) async {
      final routes = defaultRoutes()
        ..['https://nuevo.example.com/manifest.json'] = manifestJson(
          'org.example.nuevo',
          'Nuevo',
        );
      await _openAddons(
        tester,
        dir,
        mockWorld(routes),
        urls: const [cinemetaUrl],
      );
      await _tap(tester, find.byKey(const Key('add-by-url')));
    }

    testWidgets(
      'una dirección que no es de un addon se explica sin llamar a la red',
      (tester) async {
        await openDialog(tester);

        await tester.enterText(find.byKey(const Key('add-addon-url')), 'hola');
        await _tap(tester, find.byKey(const Key('add-addon-submit')));
        expect(find.textContaining('no parece la de un addon'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('add-addon-url')), '  ');
        await _tap(tester, find.byKey(const Key('add-addon-submit')));
        expect(
          find.text('Pegá la URL del manifest del addon.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'un addon que no responde muestra el motivo y deja reintentar',
      (tester) async {
        await openDialog(tester);

        await tester.enterText(
          find.byKey(const Key('add-addon-url')),
          'https://caido.example.com/manifest.json',
        );
        await tester.tap(find.byKey(const Key('add-addon-submit')));
        await pumpUntil(
          tester,
          find.text('El addon respondió con un error (HTTP 404).'),
        );
        // Tras la falla se puede corregir y volver a probar.
        final field = tester.widget<TextField>(
          find.byKey(const Key('add-addon-url')),
        );
        expect(field.enabled, isTrue);
        final submit = tester.widget<FilledButton>(
          find.byKey(const Key('add-addon-submit')),
        );
        expect(submit.onPressed, isNotNull);
        expect(find.text('Agregando…'), findsNothing);
      },
    );

    testWidgets('uno repetido avisa que ya está instalado', (tester) async {
      await openDialog(tester);

      await tester.enterText(
        find.byKey(const Key('add-addon-url')),
        cinemetaUrl,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpUntil(tester, find.text('Ya tenés instalado Cinemeta.'));
    });

    testWidgets('uno nuevo se instala al final y se avisa', (tester) async {
      await openDialog(tester);

      await tester.enterText(
        find.byKey(const Key('add-addon-url')),
        'https://nuevo.example.com',
      );
      await tester.tap(find.byKey(const Key('add-addon-submit')));
      await pumpUntil(tester, find.text('Agregaste Nuevo.'));
      await pumpIo(tester);

      await expectSavedAddons(tester, dir, ['Cinemeta', 'Nuevo']);
      expect(find.byKey(const Key('add-addon-url')), findsNothing);
    });
  });

  testWidgets(
    'Importar desde Stremio o Nuvio reabre el asistente y Atrás vuelve',
    (tester) async {
      final client = mockWorld(defaultRoutes());
      await _openAddons(tester, dir, client);

      await _tap(tester, find.byKey(const Key('import-from-accounts')));
      expect(find.text('Traé tus addons'), findsOneWidget);

      await _tap(tester, find.text('Atrás'));
      expect(find.text('Traé tus addons'), findsNothing);
      expect(find.byKey(const Key('add-by-url')), findsOneWidget);
    },
  );
}
