import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/shared/media_row.dart';
import 'package:parcel_desktop/shared/poster_card.dart';

const _preview = CardPreview(
  rating: '8.7',
  year: '1999',
  genres: ['Acción', 'Ciencia ficción'],
  synopsis: 'Un hacker descubre la verdad.',
);

Future<void> _pumpRow(
  WidgetTester tester, {
  bool reduceMotion = false,
  VoidCallback? onTap,
  int count = 12,
  double width = 900,
  VoidCallback? onPlay,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Shelf(
              itemCount: count,
              itemBuilder: (context, index) => PosterCard(
                title: 'Peli $index',
                caption: '1999',
                preview: CardPreview(
                  rating: _preview.rating,
                  year: _preview.year,
                  genres: _preview.genres,
                  synopsis: _preview.synopsis,
                  onPlay: onPlay,
                ),
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<TestGesture> _hover(WidgetTester tester, Finder finder) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(finder));
  await tester.pump();
  return mouse;
}

/// Saca el mouse y deja correr los tiempos pendientes de las tarjetas.
Future<void> _end(WidgetTester tester, TestGesture mouse) async {
  await mouse.removePointer();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('con el mouse encima, tras 350 ms crece en su lugar y abre el '
      'panel', (tester) async {
    await _pumpRow(tester);
    final base = tester.getRect(find.text('Peli 2').first);
    final cardRect = tester.getRect(find.byType(PosterCard).at(2));
    final mouse = await _hover(tester, find.byType(PosterCard).at(2));

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('card-grown')), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    final grown = tester.getRect(find.byKey(const Key('card-grown')));
    expect(grown.width, closeTo(140 * CardGrowth.scale, 0.5));
    expect(grown.height, closeTo(210 * CardGrowth.scale, 0.5));
    // Crece alrededor de su centro: no se corre más de lo que se agranda.
    expect(grown.center.dx, closeTo(cardRect.center.dx, 0.5));
    // Las vecinas no se movieron.
    expect(tester.getRect(find.text('Peli 2').first), base);
    expect(find.byKey(const Key('card-panel')), findsOneWidget);
    expect(
      find.text('★ 8.7 · 1999 · Acción · Ciencia ficción'),
      findsOneWidget,
    );
    expect(find.text('Un hacker descubre la verdad.'), findsOneWidget);
    expect(find.text('Ver'), findsOneWidget);
    expect(find.text('Más info'), findsOneWidget);
    // El panel queda debajo de la tarjeta agrandada.
    expect(
      tester.getRect(find.byKey(const Key('card-panel'))).top,
      greaterThanOrEqualTo(grown.bottom),
    );
    await _end(tester, mouse);
  });

  testWidgets('la primera tarjeta se ancla a la izquierda de la fila', (
    tester,
  ) async {
    await _pumpRow(tester);
    final mouse = await _hover(tester, find.byType(PosterCard).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final grown = tester.getRect(find.byKey(const Key('card-grown')));
    expect(grown.left, greaterThanOrEqualTo(8));
    await _end(tester, mouse);
  });

  testWidgets('al salir vuelve con la animación inversa y se va', (
    tester,
  ) async {
    await _pumpRow(tester);
    final mouse = await _hover(tester, find.byType(PosterCard).at(2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('card-panel')), findsOneWidget);

    await mouse.moveTo(const Offset(5, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 130));
    // A mitad de camino todavía se ve, más chica.
    final mid = tester.getRect(find.byKey(const Key('card-grown')));
    expect(mid.width, lessThan(140 * CardGrowth.scale));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('card-grown')), findsNothing);
    expect(find.byKey(const Key('card-panel')), findsNothing);
    await _end(tester, mouse);
  });

  testWidgets('un paso rápido del mouse por la tarjeta no la abre', (
    tester,
  ) async {
    await _pumpRow(tester);
    final mouse = await _hover(tester, find.byType(PosterCard).at(2));
    await tester.pump(const Duration(milliseconds: 150));
    await mouse.moveTo(const Offset(5, 500));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('card-grown')), findsNothing);
    await _end(tester, mouse);
  });

  testWidgets('con reducir movimiento no escala: solo aparece con un fundido', (
    tester,
  ) async {
    await _pumpRow(tester, reduceMotion: true);
    final mouse = await _hover(tester, find.byType(PosterCard).at(2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final grown = tester.getRect(find.byKey(const Key('card-grown')));
    expect(grown.width, closeTo(140, 0.5));
    expect(find.byKey(const Key('card-panel')), findsOneWidget);
    await _end(tester, mouse);
  });

  testWidgets('con el foco del teclado también crece, y Enter la abre', (
    tester,
  ) async {
    var opened = 0;
    await _pumpRow(tester, onTap: () => opened++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('card-grown')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, 1);
  });

  testWidgets('un clic en la tarjeta agrandada la abre', (tester) async {
    var opened = 0;
    await _pumpRow(tester, onTap: () => opened++);
    final mouse = await _hover(tester, find.byType(PosterCard).at(2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await mouse.down(tester.getCenter(find.byKey(const Key('card-grown'))));
    await mouse.up();
    await tester.pump();
    expect(opened, 1);
    await _end(tester, mouse);
  });

  testWidgets('la rueda sobre la tarjeta agrandada mueve la página', (
    tester,
  ) async {
    final page = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: page,
            children: [
              Shelf(
                itemCount: 12,
                itemBuilder: (context, index) => PosterCard(
                  title: 'Peli $index',
                  preview: _preview,
                  onTap: () {},
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final mouse = await _hover(tester, find.byType(PosterCard).at(2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('card-grown')), findsOneWidget);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byKey(const Key('card-grown'))),
        scrollDelta: const Offset(0, 120),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    expect(page.offset, greaterThan(0));
    await _end(tester, mouse);
  });

  group('gestos sobre la tarjeta agrandada', () {
    late ScrollController page;

    Future<void> pumpPage(WidgetTester tester) async {
      page = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: page,
              children: [
                Shelf(
                  itemCount: 12,
                  itemBuilder: (context, index) => PosterCard(
                    title: 'Peli $index',
                    preview: _preview,
                    onTap: () {},
                  ),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    double rowOffset(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(Shelf),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .pixels;

    Future<TestGesture> openGrown(WidgetTester tester) async {
      final mouse = await _hover(tester, find.byType(PosterCard).at(2));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('card-grown')), findsOneWidget);
      return mouse;
    }

    testWidgets('Shift + rueda mueve la fila y no la página', (tester) async {
      await pumpPage(tester);
      final mouse = await openGrown(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byKey(const Key('card-grown'))),
          scrollDelta: const Offset(0, 120),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(rowOffset(tester), greaterThan(0));
      expect(page.offset, 0);
      await _end(tester, mouse);
    });

    testWidgets('el desplazamiento horizontal mueve la fila', (tester) async {
      await pumpPage(tester);
      final mouse = await openGrown(tester);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byKey(const Key('card-grown'))),
          scrollDelta: const Offset(100, 0),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      expect(rowOffset(tester), greaterThan(0));
      expect(page.offset, 0);
      await _end(tester, mouse);
    });

    testWidgets('arrastrar con el mouse mueve la fila', (tester) async {
      await pumpPage(tester);
      final mouse = await openGrown(tester);
      await mouse.down(tester.getCenter(find.byKey(const Key('card-grown'))));
      await mouse.moveBy(const Offset(-60, 0));
      await mouse.moveBy(const Offset(-60, 0));
      await mouse.up();
      await tester.pump();
      expect(rowOffset(tester), greaterThan(60));
      await _end(tester, mouse);
    });

    testWidgets('el pan del trackpad mueve la fila y la página', (
      tester,
    ) async {
      await pumpPage(tester);
      final mouse = await openGrown(tester);
      final at = tester.getCenter(find.byKey(const Key('card-grown')));
      final pad = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pad.panZoomStart(at);
      await pad.panZoomUpdate(at, pan: const Offset(-80, 0));
      await tester.pump();
      expect(rowOffset(tester), greaterThan(0));
      await pad.panZoomUpdate(at, pan: const Offset(-80, -90));
      await pad.panZoomEnd();
      await tester.pump();
      expect(page.offset, greaterThan(0));
      await _end(tester, mouse);
    });
  });

  group('una sola tarjeta agrandada', () {
    testWidgets('el hover en otra tarjeta con una enfocada deja una sola', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await _pumpRow(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('card-grown')), findsOneWidget);
      final first = tester.getCenter(find.byKey(const Key('card-grown')));

      final mouse = await _hover(tester, find.byType(PosterCard).at(4));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('card-grown')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('card-grown'))).dx,
        isNot(closeTo(first.dx, 1)),
      );
      await _end(tester, mouse);
    });

    testWidgets('el foco crece solo en modo teclado: al pasar a toque se '
        'cierra', (tester) async {
      await _pumpRow(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('card-grown')), findsOneWidget);

      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('card-grown')), findsNothing);
    });

    testWidgets('scrollear la fila la cierra', (tester) async {
      await _pumpRow(tester);
      final mouse = await _hover(tester, find.byType(PosterCard).at(2));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('card-grown')), findsOneWidget);

      tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(Shelf),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .jumpTo(40);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const Key('card-grown')), findsNothing);
      await _end(tester, mouse);
    });

    testWidgets('mientras se cierra no recibe toques', (tester) async {
      var played = 0;
      await _pumpRow(tester, onPlay: () => played++);
      final mouse = await _hover(tester, find.byType(PosterCard).at(2));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      final play = tester.getCenter(find.byKey(const Key('card-play')));

      await mouse.moveTo(const Offset(5, 700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const Key('card-grown')), findsOneWidget);
      await tester.tapAt(play);
      await tester.pump();
      expect(played, 0);
      await _end(tester, mouse);
    });
  });

  group('flechas de la fila', () {
    testWidgets('la tarjeta agrandada deja libre la franja de la ›', (
      tester,
    ) async {
      await _pumpRow(tester, width: 700);
      final mouse = await _hover(tester, find.byType(PosterCard).at(3));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      final grown = tester.getRect(find.byKey(const Key('card-grown')));
      final panel = tester.getRect(find.byKey(const Key('card-panel')));
      final limit = 700 - 8 - CardGrowth.arrowGutter;
      expect(grown.right, lessThanOrEqualTo(limit + 0.5));
      expect(panel.right, lessThanOrEqualTo(limit + 0.5));
      await _end(tester, mouse);
    });

    testWidgets('el mouse sobre la tarjeta agrandada no apaga las flechas y '
        'la › sigue andando', (tester) async {
      await _pumpRow(tester, width: 700);
      final mouse = await _hover(tester, find.byType(PosterCard).at(3));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await mouse.moveTo(tester.getCenter(find.byKey(const Key('card-panel'))));
      await tester.pump(const Duration(milliseconds: 300));
      final arrow = find.ancestor(
        of: find.byTooltip('Ver más'),
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(arrow).opacity, 1);

      final shelf = find.descendant(
        of: find.byType(Shelf),
        matching: find.byType(Scrollable),
      );
      await mouse.moveTo(tester.getCenter(find.byTooltip('Ver más')));
      await tester.pump();
      await mouse.down(tester.getCenter(find.byTooltip('Ver más')));
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.state<ScrollableState>(shelf).position.pixels,
        greaterThan(0),
      );
      await _end(tester, mouse);
    });

    testWidgets('con la ‹ se ve a la izquierda al llegar al final y la › se '
        'oculta', (tester) async {
      await _pumpRow(tester);
      final shelf = find.descendant(
        of: find.byType(Shelf),
        matching: find.byType(Scrollable),
      );
      final mouse = await _hover(tester, find.byType(PosterCard).at(1));
      double opacity(String tooltip) => tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.byTooltip(tooltip),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity('Ver más'), 1);
      expect(opacity('Ver anteriores'), 0);

      final position = tester.state<ScrollableState>(shelf).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity('Ver más'), 0);
      expect(opacity('Ver anteriores'), 1);
      await _end(tester, mouse);
    });

    testWidgets('al agrandar la ventana o cambiar itemCount se recalcula', (
      tester,
    ) async {
      await _pumpRow(tester, width: 400, count: 12);
      final mouse = await _hover(tester, find.byType(PosterCard).first);
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.byTooltip('Ver más'),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity(), 1);

      // Cabe todo: ya no hay a dónde ir.
      await _pumpRow(tester, width: 1400, count: 3);
      await mouse.moveTo(const Offset(5, 700));
      await mouse.moveTo(tester.getCenter(find.byType(PosterCard).first));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity(), 0);

      // Vuelven a sobrar tarjetas.
      await _pumpRow(tester, width: 1400, count: 30);
      await mouse.moveTo(const Offset(5, 700));
      await mouse.moveTo(tester.getCenter(find.byType(PosterCard).first));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity(), 1);
      await _end(tester, mouse);
    });
  });

  testWidgets('la tarjeta agrandada no sube por encima del área de la página', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Barra')),
          body: ListView(
            children: [
              Shelf(
                itemCount: 12,
                itemBuilder: (context, index) => PosterCard(
                  title: 'Peli $index',
                  preview: _preview,
                  onTap: () {},
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final pageTop = tester.getTopLeft(find.byType(ListView).first).dy;
    final mouse = await _hover(tester, find.byType(PosterCard).at(2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final grown = tester.getRect(find.byKey(const Key('card-grown')));
    expect(pageTop, greaterThan(0));
    expect(grown.top, greaterThanOrEqualTo(pageTop + 8 - 0.5));
    await _end(tester, mouse);
  });

  testWidgets('una fila que se vuelve a armar queda donde estaba', (
    tester,
  ) async {
    final page = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: page,
            children: [
              Shelf(
                key: const PageStorageKey<String>('fila'),
                itemCount: 12,
                itemBuilder: (context, index) =>
                    PosterCard(title: 'Peli $index', onTap: () {}),
              ),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final row = find.descendant(
      of: find.byType(Shelf),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(row).position.jumpTo(300);
    await tester.pump();

    // La fila sale de la zona armada y se desarma.
    page.jumpTo(2500);
    await tester.pump();
    expect(find.byType(Shelf), findsNothing);

    page.jumpTo(0);
    await tester.pump();
    expect(find.byType(Shelf), findsOneWidget);
    expect(tester.state<ScrollableState>(row).position.pixels, 300);
  });
}
