import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/app/diagnostics/diag_log.dart';
import 'package:parcel_desktop/app/diagnostics/playback_diagnostics.dart';

import 'support/pump.dart';
import 'support/test_env.dart';

const _brokenUrl = 'https://roto.example.com/token-secreto/manifest.json';

void main() {
  late Directory dir;

  setUp(() => dir = makeTempDir());
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'PARCEL_DIAG_PASTE llega a la configuración (solo con PARCEL_DIAG=1)',
    () {
      // fromEnvironment solo devuelve algo en debug, que es como corren los tests.
      final config = DiagnosticsConfig.fromEnvironment({
        'PARCEL_DIAG': '1',
        'PARCEL_DIAG_PASTE': 'https://a.example.com https://b.example.com',
      });
      expect(config?.paste, 'https://a.example.com https://b.example.com');
      expect(
        DiagnosticsConfig.fromEnvironment({'PARCEL_DIAG_PASTE': 'x'}),
        isNull,
      );
    },
  );

  test('DiagLog antepone [diag] y el apagado no escribe nada', () {
    final lines = <String>[];
    DiagLog(sink: lines.add).log('hola');
    const DiagLog.disabled().log('no sale');
    expect(lines, ['[diag] hola']);
  });

  testWidgets(
    'el diagnóstico pega la lista, confirma y deja el informe en el log',
    (tester) async {
      final lines = <String>[];
      await pumpApp(
        tester,
        dir,
        mockWorld(defaultRoutes()),
        overrides: [
          diagnosticsConfigProvider.overrideWithValue(
            const DiagnosticsConfig(
              paste: '$cinemetaUrl $subtitlesUrl $_brokenUrl',
            ),
          ),
          diagLogProvider.overrideWithValue(DiagLog(sink: lines.add)),
        ],
      );
      await pumpUntil(tester, find.byKey(const Key('go-home')));

      final log = lines.join('\n');
      expect(lines, everyElement(startsWith('[diag] ')));
      expect(log, contains('onboarding paso=welcome'));
      expect(log, contains('onboarding fuente=pasted candidatos=3'));
      expect(log, contains('onboarding paso=progress'));
      expect(
        log,
        contains('onboarding informe instalados=2 yaEstaban=0 fallaron=1'),
      );
      // El que falló sale con su host y su motivo, nunca con la URL completa.
      expect(
        log,
        contains(
          'roto.example.com resultado=failed '
          'motivo="El addon respondió con un error (HTTP 404)."',
        ),
      );
      expect(log, isNot(contains('token-secreto')));
      expect(log, isNot(contains('/manifest.json')));
    },
  );
}
