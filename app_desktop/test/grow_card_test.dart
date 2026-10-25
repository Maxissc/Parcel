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
            width: 900,
            child: Shelf(
              itemCount: count,
              itemBuilder: (context, index) => PosterCard(
                title: 'Peli $index',
                caption: '1999',
                preview: _preview,
                onTap: onTap,
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
    await mouse.removePointer();
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
    await mouse.removePointer();
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
    await mouse.removePointer();
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
    await mouse.removePointer();
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
    await mouse.removePointer();
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
    await mouse.removePointer();
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
    await mouse.removePointer();
  });
}
