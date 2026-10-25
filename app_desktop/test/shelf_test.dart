import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_desktop/shared/media_row.dart';

void main() {
  testWidgets('desplazar la fila no la redibuja entera en cada paso', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Shelf(
            itemCount: 60,
            itemBuilder: (context, index) {
              builds++;
              return SizedBox(width: 150, child: Text('Ítem $index'));
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    // El primer paso hace aparecer la flecha de «anteriores».
    await gesture.moveBy(const Offset(-6, 0));
    await tester.pump();
    await tester.pump();
    final afterFirst = builds;

    // Los siguientes no cambian ninguna flecha ni traen ítems nuevos.
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-3, 0));
      await tester.pump();
    }
    await gesture.up();

    expect(builds, afterFirst);
  });

  testWidgets('las flechas aparecen al pasar el mouse según se pueda mover', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Shelf(
            itemCount: 60,
            itemBuilder: (context, index) =>
                SizedBox(width: 150, child: Text('Ítem $index')),
          ),
        ),
      ),
    );
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(Shelf)));
    await tester.pump(const Duration(milliseconds: 300));

    double opacityOf(String tooltip) => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byTooltip(tooltip),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;

    // Al principio solo se puede ir hacia adelante.
    expect(opacityOf('Ver más'), 1);
    expect(opacityOf('Ver anteriores'), 0);

    await tester.tap(find.byTooltip('Ver más'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));

    expect(opacityOf('Ver anteriores'), 1);
    await mouse.removePointer();
  });

  group('rueda, arrastre y flechas', () {
    final pageKey = GlobalKey();
    final rowKey = GlobalKey();
    var taps = 0;

    Future<void> pumpPage(WidgetTester tester) async {
      taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              key: pageKey,
              children: [
                Shelf(
                  key: rowKey,
                  itemCount: 60,
                  itemBuilder: (context, index) => GestureDetector(
                    onTap: () => taps++,
                    child: SizedBox(width: 150, child: Text('Ítem $index')),
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

    ScrollPosition positionIn(WidgetTester tester, Key key) => tester
        .state<ScrollableState>(
          find
              .descendant(of: find.byKey(key), matching: find.byType(Scrollable))
              .first,
        )
        .position;

    Future<void> wheel(WidgetTester tester, Offset delta) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final at = tester.getCenter(find.byKey(rowKey));
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(delta));
      await tester.pump();
    }

    testWidgets('la rueda vertical mueve la página y no la fila', (
      tester,
    ) async {
      await pumpPage(tester);
      await wheel(tester, const Offset(0, 100));
      expect(positionIn(tester, pageKey).pixels, greaterThan(0));
      expect(positionIn(tester, rowKey).pixels, 0);
    });

    testWidgets('Shift + rueda mueve la fila y no la página', (tester) async {
      await pumpPage(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await wheel(tester, const Offset(0, 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(positionIn(tester, rowKey).pixels, greaterThan(0));
      expect(positionIn(tester, pageKey).pixels, 0);
    });

    testWidgets('el desplazamiento horizontal mueve la fila', (tester) async {
      await pumpPage(tester);
      await wheel(tester, const Offset(100, 0));
      expect(positionIn(tester, rowKey).pixels, greaterThan(0));
      expect(positionIn(tester, pageKey).pixels, 0);
    });

    testWidgets('la flecha avanza el 85 % del ancho visible', (tester) async {
      await pumpPage(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byKey(rowKey)));
      await tester.pump(const Duration(milliseconds: 300));
      final viewport = positionIn(tester, rowKey).viewportDimension;
      await tester.tap(find.byTooltip('Ver más'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(positionIn(tester, rowKey).pixels, closeTo(viewport * 0.85, 1));
      await mouse.removePointer();
    });

    testWidgets('arrastrar con el mouse mueve la fila y no abre la tarjeta', (
      tester,
    ) async {
      await pumpPage(tester);
      final start =
          tester.getTopLeft(find.text('Ítem 3')) + const Offset(20, 8);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(positionIn(tester, rowKey).pixels, greaterThan(100));
      expect(taps, 0);
    });
  });
}
