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

  test('sin PARCEL_DIAG no hay configuración', () {
    expect(DiagnosticsConfig.fromEnvironment({}), isNull);
  });
}
