import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/router.dart';
import 'package:parcel_desktop/data/platform.dart';
import 'package:parcel_desktop/data/progress_providers.dart';
import 'package:parcel_desktop/data/providers.dart';
import 'package:parcel_desktop/features/player/play_item.dart';
import 'package:parcel_desktop/features/player/player_route.dart';
import 'package:parcel_desktop/features/player/player_screen.dart';
import 'package:parcel_desktop/features/player/track_preferences.dart';

import 'support/catalog_world.dart';
import 'support/fakes.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _matrixId = 'tt0133093';
const _opensubsMatrix = 'opensubtitles-v3.strem.io/subtitles/movie/$_matrixId';

Meta _matrix() => Meta.fromJson(movieMeta(_matrixId, 'The Matrix'));
Meta _breakingBad() => Meta.fromJson(seriesMeta('tt0903747', 'Breaking Bad'));

AddonStream _stream({Map<String, dynamic> hints = const {}}) =>
    AddonStream.fromJson({
      'url': 'http://media.example.com/video.mkv',
      'name': '1080p',
      'behaviorHints': hints,
    });

PlayItem _movieItem({Map<String, dynamic> hints = const {}}) => PlayItem(
  meta: _matrix(),
  stream: _stream(hints: hints),
  addonUrl: streamsAddonUrl,
);

PlayItem _episodeItem(int index) {
  final meta = _breakingBad();
  return PlayItem(
    meta: meta,
    video: meta.videos[index],
    stream: _stream(hints: {'bingeGroup': 'bg-1080'}),
    addonUrl: streamsAddonUrl,
  );
}

PlaybackProgress _saved({
  Duration position = const Duration(minutes: 2),
  String videoId = _matrixId,
  String type = 'movie',
  String metaId = _matrixId,
}) => PlaybackProgress(
  type: type,
  metaId: metaId,
  videoId: videoId,
  position: position,
  duration: const Duration(minutes: 10),
  name: 'The Matrix',
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  late Directory dir;
  late CatalogWorld world;
  late FakeWindowService window;

  setUp(() {
    dir = makeTempDir();
    world = CatalogWorld();
    window = FakeWindowService();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FakePlaybackEngine engine({
    List<AudioTrack> audio = const [AudioTrack(id: '1', language: 'eng')],
    List<SubtitleTrack> subtitles = const [],
  }) => FakePlaybackEngine(
    mediaDuration: const Duration(minutes: 10),
    audioTracks: audio,
    subtitleTracks: subtitles,
  );

  /// Abre la app con los addons de prueba y empuja el reproductor.
  Future<void> openPlayer(
    WidgetTester tester,
    FakePlaybackEngine fake,
    PlayerArgs args, {
    PlaybackProgress? saved,
    String? subtitleLanguage,
    String? audioLanguage,
  }) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: [cinemetaUrl, subtitlesUrl, streamsAddonUrl],
      onboardingCompleted: true,
      audioLanguage: audioLanguage,
      subtitleLanguage: subtitleLanguage,
      progress: [?saved],
    );
    await pumpApp(
      tester,
      dir,
      world.client,
      overrides: [playbackEngineFactoryProvider.overrideWithValue(() => fake)],
      window: window,
    );
    routerOf(tester).push(Routes.player, extra: args);
    await pumpIo(tester, ticks: 4);
  }

  /// Sale del reproductor con Esc. La ruta lo abre en pantalla completa, así
  /// que el primer Esc la deja y el segundo vuelve.
  Future<void> leavePlayer(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpIo(tester, ticks: 3);
      if (find.byKey(const Key('player-controls')).evaluate().isEmpty) break;
    }
    // Deja terminar la escritura del progreso antes de borrar la carpeta.
    await pumpIo(tester, ticks: 12);
  }

  PlaybackProgress? stored(WidgetTester tester, [String id = _matrixId]) =>
      containerOf(tester)
          .read(progressRepositoryProvider)
          .get('movie', _matrixId, id);

  testWidgets('guarda el progreso al pausar y al salir', (tester) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(url: 'http://media.example.com/video.mkv', item: _movieItem()),
    );
    expect(stored(tester), isNull);

    fake.tick(const Duration(minutes: 2));
    await tester.pump();
    expect(stored(tester), isNull, reason: 'mientras reproduce no guarda');

    await fake.pause();
    await tester.pump();
    final onPause = stored(tester)!;
    expect(onPause.position, const Duration(minutes: 2));
    expect(onPause.duration, const Duration(minutes: 10));
    expect(onPause.name, 'The Matrix');

    await fake.play();
    fake.tick(const Duration(minutes: 1));
    await tester.pump();
    await leavePlayer(tester);
    expect(stored(tester)!.position, const Duration(minutes: 3));
    expect(find.byKey(const Key('player-controls')), findsNothing);
    await pumpIo(tester);
  });

  testWidgets('cerrar la ventana con el video abierto guarda la posición', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(url: 'http://media.example.com/video.mkv', item: _movieItem()),
    );
    fake.tick(const Duration(minutes: 4));
    await tester.pump();
    expect(stored(tester), isNull, reason: 'mientras reproduce no guarda');

    // Como el cierre de la ventana: guarda y espera a que se escriba el archivo.
    var closed = false;
    unawaited(window.beforeClose!().then((_) => closed = true));
    await pumpIo(tester, ticks: 20);
    expect(closed, isTrue);

    expect(stored(tester)!.position, const Duration(minutes: 4));
    final onDisk = File('${dir.path}/progress.json').readAsStringSync();
    expect(onDisk, contains('"tt0133093"'));
    await leavePlayer(tester);
  });

  testWidgets('si no se puede escribir el progreso, la reproducción sigue', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(url: 'http://media.example.com/video.mkv', item: _movieItem()),
    );
    // Un directorio donde va el archivo temporal hace fallar la escritura.
    Directory('${dir.path}/progress.json.tmp').createSync();
    fake.tick(const Duration(minutes: 2));
    await tester.pump();

    await fake.pause();
    await pumpIo(tester, ticks: 10);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('player-controls')), findsOneWidget);
    expect(stored(tester)!.position, const Duration(minutes: 2));
    Directory('${dir.path}/progress.json.tmp').deleteSync();
    await leavePlayer(tester);
  });

  testWidgets('cerrar la ventana sin reproductor no guarda nada', (
    tester,
  ) async {
    await seedData(tester, dir, world.client, onboardingCompleted: true);
    await pumpApp(tester, dir, world.client, window: window);

    var closed = false;
    unawaited(window.beforeClose!().then((_) => closed = true));
    await pumpIo(tester, ticks: 20);
    expect(closed, isTrue);

    expect(File('${dir.path}/progress.json').existsSync(), isFalse);
  });

  testWidgets('Esc en «Ya empezaste esto» vuelve sin reproducir', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(url: 'http://media.example.com/video.mkv', item: _movieItem()),
      saved: _saved(),
    );
    expect(find.text('Ya empezaste esto'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpIo(tester, ticks: 10);

    expect(find.text('Ya empezaste esto'), findsNothing);
    expect(find.byKey(const Key('player-controls')), findsNothing);
    expect(fake.lastSource, isNull, reason: 'no se reprodujo nada');
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('guarda el progreso cada 10 segundos mientras reproduce', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(url: 'http://media.example.com/video.mkv', item: _movieItem()),
    );
    fake.tick(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 11));

    expect(stored(tester)!.position, const Duration(minutes: 1));
    await leavePlayer(tester);
  });

  testWidgets('salir enseguida no pisa el progreso que había', (tester) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(url: 'http://media.example.com/video.mkv', item: _movieItem()),
      saved: _saved(),
    );
    await tester.tap(find.text('Desde el principio'));
    await pumpIo(tester, ticks: 3);
    fake.tick(const Duration(seconds: 2));
    await tester.pump();
    await leavePlayer(tester);

    expect(stored(tester)!.position, const Duration(minutes: 2));
  });

  testWidgets('con progreso guardado pregunta si continuar', (tester) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(url: 'http://media.example.com/video.mkv', item: _movieItem()),
      saved: _saved(),
    );

    expect(find.text('Ya empezaste esto'), findsOneWidget);
    expect(fake.lastSource, isNull, reason: 'espera la respuesta');
    await tester.tap(find.text('Continuar desde 2:00'));
    await pumpIo(tester, ticks: 3);

    expect(fake.lastSource!.startPosition, const Duration(minutes: 2));
    await leavePlayer(tester);
  });

  testWidgets('«Desde el principio» arranca en cero', (tester) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(url: 'http://media.example.com/video.mkv', item: _movieItem()),
      saved: _saved(),
    );

    await tester.tap(find.text('Desde el principio'));
    await pumpIo(tester, ticks: 3);

    expect(fake.lastSource!.startPosition, Duration.zero);
    await leavePlayer(tester);
  });

  testWidgets('si el usuario eligió «Continuar» retoma sin preguntar', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(
        url: 'http://media.example.com/video.mkv',
        item: _movieItem(),
        resume: ResumeMode.resume,
      ),
      saved: _saved(),
    );

    expect(find.text('Ya empezaste esto'), findsNothing);
    expect(fake.lastSource!.startPosition, const Duration(minutes: 2));
    await leavePlayer(tester);
  });

  testWidgets('abre el video con los headers que pide el stream', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(
        url: 'http://media.example.com/video.mkv',
        headers: const {'Referer': 'http://origen.example.com'},
        item: _movieItem(),
      ),
    );

    expect(fake.lastSource!.headers, {'Referer': 'http://origen.example.com'});
    await leavePlayer(tester);
  });

  group('subtítulos y pistas', () {
    setUp(() {
      world.routes['$_opensubsMatrix/videoHash=abc&videoSize=100&filename=m.mkv.json'] =
          {
            'subtitles': [
              {
                'id': '1',
                'url': 'http://subs.example.com/en.srt',
                'lang': 'eng',
              },
              {
                'id': '2',
                'url': 'http://subs.example.com/es.srt',
                'lang': 'spa',
              },
              {'id': '3', 'url': 'file:///c:/local.srt', 'lang': 'spa'},
            ],
          };
    });

    const hints = {'videoHash': 'abc', 'videoSize': 100, 'filename': 'm.mkv'};

    testWidgets(
      'baja los subtítulos de los addons sin cargarlos y carga solo el del idioma preferido',
      (tester) async {
        final fake = engine();
        await openPlayer(
          tester,
          fake,
          PlayerArgs(
            url: 'http://media.example.com/video.mkv',
            item: _movieItem(hints: hints),
          ),
          subtitleLanguage: 'spa',
        );
        await pumpIo(tester);
        // Al arrancar todavía no se cargan: primero el video tiene que avanzar.
        expect(fake.state.subtitleTracks.where((t) => t.isExternal), isEmpty);
        fake.tick(const Duration(seconds: 3));
        await tester.pump();
        await pumpIo(tester);

        expect(
          world.requests,
          contains(
            '$_opensubsMatrix/videoHash=abc&videoSize=100&filename=m.mkv.json',
          ),
        );
        final externals = fake.state.subtitleTracks.where((t) => t.isExternal);
        // Se piden al addon, pero solo se carga al video el que se elige.
        expect(externals.map((t) => t.language), ['spa']);
        expect(fake.state.selectedSubtitle?.language, 'spa');
        await leavePlayer(tester);
      },
    );

    testWidgets('sin subtítulos del idioma preferido los deja apagados', (
      tester,
    ) async {
      final fake = engine();
      await openPlayer(
        tester,
        fake,
        PlayerArgs(
          url: 'http://media.example.com/video.mkv',
          item: _movieItem(hints: hints),
        ),
        subtitleLanguage: 'por',
      );
      await pumpIo(tester);
      fake.tick(const Duration(seconds: 3));
      await tester.pump();
      await pumpIo(tester);

      expect(fake.state.subtitleTracks.where((t) => t.isExternal), isEmpty);
      expect(fake.state.selectedSubtitle, isNull);
      await leavePlayer(tester);
    });

    testWidgets('elige la pista de audio del idioma preferido', (tester) async {
      final fake = engine(
        audio: const [
          AudioTrack(id: '1', language: 'eng'),
          AudioTrack(id: '2', language: 'spa'),
        ],
      );
      await openPlayer(
        tester,
        fake,
        PlayerArgs(
          url: 'http://media.example.com/video.mkv',
          item: _movieItem(),
        ),
        audioLanguage: 'spa',
      );
      await pumpIo(tester);

      expect(fake.state.selectedAudio?.id, '2');
      await leavePlayer(tester);
    });
  });

  testWidgets('al terminar un episodio ofrece el siguiente', (tester) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(
        url: 'http://media.example.com/video.mkv',
        item: _episodeItem(2),
      ),
    );
    expect(find.byKey(const Key('player-next-card')), findsNothing);

    fake.tick(const Duration(minutes: 11));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('player-next-card')), findsOneWidget);
    expect(find.text('T2 E1 · Episodio 2x1'), findsOneWidget);
    // Terminó: el progreso queda al final y no figura como «en curso».
    final p = containerOf(tester)
        .read(progressRepositoryProvider)
        .get('series', 'tt0903747', 'tt0903747:1:3');
    expect(p!.position, const Duration(minutes: 10));
    expect(containerOf(tester).read(continueWatchingProvider), isEmpty);
    await leavePlayer(tester);
  });

  testWidgets('el título del reproductor y de la ventana lleva el episodio', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(
      tester,
      fake,
      PlayerArgs(
        url: 'http://media.example.com/video.mkv',
        item: _episodeItem(0),
      ),
    );

    expect(find.text('Breaking Bad · T1 E1 · Episodio 1x1'), findsOneWidget);
    expect(window.title, 'Breaking Bad · T1 E1 · Episodio 1x1 · Parcel');
    await leavePlayer(tester);
    expect(window.title, 'Parcel');
  });

  group('pantalla completa', () {
    Future<FakePlaybackEngine> pumpScreen(WidgetTester tester) async {
      final fake = engine();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayerScreen(
                      engine: fake,
                      source: PlaybackSource(url: 'http://x/video.mkv'),
                      window: window,
                    ),
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('F la alterna', (tester) async {
      window.fullScreen = true;
      await pumpScreen(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(window.fullScreen, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(window.fullScreen, isTrue);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Esc sale de pantalla completa antes de volver', (
      tester,
    ) async {
      window.fullScreen = true;
      await pumpScreen(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(window.fullScreen, isFalse);
      expect(find.byKey(const Key('player-controls')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-controls')), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('el doble clic la alterna sin cambiar la reproducción', (
      tester,
    ) async {
      final fake = await pumpScreen(tester);
      expect(window.fullScreen, isFalse);

      await tester.tap(find.byKey(const Key('player-surface')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('player-surface')));
      await tester.pump();

      expect(window.fullScreen, isTrue);
      expect(fake.state.playing, isTrue);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('lógica de pistas', () {
    test(
      'selectAddonSubtitles limita por idioma, ordena y descarta archivos',
      () {
        Subtitle sub(String id, String lang, [String? url]) =>
            Subtitle(id: id, url: url ?? 'http://s/$id.srt', lang: lang);
        final result = selectAddonSubtitles([
          sub('1', 'eng'),
          sub('2', 'eng'),
          sub('3', 'spa'),
          sub('4', 'eng'),
          sub('5', 'eng'),
          sub('6', 'spa', 'file:///c:/x.srt'),
          sub('7', 'spa', 'http://s/3.srt'),
        ], preferredLanguage: 'spa');

        expect(result.map((s) => s.id), ['3', '1', '2']);
        expect(result.first.label, 'Español');
        expect(result[1].label, 'Inglés 1');
      },
    );

    test('el idioma preferido elige pista de audio y de subtítulos', () {
      const prefs = TrackPreferences(
        audioLanguage: 'spa',
        subtitleLanguage: 'eng',
      );
      const audio = [
        AudioTrack(id: '1', language: 'en'),
        AudioTrack(id: '2', language: 'es'),
      ];
      const subs = [SubtitleTrack(id: '3', language: 'eng')];

      expect(prefs.pickAudio(audio)?.id, '2');
      expect(prefs.pickSubtitle(subs)?.id, '3');
      expect(const TrackPreferences().pickAudio(audio), isNull);
    });

    test(
      'el episodio que sigue salta de temporada y no entra a especiales',
      () {
        final meta = _breakingBad();
        final byId = {for (final v in meta.videos) v.id: v};

        expect(nextVideo(meta, byId['tt0903747:1:3'])?.id, 'tt0903747:2:1');
        expect(nextVideo(meta, byId['tt0903747:1:1'])?.id, 'tt0903747:1:2');
        expect(nextVideo(meta, byId['tt0903747:2:2']), isNull);
        expect(nextVideo(meta, byId['tt0903747:0:1']), isNull);
        expect(nextVideo(meta, null), isNull);
      },
    );

    test('no ofrece un episodio que todavía no salió', () {
      final meta = _breakingBad();
      final byId = {for (final v in meta.videos) v.id: v};
      final current = byId['tt0903747:1:1']!;
      final next = byId['tt0903747:1:2']!;
      // Los episodios de prueba salieron en enero de 2008.
      expect(next.released, isNotNull);

      expect(
        nextVideo(
          meta,
          current,
          now: next.released!.add(const Duration(days: 1)),
        )?.id,
        next.id,
      );
      expect(
        nextVideo(
          meta,
          current,
          now: next.released!.subtract(const Duration(days: 1)),
        ),
        isNull,
      );
    });

    test('un episodio sin fecha se ofrece', () {
      final meta = Meta.fromJson({
        'id': 'tt1',
        'type': 'series',
        'name': 'Serie',
        'videos': [
          {'id': 'tt1:1:1', 'season': 1, 'episode': 1},
          {'id': 'tt1:1:2', 'season': 1, 'episode': 2},
        ],
      });
      expect(nextVideo(meta, meta.videos.first)?.id, 'tt1:1:2');
    });
  });
}
