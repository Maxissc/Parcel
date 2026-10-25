import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/data/platform.dart';
import 'package:parcel_desktop/features/player/player_screen.dart';
import 'package:parcel_desktop/features/player/side_panel.dart';
import 'package:parcel_desktop/playback/subtitle_position.dart';

import 'support/fakes.dart';

const _audioEs = AudioTrack(id: '1', language: 'spa', title: 'Castellano');
const _audioEn = AudioTrack(id: '2', language: 'eng', title: 'Original');
const _subEs = SubtitleTrack(id: '3', language: 'spa', title: 'Español');

FakePlaybackEngine _engine() => FakePlaybackEngine(
  mediaDuration: const Duration(minutes: 2),
  audioTracks: const [_audioEs, _audioEn],
  subtitleTracks: const [_subEs],
);

Future<void> _pump(
  WidgetTester tester,
  FakePlaybackEngine engine, {
  List<Subtitle> subtitles = const [],
  WindowService? window,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PlayerScreen(
        engine: engine,
        source: PlaybackSource(url: 'http://x/video.mkv'),
        subtitles: subtitles,
        window: window,
        title: 'video.mkv',
      ),
    ),
  );
  await tester.pump();
}

Finder _menuItem(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(PanelOption));

double _controlsOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const Key('player-controls')))
    .opacity;

void main() {
  testWidgets('abre la fuente y muestra los controles con los tiempos', (
    tester,
  ) async {
    final engine = _engine();
    await _pump(tester, engine);

    expect(engine.lastSource?.url, 'http://x/video.mkv');
    expect(find.byKey(const Key('player-seek')), findsOneWidget);
    expect(find.byKey(const Key('player-volume')), findsOneWidget);
    expect(find.byTooltip('Audio'), findsOneWidget);
    expect(find.byTooltip('Subtítulos'), findsOneWidget);
    expect(find.byTooltip('Volver'), findsOneWidget);
    expect(find.text('video.mkv'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('2:00'), findsOneWidget);
  });

  testWidgets('las opciones van contra el borde derecho y los chips a la '
      'izquierda, también a 960 px', (tester) async {
    tester.view.physicalSize = const Size(960, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = _engine();
    await _pump(tester, engine, window: FakeWindowService());
    engine.emitStats(
      const PlaybackStats(videoHeight: 2160, audioChannels: 6, fps: 24),
    );
    await tester.pump();
    await tester.pump();

    // El último botón termina donde termina el relleno de la barra (16 px).
    expect(
      tester.getTopRight(find.byKey(const Key('player-fullscreen'))).dx,
      closeTo(944, 1),
    );
    final chips = tester.getRect(find.byKey(const Key('player-stats-chips')));
    final volume = tester.getRect(find.byKey(const Key('player-volume')));
    expect(chips.left, greaterThanOrEqualTo(volume.right));
    expect(chips.right, lessThan(500));
    expect(
      tester.getTopLeft(find.byKey(const Key('player-play'))).dx,
      lessThan(60),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('play/pausa cambia el ícono', (tester) async {
    final engine = _engine();
    await _pump(tester, engine);
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-play')));
    await tester.pump();
    expect(engine.state.playing, isFalse);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-play')));
    await tester.pump();
    expect(engine.state.playing, isTrue);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets(
    'el menú de subtítulos lista Desactivados y las pistas, y elige',
    (tester) async {
      final engine = _engine();
      await _pump(tester, engine);

      await tester.tap(find.byTooltip('Subtítulos'));
      await tester.pumpAndSettle();
      expect(find.text('Desactivados'), findsOneWidget);
      expect(find.text('Español (spa)'), findsOneWidget);

      await tester.tap(_menuItem('Español (spa)'));
      await tester.pumpAndSettle();
      expect(engine.state.selectedSubtitle, _subEs);

      await tester.tap(find.byTooltip('Subtítulos'));
      await tester.pumpAndSettle();
      await tester.tap(_menuItem('Desactivados'));
      await tester.pumpAndSettle();
      expect(engine.state.selectedSubtitle, isNull);
    },
  );

  testWidgets('el menú de audio lista las pistas y cambia la elegida', (
    tester,
  ) async {
    final engine = _engine();
    await _pump(tester, engine);

    await tester.tap(find.byTooltip('Audio'));
    await tester.pumpAndSettle();
    expect(find.text('Castellano (spa)'), findsOneWidget);
    await tester.tap(_menuItem('Original (eng)'));
    await tester.pumpAndSettle();

    expect(engine.state.selectedAudio, _audioEn);
  });

  testWidgets(
    'los subtítulos externos se cargan al abrir y aparecen en el menú',
    (tester) async {
      final engine = _engine();
      await _pump(
        tester,
        engine,
        subtitles: const [
          Subtitle(
            id: 'e',
            url: 'http://x/sub.srt',
            lang: 'und',
            label: 'Mi sub',
          ),
        ],
      );
      await tester.pump();

      expect(engine.state.subtitleTracks.last.isExternal, isTrue);
      await tester.tap(find.byTooltip('Subtítulos'));
      await tester.pumpAndSettle();
      expect(find.text('Mi sub · externo'), findsOneWidget);
    },
  );

  testWidgets('el error muestra el mensaje y Reintentar vuelve a abrir', (
    tester,
  ) async {
    final engine = _engine()..openError = 'HTTP 404';
    await _pump(tester, engine);
    await tester.pump();

    expect(find.text('No se pudo reproducir el video'), findsOneWidget);
    expect(find.text('HTTP 404'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    engine.openError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();

    expect(find.text('No se pudo reproducir el video'), findsNothing);
    expect(engine.state.playing, isTrue);
  });

  testWidgets('un error de reproducción en curso muestra Reintentar', (
    tester,
  ) async {
    final engine = _engine();
    await _pump(tester, engine);
    engine.fail('Se cortó la conexión');
    await tester.pump();
    await tester.pump();

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Se cortó la conexión'), findsOneWidget);
  });

  testWidgets('la pantalla de error no muestra la URL ni el token', (
    tester,
  ) async {
    final engine = _engine();
    await _pump(tester, engine);
    engine.fail('No abre http://127.0.0.1:7000/no-existe?token=SECRETO');
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('SECRETO'), findsNothing);
    expect(find.text('No abre 127.0.0.1:7000'), findsOneWidget);
  });

  testWidgets('los controles se ocultan a los 3 s y vuelven con el mouse', (
    tester,
  ) async {
    final engine = _engine();
    await _pump(tester, engine);
    expect(_controlsOpacity(tester), 1);

    await tester.pump(const Duration(seconds: 2));
    expect(_controlsOpacity(tester), 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_controlsOpacity(tester), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_controlsOpacity(tester), 1);
    await mouse.removePointer();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('el subtítulo sube con los controles y vuelve al ocultarse', (
    tester,
  ) async {
    final engine = _LiftEngine();
    await _pump(tester, engine);
    await tester.pump(const Duration(milliseconds: 400));
    // Con los controles a la vista queda arriba de la barra: unos 88 px de
    // los 600 de alto.
    expect(engine.lift, closeTo(88 / 600, 0.01));

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_controlsOpacity(tester), 0);
    expect(engine.lift, 0);
    // Cambia de a poco, no de golpe.
    expect(engine.lifts.where((l) => l > 0 && l < 88 / 600 - 0.01), isNotEmpty);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.lift, closeTo(88 / 600, 0.01));
    await mouse.removePointer();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('con las animaciones apagadas el subtítulo cambia de golpe', (
    tester,
  ) async {
    final engine = _LiftEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            disableAnimations: true,
          ),
          child: PlayerScreen(
            engine: engine,
            source: PlaybackSource(url: 'http://x/video.mkv'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));

    expect(engine.lifts, [88 / 600, 0]);
  });

  testWidgets('atajos: espacio, flechas y volumen', (tester) async {
    final engine = _engine();
    await _pump(tester, engine);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.state.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.state.position, const Duration(seconds: 10));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(engine.state.position, Duration.zero);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.state.volume, closeTo(0.95, 0.001));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(engine.state.volume, 1.0);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('Esc vuelve y libera el motor', (tester) async {
    final engine = _engine();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerScreen(
                    engine: engine,
                    source: PlaybackSource(url: 'http://x/video.mkv'),
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
    expect(find.byKey(const Key('player-controls')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-controls')), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
    // El motor se liberó: su stream quedó cerrado.
    expect(engine.stream, emitsDone);
  });
}

/// Motor falso que además guarda cuánto se subieron los subtítulos.
class _LiftEngine extends FakePlaybackEngine implements SubtitleLiftable {
  _LiftEngine() : super(mediaDuration: const Duration(minutes: 2));

  /// Cada valor que se pidió, en orden.
  final List<double> lifts = [];

  double get lift => lifts.isEmpty ? 0 : lifts.last;

  @override
  Future<void> setSubtitleLift(double lift) async => lifts.add(lift);
}
