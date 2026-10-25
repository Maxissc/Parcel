import 'dart:async';
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
import 'support/fakes.dart';
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

/// Una ventana que, al cambiar de modo, se queda con el foco del teclado.
class _FocusStealingWindow extends FakeWindowService {
  @override
  Future<void> setFullScreen(bool value) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await super.setFullScreen(value);
  }
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
  tearDown(() => deleteTempDir(dir));

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

  PlayerArgs playerArgs({Meta? m}) => PlayerArgs(
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
  );

  Future<void> openPlayer(
    WidgetTester tester,
    FakePlaybackEngine fake, {
    Meta? m,
    String subtitleLanguage = 'latam',
    List<FakePlaybackEngine> more = const [],
    WindowService window = const NoopWindowService(),
  }) async {
    final engines = [fake, ...more];
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
      overrides: [
        playbackEngineFactoryProvider.overrideWithValue(
          () => engines.length > 1 ? engines.removeAt(0) : engines.first,
        ),
      ],
      window: window,
    );
    routerOf(tester).push(Routes.player, extra: playerArgs(m: m));
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

  testWidgets('un subtítulo de otra velocidad lleva la etiqueta «Otra '
      'velocidad (fps)» en el menú', (tester) async {
    // Dura como 25 fps sobre un video de 23,976: 7200 s × 25 / 23,976.
    world.routes['subs.example.com/es.srt'] = srt(7510);
    final fake = FakePlaybackEngine(
      mediaDuration: const Duration(hours: 2),
      audioTracks: const [AudioTrack(id: '1', language: 'eng')],
    );
    await openPlayer(tester, fake);
    tester.view.physicalSize = const Size(1280, 1600);
    await letSubtitlesLoad(tester, fake);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Otra velocidad (fps)'), findsOneWidget);
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
    final fake = engine(
      audio: const [AudioTrack(id: '1', language: 'eng', title: 'Atmos')],
    );
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

  testWidgets('Atmos sale de la pista de audio, no del nombre del stream', (
    tester,
  ) async {
    // El stream se llama «1080p Atmos», pero la pista que suena no lo dice.
    final fake = engine();
    await openPlayer(tester, fake);
    fake.emitStats(const PlaybackStats(audioChannels: 6));
    await twice(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('player-stats-chips'))).data,
      '5.1',
    );
  });

  testWidgets(
    'el panel de datos sin datos todavía no inventa Software ni SDR',
    (tester) async {
      final fake = engine();
      await openPlayer(tester, fake);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await twice(tester);

      expect(find.byKey(const Key('player-info-panel')), findsOneWidget);
      expect(find.text('Software'), findsNothing);
      expect(find.text('SDR'), findsNothing);
    },
  );

  group('asistente de sincronización: foco', () {
    Future<void> openAssistant(
      WidgetTester tester,
      FakePlaybackEngine fake,
    ) async {
      await openPlayer(tester, fake);
      await letSubtitlesLoad(tester, fake);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await twice(tester);
      expect(find.byKey(const Key('sync-overlay')), findsOneWidget);
    }

    testWidgets('S marca también después de F: no reabre ni borra las marcas', (
      tester,
    ) async {
      final fake = engine();
      await openAssistant(tester, fake);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await twice(tester);
      expect(find.text('1 marca'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await twice(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await twice(tester);

      expect(find.text('2 marcas'), findsOneWidget);
      expect(find.byKey(const Key('sync-overlay')), findsOneWidget);
    });

    testWidgets('después de F, si la ventana se queda con el foco, vuelve al '
        'asistente', (tester) async {
      final fake = engine();
      await openPlayer(tester, fake, window: _FocusStealingWindow());
      await letSubtitlesLoad(tester, fake);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await twice(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await twice(tester);

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'sync-overlay');
    });

    testWidgets('con el foco en el reproductor, S marca y Esc cierra el '
        'asistente', (tester) async {
      final fake = engine();
      await openAssistant(tester, fake);
      FocusManager.instance.rootScope.descendants
          .firstWhere((n) => n.debugLabel == 'player')
          .requestFocus();
      await twice(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await twice(tester);
      expect(find.text('1 marca'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await twice(tester);
      expect(find.byKey(const Key('sync-overlay')), findsNothing);
      expect(find.byKey(const Key('player-controls')), findsOneWidget);
    });

    testWidgets('I cierra el asistente y abre el panel de datos', (
      tester,
    ) async {
      final fake = engine();
      await openAssistant(tester, fake);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await twice(tester);

      expect(find.byKey(const Key('sync-overlay')), findsNothing);
      expect(find.byKey(const Key('player-info-panel')), findsOneWidget);
    });

    testWidgets('el menú de subtítulos no borra las marcas de un asistente '
        'abierto', (tester) async {
      final fake = engine();
      await openAssistant(tester, fake);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await twice(tester);

      await tester.tap(find.byKey(const Key('player-subtitle-menu')));
      await tester.pumpAndSettle();
      await tester.tap(_menuItem('Sincronizar subtítulos… (S)'));
      await pumpIo(tester, ticks: 4);

      expect(find.text('1 marca'), findsOneWidget);
    });
  });

  testWidgets('S sin subtítulos de addons avisa en vez de abrir el asistente', (
    tester,
  ) async {
    world.routes.remove(_opensubs);
    final fake = engine();
    await openPlayer(tester, fake);
    await letSubtitlesLoad(tester, fake);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await twice(tester);

    expect(find.byKey(const Key('sync-overlay')), findsNothing);
    expect(
      find.text('No hay subtítulos de addons para sincronizar'),
      findsOneWidget,
    );
  });

  testWidgets('«Reintentar» vuelve a cargar el subtítulo externo elegido, '
      'sin rehacer el análisis', (tester) async {
    final fake = engine();
    await openPlayer(tester, fake);
    await letSubtitlesLoad(tester, fake);
    expect(fake.state.selectedSubtitle?.isExternal, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await twice(tester);
    final downloads = world.count('subs.example.com');

    fake.fail('Failed to open');
    await twice(tester);
    expect(find.byKey(const Key('player-error')), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await pumpIo(tester, ticks: 8);

    expect(fake.openCount, 2);
    expect(fake.state.selectedSubtitle?.isExternal, isTrue);
    expect(fake.state.selectedSubtitle?.language, 'spl');
    expect(fake.state.subtitleTracks.where((t) => t.isExternal), hasLength(1));
    expect(fake.subtitleDelay, const Duration(milliseconds: 100));
    expect(
      world.count('subs.example.com'),
      downloads,
      reason: 'el análisis es del contenido, no del intento',
    );
  });

  testWidgets('el retraso es de cada subtítulo: al cambiar de pista vuelve a '
      'cero y al volver se recupera', (tester) async {
    final fake = engine();
    await openPlayer(tester, fake);
    tester.view.physicalSize = const Size(1280, 1600);
    await letSubtitlesLoad(tester, fake);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    }
    await twice(tester);
    expect(fake.subtitleDelay, const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(_menuItem('Español'));
    await pumpIo(tester, ticks: 4);
    expect(fake.state.selectedSubtitle?.language, 'spa');
    expect(fake.subtitleDelay, Duration.zero);
    expect(find.text('Subtítulos 0,0 s'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(_menuItem('Español (Latinoamérica)'));
    await pumpIo(tester, ticks: 4);
    expect(fake.state.selectedSubtitle?.language, 'spl');
    expect(fake.subtitleDelay, const Duration(milliseconds: 300));
  });

  testWidgets('el retraso fijado se aplica al volver a abrir el reproductor', (
    tester,
  ) async {
    final first = engine();
    final second = engine();
    await openPlayer(tester, first, more: [second]);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await twice(tester);
    expect(first.subtitleDelay, const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpIo(tester, ticks: 6);
    expect(find.byKey(const Key('player-controls')), findsNothing);

    // El mismo contenido otra vez, con otro motor: arranca con el retraso.
    routerOf(tester).push(Routes.player, extra: playerArgs());
    await pumpIo(tester, ticks: 6);

    expect(second.openCount, 1);
    expect(second.subtitleDelay, const Duration(milliseconds: 200));
  });

  testWidgets('una fuente elegida a mano que no arranca en 30 s muestra el '
      'error con Reintentar y Elegir otra fuente', (tester) async {
    final fake = engine()..stallOnOpen = true;
    await openPlayer(tester, fake);

    await tester.pump(const Duration(seconds: 29));
    expect(find.byKey(const Key('player-error')), findsNothing);
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('player-error')), findsOneWidget);
    expect(find.text('La fuente no empezó a reproducirse.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Elegir otra fuente'), findsOneWidget);

    fake.stallOnOpen = false;
    await tester.tap(find.text('Reintentar'));
    await pumpIo(tester, ticks: 6);
    expect(fake.openCount, 2);
    expect(find.byKey(const Key('player-error')), findsNothing);
  });

  testWidgets('un stream en vivo (sin duración) que avanza no se da por '
      'caído', (tester) async {
    final fake = engine()..stallOnOpen = true;
    await openPlayer(tester, fake);
    fake.tick(const Duration(seconds: 2));
    await twice(tester);

    await tester.pump(const Duration(seconds: 40));
    expect(find.byKey(const Key('player-error')), findsNothing);
  });

  testWidgets('un subtítulo que todavía se baja muestra «Descargando…» y '
      'queda elegido hasta que carga', (tester) async {
    final fake = engine();
    await openPlayer(tester, fake);
    await letSubtitlesLoad(tester, fake);
    expect(fake.state.selectedSubtitle?.language, 'spl');

    fake.externalGate = Completer<void>();
    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(_menuItem('Español'));
    await twice(tester);

    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Descargando…'), findsOneWidget);
    expect(
      find.descendant(
        of: _menuItem('Español'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<CheckedPopupMenuItem<Object>>(_menuItem('Español')).checked,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));

    fake.externalGate!.complete();
    await pumpIo(tester, ticks: 4);
    expect(fake.state.selectedSubtitle?.language, 'spa');
    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Descargando…'), findsNothing);
  });

  testWidgets('si el subtítulo no se baja, avisa y queda el anterior', (
    tester,
  ) async {
    final fake = engine();
    await openPlayer(tester, fake);
    await letSubtitlesLoad(tester, fake);

    fake.externalFails = true;
    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    await tester.tap(_menuItem('Español'));
    await pumpIo(tester, ticks: 4);

    expect(find.text('No se pudo cargar el subtítulo'), findsOneWidget);
    expect(fake.state.selectedSubtitle?.language, 'spl');
    await tester.tap(find.byKey(const Key('player-subtitle-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Descargando…'), findsNothing);
  });

  testWidgets('el overlay de carga se va con el primer cuadro real y no '
      'antes', (tester) async {
    final fake = engine()..stallOnOpen = true;
    await openPlayer(tester, fake);
    expect(find.byKey(const Key('player-loading')), findsOneWidget);

    // Antes de medio segundo de video real, sigue.
    fake.setBuffering(false);
    fake.tick(const Duration(milliseconds: 300));
    await twice(tester);
    expect(find.byKey(const Key('player-loading')), findsOneWidget);

    // Un stream en vivo (sin duración) que avanza ya arrancó: se va.
    fake.tick(const Duration(milliseconds: 300));
    await twice(tester);
    expect(find.byKey(const Key('player-loading')), findsNothing);
  });

  testWidgets('con duración pero cargando, el overlay sigue hasta que '
      'termina de cargar', (tester) async {
    final fake = engine();
    await openPlayer(tester, fake);
    await twice(tester);
    expect(find.byKey(const Key('player-loading')), findsNothing);

    fake.setBuffering(true);
    await twice(tester);
    expect(find.byKey(const Key('player-loading')), findsOneWidget);
    fake.setBuffering(false);
    await twice(tester);
    expect(find.byKey(const Key('player-loading')), findsNothing);
  });
}

/// El ítem de un menú emergente que lleva [text].
Finder _menuItem(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate((w) => w is PopupMenuItem<Object>),
);
