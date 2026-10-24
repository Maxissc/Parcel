import 'dart:async';

import 'package:parcel_core/parcel_core.dart';
import 'package:test/test.dart';

const _es = AudioTrack(id: 'a1', language: 'spa', title: 'Castellano');
const _en = AudioTrack(id: 'a2', language: 'eng');
const _subEs = SubtitleTrack(id: 's1', language: 'spa', title: 'Español');

FakePlaybackEngine _newEngine() => FakePlaybackEngine(
  mediaDuration: const Duration(minutes: 10),
  audioTracks: const [_es, _en],
  subtitleTracks: const [_subEs],
);

void main() {
  late FakePlaybackEngine engine;

  setUp(() => engine = _newEngine());
  tearDown(() => engine.dispose());

  test('antes de abrir no hay nada cargado', () {
    expect(engine.state.playing, isFalse);
    expect(engine.state.duration, Duration.zero);
    expect(engine.state.audioTracks, isEmpty);
    expect(engine.state.selectedSubtitle, isNull);
    expect(engine.state.volume, 1.0);
  });

  test(
    'open carga el medio, empieza a reproducir y elige el primer audio',
    () async {
      await engine.open(
        PlaybackSource(
          url: 'http://x/video.mkv',
          startPosition: const Duration(seconds: 30),
        ),
      );

      expect(engine.state.playing, isTrue);
      expect(engine.state.buffering, isFalse);
      expect(engine.state.position, const Duration(seconds: 30));
      expect(engine.state.duration, const Duration(minutes: 10));
      expect(engine.state.audioTracks, [_es, _en]);
      expect(engine.state.selectedAudio, _es);
      expect(engine.state.selectedSubtitle, isNull);
      expect(engine.lastSource?.url, 'http://x/video.mkv');
    },
  );

  test('guarda los headers de la fuente', () async {
    await engine.open(
      PlaybackSource(url: 'http://x', headers: const {'Referer': 'r'}),
    );
    expect(engine.lastSource?.headers, {'Referer': 'r'});
  });

  test('play, pause y playOrPause cambian playing', () async {
    await engine.open(PlaybackSource(url: 'http://x'));
    await engine.pause();
    expect(engine.state.playing, isFalse);
    await engine.play();
    expect(engine.state.playing, isTrue);
    await engine.playOrPause();
    expect(engine.state.playing, isFalse);
    await engine.playOrPause();
    expect(engine.state.playing, isTrue);
  });

  test('seek queda dentro de 0 y la duración', () async {
    await engine.open(PlaybackSource(url: 'http://x'));
    await engine.seek(const Duration(minutes: 3));
    expect(engine.state.position, const Duration(minutes: 3));
    await engine.seek(const Duration(hours: 5));
    expect(engine.state.position, const Duration(minutes: 10));
    await engine.seek(const Duration(seconds: -4));
    expect(engine.state.position, Duration.zero);
  });

  test('setVolume queda entre 0 y 1', () async {
    await engine.setVolume(0.4);
    expect(engine.state.volume, 0.4);
    await engine.setVolume(3);
    expect(engine.state.volume, 1.0);
    await engine.setVolume(-1);
    expect(engine.state.volume, 0.0);
  });

  test('setAudioTrack elige la pista', () async {
    await engine.open(PlaybackSource(url: 'http://x'));
    await engine.setAudioTrack(_en);
    expect(engine.state.selectedAudio, _en);
  });

  test('setSubtitleTrack elige y null desactiva', () async {
    await engine.open(PlaybackSource(url: 'http://x'));
    await engine.setSubtitleTrack(_subEs);
    expect(engine.state.selectedSubtitle, _subEs);
    await engine.setSubtitleTrack(null);
    expect(engine.state.selectedSubtitle, isNull);
  });

  test(
    'addExternalSubtitle suma la pista, marcada como externa, y la elige',
    () async {
      await engine.open(PlaybackSource(url: 'http://x'));
      await engine.addExternalSubtitle(
        'http://x/sub.srt',
        title: 'Externo',
        language: 'eng',
      );

      final added = engine.state.subtitleTracks.last;
      expect(added.isExternal, isTrue);
      expect(added.title, 'Externo');
      expect(added.language, 'eng');
      expect(engine.state.selectedSubtitle, added);
      expect(engine.state.subtitleTracks.length, 2);
    },
  );

  test('tick avanza la posición y completa al llegar al final', () async {
    await engine.open(PlaybackSource(url: 'http://x'));
    engine.tick(const Duration(seconds: 5));
    expect(engine.state.position, const Duration(seconds: 5));
    expect(engine.state.completed, isFalse);

    engine.tick(const Duration(minutes: 20));
    expect(engine.state.position, const Duration(minutes: 10));
    expect(engine.state.completed, isTrue);
    expect(engine.state.playing, isFalse);
  });

  test('fail pone el error y open lo limpia', () async {
    await engine.open(PlaybackSource(url: 'http://x'));
    engine.fail('No se pudo conectar');
    expect(engine.state.error, 'No se pudo conectar');
    expect(engine.state.playing, isFalse);

    await engine.open(PlaybackSource(url: 'http://x'));
    expect(engine.state.error, isNull);
    expect(engine.state.playing, isTrue);
  });

  test('openError hace que open termine en error', () async {
    engine.openError = 'HTTP 404';
    await engine.open(PlaybackSource(url: 'http://x'));
    expect(engine.state.error, 'HTTP 404');
    expect(engine.state.playing, isFalse);
  });

  test('el stream emite cada cambio de estado', () async {
    final seen = <PlaybackState>[];
    final sub = engine.stream.listen(seen.add);
    await engine.open(PlaybackSource(url: 'http://x'));
    await engine.pause();
    await engine.play();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(seen.map((s) => s.playing), [true, false, true]);
    expect(seen.first.duration, const Duration(minutes: 10));
    expect(seen.first.audioTracks, const [_es, _en]);
    expect(seen.last, engine.state);
  });

  test('dispose cierra el stream y después no cambia el estado', () async {
    final done = Completer<void>();
    engine.stream.listen((_) {}, onDone: done.complete);
    await engine.dispose();
    await done.future.timeout(const Duration(seconds: 1));
    await engine.play();
    expect(engine.state.playing, isFalse);
  });

  test('PlaybackSource rechaza una URL vacía', () {
    expect(() => PlaybackSource(url: ''), throwsArgumentError);
  });
}
