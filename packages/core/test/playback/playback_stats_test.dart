import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

void main() {
  late FakePlaybackEngine engine;

  setUp(() => engine = FakePlaybackEngine());
  tearDown(() => engine.dispose());

  test('los datos técnicos arrancan vacíos y se actualizan por el stream', () {
    expect(engine.stats, PlaybackStats.empty);
    const stats = PlaybackStats(
      videoWidth: 3840,
      videoHeight: 2160,
      fps: 23.976,
      dynamicRange: DynamicRange.hdr10,
      audioChannels: 6,
      bufferAhead: Duration(seconds: 25),
    );
    expectLater(engine.statsStream, emits(stats));
    engine.emitStats(stats);
    expect(engine.stats, stats);
    expect(engine.stats.dynamicRange.shortLabel, 'HDR');
  });

  test('un retraso de subtítulos queda guardado y se reinicia al abrir', () async {
    await engine.setSubtitleDelay(const Duration(milliseconds: -300));
    expect(engine.subtitleDelay, const Duration(milliseconds: -300));
    await engine.open(PlaybackSource(url: 'http://x/v.mkv'));
    expect(engine.subtitleDelay, Duration.zero);
  });

  test('con stallOnOpen el video queda cargando sin duración', () async {
    engine.stallOnOpen = true;
    await engine.open(PlaybackSource(url: 'http://x/v.mkv'));
    expect(engine.state.buffering, isTrue);
    expect(engine.state.duration, Duration.zero);
    expect(engine.openCount, 1);
  });
}
