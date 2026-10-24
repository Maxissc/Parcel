import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/app/router.dart';
import 'package:parcel_desktop/data/platform.dart';
import 'package:parcel_desktop/data/playback_providers.dart';
import 'package:parcel_desktop/features/player/play_item.dart';
import 'package:parcel_desktop/features/player/player_route.dart';

import 'support/catalog_world.dart';
import 'support/pump.dart';
import 'support/test_env.dart';

const _matrixId = 'tt0133093';
const _opensubs = 'opensubtitles-v3.strem.io/subtitles/movie/$_matrixId.json';

/// Un SRT con un cue de 3 s cada 10 s, el primero a los [offset] segundos,
/// hasta [endSeconds].
String srt(int endSeconds, {double offset = 5}) {
  final b = StringBuffer();
  var n = 1;
  String ts(double s) {
    final ms = (s * 1000).round();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(ms ~/ 3600000)}:${two(ms % 3600000 ~/ 60000)}:'
        '${two(ms % 60000 ~/ 1000)},${(ms % 1000).toString().padLeft(3, '0')}';
  }

  for (var t = offset; t + 3 <= endSeconds; t += 10) {
    b.writeln(n++);
    b.writeln('${ts(t)} --> ${ts(t + 3)}');
    b.writeln('Linea $n');
    b.writeln();
  }
  return b.toString();
}

/// Los streams del motor entregan en un microtask: hace falta un segundo
/// cuadro para ver el cambio en pantalla.
Future<void> twice(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  late Directory dir;
  late CatalogWorld world;

  setUp(() {
    dir = makeTempDir();
    world = CatalogWorld();
    world.routes[_opensubs] = {
      'subtitles': [
        {'id': 'fr', 'url': 'http://subs.example.com/fr.srt', 'lang': 'fre'},
        {'id': 'en', 'url': 'http://subs.example.com/en.srt', 'lang': 'eng'},
        {'id': 'es', 'url': 'http://subs.example.com/es.srt', 'lang': 'spa'},
        {'id': 'la', 'url': 'http://subs.example.com/la.srt', 'lang': 'spl'},
      ],
    };
    // LatAm calza con el video de 10 min; el español termina a la mitad.
    world.routes['subs.example.com/la.srt'] = srt(595);
    world.routes['subs.example.com/es.srt'] = srt(300, offset: 8);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Meta meta({String? originalLanguage}) => Meta(
    id: _matrixId,
    type: 'movie',
    name: 'The Matrix',
    imdbRating: '8.7',
    releaseInfo: '1999',
    runtime: '136 min',
    genres: const ['Acción'],
    originalLanguage: originalLanguage,
  );

  FakePlaybackEngine engine({List<AudioTrack>? audio}) => FakePlaybackEngine(
    mediaDuration: const Duration(minutes: 10),
    audioTracks: audio ?? const [AudioTrack(id: '1', language: 'eng')],
  );

  Future<void> openPlayer(
    WidgetTester tester,
    FakePlaybackEngine fake, {
    Meta? m,
    String subtitleLanguage = 'latam',
  }) async {
    await seedData(
      tester,
      dir,
      world.client,
      urls: [cinemetaUrl, subtitlesUrl, streamsAddonUrl],
      onboardingCompleted: true,
      subtitleLanguage: subtitleLanguage,
    );
    await pumpApp(
      tester,
      dir,
      world.client,
      overrides: [playbackEngineFactoryProvider.overrideWithValue(() => fake)],
    );
    routerOf(tester).push(
      Routes.player,
      extra: PlayerArgs(
        url: 'http://media.example.com/video.mkv',
        item: PlayItem(
          meta: m ?? meta(),
          stream: AddonStream.fromJson({
            'url': 'http://media.example.com/video.mkv?token=SECRETO',
            'name': 'Torrentio\n1080p Atmos',
          }),
          addonUrl: streamsAddonUrl,
          addonName: 'Streams uno',
        ),
      ),
    );
    await pumpIo(tester, ticks: 4);
  }

  /// Avanza el video y deja que se bajen y analicen los subtítulos.
  Future<void> letSubtitlesLoad(
    WidgetTester tester,
    FakePlaybackEngine fake,
  ) async {
    await pumpIo(tester, ticks: 6);
    fake.tick(const Duration(seconds: 3));
    await twice(tester);
    await pumpIo(tester, ticks: 8);
  }

  testWidgets('audio original y subtítulo de Latinoamérica por defecto', (
    tester,
  ) async {
    final fake = engine(
      audio: const [
        AudioTrack(id: '1', language: 'spa', title: 'Castellano'),
        AudioTrack(id: '2', language: 'eng', isDefault: true),
        AudioTrack(id: '3', language: 'jpn'),
      ],
    );
    await openPlayer(tester, fake, m: meta(originalLanguage: 'ja'));
    await letSubtitlesLoad(tester, fake);

    expect(fake.state.selectedAudio?.id, '3');
    final sub = fake.state.selectedSubtitle;
    expect(sub?.language, 'spl');
    expect(sub?.isExternal, isTrue);
    // Solo se cargó el elegido: el resto está en el menú pero no en el video.
    expect(fake.state.subtitleTracks.where((t) => t.isExternal), hasLength(1));
  });

  testWidgets('sin idioma original conocido deja el audio por defecto', (
    tester,
  ) async {
    final fake = engine(
      audio: const [
        AudioTrack(id: '1', language: 'spa'),
        AudioTrack(id: '2', language: 'eng', isDefault: true),
      ],
    );
    await openPlayer(tester, fake);
    await pumpIo(tester, ticks: 6);

    expect(fake.state.selectedAudio?.id, '2');
  });

  testWidgets('el menú de subtítulos va ordenado y con etiquetas', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(tester, fake);
    await letSubtitlesLoad(tester, fake);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();

    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('Español (Latinoamérica)'), lessThan(y('Español')));
    expect(y('Español'), lessThan(y('Inglés')));
    expect(y('Inglés'), lessThan(y('Más idiomas')));
    expect(y('Más idiomas'), lessThan(y('Francés')));
    expect(find.text('Probablemente sincronizado'), findsOneWidget);
    expect(find.text('Puede estar desfasado'), findsOneWidget);
    expect(find.text('Sincronizar subtítulos… (S)'), findsOneWidget);
  });

  testWidgets('la barra de progreso muestra el tramo ya cargado', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(tester, fake);
    fake.tick(const Duration(seconds: 60));
    fake.emitStats(const PlaybackStats(bufferAhead: Duration(seconds: 30)));
    await twice(tester);

    await twice(tester);
    final bar = tester.widget<FractionallySizedBox>(
      find.byKey(const Key('player-buffer')),
    );
    // (60 + 30) s de 600 s.
    expect(bar.widthFactor, closeTo(0.15, 1e-9));
  });

  testWidgets('I abre el panel de datos con lo que informa el motor', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(tester, fake);
    // Alta, para que se armen todas las filas del panel.
    tester.view.physicalSize = const Size(1280, 1600);
    fake.emitStats(
      const PlaybackStats(
        videoWidth: 1920,
        videoHeight: 1080,
        fps: 23.976,
        videoCodec: 'hevc',
        dynamicRange: DynamicRange.hdr10,
        hardwareDecoder: 'd3d11va',
        videoBitrate: 8200000,
        audioCodec: 'eac3',
        audioChannels: 6,
        bufferAhead: Duration(seconds: 25),
        bufferBehind: Duration(seconds: 12),
        cacheLevel: 'Media · 300 MB',
      ),
    );
    await twice(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('player-stats-chips'))).data,
      '1080p · HDR · 5.1 Atmos · 24 fps',
    );
    expect(find.byKey(const Key('player-info-panel')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await twice(tester);

    expect(find.byKey(const Key('player-info-panel')), findsOneWidget);
    for (final text in [
      '1920×1080',
      '23,98',
      'hevc',
      'HDR10',
      'Hardware (d3d11va)',
      '8,2 Mb/s',
      'eac3',
      '5.1 · Atmos',
      '25 s',
      '12 s',
      'Media · 300 MB',
      'Streams uno',
      'Torrentio · 1080p Atmos',
      '★ 8.7',
      '1999',
      '136 min',
      'Acción',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    // Nada de URLs ni de claves.
    expect(find.textContaining('SECRETO'), findsNothing);
    expect(find.textContaining('media.example.com'), findsNothing);

    // Cabe en la ventana más chica sin desbordar.
    tester.view.physicalSize = const Size(960, 600);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    // Esc lo cierra sin salir del reproductor.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await twice(tester);
    expect(find.byKey(const Key('player-info-panel')), findsNothing);
    expect(find.byKey(const Key('player-controls')), findsOneWidget);
  });

  testWidgets('H y G corren los subtítulos de a 100 ms', (tester) async {
    final fake = engine();
    await openPlayer(tester, fake);

    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    }
    await twice(tester);
    expect(fake.subtitleDelay, const Duration(milliseconds: 300));
    expect(find.text('Subtítulos +0,3 s'), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    }
    await twice(tester);
    expect(fake.subtitleDelay, const Duration(milliseconds: -200));
    expect(find.text('Subtítulos −0,2 s'), findsOneWidget);
  });

  testWidgets('el asistente de sincronización descarta y aplica el retraso', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(tester, fake);
    await letSubtitlesLoad(tester, fake);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await twice(tester);
    expect(find.byKey(const Key('sync-overlay')), findsOneWidget);
    expect(
      find.text(
        'Apretá S (o hacé clic acá) justo cuando alguien empieza a hablar.',
      ),
      findsOneWidget,
    );

    // Primera marca: los cues de LatAm empiezan a los 5, 15, 25... segundos.
    fake.tick(const Duration(milliseconds: 15500 - 3000));
    await twice(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await twice(tester);
    expect(find.text('Queda 1 subtítulo que coincide'), findsOneWidget);
    // Con una sola marca todavía no se lista nada.
    expect(find.byKey(const Key('sync-list')), findsNothing);

    // Segunda marca.
    fake.tick(const Duration(seconds: 10));
    await twice(tester);
    await tester.tap(find.byKey(const Key('sync-mark')));
    await twice(tester);
    expect(find.text('Queda 1 subtítulo que coincide'), findsOneWidget);
    expect(find.byKey(const Key('sync-row-la')), findsOneWidget);
    expect(find.byKey(const Key('sync-row-es')), findsNothing);
    expect(find.textContaining('retraso +0,5 s'), findsOneWidget);

    // El descartado se puede ver igual.
    await tester.tap(find.byKey(const Key('sync-discarded')));
    await twice(tester);
    expect(find.byKey(const Key('sync-row-es')), findsOneWidget);

    // 960×600 sin desbordar.
    tester.view.physicalSize = const Size(960, 600);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('sync-row-la')));
    await pumpIo(tester, ticks: 4);

    expect(find.byKey(const Key('sync-overlay')), findsNothing);
    expect(fake.subtitleDelay, const Duration(milliseconds: 500));
    expect(fake.state.selectedSubtitle?.language, 'spl');
  });

  testWidgets('Esc cierra el asistente sin salir del reproductor', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(tester, fake);
    await letSubtitlesLoad(tester, fake);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await twice(tester);
    expect(find.byKey(const Key('sync-overlay')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await twice(tester);

    expect(find.byKey(const Key('sync-overlay')), findsNothing);
    expect(find.byKey(const Key('player-controls')), findsOneWidget);
  });

  testWidgets('el retraso fijado se recuerda para el mismo contenido', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(tester, fake);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await twice(tester);
    expect(fake.subtitleDelay, const Duration(milliseconds: 200));

    // Queda guardado por contenido mientras la app esté abierta.
    expect(
      containerOf(tester).read(subtitleDelaysProvider)['movie:$_matrixId'],
      const Duration(milliseconds: 200),
    );
  });
}
