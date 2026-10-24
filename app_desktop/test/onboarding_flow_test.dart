import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/providers.dart';

import 'support/accounts_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _fillAccount(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('account-email')),
    'persona@example.com',
  );
  await tester.enterText(find.byKey(const Key('account-password')), 'ok');
}

final _nuvioRows = [
  {
    'url': cinemetaUrl,
    'name': 'Cinemeta',
    'enabled': true,
    'sort_order': 0,
    'profile_id': 1,
  },
];

final _stremioAddons = [
  stremioEntry(cinemetaUrl, 'com.linvo.cinemeta', 'Cinemeta'),
];

/// Motor de migración que falla como si el disco se hubiera roto del todo.
class _BrokenMigrationService extends MigrationService {
  _BrokenMigrationService(super.repository);

  @override
  Future<MigrationReport> apply(
    MigrationPlan plan,
    Iterable<MigrationCandidate> selected,
  ) => throw const FileSystemException('disco roto', 'C:/secreto/addons.json');
}

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir());
  tearDown(() => dir.deleteSync(recursive: true));

  group('cancelar a mitad de un login', () {
    testWidgets('Nuvio: Atrás durante el login no llega a revisar y cierra la '
        'sesión', (tester) async {
      final calls = AccountCalls();
      final gate = Completer<void>();
      await pumpApp(
        tester,
        dir,
        nuvioWorld(calls: calls, rows: _nuvioRows, loginGate: gate.future),
      );
      await _tap(tester, find.byKey(const Key('source-nuvio')));
      await _fillAccount(tester);
      await _tap(tester, find.byKey(const Key('account-submit')));

      await _tap(tester, find.text('Atrás'));
      expect(find.text('Traé tus addons'), findsOneWidget);

      gate.complete();
      await pumpIo(tester);

      expect(find.text('Traé tus addons'), findsOneWidget);
      expect(find.byKey(const Key('import-button')), findsNothing);
      expect(calls.count('/auth/v1/logout'), 1);
      expect(calls.count('/rest/v1/addons'), 0);
    });

    testWidgets('Stremio con email: Atrás durante el login no llega a revisar '
        'y cierra la sesión', (tester) async {
      final calls = AccountCalls();
      final gate = Completer<void>();
      await pumpApp(
        tester,
        dir,
        stremioWorld(
          calls: calls,
          addons: _stremioAddons,
          pendingReads: -1,
          loginGate: gate.future,
        ),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await _tap(tester, find.text('Con email'));
      await tester.pump(const Duration(milliseconds: 400));
      await _fillAccount(tester);
      await _tap(tester, find.byKey(const Key('account-submit')));

      await _tap(tester, find.text('Atrás'));
      gate.complete();
      await pumpIo(tester);

      expect(find.text('Traé tus addons'), findsOneWidget);
      expect(find.byKey(const Key('import-button')), findsNothing);
      expect(calls.count('/api/logout'), 1);
      expect(calls.count('/api/addonCollectionGet'), 0);
    });

    testWidgets('Stremio con código: Atrás mientras trae los addons no llega a '
        'revisar', (tester) async {
      final calls = AccountCalls();
      final gate = Completer<void>();
      await pumpApp(
        tester,
        dir,
        stremioWorld(
          calls: calls,
          addons: _stremioAddons,
          collectionGate: gate.future,
        ),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await pumpUntil(tester, find.text('Trayendo tus addons…'));

      await _tap(tester, find.text('Atrás'));
      expect(find.text('Traé tus addons'), findsOneWidget);
      gate.complete();
      await pumpIo(tester);

      expect(find.text('Traé tus addons'), findsOneWidget);
      expect(find.byKey(const Key('import-button')), findsNothing);
      expect(calls.count('/api/logout'), 1);
    });
  });

  group('la sesión se cierra siempre', () {
    testWidgets('Stremio: si leer los addons falla, se cierra una vez', (
      tester,
    ) async {
      final calls = AccountCalls();
      await pumpApp(
        tester,
        dir,
        stremioWorld(
          calls: calls,
          addons: _stremioAddons,
          pendingReads: -1,
          collectionFails: true,
        ),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await _tap(tester, find.text('Con email'));
      await tester.pump(const Duration(milliseconds: 400));
      await _fillAccount(tester);
      await _tap(tester, find.byKey(const Key('account-submit')));
      await pumpUntil(tester, find.byKey(const Key('account-error')));

      expect(calls.count('/api/logout'), 1);
    });

    testWidgets('Nuvio: si leer los addons falla, se cierra una vez', (
      tester,
    ) async {
      final calls = AccountCalls();
      await pumpApp(
        tester,
        dir,
        nuvioWorld(calls: calls, rows: _nuvioRows, addonsFail: true),
      );
      await _tap(tester, find.byKey(const Key('source-nuvio')));
      await _fillAccount(tester);
      await _tap(tester, find.byKey(const Key('account-submit')));
      await pumpUntil(tester, find.byKey(const Key('account-error')));

      expect(calls.count('/auth/v1/logout'), 1);
    });
  });

  group('Stremio por código', () {
    testWidgets('pide un solo código por entrada a la pestaña', (tester) async {
      final calls = AccountCalls();
      await pumpApp(
        tester,
        dir,
        stremioWorld(calls: calls, addons: _stremioAddons, pendingReads: -1),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await pumpUntil(tester, find.byKey(const Key('link-code')));
      expect(calls.count('/api/v2/create'), 1);

      // Ir a «Con email» no pide otro código.
      await _tap(tester, find.text('Con email'));
      await tester.pump(const Duration(milliseconds: 400));
      await pumpIo(tester);
      expect(calls.count('/api/v2/create'), 1);

      // Volver a «Con código» es una entrada nueva: uno más, no dos.
      await _tap(tester, find.text('Con código'));
      await tester.pump(const Duration(milliseconds: 400));
      await pumpUntil(tester, find.byKey(const Key('link-code')));
      await pumpIo(tester);
      expect(calls.count('/api/v2/create'), 2);

      await _tap(tester, find.text('Cancelar'));
    });

    testWidgets('al pasar a «Con email» el foco queda en el campo de email', (
      tester,
    ) async {
      await pumpApp(
        tester,
        dir,
        stremioWorld(
          calls: AccountCalls(),
          addons: _stremioAddons,
          pendingReads: -1,
        ),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await pumpUntil(tester, find.byKey(const Key('link-code')));

      await _tap(tester, find.text('Con email'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final email = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('account-email')),
          matching: find.byType(EditableText),
        ),
      );
      expect(email.focusNode.hasFocus, isTrue);
    });

    testWidgets('si falla leer los addons tras aprobar, el título lo dice', (
      tester,
    ) async {
      await pumpApp(
        tester,
        dir,
        stremioWorld(
          calls: AccountCalls(),
          addons: _stremioAddons,
          collectionFails: true,
        ),
      );
      await _tap(tester, find.byKey(const Key('source-stremio')));
      await pumpUntil(tester, find.text('No pudimos traer tus addons'));

      expect(find.text('No pudimos conseguir el código'), findsNothing);
    });
  });

  testWidgets('Nuvio con un perfil: desde Revisar, Atrás y Atrás llegan a '
      'Bienvenida', (tester) async {
    await pumpApp(
      tester,
      dir,
      nuvioWorld(calls: AccountCalls(), rows: _nuvioRows),
    );
    await _tap(tester, find.byKey(const Key('source-nuvio')));
    await _fillAccount(tester);
    await _tap(tester, find.byKey(const Key('account-submit')));
    await pumpUntil(tester, find.byKey(const Key('import-button')));

    await _tap(tester, find.text('Atrás'));
    expect(find.byKey(const Key('account-email')), findsOneWidget);

    await _tap(tester, find.text('Atrás'));
    expect(find.text('Traé tus addons'), findsOneWidget);
    expect(find.byKey(const Key('account-email')), findsNothing);
  });

  testWidgets('si instalar falla por completo, sale de «Instalando» y deja '
      'reintentar', (tester) async {
    await pumpApp(
      tester,
      dir,
      mockWorld(defaultRoutes()),
      overrides: [
        migrationServiceProvider.overrideWith(
          (ref) => _BrokenMigrationService(ref.watch(addonRepositoryProvider)),
        ),
      ],
    );
    await _tap(tester, find.byKey(const Key('source-paste')));
    await tester.enterText(find.byKey(const Key('paste-text')), cinemetaUrl);
    await tester.pump();
    await _tap(tester, find.byKey(const Key('paste-continue')));
    await _tap(tester, find.byKey(const Key('import-button')));
    await pumpUntil(tester, find.byKey(const Key('go-home')));

    expect(find.text('1 falló'), findsOneWidget);
    expect(find.text('No se pudo guardar en disco.'), findsOneWidget);
    expect(find.textContaining('secreto'), findsNothing);
    expect(find.byKey(const Key('retry-failed')), findsOneWidget);
  });

  testWidgets('si no se puede guardar que terminó, «Ir al inicio» avisa', (
    tester,
  ) async {
    await pumpApp(tester, dir, mockWorld(defaultRoutes()));
    await _tap(tester, find.byKey(const Key('use-defaults')));
    await pumpUntil(tester, find.byKey(const Key('go-home')));
    // Un directorio donde va el archivo temporal hace fallar la escritura.
    Directory('${dir.path}/settings.json.tmp').createSync();

    await _tap(tester, find.byKey(const Key('go-home')));
    await pumpUntil(
      tester,
      find.text('No se pudo guardar que terminaste. Probá de nuevo.'),
    );

    expect(find.byKey(const Key('go-home')), findsOneWidget);
  });

  testWidgets('Esc durante el login de Nuvio también cancela', (tester) async {
    final calls = AccountCalls();
    final gate = Completer<void>();
    await pumpApp(
      tester,
      dir,
      nuvioWorld(calls: calls, rows: _nuvioRows, loginGate: gate.future),
    );
    await _tap(tester, find.byKey(const Key('source-nuvio')));
    await _fillAccount(tester);
    await _tap(tester, find.byKey(const Key('account-submit')));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));
    gate.complete();
    await pumpIo(tester);

    expect(find.text('Traé tus addons'), findsOneWidget);
    expect(calls.count('/auth/v1/logout'), 1);
  });
}
