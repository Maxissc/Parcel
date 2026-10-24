import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/accounts_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _brokenUrl = 'https://roto.example.com/token-secreto/manifest.json';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pastePasoYRevisar(WidgetTester tester, String text) async {
  await _tap(tester, find.byKey(const Key('source-paste')));
  await tester.enterText(find.byKey(const Key('paste-text')), text);
  await tester.pump();
  await _tap(tester, find.byKey(const Key('paste-continue')));
}

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir());
  tearDown(() => dir.deleteSync(recursive: true));

  group('bienvenida', () {
    testWidgets('ofrece Stremio, Nuvio, Pegar lista y los addons básicos', (
      tester,
    ) async {
      await pumpApp(tester, dir, mockWorld(defaultRoutes()));

      expect(find.text('Traé tus addons'), findsOneWidget);
      expect(find.text('Stremio'), findsOneWidget);
      expect(find.text('Nuvio'), findsOneWidget);
      expect(find.text('Pegar lista'), findsOneWidget);
      expect(find.text('Empezar con los addons básicos'), findsOneWidget);
    });

    testWidgets('los addons básicos instalan Cinemeta y OpenSubtitles v3', (
      tester,
    ) async {
      await pumpApp(tester, dir, mockWorld(defaultRoutes()));

      await _tap(tester, find.byKey(const Key('use-defaults')));
      await pumpUntil(tester, find.byKey(const Key('go-home')));

      expect(find.text('2 instalados'), findsOneWidget);
      await expectSavedAddons(tester, dir, ['Cinemeta', 'OpenSubtitles v3']);
    });
  });

  group('pegar lista', () {
    testWidgets('pegar → revisar → importar instala y muestra el informe', (
      tester,
    ) async {
      final routes = defaultRoutes();
      await pumpApp(tester, dir, mockWorld(routes));

      await _tap(tester, find.byKey(const Key('source-paste')));
      expect(
        find.text(
          'Todavía no detectamos ninguna URL. Ctrl+Enter para revisar.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('paste-text')),
        '$cinemetaUrl\n$subtitlesUrl, $_brokenUrl',
      );
      await tester.pump();
      expect(
        find.text('3 URLs detectadas. Ctrl+Enter para revisar.'),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('paste-continue')));

      // Revisar: nunca se ve la URL completa (puede traer tokens).
      expect(find.text('Importar 3 addons'), findsOneWidget);
      expect(find.text('roto.example.com'), findsOneWidget);
      expect(find.textContaining('token-secreto'), findsNothing);

      await _tap(tester, find.byKey(const Key('import-button')));
      await pumpUntil(tester, find.byKey(const Key('go-home')));

      expect(find.text('2 instalados'), findsOneWidget);
      expect(find.text('1 falló'), findsOneWidget);
      expect(
        find.text('El addon respondió con un error (HTTP 404).'),
        findsOneWidget,
      );
      expect(find.textContaining('token-secreto'), findsNothing);
      await expectSavedAddons(tester, dir, ['Cinemeta', 'OpenSubtitles v3']);

      // Reintentar los que fallaron: ahora el addon responde.
      routes[_brokenUrl] = manifestJson('org.example.roto', 'Roto');
      await _tap(tester, find.byKey(const Key('retry-failed')));
      await pumpUntil(tester, find.text('3 instalados'));
      expect(find.text('0 fallaron'), findsOneWidget);
      expect(find.byKey(const Key('retry-failed')), findsNothing);
      await expectSavedAddons(tester, dir, [
        'Cinemeta',
        'OpenSubtitles v3',
        'Roto',
      ]);

      // «Ir al inicio» recuerda que el asistente se completó y abre la app.
      await _tap(tester, find.byKey(const Key('go-home')));
      await pumpUntil(tester, find.byType(NavigationRail));
      await pumpIo(tester);
      expect(
        File('${dir.path}/settings.json').readAsStringSync(),
        contains('"onboardingCompleted":true'),
      );
    });

    testWidgets('lo que ya está instalado queda sin tildar', (tester) async {
      final client = mockWorld(defaultRoutes());
      await seedData(tester, dir, client, urls: [cinemetaUrl]);
      await pumpApp(tester, dir, client);
      tester.view.physicalSize = const Size(1280, 1800);
      await _tap(
        tester,
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Ajustes'),
        ),
      );
      await _tap(tester, find.text('Volver a correr el asistente'));
      await _pastePasoYRevisar(tester, '$cinemetaUrl $subtitlesUrl');

      expect(find.text('Ya instalado'), findsOneWidget);
      expect(find.text('Importar 1 addon'), findsOneWidget);
    });

    testWidgets('Seleccionar todo y Ninguno cambian el botón de importar', (
      tester,
    ) async {
      await pumpApp(tester, dir, mockWorld(defaultRoutes()));
      await _pastePasoYRevisar(tester, '$cinemetaUrl $subtitlesUrl');
      expect(find.text('Importar 2 addons'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('select-none')));
      final button = find.byKey(const Key('import-button'));
      expect(find.text('Importar 0 addons'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);

      await _tap(tester, find.byKey(const Key('select-all')));
      expect(find.text('Importar 2 addons'), findsOneWidget);
    });

    testWidgets('Esc vuelve un paso', (tester) async {
      await pumpApp(tester, dir, mockWorld(defaultRoutes()));
      await _tap(tester, find.byKey(const Key('source-paste')));
      expect(find.byKey(const Key('paste-text')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('paste-text')), findsNothing);
      expect(find.text('Traé tus addons'), findsOneWidget);
    });
  });

  group('Stremio por código', () {
    final addons = [
      stremioEntry(cinemetaUrl, 'com.linvo.cinemeta', 'Cinemeta'),
      stremioEntry(torrentUrl, 'org.example.torrent', 'Torrent'),
      {
        'transportUrl': 'http://127.0.0.1:11470/local-addon/manifest.json',
        'manifest': manifestJson('org.stremio.local', 'Local Files'),
      },
    ];

    testWidgets('muestra el código y, aprobado, pasa a revisar', (
      tester,
    ) async {
      final calls = AccountCalls();
      final opened = <Uri>[];
      await pumpApp(
        tester,
        dir,
        stremioWorld(calls: calls, addons: addons, pendingReads: 1),
        openedUrls: opened,
      );

      await _tap(tester, find.byKey(const Key('source-stremio')));
      await pumpUntil(tester, find.byKey(const Key('link-code')));
      expect(find.text('ABCD'), findsOneWidget);
      expect(find.textContaining('Esperando aprobación…'), findsOneWidget);
      expect(find.textContaining('5:00'), findsOneWidget);
      expect(
        find.text(
          'Entrá con tu cuenta de Stremio en el navegador y aprobá el código.',
        ),
        findsOneWidget,
      );

      await _tap(tester, find.text('Abrir en el navegador'));
      expect(opened, [Uri.parse(stremioLinkUrl)]);

      // La segunda consulta (a los 3 s) ya está aprobada.
      await tester.pump(const Duration(seconds: 3));
      await pumpUntil(tester, find.byKey(const Key('import-button')));

      expect(find.text('Cinemeta'), findsOneWidget);
      expect(find.text('Torrent'), findsOneWidget);
      expect(find.text('Solo funciona dentro de Stremio'), findsOneWidget);
      expect(find.text('Importar 2 addons'), findsOneWidget);
      expect(find.textContaining('secret-token'), findsNothing);
      // La sesión se cierra apenas se leen los addons.
      expect(calls.count('/api/logout'), 1);
    });

    testWidgets('cuando el código vence ofrece generar otro', (tester) async {
      final calls = AccountCalls();
      await pumpApp(
        tester,
        dir,
        stremioWorld(calls: calls, addons: addons, pendingReads: -1),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await pumpUntil(tester, find.byKey(const Key('link-code')));

      await tester.pump(const Duration(minutes: 5, seconds: 5));
      await tester.pump();

      expect(find.text('El código venció'), findsOneWidget);
      await _tap(tester, find.text('Generar otro'));
      await pumpUntil(tester, find.byKey(const Key('link-code')));
      expect(calls.count('/api/v2/create'), 2);
      // Dejar el árbol limpio frena el polling.
      await _tap(tester, find.text('Cancelar'));
    });

    testWidgets('Cancelar detiene las consultas', (tester) async {
      final calls = AccountCalls();
      await pumpApp(
        tester,
        dir,
        stremioWorld(calls: calls, addons: addons, pendingReads: -1),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await pumpUntil(tester, find.byKey(const Key('link-code')));
      await tester.pump(const Duration(seconds: 3));
      expect(calls.count('/api/v2/read'), greaterThan(1));

      await _tap(tester, find.text('Cancelar'));
      final before = calls.count('/api/v2/read');
      await tester.pump(const Duration(seconds: 30));

      expect(find.text('Traé tus addons'), findsOneWidget);
      expect(calls.count('/api/v2/read'), before);
    });
  });

  group('cuentas con email', () {
    testWidgets('Stremio: una contraseña incorrecta se explica bajo el campo', (
      tester,
    ) async {
      final calls = AccountCalls();
      await pumpApp(
        tester,
        dir,
        stremioWorld(
          calls: calls,
          addons: const [],
          pendingReads: -1,
          loginError: {'code': 3, 'wrongPassphrase': true},
        ),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await _tap(tester, find.text('Con email'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Si entrás a Stremio con Google o Facebook, usá el código.'),
        findsOneWidget,
      );

      // Campos vacíos: se avisa sin llamar a Stremio.
      await _tap(tester, find.byKey(const Key('account-submit')));
      expect(find.text('Escribí tu email.'), findsOneWidget);
      expect(find.text('Escribí tu contraseña.'), findsOneWidget);
      expect(calls.count('/api/login'), 0);

      await tester.enterText(
        find.byKey(const Key('account-email')),
        'persona@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('account-password')),
        'incorrecta',
      );
      await _tap(tester, find.byKey(const Key('account-submit')));
      await pumpUntil(tester, find.text('La contraseña es incorrecta.'));

      expect(find.text('Escribí tu email.'), findsNothing);
      // Se puede volver a intentar.
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('account-submit')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('Stremio con email trae los addons y cierra la sesión', (
      tester,
    ) async {
      final calls = AccountCalls();
      await pumpApp(
        tester,
        dir,
        stremioWorld(
          calls: calls,
          addons: [stremioEntry(cinemetaUrl, 'com.linvo.cinemeta', 'Cinemeta')],
          pendingReads: -1, // el código no se aprueba: se entra con email
        ),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await _tap(tester, find.text('Con email'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byKey(const Key('account-email')),
        'persona@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('account-password')),
        'secreta',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpUntil(tester, find.byKey(const Key('import-button')));

      expect(find.text('Cinemeta'), findsOneWidget);
      expect(calls.count('/api/logout'), 1);
    });

    testWidgets('Nuvio: credenciales inválidas muestran el mensaje', (
      tester,
    ) async {
      await pumpApp(
        tester,
        dir,
        nuvioWorld(calls: AccountCalls(), rows: const [], badCredentials: true),
      );
      await _tap(tester, find.byKey(const Key('source-nuvio')));
      // El foco inicial está en el email.
      final email = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('account-email')),
          matching: find.byType(EditableText),
        ),
      );
      expect(email.focusNode.hasFocus, isTrue);

      await tester.enterText(
        find.byKey(const Key('account-email')),
        'persona@example.com',
      );
      await tester.enterText(find.byKey(const Key('account-password')), 'mal');
      await _tap(tester, find.byKey(const Key('account-submit')));
      await pumpUntil(
        tester,
        find.text('El email o la contraseña no son correctos.'),
      );
    });

    testWidgets(
      'Nuvio con dos perfiles pide elegir el perfil antes de revisar',
      (tester) async {
        final calls = AccountCalls();
        await pumpApp(
          tester,
          dir,
          nuvioWorld(
            calls: calls,
            rows: [
              {
                'url': cinemetaUrl,
                'name': 'Cinemeta',
                'enabled': true,
                'sort_order': 0,
                'profile_id': 1,
              },
              {
                'url': torrentUrl,
                'name': 'Torrent',
                'enabled': false,
                'sort_order': 1,
                'profile_id': 1,
              },
              {
                'url': subtitlesUrl,
                'name': 'OpenSubtitles v3',
                'enabled': true,
                'sort_order': 0,
                'profile_id': 2,
              },
            ],
          ),
        );
        await _tap(tester, find.byKey(const Key('source-nuvio')));
        await tester.enterText(
          find.byKey(const Key('account-email')),
          'persona@example.com',
        );
        await tester.enterText(find.byKey(const Key('account-password')), 'ok');
        await _tap(tester, find.byKey(const Key('account-submit')));
        await pumpUntil(tester, find.byKey(const Key('profile-continue')));

        expect(find.text('Perfil 1'), findsOneWidget);
        expect(find.text('2 addons'), findsOneWidget);
        expect(find.text('Perfil 2'), findsOneWidget);
        expect(calls.count('/auth/v1/logout'), 1);

        await _tap(tester, find.byKey(const Key('profile-2')));
        await _tap(tester, find.byKey(const Key('profile-continue')));

        expect(find.text('OpenSubtitles v3'), findsOneWidget);
        expect(find.text('Cinemeta'), findsNothing);
        expect(find.text('Importar 1 addon'), findsOneWidget);

        // Atrás vuelve al selector de perfil.
        await _tap(tester, find.text('Atrás'));
        expect(find.byKey(const Key('profile-continue')), findsOneWidget);
      },
    );

    testWidgets('Nuvio: lo desactivado entra sin tildar y con su aviso', (
      tester,
    ) async {
      await pumpApp(
        tester,
        dir,
        nuvioWorld(
          calls: AccountCalls(),
          rows: [
            {
              'url': cinemetaUrl,
              'name': 'Cinemeta',
              'enabled': true,
              'sort_order': 0,
              'profile_id': 1,
            },
            {
              'url': torrentUrl,
              'name': 'Torrent',
              'enabled': false,
              'sort_order': 1,
              'profile_id': 1,
            },
          ],
        ),
      );
      await _tap(tester, find.byKey(const Key('source-nuvio')));
      await tester.enterText(
        find.byKey(const Key('account-email')),
        'persona@example.com',
      );
      await tester.enterText(find.byKey(const Key('account-password')), 'ok');
      await _tap(tester, find.byKey(const Key('account-submit')));
      await pumpUntil(tester, find.byKey(const Key('import-button')));

      expect(find.text('Desactivado en Nuvio'), findsOneWidget);
      expect(find.text('Importar 1 addon'), findsOneWidget);
    });
  });
}
