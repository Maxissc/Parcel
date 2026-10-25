import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_core/parcel_core.dart';
import 'package:parcel_desktop/features/player/loading_view.dart';
import 'package:parcel_desktop/features/player/player_screen.dart';

Widget _app(
  Widget child, {
  bool disableAnimations = false,
  Size size = const Size(960, 600),
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: disableAnimations),
    child: child,
  ),
);

PlayerLoadingView _view({
  LoadingArt art = const LoadingArt(
    name: 'Michael',
    background: 'https://img.example.com/bg.jpg',
    logo: 'https://img.example.com/logo.png',
  ),
  String status = 'Abriendo…',
  VoidCallback? onBack,
}) => PlayerLoadingView(art: art, status: status, onBack: onBack ?? () {});

double _opacity(WidgetTester tester) =>
    tester.widget<Opacity>(find.byKey(const Key('loading-breathing'))).opacity;

double _scale(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(
        of: find.byKey(const Key('loading-breathing')),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .storage[0];

void main() {
  testWidgets('con logo muestra el logo y el fondo; el nombre queda de '
      'reserva si el logo no carga', (tester) async {
    await tester.pumpWidget(_app(_view()));

    expect(find.byKey(const Key('loading-logo')), findsOneWidget);
    expect(find.byKey(const Key('loading-name')), findsNothing);
    // El fondo es una imagen de la red debajo del velo.
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Abriendo…'), findsOneWidget);

    // En los tests la red no responde: el logo falla y aparece el nombre.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('loading-name')), findsOneWidget);
    expect(find.text('Michael'), findsOneWidget);
  });

  testWidgets('sin logo muestra el nombre en letra grande', (tester) async {
    await tester.pumpWidget(
      _app(_view(art: const LoadingArt(name: 'Michael'))),
    );

    expect(find.byKey(const Key('loading-logo')), findsNothing);
    final name = tester.widget<Text>(find.byKey(const Key('loading-name')));
    expect(name.data, 'Michael');
    expect(
      name.style!.fontSize!,
      greaterThanOrEqualTo(
        Theme.of(tester.element(find.text('Michael')))
            .textTheme
            .displayMedium!
            .fontSize!,
      ),
    );
  });

  testWidgets('Volver arriba a la izquierda avisa', (tester) async {
    var back = 0;
    await tester.pumpWidget(_app(_view(onBack: () => back++)));

    final rect = tester.getRect(find.byKey(const Key('loading-back')));
    expect(rect.left, lessThan(60));
    expect(rect.top, lessThan(60));
    await tester.tap(find.byKey(const Key('loading-back')));
    expect(back, 1);
  });

  testWidgets('respira: opacidad 0,55 a 1 y escala 0,98 a 1,02 cada 2,4 s', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_view(art: const LoadingArt(name: 'X'))));

    expect(_opacity(tester), closeTo(0.55, 0.01));
    expect(_scale(tester), closeTo(0.98, 0.005));

    await tester.pump(const Duration(milliseconds: 1200));
    expect(_opacity(tester), closeTo(1.0, 0.01));
    expect(_scale(tester), closeTo(1.02, 0.005));

    await tester.pump(const Duration(milliseconds: 1200));
    expect(_opacity(tester), closeTo(0.55, 0.01));
    expect(_scale(tester), closeTo(0.98, 0.005));

    // En el medio del camino no está en ningún extremo (curva suave).
    await tester.pump(const Duration(milliseconds: 600));
    expect(_opacity(tester), closeTo(0.775, 0.02));
  });

  testWidgets('con las animaciones apagadas queda quieto', (tester) async {
    await tester.pumpWidget(
      _app(_view(art: const LoadingArt(name: 'X')), disableAnimations: true),
    );

    expect(find.byKey(const Key('loading-breathing')), findsNothing);
    expect(find.text('X'), findsOneWidget);
    // Sin animaciones corriendo, todo se asienta.
    await tester.pumpAndSettle();
  });

  testWidgets('FadingOverlay se apaga con un fundido y sale del árbol', (
    tester,
  ) async {
    Widget overlay(bool visible) => _app(
      FadingOverlay(
        visible: visible,
        child: const SizedBox(key: Key('contenido'), width: 10, height: 10),
      ),
    );
    await tester.pumpWidget(overlay(true));
    expect(find.byKey(const Key('contenido')), findsOneWidget);

    await tester.pumpWidget(overlay(false));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('contenido')), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byKey(const Key('contenido')), findsNothing);
  });

  group('en el reproductor', () {
    Future<FakePlaybackEngine> open(
      WidgetTester tester, {
      bool stall = true,
      LoadingArt? art = const LoadingArt(name: 'Michael'),
      bool disableAnimations = false,
    }) async {
      final engine = FakePlaybackEngine(
        mediaDuration: const Duration(minutes: 2),
      )..stallOnOpen = stall;
      await tester.pumpWidget(
        _app(
          PlayerScreen(
            engine: engine,
            source: PlaybackSource(url: 'http://x/video.mkv'),
            title: 'Michael',
            loadingArt: art,
          ),
          disableAnimations: disableAnimations,
        ),
      );
      await tester.pump();
      return engine;
    }

    testWidgets('mientras abre muestra la pantalla de carga, sin los '
        'controles, y se va con un fundido al primer cuadro', (tester) async {
      final engine = await open(tester);

      expect(find.byKey(const Key('player-loading')), findsOneWidget);
      expect(find.text('Abriendo…'), findsOneWidget);
      expect(find.byKey(const Key('loading-name')), findsOneWidget);
      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(const Key('player-controls')))
            .opacity,
        0,
      );
      expect(tester.takeException(), isNull);

      engine.stallOnOpen = false;
      await engine.open(PlaybackSource(url: 'http://x/video.mkv'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      // A mitad del fundido todavía está.
      expect(find.byKey(const Key('player-loading')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byKey(const Key('player-loading')), findsNothing);
    });

    testWidgets('sin datos del contenido usa el título de la pantalla', (
      tester,
    ) async {
      await open(tester, art: null);

      expect(find.byKey(const Key('loading-name')), findsOneWidget);
      expect(find.text('Michael'), findsWidgets);
    });

    testWidgets('con las animaciones apagadas no respira ni hace fundido', (
      tester,
    ) async {
      final engine = await open(tester, disableAnimations: true);
      expect(find.byKey(const Key('loading-breathing')), findsNothing);

      engine.stallOnOpen = false;
      await engine.open(PlaybackSource(url: 'http://x/video.mkv'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('player-loading')), findsNothing);
    });
  });
}
