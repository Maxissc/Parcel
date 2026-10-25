import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/diagnostics/playback_diagnostics.dart';

void main() {
  test('registra pistas, elección y errores del motor', () async {
    final engine = FakePlaybackEngine(
      mediaDuration: const Duration(minutes: 1),
      audioTracks: const [
        AudioTrack(id: '1', language: 'spa', title: 'Castellano'),
        AudioTrack(id: '2', language: 'eng'),
      ],
      subtitleTracks: const [SubtitleTrack(id: '3', language: 'spa')],
    );
    final lines = <String>[];
    final diag = PlaybackDiagnostics(
      engine,
      config: const DiagnosticsConfig(),
      sink: lines.add,
    )..start();

    await engine.open(PlaybackSource(url: 'http://x'));
    await engine.setAudioTrack(engine.state.audioTracks.last);
    await engine.addExternalSubtitle('http://x/s.srt', title: 'Ext');
    engine.fail('boom');
    await Future<void>.delayed(Duration.zero);
    diag.stop();
    await engine.dispose();

    final log = lines.join('\n');
    expect(log, contains('PISTAS_AUDIO 2'));
    expect(log, contains('Castellano'));
    expect(log, contains('PISTAS_SUBTITULOS 1'));
    expect(log, contains('AUDIO_ELEGIDO AudioTrack(2 eng null)'));
    expect(log, contains('PISTAS_SUBTITULOS 2'));
    expect(log, contains('externa'));
    expect(log, contains('ERROR boom'));
  });

  test('un error con una URL no deja el token en el log', () async {
    final engine = FakePlaybackEngine(
      mediaDuration: const Duration(minutes: 1),
    );
    final lines = <String>[];
    final diag = PlaybackDiagnostics(
      engine,
      config: const DiagnosticsConfig(),
      sink: lines.add,
    )..start();

    engine.fail(
      'Failed to open http://127.0.0.1:7000/no-existe?token=SECRETO.',
    );
    await Future<void>.delayed(Duration.zero);
    diag.stop();
    await engine.dispose();

    final log = lines.join('\n');
    expect(log, contains('ERROR'));
    expect(log, isNot(contains('SECRETO')));
    expect(log, contains('127.0.0.1:7000'));
  });

  test('sin PARCEL_DIAG no hay configuración', () {
    expect(DiagnosticsConfig.fromEnvironment({}), isNull);
  });

  group('resumen de cuadros', () {
    Duration ms(int v) => Duration(milliseconds: v);

    test('cuenta lentos por armado o por raster, no por el total', () {
      final line = frameSummary([
        (build: ms(5), raster: ms(5)),
        // Cada etapa entra en 16,7 ms aunque juntas pasen: no es lento.
        (build: ms(12), raster: ms(12)),
        (build: ms(20), raster: ms(4)),
        (build: ms(3), raster: ms(30)),
      ], ms(5000));
      expect(line, contains('cuadros: 4 en 5.0 s'));
      expect(line, contains('más de 16,7 ms: 2'));
      expect(line, contains('armado medio 10.0 ms (peor 20.0)'));
      expect(line, contains('raster medio 12.8 ms (peor 30.0)'));
    });

    test('dice el tiempo real del tramo, no siempre 5 s', () {
      final line = frameSummary([(build: ms(5), raster: ms(5))], ms(2300));
      expect(line, contains('en 2.3 s'));
      expect(line, isNot(contains('en 5')));
    });
  });
}
